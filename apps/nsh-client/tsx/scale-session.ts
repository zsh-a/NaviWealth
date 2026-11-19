import { cleanup, effect, lifecycle, signal, untracked } from "nsh";
import type { Signal } from "nsh";
import { scaleBle, scaleNative } from "./scale-bridge";
import type { ScaleCopy } from "./scale-copy";
import type {
  AlgorithmId,
  AlgorithmOption,
  Device,
  LiveReading,
  Notification,
  Preview,
  ScaleIdentity,
} from "./scale-types";

const SCAN_TIMEOUT_MS = 12_000;
const MEASUREMENT_TIMEOUT_MS = 30_000;
const COMPOSITION_NOTICE_MS = 15_000;
const MAX_DEVICES = 16;
const MAX_PENDING_NOTIFICATIONS = 64;
const MAX_RECOVERY_ATTEMPTS = 4;

export function createScaleSession(labels: ScaleCopy, close: () => void, busy: Signal<boolean>) {
  const state = signal<
    "idle" | "scanning" | "connecting" | "measuring" | "review" | "failed" | "saved"
  >("idle");
  const devices = signal<Device[]>([]);
  const remembered = signal<ScaleIdentity | null>(null);
  const finding = signal(false);
  const processing = signal(false);
  const recalculating = signal(false);
  const algorithms = signal<AlgorithmOption[]>([]);
  const selectedAlgorithm = signal<AlgorithmId>("segal");
  const activeAlgorithm = signal<AlgorithmOption | null>(null);
  const compositionPhase = signal<
    "none" | "waiting" | "delayed" | "incomplete" | "complete" | "unavailable"
  >("none");
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
    // The drain owns processing/busy until an in-flight feed has settled and
    // its authoritative draft has been recovered. Pausing BLE cannot unlock it.
    receivedNotification = false;
    liveReading.set(null);
    clearTimeout(scanTimer);
    scanTimer = undefined;
    clearMeasurementTimeout();
    clearCompositionTimeout();
    compositionPhase.set(preview() ? finishedPhase(preview()!) : "none");
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
  function finishedPhase(reading: Preview) {
    return reading.algorithm_unavailable
      ? "unavailable"
      : reading.measurement.metrics
        ? "complete"
        : "incomplete";
  }
  function acceptPreview(result: Preview | null, attempt: number, live: boolean) {
    const previous = preview();
    if (!result || result.algorithm_unavailable || result.measurement.metrics || !live) {
      clearCompositionTimeout();
      compositionPhase.set(result ? finishedPhase(result) : "none");
    } else if (
      !previous ||
      previous.measurement.weight_grams !== result.measurement.weight_grams ||
      compositionPhase() === "unavailable" ||
      compositionPhase() === "complete"
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
    if (!result || previous?.token !== result.token) replacement.set(false);
    if (result) {
      clearMeasurementTimeout();
      activeAlgorithm.set(result.algorithm);
    } else if (live) awaitReading();
    preview.set(result);
    state.set(result ? "review" : "measuring");
  }

  function clearUnverifiedPreview() {
    preview.set(null);
    replacement.set(false);
    halt();
    fail(labels.stale);
  }

  async function recoverPreview(sessionId: string) {
    for (let retry = 0; retry < MAX_RECOVERY_ATTEMPTS && !disposed; retry++) {
      const attempt = generation;
      try {
        const kept = await scaleNative.pending();
        if (disposed) return;
        // Another pause may have happened while this snapshot was in flight.
        // Keep confirmation locked and read again against the new generation.
        if (!isCurrent(attempt)) continue;
        if (kept?.session_id === sessionId) {
          acceptPreview(kept, attempt, !!liveId && initialized);
        } else {
          clearUnverifiedPreview();
        }
        return;
      } catch {
        if (disposed) return;
        if (!isCurrent(attempt)) continue;
        break;
      }
    }
    // Repeated lifecycle changes or failed storage reads must never expose an
    // old review token. The persisted draft can still be reopened later.
    if (!disposed) clearUnverifiedPreview();
  }

  async function recoverPreference() {
    for (let retry = 0; retry < MAX_RECOVERY_ATTEMPTS && !disposed; retry++) {
      const attempt = generation;
      try {
        const config = await scaleNative.algorithms();
        if (disposed) return;
        if (!isCurrent(attempt)) continue;
        selectedAlgorithm.set(config.selected);
        activeAlgorithm.set(null);
        return;
      } catch {
        if (disposed) return;
        if (!isCurrent(attempt)) continue;
        break;
      }
    }
    if (!disposed) clearUnverifiedPreview();
  }

  async function chooseAlgorithm(id: AlgorithmId) {
    if (busy() || processing() || !profileLoaded() || recalculating()) return;
    const reviewed = preview();
    if (!reviewed && (state() === "connecting" || state() === "measuring")) return;
    const currentId = reviewed?.algorithm.id ?? activeAlgorithm()?.id ?? selectedAlgorithm();
    if (id === currentId || !algorithms().some((option) => option.id === id)) return;
    const attempt = generation;
    let needsRecovery = false;
    // Lock confirmation/dismissal while Rust rotates this draft's review token.
    // Notifications remain queued, and no BLE operations are performed here.
    busy.set(true);
    recalculating.set(true);
    replacement.set(false);
    message.set("");
    try {
      if (reviewed) {
        const result = await scaleNative.reestimate(reviewed.session_id, reviewed.token, id);
        if (!isCurrent(attempt) || preview()?.token !== reviewed.token) return;
        if (
          result.day !== reviewed.day ||
          result.measured_at_ms !== reviewed.measured_at_ms ||
          result.measurement.weight_grams !== reviewed.measurement.weight_grams ||
          result.measurement.profile.height_cm !== reviewed.measurement.profile.height_cm ||
          result.measurement.profile.age_years !== reviewed.measurement.profile.age_years ||
          result.measurement.profile.sex !== reviewed.measurement.profile.sex
        ) {
          throw new Error("invalid_scale_reestimate_snapshot");
        }
        acceptPreview(result, attempt, !!liveId && initialized);
      } else {
        await scaleNative.setAlgorithm(id);
        if (!isCurrent(attempt) || preview()) return;
        selectedAlgorithm.set(id);
        activeAlgorithm.set(null);
      }
    } catch {
      if (isCurrent(attempt)) message.set(labels.algorithmFailed);
      // A response validation failure may follow a successful atomic rotation.
      // Reload the authoritative draft before offering confirmation again.
      needsRecovery = reviewed !== null;
    } finally {
      // Backgrounding may pause BLE during the request. Refresh its rotated
      // token instead of reusing the preview that preceded recalculation.
      if (!disposed && (needsRecovery || attempt !== generation)) {
        if (reviewed) {
          // Invalid packets may have explicitly quarantined/cleared the draft
          // during recalculation. Do not resurrect that rejected preview.
          if (preview()?.session_id === reviewed.session_id)
            await recoverPreview(reviewed.session_id);
        } else {
          await recoverPreference();
        }
      }
      if (!disposed) {
        recalculating.set(false);
        busy.set(false);
        void drainNotifications();
      }
    }
  }
  async function scan() {
    if (busy() || preview() || state() === "scanning") return;
    halt();
    finding.set(true);
    replacement.set(false);
    activeAlgorithm.set(null);
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
    activeAlgorithm.set(algorithms().find((option) => option.id === selectedAlgorithm()) ?? null);
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
    busy.set(true);
    try {
      while (queue.length && isCurrent(attempt)) {
        const packet = queue.shift();
        if (packet == null) {
          invalidate(labels.packet);
          return;
        }
        const update = await scaleNative.feed(id, packet);
        if (!isCurrent(attempt)) return;
        const result = update.preview;
        liveReading.set(update.reading);
        acceptPreview(result, attempt, true);
        message.set("");
      }
    } catch {
      if (isCurrent(attempt)) invalidate(labels.packet);
    } finally {
      if (!disposed && attempt !== generation && state() !== "failed") {
        await recoverPreview(id);
      }
      if (!disposed) {
        processing.set(false);
        busy.set(false);
      }
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
      if (
        !liveId ||
        event.sessionId !== liveId ||
        !notifications ||
        (busy() && !recalculating() && !processing())
      )
        return;
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
      const config = await scaleNative.algorithms();
      if (disposed) return;
      algorithms.set(config.options);
      selectedAlgorithm.set(config.selected);
      const ready = await scaleNative.profileReady();
      if (disposed) return;
      profileReady.set(ready);
      const saved = await scaleNative.remembered().catch(() => null);
      const kept = await scaleNative.pending();
      if (disposed) return;
      remembered.set(saved);
      if (kept) {
        preview.set(kept);
        activeAlgorithm.set(kept.algorithm);
        compositionPhase.set(finishedPhase(kept));
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
    recalculating,
    algorithms,
    selectedAlgorithm,
    activeAlgorithm,
    chooseAlgorithm,
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
