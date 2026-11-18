import { cleanup, effect, lifecycle, signal, untracked } from "nsh";
import type { Signal } from "nsh";
import { scaleBle, scaleNative } from "./scale-bridge";
import type { ScaleCopy } from "./scale-copy";
import type { Device, Preview } from "./scale-types";

const SCAN_TIMEOUT_MS = 12_000;
const MEASUREMENT_TIMEOUT_MS = 30_000;
const MAX_DEVICES = 16;

export function createScaleSession(labels: ScaleCopy, close: () => void, busy: Signal<boolean>) {
  const state = signal<
    "idle" | "scanning" | "connecting" | "measuring" | "review" | "failed" | "saved"
  >("idle");
  const devices = signal<Device[]>([]);
  const preview = signal<Preview | null>(null);
  const message = signal("");
  const replacement = signal(false);
  const profileReady = signal(false);
  const profileLoaded = signal(false);
  let liveId = "";
  let scanId = "";
  let generation = 0;
  let scanTimer: ReturnType<typeof setTimeout> | undefined;
  let disposed = false;
  let initialized = false;
  let measurementTimer: ReturnType<typeof setTimeout> | undefined;
  const isCurrent = (attempt: number) => !disposed && attempt === generation;
  function clearMeasurementTimeout() {
    clearTimeout(measurementTimer);
    measurementTimer = undefined;
  }
  function awaitReading() {
    if (measurementTimer !== undefined) return;
    const attempt = generation;
    measurementTimer = setTimeout(() => {
      if (!isCurrent(attempt) || preview()) return;
      halt();
      fail(labels.measurementTimeout);
    }, MEASUREMENT_TIMEOUT_MS);
  }
  const halt = () => {
    generation++;
    initialized = false;
    clearTimeout(scanTimer);
    scanTimer = undefined;
    clearMeasurementTimeout();
    const scan = scanId;
    scanId = "";
    const live = liveId;
    liveId = "";
    if (scan) void scaleBle.stopScan(scan).catch(() => {});
    if (live) {
      void scaleNative.pause(live).catch(() => {});
      void scaleBle.disconnect(live).catch(() => {});
    }
  };
  const leave = () => {
    if (busy()) return;
    halt();
    close();
  };
  const cancel = async () => {
    if (busy()) return false;
    busy.set(true);
    const id = liveId || preview()?.session_id;
    halt();
    try {
      if (id) await scaleNative.cancel(id);
      if (!disposed) close();
      return true;
    } catch {
      if (!disposed) {
        message.set(labels.saveFailed);
        state.set(preview() ? "review" : "failed");
      }
      return false;
    } finally {
      if (!disposed) busy.set(false);
    }
  };
  const invalidate = (detail: string) => {
    const id = liveId || preview()?.session_id;
    // Invalidate before pausing. Rust quarantines the draft even if deletion fails.
    if (id) void scaleNative.invalidate(id).catch(() => {});
    preview.set(null);
    replacement.set(false);
    halt();
    fail(detail);
  };
  function fail(detail: string) {
    message.set(detail);
    state.set("failed");
  }
  async function scan() {
    if (busy() || preview() || state() === "scanning") return;
    halt();
    replacement.set(false);
    devices.set([]);
    message.set("");
    const attempt = generation;
    scanId = `scan-${Date.now()}-${attempt}`;
    if (!scaleBle.available()) {
      fail(labels.unsupported);
      return;
    }
    state.set("scanning");
    try {
      const status = await scaleBle.status();
      if (!isCurrent(attempt)) return;
      if (!status.available) {
        fail(labels.unsupported);
        return;
      }
      if (status.permissionGranted === true && !status.enabled) {
        fail(labels.failed);
        return;
      }
      await scaleBle.startScan(scanId, SCAN_TIMEOUT_MS);
      if (!isCurrent(attempt) || !scanId) return;
      scanTimer = setTimeout(() => {
        if (!isCurrent(attempt)) return;
        const id = scanId;
        finishScan();
        if (id) void scaleBle.stopScan(id).catch(() => {});
      }, SCAN_TIMEOUT_MS + 500);
    } catch {
      if (isCurrent(attempt)) {
        halt();
        fail(labels.failed);
      }
    }
  }
  async function connect(device: Device) {
    if (busy() || preview() || state() === "connecting" || liveId) return;
    halt();
    const attempt = generation;
    message.set("");
    replacement.set(false);
    state.set("connecting");
    try {
      const start = await scaleNative.begin(device);
      if (!isCurrent(attempt)) {
        void scaleNative.cancel(start.session_id).catch(() => {});
        return;
      }
      liveId = start.session_id;
      await scaleBle.connect(liveId, device.address);
      if (!isCurrent(attempt)) return;
      for (const dataBase64 of start.commands) {
        await scaleBle.write(liveId, dataBase64);
        if (!isCurrent(attempt)) return;
      }
      initialized = true;
      state.set("measuring");
      awaitReading();
    } catch {
      if (isCurrent(attempt)) invalidate(labels.failed);
    }
  }
  async function save() {
    const reviewed = preview();
    if (!reviewed || busy()) return;
    // A paused/reopened review is valid without a connection. A live attempt
    // must finish its profile/time initialization before it can be confirmed.
    if (liveId && !initialized) return;
    if (reviewed.existing_kg !== null && !replacement()) {
      replacement.set(true);
      return;
    }
    busy.set(true);
    try {
      await scaleNative.confirm(reviewed.session_id, reviewed.token, replacement());
      if (disposed) return;
      halt();
      preview.set(null);
      message.set(labels.saved);
      state.set("saved");
    } catch (error) {
      if (disposed) return;
      const code = error instanceof Error ? error.message : String(error);
      if (code === "storage_unavailable" || code.endsWith(": storage_unavailable")) {
        // Rust rolled back the transaction and retained this exact draft.
        halt();
        message.set(labels.saveFailed);
        state.set("review");
      } else {
        preview.set(null);
        replacement.set(false);
        halt();
        message.set(labels.stale);
        state.set("failed");
      }
    } finally {
      if (!disposed) busy.set(false);
    }
  }

  function finishScan() {
    clearTimeout(scanTimer);
    scanTimer = undefined;
    scanId = "";
    state.set("idle");
    message.set(devices().length ? labels.stopped : labels.empty);
  }

  const stops = [
    scaleBle.onDevice((device) => {
      if (!scanId || device.sessionId !== scanId || !device.name.startsWith("AFU-WL")) return;
      const current = devices();
      if (current.some((item) => item.address === device.address)) {
        devices.set(current.map((item) => (item.address === device.address ? device : item)));
      } else if (current.length < MAX_DEVICES) {
        devices.set([...current, device]);
      }
    }),
    scaleBle.onConnection((event) => {
      if (scanId && event.sessionId === scanId && event.state === "scan_stopped") {
        finishScan();
        return;
      }
      if (event.sessionId === liveId && event.state === "disconnected") {
        if (!initialized) {
          invalidate(labels.failed);
          return;
        }
        halt();
        if (!busy()) {
          message.set(labels.disconnected);
          state.set(preview() ? "review" : "failed");
        }
      }
    }),
    scaleBle.onNotification(async (event) => {
      if (!liveId || event.sessionId !== liveId || !initialized || busy()) return;
      if (event.dataBase64 === null) {
        invalidate(labels.packet);
        return;
      }
      const id = liveId;
      const attempt = generation;
      try {
        const result = await scaleNative.feed(id, event.dataBase64);
        if (!isCurrent(attempt) || id !== liveId || busy()) return;
        const previous = preview();
        if (
          !result ||
          previous?.session_id !== result.session_id ||
          previous?.token !== result.token
        )
          replacement.set(false);
        if (result) clearMeasurementTimeout();
        else awaitReading();
        preview.set(result);
        state.set(result ? "review" : "measuring");
        message.set("");
      } catch {
        if (!isCurrent(attempt) || busy()) return;
        invalidate(labels.packet);
      }
    }),
    scaleBle.onError((event) => {
      if (event.sessionId !== liveId && event.sessionId !== scanId) return;
      if (liveId && !initialized) {
        invalidate(labels.failed);
        return;
      }
      halt();
      if (!busy()) fail(labels.failed);
    }),
  ];
  // A runtime permission dialog makes Android inactive, not backgrounded.
  // Keep that explicit permission request alive; native onStop still closes BLE.
  effect(() => {
    if (lifecycle() === "background")
      untracked(() => {
        halt();
        if (!busy()) {
          message.set(labels.disconnected);
          state.set(preview() ? "review" : "idle");
        }
      });
  });
  cleanup(() => {
    disposed = true;
    busy.set(false);
    halt();
    stops.forEach((stop) => stop());
  });
  async function restoreDraft() {
    try {
      const ready = await scaleNative.profileReady();
      if (disposed) return;
      profileReady.set(ready);
      const kept = await scaleNative.pending();
      if (disposed) return;
      if (kept) {
        preview.set(kept);
        state.set("review");
        message.set(labels.draft);
      }
    } catch {
      if (!disposed) fail(labels.failed);
    } finally {
      if (!disposed) profileLoaded.set(true);
    }
  }
  void restoreDraft();

  async function openProfile() {
    try {
      if (await cancel()) await scaleNative.openProfile();
    } catch {
      if (!disposed) fail(labels.failed);
    }
  }

  return {
    state,
    devices,
    preview,
    message,
    replacement,
    profileReady,
    profileLoaded,
    scan,
    connect,
    save,
    leave,
    cancel,
    openProfile,
  };
}
