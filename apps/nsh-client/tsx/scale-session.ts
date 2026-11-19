import { cleanup, effect, lifecycle, signal, untracked } from "nsh";
import type { Signal } from "nsh";
import { scaleBle, scaleNative } from "./scale-bridge";
import type { ScaleCopy } from "./scale-copy";
import type { Device, LiveReading, Notification, Preview, ScaleIdentity } from "./scale-types";

const SCAN_TIMEOUT_MS = 12_000;
const MEASUREMENT_TIMEOUT_MS = 30_000;
const COMPOSITION_NOTICE_MS = 15_000;
const MAX_DEVICES = 16;
const MAX_PENDING_NOTIFICATIONS = 64;

export function createScaleSession(labels: ScaleCopy, close: () => void, busy: Signal<boolean>) {
  const state = signal<
    "idle" | "scanning" | "connecting" | "measuring" | "review" | "failed" | "saved"
  >("idle");
  const devices = signal<Device[]>([]);
  const remembered = signal<ScaleIdentity | null>(null);
  const finding = signal(false);
  const processing = signal(false);
  const compositionPhase = signal<"none" | "waiting" | "delayed" | "incomplete" | "complete">(
    "none",
  );
  const preview = signal<Preview | null>(null);
  const liveReading = signal<LiveReading | null>(null);
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
  let notifications: Notification["dataBase64"][] | undefined;
  let receivedNotification = false;
  let lastDevice: Device | undefined;
  let measurementTimer: ReturnType<typeof setTimeout> | undefined;
  let compositionTimer: ReturnType<typeof setTimeout> | undefined;
  function clearCompositionTimeout() {
    clearTimeout(compositionTimer);
    compositionTimer = undefined;
  }
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
      const detail = receivedNotification ? labels.measurementTimeout : labels.noSignal;
      halt();
      fail(detail);
    }, MEASUREMENT_TIMEOUT_MS);
  }
  const halt = () => {
    generation++;
    initialized = false;
    notifications = undefined;
    processing.set(false);
    receivedNotification = false;
    liveReading.set(null);
    clearTimeout(scanTimer);
    scanTimer = undefined;
    clearMeasurementTimeout();
    clearCompositionTimeout();
    compositionPhase.set(
      preview() ? (preview()?.measurement.metrics ? "complete" : "incomplete") : "none",
    );
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
    finding.set(true);
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
  async function connect(device?: Device) {
    if (busy() || preview() || state() === "connecting" || liveId) return;
    halt();
    finding.set(false);
    devices.set([]);
    const attempt = generation;
    message.set("");
    replacement.set(false);
    if (!scaleBle.available()) {
      fail(labels.unsupported);
      return;
    }
    state.set("connecting");
    try {
      const start = await scaleNative.begin(device);
      if (!isCurrent(attempt)) {
        void scaleNative.cancel(start.session_id).catch(() => {});
        return;
      }
      liveId = start.session_id;
      lastDevice = device;
      await scaleBle.connect(liveId, start.address);
      if (!isCurrent(attempt)) return;
      for (const [index, dataBase64] of start.commands.entries()) {
        if (index === start.commands.length - 1) notifications = [];
        await scaleBle.write(liveId, dataBase64);
        if (!isCurrent(attempt)) return;
      }
      initialized = true;
      state.set("measuring");
      awaitReading();
      if (device) {
        void scaleNative
          .remember(liveId)
          .then((saved) => {
            if (isCurrent(attempt) && saved) remembered.set(saved);
          })
          .catch(() => {});
      }
      void drainNotifications();
    } catch {
      if (isCurrent(attempt)) invalidate(labels.failed);
    }
  }
  async function save() {
    const reviewed = preview();
    if (!reviewed || busy() || processing()) return;
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

  async function remeasure() {
    if (busy() || processing() || !preview()) return;
    const id = liveId || preview()?.session_id;
    halt();
    const attempt = generation;
    busy.set(true);
    try {
      if (id) await scaleNative.cancel(id);
      if (disposed) return;
      preview.set(null);
      compositionPhase.set("none");
      replacement.set(false);
      message.set("");
      state.set("idle");
    } catch {
      if (!disposed) {
        message.set(labels.saveFailed);
        state.set("review");
      }
      return;
    } finally {
      if (!disposed) busy.set(false);
    }
    if (!isCurrent(attempt) || lifecycle() === "background") return;
    if (lastDevice || remembered()) await connect(lastDevice);
    else await scan();
  }

  function finishScan() {
    clearTimeout(scanTimer);
    scanTimer = undefined;
    scanId = "";
    state.set("idle");
    message.set(devices().length ? labels.stopped : labels.empty);
  }

  async function drainNotifications() {
    const queue = notifications;
    if (!initialized || !queue?.length || processing() || busy()) return;
    const id = liveId;
    const attempt = generation;
    processing.set(true);
    try {
      while (queue.length && isCurrent(attempt) && !busy()) {
        const packet = queue.shift();
        if (packet == null) {
          invalidate(labels.packet);
          return;
        }
        const update = await scaleNative.feed(id, packet);
        if (!isCurrent(attempt) || busy()) return;
        const result = update.preview;
        liveReading.set(update.reading);
        const previous = preview();
        if (!result || result.measurement.metrics) {
          clearCompositionTimeout();
          compositionPhase.set(result ? "complete" : "none");
        } else if (
          !previous ||
          previous.measurement.weight_grams !== result.measurement.weight_grams
        ) {
          clearCompositionTimeout();
          compositionPhase.set("waiting");
          compositionTimer = setTimeout(() => {
            compositionTimer = undefined;
            if (isCurrent(attempt) && compositionPhase() === "waiting") {
              compositionPhase.set("delayed");
            }
          }, COMPOSITION_NOTICE_MS);
        }
        if (!result || preview()?.token !== result.token) replacement.set(false);
        if (result) clearMeasurementTimeout();
        else awaitReading();
        preview.set(result);
        state.set(result ? "review" : "measuring");
        message.set("");
      }
    } catch {
      if (isCurrent(attempt) && !busy()) invalidate(labels.packet);
    } finally {
      if (isCurrent(attempt)) processing.set(false);
    }
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
          message.set(preview() ? labels.disconnected : labels.disconnectedEarly);
          state.set(preview() ? "review" : "failed");
        }
      }
    }),
    scaleBle.onNotification((event) => {
      if (!liveId || event.sessionId !== liveId || !notifications || busy()) return;
      if (notifications.length >= MAX_PENDING_NOTIFICATIONS) {
        invalidate(labels.packet);
        return;
      }
      receivedNotification = true;
      notifications.push(event.dataBase64);
      void drainNotifications();
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
          message.set(preview() ? labels.disconnected : "");
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
    let reconnect = false;
    try {
      const ready = await scaleNative.profileReady();
      if (disposed) return;
      profileReady.set(ready);
      const saved = await scaleNative.remembered().catch(() => null);
      const kept = await scaleNative.pending();
      if (disposed) return;
      remembered.set(saved);
      if (kept) {
        preview.set(kept);
        compositionPhase.set(kept.measurement.metrics ? "complete" : "incomplete");
        state.set("review");
        message.set(labels.draft);
      } else reconnect = ready && saved !== null;
    } catch {
      if (!disposed) fail(labels.failed);
    } finally {
      if (!disposed) profileLoaded.set(true);
    }
    if (reconnect && !disposed && state() === "idle" && lifecycle() !== "background") {
      await connect();
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
    remembered,
    finding,
    processing,
    compositionPhase,
    preview,
    liveReading,
    message,
    replacement,
    profileReady,
    profileLoaded,
    scan,
    connect,
    save,
    remeasure,
    leave,
    cancel,
    openProfile,
  };
}
