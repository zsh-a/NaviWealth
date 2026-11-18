package com.naviwealth.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import com.longbridge.nsh.NshHostReply
import com.longbridge.nsh.NshView
import java.util.ArrayDeque
import java.util.UUID

/** Foreground-only BLE transport. Protocol bytes and confirmed writes belong to Rust. */
@SuppressLint("MissingPermission") // Every operation and callback rechecks permission; races fail closed.
internal class ScaleBleBridge(private val activity: Activity, private val nsh: NshView) {
    companion object {
        private const val PERMISSION_REQUEST = 4207
        private val SERVICE = UUID.fromString("0000ffb0-0000-1000-8000-00805f9b34fb")
        private val WRITE = UUID.fromString("0000ffb1-0000-1000-8000-00805f9b34fb")
        private val NOTIFY = UUID.fromString("0000ffb2-0000-1000-8000-00805f9b34fb")
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
    private val main = Handler(Looper.getMainLooper())
    private val gate = BleSessionGate()
    private var foreground = true
    private var destroyed = false
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var scanSession: String? = null
    private var scanDeadline: Runnable? = null
    private var connectDeadline: Runnable? = null
    private var writeDeadline: Runnable? = null
    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var ready = false
    private var connectReply: NshHostReply? = null
    private data class PendingPermission(val session: String, val reply: NshHostReply, val action: () -> Unit)
    private var permission: PendingPermission? = null
    private var permissionInFlight = false
    private data class Write(val bytes: ByteArray, val reply: NshHostReply)
    private val writes = ArrayDeque<Write>()
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED &&
                intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR) != BluetoothAdapter.STATE_ON) {
                val scanning = scanSession
                stopScan()
                if (scanning != null) error(scanning, "bluetooth_off")
                closeConnection("bluetooth_off")
                cancelPermission("bluetooth_off")
            }
        }
    }

    init {
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else activity.registerReceiver(receiver, filter)
        handle("ble.status") { _, reply ->
            val adapter = adapter()
            val granted = permissionsGranted()
            reply.resolve(mapOf("available" to (adapter != null && activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)), "enabled" to (granted && adapter?.isEnabled == true),
                "permissionGranted" to granted, "requiresPermission" to !granted))
        }
        handle("ble.scan.start") { data, reply ->
            val id = session(data)
            withPermission(id, reply) { startScan(id, timeout(data, 10000, 30000), reply) }
        }
        handle("ble.scan.stop") { data, reply ->
            val id = session(data)
            if (scanSession == id) stopScan()
            if (permission?.session == id) cancelPermission("cancelled")
            reply.resolve(mapOf("stopped" to true))
        }
        handle("ble.connect") { data, reply ->
            val id = session(data)
            val address = data["address"] as? String ?: throw IllegalArgumentException()
            require(BluetoothAdapter.checkBluetoothAddress(address))
            withPermission(id, reply) { connect(id, address, reply) }
        }
        handle("ble.disconnect") { data, reply ->
            val id = session(data)
            if (scanSession == id) stopScan()
            if (permission?.session == id) cancelPermission("cancelled")
            if (gate.sessionId == id) closeConnection("cancelled")
            reply.resolve(mapOf("disconnected" to true))
        }
        handle("ble.write") { data, reply ->
            val id = session(data)
            require(id == gate.sessionId && ready && permissionsGranted())
            val encoded = data["dataBase64"] as? String ?: throw IllegalArgumentException()
            require(encoded.length <= 32)
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            // AFU-WL uses 20-byte protocol frames, without ATT fragmentation.
            require(bytes.size in 1..20)
            if (writes.size >= 16) { reply.reject("write_queue_full"); return@handle }
            writes.addLast(Write(bytes, reply))
            if (writes.size == 1) writeNext()
        }
    }

    private fun handle(name: String, operation: (Map<*, *>, NshHostReply) -> Unit) {
        nsh.handle(name) { raw, reply ->
            if (destroyed) { reply.reject("host_destroyed"); return@handle }
            try {
                val data = (raw as? Map<*, *>) ?: emptyMap<String, Any>()
                operation(data, reply)
            } catch (_: SecurityException) { reply.reject("permission_denied"); closeConnection("permission_denied") }
            catch (_: IllegalArgumentException) { reply.reject("invalid_request") }
            catch (_: Exception) { reply.reject("bluetooth_unavailable"); closeConnection("bluetooth_unavailable") }
        }
    }
    private fun session(data: Map<*, *>): String {
        val id = data["sessionId"] as? String ?: throw IllegalArgumentException()
        require(id.length in 1..96 && id.all { it.isLetterOrDigit() || it in "-_:" })
        return id
    }
    private fun timeout(data: Map<*, *>, fallback: Int, maximum: Int): Long =
        ((data["timeoutMs"] as? Number)?.toInt() ?: fallback).coerceIn(1000, maximum).toLong()
    private fun adapter(): BluetoothAdapter? = activity.getSystemService(BluetoothManager::class.java)?.adapter
    private fun requiredPermissions(): Array<String> = if (Build.VERSION.SDK_INT >= 31)
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    private fun permissionsGranted(): Boolean = requiredPermissions().all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    private fun withPermission(id: String, reply: NshHostReply, action: () -> Unit) {
        if (!foreground) { reply.reject("app_background"); return }
        if (permissionsGranted()) { action(); return }
        if (permissionInFlight) { reply.reject("permission_pending"); return }
        permission = PendingPermission(id, reply, action)
        permissionInFlight = true
        try { activity.requestPermissions(requiredPermissions(), PERMISSION_REQUEST) }
        catch (_: Exception) {
            permissionInFlight = false
            permission = null
            reply.reject("permission_denied")
        }
    }
    fun onPermissionResult(code: Int) {
        if (code != PERMISSION_REQUEST) return
        permissionInFlight = false
        val pending = permission ?: return
        permission = null
        if (!foreground || destroyed) pending.reply.reject("app_background")
        else if (!permissionsGranted()) pending.reply.reject("permission_denied")
        else try { pending.action() } catch (_: Exception) { pending.reply.reject("bluetooth_unavailable") }
    }
    private fun cancelPermission(reason: String) { permission?.reply?.reject(reason); permission = null }
    fun onForeground() { foreground = true }
    fun onBackground() {
        foreground = false
        stopScan()
        cancelPermission("app_background")
        closeConnection("app_background")
    }
    fun destroy() {
        if (destroyed) return
        onBackground()
        destroyed = true
        main.removeCallbacksAndMessages(null)
        activity.unregisterReceiver(receiver)
        for (name in listOf("ble.status", "ble.scan.start", "ble.scan.stop", "ble.connect", "ble.disconnect", "ble.write")) nsh.handle(name, null)
    }
    private fun send(name: String, id: String, data: Map<String, Any>) {
        if (!destroyed) nsh.send(name, data + ("sessionId" to id))
    }
    private fun error(id: String, code: String) { send("ble.error", id, mapOf("code" to code, "message" to code)) }
    private fun startScan(id: String, duration: Long, reply: NshHostReply) {
        stopScan()
        closeConnection("replaced")
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) { reply.reject("bluetooth_off"); return }
        val current = adapter.bluetoothLeScanner ?: run { reply.reject("bluetooth_unavailable"); return }
        val seen = mutableSetOf<String>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                main.post {
                    if (destroyed || scanCallback !== this || scanSession != id || !foreground) return@post
                    try {
                        if (!permissionsGranted()) { stopScan(); error(id, "permission_denied"); return@post }
                        val name = result.scanRecord?.deviceName ?: result.device.name ?: ""
                        // Known AFU-WL target; service UUIDs may be absent from its advertisements.
                        val record = result.scanRecord
                        val services = record?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
                        if (!name.startsWith("AFU-WL", ignoreCase = true) && SERVICE.toString() !in services) return@post
                        val manufacturerData = mutableMapOf<String, String>()
                        record?.manufacturerSpecificData?.let { data ->
                            for (i in 0 until data.size()) {
                                val bytes = data.valueAt(i)
                                if (bytes.size <= 512) manufacturerData[data.keyAt(i).toString()] = Base64.encodeToString(bytes, Base64.NO_WRAP)
                            }
                        }
                        val serviceData = record?.serviceData?.entries?.filter { it.value.size <= 512 }?.associate {
                            it.key.uuid.toString() to Base64.encodeToString(it.value, Base64.NO_WRAP)
                        } ?: emptyMap()
                        val address = result.device.address
                        if (seen.size >= 64 || !seen.add(address)) return@post
                        send("ble.device", id, mapOf("address" to address, "name" to name.take(80), "rssi" to result.rssi,
                            "manufacturerData" to manufacturerData, "serviceUuids" to services, "serviceData" to serviceData))
                    } catch (_: SecurityException) { stopScan(); error(id, "permission_denied") }
                }
            }
            override fun onScanFailed(errorCode: Int) { main.post {
                if (scanCallback === this && scanSession == id) { stopScan(); error(id, "scan_failed") }
            } }
        }
        scanSession = id; scanner = current; scanCallback = callback
        try { current.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback) }
        catch (_: Exception) { stopScan(); reply.reject("scan_failed"); return }
        scanDeadline = Runnable {
            if (scanSession == id && scanCallback === callback) {
                stopScan()
                send("ble.connection", id, mapOf("state" to "scan_stopped", "reason" to "scan_timeout"))
            }
        }.also { main.postDelayed(it, duration) }
        reply.resolve(mapOf("started" to true))
    }
    private fun stopScan() {
        scanDeadline?.let { main.removeCallbacks(it) }; scanDeadline = null
        val current = scanner; val callback = scanCallback
        scanner = null; scanCallback = null; scanSession = null
        if (current != null && callback != null) try { current.stopScan(callback) } catch (_: Exception) { /* permission may have been revoked */ }
    }
    private fun connect(id: String, address: String, reply: NshHostReply) {
        stopScan(); closeConnection("replaced")
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) { reply.reject("bluetooth_off"); return }
        val token = gate.begin(id)
        connectReply = reply
        send("ble.connection", id, mapOf("state" to "connecting"))
        val callback = object : BluetoothGattCallback() {
            private fun post(current: BluetoothGatt, operation: () -> Unit) { main.post {
                if (!destroyed && foreground && gate.accepts(id, token) && gatt === current) {
                    try {
                        if (!permissionsGranted()) { closeConnection("permission_denied"); return@post }
                        operation()
                    } catch (_: SecurityException) { closeConnection("permission_denied") }
                    catch (_: Exception) { closeConnection("gatt_failed") }
                }
            } }
            override fun onConnectionStateChange(current: BluetoothGatt, status: Int, state: Int) = post(current) {
                if (status != BluetoothGatt.GATT_SUCCESS || state == BluetoothProfile.STATE_DISCONNECTED) closeConnection("disconnected")
                else if (state == BluetoothProfile.STATE_CONNECTED && !current.discoverServices()) closeConnection("service_discovery_failed")
            }
            override fun onServicesDiscovered(current: BluetoothGatt, status: Int) = post(current) {
                if (status != BluetoothGatt.GATT_SUCCESS) { closeConnection("service_discovery_failed"); return@post }
                val service = current.getService(SERVICE)
                val write = service?.getCharacteristic(WRITE)
                val notify = service?.getCharacteristic(NOTIFY)
                val descriptor = notify?.getDescriptor(CCCD)
                if (write == null || notify == null || descriptor == null ||
                    write.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) == 0 ||
                    notify.properties and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) == 0) {
                    closeConnection("unsupported_scale"); return@post
                }
                writeCharacteristic = write
                if (!current.setCharacteristicNotification(notify, true)) { closeConnection("notify_failed"); return@post }
                val value = if (notify.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0)
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                if (!writeDescriptor(current, descriptor, value)) closeConnection("notify_failed")
            }
            override fun onDescriptorWrite(current: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) = post(current) {
                if (descriptor.uuid != CCCD || ready) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) { closeConnection("notify_failed"); return@post }
                ready = true
                connectDeadline?.let { main.removeCallbacks(it) }; connectDeadline = null
                connectReply?.resolve(mapOf("connected" to true)); connectReply = null
                send("ble.connection", id, mapOf("state" to "ready"))
            }
            @Suppress("DEPRECATION")
            @Deprecated("Pre-Android 13 notification callback")
            override fun onCharacteristicChanged(current: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                if (Build.VERSION.SDK_INT < 33) notification(current, characteristic, characteristic.value?.clone() ?: byteArrayOf())
            }
            override fun onCharacteristicChanged(current: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) = notification(current, characteristic, value.clone())
            private fun notification(current: BluetoothGatt, characteristic: BluetoothGattCharacteristic, bytes: ByteArray) = post(current) {
                if (ready && characteristic.uuid == NOTIFY && bytes.size in 1..512)
                    send("ble.notification", id, mapOf("dataBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP)))
            }
            override fun onCharacteristicWrite(current: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) = post(current) {
                if (characteristic.uuid != WRITE || writes.isEmpty()) return@post
                writeDeadline?.let { main.removeCallbacks(it) }; writeDeadline = null
                if (status != BluetoothGatt.GATT_SUCCESS) { closeConnection("write_failed"); return@post }
                writes.removeFirst().reply.resolve(mapOf("written" to true))
                writeNext()
            }
        }
        try { gatt = adapter.getRemoteDevice(address).connectGatt(activity, false, callback, BluetoothDevice.TRANSPORT_LE) }
        catch (_: Exception) { closeConnection("connect_failed"); return }
        if (gatt == null) { closeConnection("connect_failed"); return }
        connectDeadline = Runnable { if (gate.accepts(id, token) && !ready) closeConnection("connect_timeout") }
            .also { main.postDelayed(it, 20000) }
    }
    private fun writeNext() {
        if (writes.isEmpty()) return
        val current = gatt ?: return
        val characteristic = writeCharacteristic ?: return
        val item = writes.first
        val type = if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0)
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        if (!writeCharacteristic(current, characteristic, item.bytes, type)) { closeConnection("write_failed"); return }
        writeDeadline = Runnable { closeConnection("write_timeout") }.also { main.postDelayed(it, 8000) }
    }
    private fun closeConnection(reason: String) {
        val id = gate.sessionId
        gate.invalidate()
        ready = false
        connectDeadline?.let { main.removeCallbacks(it) }; connectDeadline = null
        writeDeadline?.let { main.removeCallbacks(it) }; writeDeadline = null
        connectReply?.reject(reason); connectReply = null
        while (writes.isNotEmpty()) writes.removeFirst().reply.reject(reason)
        val current = gatt; gatt = null; writeCharacteristic = null
        if (current != null) {
            try { current.disconnect() } catch (_: Exception) { /* permission may have been revoked */ }
            try { current.close() } catch (_: Exception) { /* platform cleanup must not crash on revocation */ }
        }
        if (id != null) send("ble.connection", id, mapOf("state" to "disconnected", "reason" to reason))
    }
    @Suppress("DEPRECATION")
    private fun writeDescriptor(current: BluetoothGatt, descriptor: BluetoothGattDescriptor, bytes: ByteArray): Boolean =
        if (Build.VERSION.SDK_INT >= 33) current.writeDescriptor(descriptor, bytes) == BluetoothStatusCodes.SUCCESS
        else { descriptor.value = bytes; current.writeDescriptor(descriptor) }
    @Suppress("DEPRECATION")
    private fun writeCharacteristic(current: BluetoothGatt, characteristic: BluetoothGattCharacteristic, bytes: ByteArray, type: Int): Boolean =
        if (Build.VERSION.SDK_INT >= 33) current.writeCharacteristic(characteristic, bytes, type) == BluetoothStatusCodes.SUCCESS
        else { characteristic.writeType = type; characteristic.value = bytes; current.writeCharacteristic(characteristic) }
}
