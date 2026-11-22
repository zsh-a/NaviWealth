import { expect, open, test } from "nsh/test";
import type { App, HostMessage, HostOptions, OpenOptions } from "nsh/test";
import type { AlgorithmId, Preview, ScaleUpdate } from "../tsx/scale-types";

// Independently attributed captures from Mzdyl/ant-afu-welland-scale's
// test_protocol_and_bodycomp.py. They exercise the actual Rust decoder.
const STABLE = "rCmAaOLCAgAFQAAAAAAAAAAp1RE=";
const IMPEDANCE = "rCkCAAIFAdgBgGjiwgAAAAAp1g4=";
const PROFILE = { height_cm: 170, age_years: 23, sex: "male" as const };
const REMEMBERED_SCALE_KEY = "scale.remembered-device.v1";
const DEVICE = {
  address: "12:34:56:78:9A:BC",
  name: "AFU-WL-TZ-A1",
  rssi: -48,
  // Company ID 0x27AC is encoded separately by Android. The six device
  // bytes and observed protocol revision 2 follow it in the advertisement.
  manufacturerData: { "10156": "AQIDBAUGAg==" },
  serviceUuids: [],
  serviceData: {},
};
const handlers = {
  "ble.status": { available: true, enabled: true },
  "ble.scan.start": { started: true },
  "ble.scan.stop": { stopped: true },
  "ble.connect": { connected: true },
  "ble.disconnect": { disconnected: true },
  "ble.write": { written: true },
};
function calls(app: App, name: string): HostMessage[] {
  return app.host.calls().filter((call) => call.name === name);
}
function data(call: HostMessage): Record<string, unknown> {
  return call.data as Record<string, unknown>;
}
function decodeBase64(value: string): number[] {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let bits = 0,
    held = 0;
  const bytes: number[] = [];
  for (const char of value) {
    if (char === "=") break;
    const number = alphabet.indexOf(char);
    if (number < 0) throw new Error("Invalid base64 command");
    held = (held << 6) | number;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((held >> bits) & 255);
    }
  }
  return bytes;
}
async function start(
  profile = true,
  withHost = true,
  status: { available: boolean; enabled: boolean; permissionGranted?: boolean } = {
    available: true,
    enabled: true,
  },
  overrides: NonNullable<HostOptions["handlers"]> = {},
  manualClock = false,
  preferences: Record<string, string> = {},
  openScale = true,
  modules: OpenOptions["modules"] = undefined,
): Promise<App> {
  const app = await open("..", {
    clock: manualClock ? {} : undefined,
    locale: "en-US",
    platform: "android",
    reducedMotion: true,
    width: 390,
    height: 844,
    storage: { "settings.v1": JSON.stringify(profile ? PROFILE : {}), ...preferences },
    network: {},
    modules,
    host: {
      params: { testMode: true },
      handlers: withHost
        ? { ...handlers, "ble.status": status, ...overrides }
        : { "ble.status": { available: false, enabled: false } },
    },
  });
  await app.waitFor("label:New entry");
  if (!openScale) return app;
  await app.press("label:Settings");
  await app.waitFor("Devices & connections");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("id:scale-panel");
  return app;
}
async function connect(app: App, waitForAcknowledgement = true): Promise<string> {
  if (
    app.shows("Connecting to the scale…") ||
    app.shows("Connected. Step onto the scale and stand still.")
  ) {
    await app.waitFor("Connected. Step onto the scale and stand still.");
    const connected = calls(app, "ble.connect").at(-1);
    if (!connected) throw new Error("Expected the foreground auto-connection");
    return data(connected).sessionId as string;
  }
  const previousScans = calls(app, "ble.scan.start").length;
  const previousWrites = calls(app, "ble.write").length;
  const previousConnections = calls(app, "ble.connect").length;
  const direct = app.shows("Connect saved scale");
  let target = "Connect saved scale";
  if (!direct) {
    await app.press("Find scale");
    await app.waitUntil(() => calls(app, "ble.scan.start").length === previousScans + 1);
    const scanId = data(calls(app, "ble.scan.start")[previousScans]).sessionId;
    await app.host.send("ble.device", { ...DEVICE, sessionId: scanId });
    target = "label:Connect AFU-WL-TZ-A1";
  }
  const pressed = app.press(target);
  // The test server awaits a function handler while serving this press.
  // Pending-write tests deliberately keep that host reply unresolved.
  if (waitForAcknowledgement) await pressed;
  else void pressed.catch(() => {});
  await app.waitUntil(() => calls(app, "ble.write").length === previousWrites + 2);
  const connected = data(calls(app, "ble.connect")[previousConnections]);
  expect(connected.address).toBe(DEVICE.address);
  expect(calls(app, "ble.scan.start").length).toBe(previousScans + (direct ? 0 : 1));
  const write = data(calls(app, "ble.write")[previousWrites]);
  expect(write.sessionId).toBe(connected.sessionId);
  const command = decodeBase64(write.dataBase64 as string);
  expect(command.length).toBe(20);
  expect(command[0]).toBe(0xac);
  expect(command[1]).toBe(0x27);
  expect(command[2]).toBe(0x08);
  // The native bridge uses the host's time zone (UTC on CI, UTC+8 locally).
  const offsetQuarters = command[7] > 127 ? command[7] - 256 : command[7];
  expect(offsetQuarters >= -48 && offsetQuarters <= 56).toBe(true);
  expect(command.slice(8, 18)).toEqual([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  expect(command[18]).toBe(0xdf);
  expect(command[19]).toBe(command.slice(2, 19).reduce((sum, byte) => (sum + byte) & 255, 0));
  const profile = data(calls(app, "ble.write")[previousWrites + 1]);
  expect(profile.sessionId).toBe(connected.sessionId);
  const profileCommand = decodeBase64(profile.dataBase64 as string);
  expect(profileCommand.length).toBe(20);
  expect(profileCommand[6]).toBe(command[7]);
  expect(profileCommand[18]).toBe(0xd0);
  expect(profileCommand[16] & 1).toBe(1);
  expect(profileCommand[19]).toBe(
    profileCommand.slice(2, 19).reduce((sum, byte) => (sum + byte) & 255, 0),
  );
  if (waitForAcknowledgement) {
    await app.waitFor("Connected. Step onto the scale and stand still.");
  }
  return connected.sessionId as string;
}
async function packet(app: App, sessionId: string, dataBase64: string): Promise<void> {
  await app.host.send("ble.notification", { sessionId, dataBase64 });
}
async function home(app: App): Promise<void> {
  await app.press("id:scale-panel >> label:Close >> nth=0");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.press("label:Back");
  await app.waitFor("label:New entry");
}

async function chooseAlgorithm(app: App, name: string): Promise<void> {
  await app.waitFor("id:scale-algorithms");
  if (!app.shows("id:scale-algorithm-options")) {
    await app.press("id:scale-algorithms >> label:Choose estimation algorithm");
  }
  await app.press(`label:Choose estimation algorithm: ${name}`);
  await app.waitFor("Updating estimate…", { state: "gone" });
  await app.waitFor(`id:scale-algorithms >> text:${name}`);
}

function algorithmPreference(app: App): string {
  return JSON.parse(app.storage()["settings.v1"]).scale_algorithm ?? "segal";
}

// Brings content up by scrolling when the page still overflows. The Body
// profile page fits the test viewport in the Instrument layout, so it can
// have nothing to scroll; the harness' scroll fails hard in that case.
async function reveal(app: App, selector: string, distance: number) {
  try {
    await app.scroll(selector, distance);
  } catch (error) {
    if (!String(error).includes("cannot scroll by")) {
      throw error;
    }
  }
}

function deferred<T>() {
  let resolve: (value: T) => void = () => {
    throw new Error("Deferred response is not initialized");
  };
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

// These boundary tests hold native responses to reproduce interleavings that
// synchronous Rust operations normally hide. The existing integration cases
// below still exercise the real decoder, estimators and confirmed writes.
function raceBridge() {
  let current: Preview | null = null;
  const feeds: ReturnType<typeof deferred<ScaleUpdate>>[] = [];
  const pending: ReturnType<typeof deferred<Preview | null>>[] = [];
  const estimate = deferred<Preview>();
  const confirmed: string[] = [];
  let estimating = false;
  function draft(
    sessionId: string,
    token: string,
    id: AlgorithmId = "segal",
    grams = 58050,
  ): Preview {
    return {
      session_id: sessionId,
      token,
      day: "2026-11-19",
      measured_at_ms: 1795046400000,
      device: { id: DEVICE.address, name: DEVICE.name },
      existing_kg: null,
      algorithm: {
        id,
        name: { segal: "Segal BIA", wu2015: "Wu 2015", sun2003: "Sun 2003" }[id],
        description: "Controlled response ordering",
        experimental: id !== "segal",
      },
      algorithm_unavailable: false,
      measurement: {
        weight_grams: grams,
        resistance_ohm: null,
        metrics: null,
        profile: PROFILE,
        algorithm_version: {
          segal: "afu_wl_scale27_bia_v1",
          wu2015: "afu_wl_scale27_wu2015_ffm_v1",
          sun2003: "afu_wl_scale27_sun2003_ffm_tbw_v1",
        }[id],
      },
      summary: {
        bmi: null,
        fat_mass_kg: null,
        fat_free_mass_kg: null,
        muscle_mass_kg: null,
        water_mass_kg: null,
      },
    };
  }
  const modules: OpenOptions["modules"] = {
    "naviwealth/native": {
      "Scale.feed": () => {
        const response = deferred<ScaleUpdate>();
        feeds.push(response);
        return response.promise;
      },
      "Scale.pending": () => {
        if (!current) return null;
        const response = deferred<Preview | null>();
        pending.push(response);
        return response.promise;
      },
      "Scale.reestimate": (sessionId: string, token: string, id: AlgorithmId) => {
        expect(current?.token).toBe(token);
        current = draft(sessionId, "estimate-token", id);
        estimating = true;
        return estimate.promise;
      },
      "Scale.confirm": (sessionId: string, token: string) => {
        expect(current?.session_id).toBe(sessionId);
        expect(current?.token).toBe(token);
        confirmed.push(token);
        return null;
      },
    },
  };
  return {
    modules,
    feeds,
    pending,
    estimate,
    confirmed,
    draft,
    current: () => current!,
    estimating: () => estimating,
    publish: (reading: Preview) => {
      current = reading;
    },
  };
}

async function startRace() {
  const bridge = raceBridge();
  const app = await start(true, true, undefined, {}, false, {}, true, bridge.modules);
  const sessionId = await connect(app);
  const delivery = packet(app, sessionId, STABLE);
  await waitForNative(app, () => bridge.feeds.length === 1);
  const original = bridge.draft(sessionId, "original-token");
  bridge.publish(original);
  bridge.feeds[0].resolve({ preview: original, reading: null });
  await delivery;
  await app.waitFor("Save weight only");
  return { app, bridge, sessionId };
}

async function beginRaceEstimate(app: App, bridge: ReturnType<typeof raceBridge>) {
  await app.press("id:scale-algorithms >> label:Choose estimation algorithm");
  await app.scroll("label:Choose estimation algorithm: Sun 2003", 300);
  const selection = app.press("label:Choose estimation algorithm: Sun 2003");
  void selection.catch(() => {});
  await waitForNative(app, bridge.estimating);
  expect(app.enabled("Save weight only")).toBe(false);
  return { selection };
}

async function waitForNative(app: App, condition: () => boolean) {
  // Pump the headless transport without awaiting its idle acknowledgement:
  // the held native response is intentionally keeping the engine non-idle.
  void app.wait(0).catch(() => {});
  const deadline = Date.now() + 5000;
  while (!condition()) {
    if (Date.now() > deadline)
      throw new Error(`Native response ordering barrier timed out: ${condition}`);
    await new Promise<void>((resolve) => setTimeout(resolve, 5));
  }
}

async function dispatchLifecycle(app: App, state: "active" | "background") {
  // A native stand-in keeps the app non-idle. Dispatch the transition now;
  // await its idle acknowledgement only after releasing the held response.
  const transition = app.setLifecycle(state);
  void transition.catch(() => {});
  // Serve the transport for each transition while a native response is held,
  // before dispatching another lifecycle state that could overtake it.
  void app.wait(0).catch(() => {});
  // Let the lifecycle effect run while the controlled native response is held.
  await new Promise<void>((resolve) => setTimeout(resolve, 50));
  return { transition };
}

test("scale mixed: background during an in-flight feed recovers its newer token before saving", async () => {
  const { app, bridge, sessionId } = await startRace();
  const delivery = packet(app, sessionId, IMPEDANCE);
  await waitForNative(app, () => bridge.feeds.length === 2);
  const newer = bridge.draft(sessionId, "newer-feed-token", "segal", 61000);
  bridge.publish(newer);
  expect(app.enabled("Save weight only")).toBe(false);
  const transitions = [
    await dispatchLifecycle(app, "background"),
    await dispatchLifecycle(app, "active"),
  ];
  bridge.feeds[1].resolve({ preview: newer, reading: null });
  await waitForNative(app, () => bridge.pending.length === 1);
  expect(app.enabled("Save weight only")).toBe(false);
  bridge.pending[0].resolve(newer);
  await delivery;
  await Promise.all(transitions.map((item) => item.transition));
  await app.waitFor("label:Weight 61.00 kg");
  await app.waitUntil(() => app.enabled("Save weight only"));
  await app.press("Save weight only");
  await app.waitFor("Measurement saved");
  expect(bridge.confirmed).toEqual(["newer-feed-token"]);
}, 30000);

test("scale mixed: notifications arriving during an in-flight feed are retained and drained", async () => {
  const { app, bridge, sessionId } = await startRace();
  const first = packet(app, sessionId, STABLE);
  await waitForNative(app, () => bridge.feeds.length === 2);
  const second = packet(app, sessionId, IMPEDANCE);
  expect(bridge.feeds.length).toBe(2);
  expect(app.enabled("Save weight only")).toBe(false);
  bridge.feeds[1].resolve({ preview: bridge.current(), reading: null });
  await waitForNative(app, () => bridge.feeds.length === 3);
  const newer = bridge.draft(sessionId, "queued-feed-token", "segal", 61000);
  bridge.publish(newer);
  bridge.feeds[2].resolve({ preview: newer, reading: null });
  await first;
  await second;
  await app.waitFor("label:Weight 61.00 kg");
  await waitForNative(app, () => app.enabled("Save weight only"));
  await app.press("Save weight only");
  await app.waitFor("Measurement saved");
  expect(bridge.confirmed).toEqual(["queued-feed-token"]);
}, 30000);

test("scale mixed: repeatedly invalidated recovery safely clears an unverified preview", async () => {
  const { app, bridge } = await startRace();
  const { selection } = await beginRaceEstimate(app, bridge);
  const transitions = [
    await dispatchLifecycle(app, "background"),
    await dispatchLifecycle(app, "active"),
  ];
  bridge.estimate.resolve(bridge.current());
  for (let request = 0; request < 4; request++) {
    await waitForNative(app, () => bridge.pending.length === request + 1);
    expect(app.enabled("Save weight only")).toBe(false);
    transitions.push(
      await dispatchLifecycle(app, "background"),
      await dispatchLifecycle(app, "active"),
    );
    bridge.pending[request].resolve(bridge.current());
  }
  await selection;
  await Promise.all(transitions.map((item) => item.transition));
  await app.waitFor("id:scale-preview", { state: "gone" });
  expect(app.shows("Save weight only")).toBe(false);
  expect(bridge.confirmed).toEqual([]);
}, 30000);

test("scale mixed: three Rust models recompute one live draft without reconnecting or changing the default", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("label:Estimated body fat 11.8%");
  await chooseAlgorithm(app, "Wu 2015");
  await app.waitFor("label:Estimated body fat 10.6%");
  await app.press("Choose estimation algorithm");
  expect(app.texts().join(" ")).toContain("Changes this draft only.");
  await chooseAlgorithm(app, "Sun 2003");
  await app.waitFor("label:Estimated body fat 12.0%");
  // New impedance and weight packets must retain the draft's chosen model.
  await packet(app, sessionId, IMPEDANCE);
  await packet(app, sessionId, STABLE);
  await app.waitFor("label:Estimated body fat 12.0%");
  expect(app.shows("id:scale-algorithms >> text:Sun 2003")).toBe(true);
  expect(calls(app, "ble.connect").length).toBe(1);
  expect(calls(app, "ble.write").length).toBe(2);
  expect(calls(app, "ble.disconnect").length).toBe(0);
  expect(algorithmPreference(app)).toBe("segal");
  if (app.shows("Hide estimation algorithms")) await app.press("Hide estimation algorithms");
  expect(app.shows("id:scale-algorithms >> text:Sun 2003")).toBe(true);
  await app.scroll("Measurement details", 300);
  await app.press("Measurement details");
  await app.waitFor("text:Sun 2003 · sun2003_table5_male_ffm_tbw");
  await app.waitFor("text:170 cm · 23 years");
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.press("label:/^Body metrics, 58.1 kg, /");
  // The native overview reads the confirmed Measurement's algorithm version.
  await app.waitFor("text:Sun 2003 · Experimental");
  await app.waitFor("text:12.0%");
}, 30000);

test("scale mixed: pre-connection selection persists as the default and survives app restart", async () => {
  const app = await start();
  await chooseAlgorithm(app, "Wu 2015");
  expect(algorithmPreference(app)).toBe("wu2015");
  expect(app.host.calls()).toEqual([]);
  const preferences = app.storage();
  const relaunched = await start(true, true, undefined, {}, false, preferences);
  await relaunched.waitFor("id:scale-algorithms >> text:Wu 2015");
  const sessionId = await connect(relaunched);
  await packet(relaunched, sessionId, STABLE);
  await packet(relaunched, sessionId, IMPEDANCE);
  await relaunched.waitFor("label:Estimated body fat 10.6%");
  await relaunched.press("Confirm and save");
  await relaunched.waitFor("Measurement saved");
}, 30000);

test("scale mixed: retained draft keeps its chosen algorithm and frozen profile after native settings change", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await chooseAlgorithm(app, "Wu 2015");
  await home(app);
  await app.press("label:Settings");
  await app.press("Body profile");
  await app.clear("label:Height");
  await app.type("label:Height", "180");
  await reveal(app, "Estimation algorithm", 1000);
  await app.press("label:Estimation algorithm, Sun 2003");
  expect(algorithmPreference(app)).toBe("sun2003");
  await app.press("label:Back");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("id:scale-algorithms >> text:Wu 2015");
  await app.waitFor("label:Estimated body fat 10.6%");
  await app.scroll("Measurement details", 300);
  await app.press("Measurement details");
  await app.waitFor("text:170 cm · 23 years");
  expect(calls(app, "ble.connect").length).toBe(1);
  await app.scroll("Hide measurement details", -2000);
  await chooseAlgorithm(app, "Sun 2003");
  await app.waitFor("label:Estimated body fat 12.0%");
  await app.waitFor("text:170 cm · 23 years");
  expect(calls(app, "ble.write").length).toBe(2);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
}, 30000);

test("scale mixed: unsupported model is recoverable and never claims missing impedance or completion", async () => {
  const app = await start(true, true, undefined, {}, true, {
    "settings.v1": JSON.stringify({ ...PROFILE, age_years: 80, scale_algorithm: "wu2015" }),
  });
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Reading body composition…");
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("This algorithm cannot estimate this measurement");
  if (!app.clock) throw new Error("Expected a manual clock");
  await app.clock.fastForward(30_000);
  expect(app.shows("Your measurement is ready")).toBe(false);
  expect(app.shows("Reading body composition…")).toBe(false);
  expect(app.shows("Still waiting for body composition")).toBe(false);
  expect(app.shows("id:scale-composition")).toBe(false);
  expect(app.enabled("Save weight only")).toBe(true);
  await chooseAlgorithm(app, "Sun 2003");
  await app.waitFor("Your measurement is ready");
  await app.waitFor("label:Estimated body fat 12.0%");
  await chooseAlgorithm(app, "Wu 2015");
  await app.waitFor("This algorithm cannot estimate this measurement");
  expect(calls(app, "ble.connect").length).toBe(1);
  expect(calls(app, "ble.write").length).toBe(2);
  await app.press("Save weight only");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:/^Body metrics, 58.1 kg, /");
}, 30000);

test("scale mixed: changing the model resets replacement confirmation for the new review token", async () => {
  const app = await start();
  let sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.press("Confirm and save");
  await app.waitFor("Replace and save");
  await chooseAlgorithm(app, "Sun 2003");
  await app.waitFor("Confirm and save");
  expect(app.shows("Replace and save")).toBe(false);
  await app.press("Confirm and save");
  await app.waitFor("Replace and save");
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("Replace and save")).toBe(true);
  await app.press("Replace and save");
  await app.waitFor("Measurement saved");
}, 30000);

test("scale mixed: native Rust settings open TSX, Rust-generated command and confirmed measurement update Today", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("id:scale-actions >> label:Save weight only");
  expect(app.shows("Confirm and save")).toBe(false);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  expect(app.shows("label:Weight 58.05 kg")).toBe(true);
  expect(app.texts().join(" ")).toContain("Estimated body fat");
  expect(app.shows("id:scale-bmi >> text:20.1")).toBe(true);
  expect(app.shows("id:scale-fat >> text:6.85 kg")).toBe(true);
  expect(app.shows("id:scale-muscle >> text:48.59 kg")).toBe(true);
  expect(app.shows("id:scale-water >> text:35.82 kg")).toBe(true);
  expect(app.shows("id:scale-stages")).toBe(false);
  expect(app.shows("id:scale-evidence")).toBe(false);
  await app.scroll("Measurement details", 300);
  await app.press("Measurement details");
  await app.waitFor("text:Segal BIA");
  await app.waitFor("text:170 cm · 23 years");
  await app.press("Hide measurement details");
  expect(app.shows("id:scale-evidence")).toBe(false);
  await packet(app, sessionId, IMPEDANCE);
  expect(app.count("id:scale-preview")).toBe(1);
  expect(calls(app, "ble.write").length).toBe(2);
  await app.press("id:scale-actions >> label:Confirm and save");
  await app.waitFor("Measurement saved");
  expect(app.count("id:scale-panel >> label:Close")).toBe(1);
  // Native callbacks queued after confirmation cannot recreate a saved draft.
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("id:scale-preview")).toBe(false);
  await home(app);
  await app.waitFor("label:/^Body metrics, 58.1 kg, /");
  expect(app.texts().join(" ")).toContain("Body fat");
  await app.press("label:/^Body metrics, 58.1 kg, /");
  expect(app.texts().join(" ")).toContain("Scale estimate");
}, 30000);

test("scale mixed: cancelling a reviewed measurement writes no weight and ignores old notifications", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await app.press("Discard measurement");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.press("label:Back");
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("label:Body metrics, Log weight");
  expect(calls(app, "ble.disconnect").length).toBe(1);
  // The same existing Rust entry remains usable after TSX cancellation.
  await app.press("label:Body metrics, Log weight");
  await app.waitFor("Save weight");
}, 30000);

test("scale mixed: missing body profile opens the dedicated editor before any hardware calls", async () => {
  const app = await start(false);
  await app.waitFor("Open body profile");
  expect(app.shows("Find scale")).toBe(false);
  expect(app.host.calls().length).toBe(0);
  await app.press("Open body profile");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.waitFor("label:Height");
  await app.waitFor("label:Birth date");
  await app.press("label:Back");
  await app.waitFor("Devices & connections");
  expect(app.shows("label:Height")).toBe(false);
}, 30000);

test("scale mixed: unavailable hardware host gives a recoverable message without replacing existing Rust UI", async () => {
  const app = await start(true, false);
  await app.press("Find scale");
  await app.waitFor(
    "This environment cannot connect to a Bluetooth scale. Use the Android build with scale support.",
  );
  await home(app);
  await app.waitFor("label:Body metrics, Log weight");
}, 30000);

test("scale mixed: a matching device name without verified manufacturer metadata cannot connect or write", async () => {
  const app = await start();
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 1);
  const sessionId = data(calls(app, "ble.scan.start")[0]).sessionId;
  await app.host.send("ble.device", { ...DEVICE, manufacturerData: {}, sessionId });
  await app.press("label:Connect AFU-WL-TZ-A1");
  await app.waitFor("Try again");
  expect(calls(app, "ble.connect").length).toBe(0);
  expect(calls(app, "ble.write").length).toBe(0);
  await home(app);
  await app.waitFor("label:Body metrics, Log weight");
}, 30000);

test("scale mixed: unrelated service candidates cannot masquerade as AFU-WL scales", async () => {
  const app = await start();
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 1);
  const sessionId = data(calls(app, "ble.scan.start")[0]).sessionId;
  await app.host.send("ble.device", {
    ...DEVICE,
    sessionId,
    name: "Nearby scale",
    manufacturerData: {},
    serviceUuids: ["0000ffb0-0000-1000-8000-00805f9b34fb"],
  });
  expect(app.shows("label:Connect Nearby scale")).toBe(false);
  expect(calls(app, "ble.connect").length).toBe(0);
  expect(calls(app, "ble.write").length).toBe(0);
}, 30000);

test("scale mixed: closing keeps a local draft and reopening does not reconnect", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await home(app);
  await app.waitFor("label:Body metrics, Log weight");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("A previous measurement is kept on this device. Review it before saving.");
  expect(calls(app, "ble.connect").length).toBe(1);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:/^Body metrics, 58.1 kg, /");
}, 30000);

test("scale mixed: replacing a same-day measurement requires a second explicit confirmation", async () => {
  const app = await start();
  let sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:/^Body metrics, 58.1 kg, /");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Connected. Step onto the scale and stand still.");
  sessionId = await connect(app);
  // Same captured wire shape, original grams changed to 61000, checksum renewed.
  await packet(app, sessionId, "rCmAaO5IAgAFQAAAAAAAAAAp1QM=");
  await packet(app, sessionId, "rCkCAAIFAdgBgGjuSAAAAAAp1gA=");
  await app.waitFor("label:Weight 61.00 kg");
  await app.press("Confirm and save");
  await app.waitFor("Replace and save");
  expect(app.texts().join(" ")).toContain("58.1 kg");
  expect(app.shows("Measurement saved")).toBe(false);
  // The same reviewed token must keep the user's armed replacement choice.
  await packet(app, sessionId, "rCkCAAIFAdgBgGjuSAAAAAAp1gA=");
  expect(app.shows("Replace and save")).toBe(true);
  expect(app.shows("Confirm and save")).toBe(false);
  await app.press("Replace and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:/^Body metrics, 61.0 kg, /");
}, 30000);

test("scale mixed: first-use Android permission gate reaches native scan authorization", async () => {
  const app = await start(true, true, {
    available: true,
    enabled: false,
    permissionGranted: false,
  });
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 1);
  expect(calls(app, "ble.status").length).toBe(1);
  expect(app.texts().join(" ")).toContain("Looking for your scale");
  expect(app.shows("Try again")).toBe(false);
  await home(app);
  expect(calls(app, "ble.scan.stop").length).toBe(1);
  await app.waitFor("label:Body metrics, Log weight");
}, 30000);

test("scale mixed: dynamic weight invalidates the old preview until a new stable reading", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  // Clear only the stable flag in the captured weight; its low-five-bit
  // checksum is unchanged because bit 7 contributes zero modulo 32.
  await packet(app, sessionId, "rCkAaOLCAgAFQAAAAAAAAAAp1RE=");
  await app.waitFor("id:scale-preview", { state: "gone" });
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("Save weight only")).toBe(false);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Save weight only");
  expect(app.shows("Confirm and save")).toBe(false);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await app.press("Discard measurement");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.press("label:Back");
  await app.waitFor("label:Body metrics, Log weight");
}, 30000);

test("scale mixed: stable weight invites the owner to stay on for composition", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Weight is stable. Stay on the scale a little longer.");
  expect(app.shows("Body composition is unfinished")).toBe(false);
  expect(app.shows("Save weight only")).toBe(true);
  if (!app.clock) throw new Error("Expected a manual clock");
  await app.clock.fastForward(8_000);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await app.clock.fastForward(15_000);
  expect(app.shows("Confirm and save")).toBe(true);
  expect(app.shows("Reading body composition…")).toBe(false);
}, 30000);

test("scale mixed: moving readings update live without offering to save", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, "rCkAaOLCAgAFQAAAAAAAAAAp1RE=");
  await app.waitFor("label:Live weight 58.05 kg");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Save weight only")).toBe(false);
  await packet(app, sessionId, STABLE);
  await app.waitFor("label:Weight 58.05 kg");
  expect(app.shows("id:scale-live-reading")).toBe(false);
  await packet(app, sessionId, IMPEDANCE);
  await app.scroll("Measurement details", 300);
  await app.press("Measurement details");
  await app.waitFor("Estimated fat-free mass");
  expect(app.texts().join(" ")).toContain("51.20 kg");
  expect(app.texts().join(" ")).toContain("Segal BIA");
}, 30000);

test("scale mixed: a slow composition reading stays unfinished without restarting for duplicates", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  if (!app.clock) throw new Error("Expected a manual clock");
  await app.clock.fastForward(14_999);
  await packet(app, sessionId, STABLE);
  expect(app.shows("Reading body composition…")).toBe(true);
  await app.clock.fastForward(1);
  await app.waitFor("Still waiting for body composition");
  expect(app.shows("Reading body composition…")).toBe(false);
  expect(app.shows("Your measurement is ready")).toBe(false);
  expect(calls(app, "ble.disconnect").length).toBe(0);
  await app.press("Save weight only");
  await app.waitFor("Measurement saved");
}, 30000);

test("scale mixed: late composition completes and zero impedance cannot erase its save token", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  if (!app.clock) throw new Error("Expected a manual clock");
  await app.clock.fastForward(20_000);
  await app.waitFor("Still waiting for body composition");
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Your measurement is ready");
  await packet(app, sessionId, "rCkCAAAAAAABgGjiwgAAAAAp1g4=");
  expect(app.shows("Confirm and save")).toBe(true);
  expect(app.texts().join(" ")).toContain("Estimated body fat");
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
}, 30000);

test("scale mixed: an unfinished draft offers a fresh session and rejects old notifications", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Reading body composition…");
  await home(app);
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Body composition is unfinished");
  expect(app.shows("Your measurement is ready")).toBe(false);
  expect(calls(app, "ble.connect").length).toBe(1);
  await app.press("Measure again");
  await app.waitFor("Connected. Step onto the scale and stand still.");
  const nextId = await connect(app);
  expect(nextId).not.toBe(sessionId);
  expect(calls(app, "ble.scan.start").length).toBe(1);
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("id:scale-preview")).toBe(false);
  await packet(app, nextId, STABLE);
  await packet(app, nextId, IMPEDANCE);
  await app.waitFor("Confirm and save");
}, 30000);

test("scale mixed: disconnection with only weight is unfinished and still permits weight-only saving", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Reading body composition…");
  await app.host.send("ble.connection", { sessionId, state: "disconnected" });
  await app.waitFor("Body composition is unfinished");
  expect(app.shows("Your measurement is ready")).toBe(false);
  expect(app.shows("Reading body composition…")).toBe(false);
  await app.press("Save weight only");
  await app.waitFor("Measurement saved");
}, 30000);

test("scale mixed: background disconnect keeps a completed review and ignores late callbacks", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await app.setLifecycle("background");
  await app.waitUntil(() => calls(app, "ble.disconnect").length === 1);
  // A late in-flight unstable reading belongs to the retired hardware session.
  await packet(app, sessionId, "rCkAaOLCAgAFQAAAAAAAAAAp1RE=");
  await app.host.send("ble.connection", { sessionId, state: "disconnected" });
  await app.setLifecycle("active");
  await app.waitFor("Confirm and save");
  expect(app.shows("label:Weight 58.05 kg")).toBe(true);
  expect(calls(app, "ble.connect").length).toBe(1);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:/^Body metrics, 58.1 kg, /");
}, 30000);

test("scale mixed: transient inactive permission UI does not cancel scanning", async () => {
  const app = await start(true, true, {
    available: true,
    enabled: false,
    permissionGranted: false,
  });
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 1);
  const scanId = data(calls(app, "ble.scan.start")[0]).sessionId;
  // Android's permission dialog temporarily makes the app inactive, not background.
  await app.setLifecycle("inactive");
  expect(calls(app, "ble.scan.stop").length).toBe(0);
  await app.setLifecycle("active");
  await app.host.send("ble.device", { ...DEVICE, sessionId: scanId });
  await app.waitFor("label:Connect AFU-WL-TZ-A1");
  expect(calls(app, "ble.scan.start").length).toBe(1);
  await home(app);
  expect(calls(app, "ble.scan.stop").length).toBe(1);
}, 30000);

test("scale mixed: oversized malformed evidence removes the retained Rust preview", async () => {
  const app = await start();
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await packet(app, sessionId, "A".repeat(260));
  await app.waitFor("Connect saved scale");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  await home(app);
  await app.waitFor("label:Body metrics, Log weight");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Connected. Step onto the scale and stand still.");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("A previous measurement is kept on this device. Review it before saving.")).toBe(
    false,
  );
}, 30000);

test("scale mixed: notifications during profile initialization are replayed only after both writes succeed", async () => {
  let initializationWrites = 0;
  let acknowledge: (value: unknown) => void = () => {
    throw new Error("Write has not started");
  };
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.write": () =>
        ++initializationWrites === 1
          ? { written: true }
          : new Promise<unknown>((resolve) => {
              acknowledge = resolve;
            }),
    },
  );
  const sessionId = await connect(app, false);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("Save weight only")).toBe(false);
  expect(app.storage()[REMEMBERED_SCALE_KEY]).toBe(undefined);
  acknowledge({ written: true });
  await app.waitFor("Confirm and save");
  await app.press("Discard measurement");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.press("label:Back");
  await app.waitFor("label:Body metrics, Log weight");
}, 30000);

test("scale mixed: rejected profile after clock sync discards buffered readings and does not remember the scale", async () => {
  let initializationWrites = 0;
  let acknowledge: (value: unknown) => void = () => {
    throw new Error("Write has not started");
  };
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.write": () =>
        ++initializationWrites === 1
          ? { written: true }
          : new Promise<unknown>((resolve) => {
              acknowledge = resolve;
            }),
    },
  );
  const sessionId = await connect(app, false);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  acknowledge({ written: false });
  await app.waitFor("Try again");
  // Late notifications after initialization failure cannot revive the draft.
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.storage()[REMEMBERED_SCALE_KEY]).toBe(undefined);
  await home(app);
  await app.waitFor("label:Body metrics, Log weight");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Find scale");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
}, 30000);

test("scale mixed: failed clock synchronization never sends the profile or remembers the scale", async () => {
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.write": { written: false },
    },
  );
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 1);
  const scanId = data(calls(app, "ble.scan.start")[0]).sessionId;
  await app.host.send("ble.device", { ...DEVICE, sessionId: scanId });
  await app.press("label:Connect AFU-WL-TZ-A1");
  await app.waitFor("Try again");
  expect(calls(app, "ble.write").length).toBe(1);
  expect(app.storage()[REMEMBERED_SCALE_KEY]).toBe(undefined);
  expect(app.shows("Confirm and save")).toBe(false);
}, 30000);

test("scale mixed: opening measurement reconnects the saved scale without scanning", async () => {
  const app = await start();
  const previousSession = await connect(app);
  await app.waitUntil(() => !!app.storage()[REMEMBERED_SCALE_KEY]);
  const encoded = app.storage()[REMEMBERED_SCALE_KEY];
  expect(JSON.parse(encoded)).toEqual({
    device: { id: DEVICE.address, name: DEVICE.name },
    identity: { device_type: 0x27, protocol_ver: 2 },
  });
  const relaunched = await start(
    true,
    true,
    undefined,
    {},
    false,
    {
      [REMEMBERED_SCALE_KEY]: encoded,
    },
    false,
  );
  expect(relaunched.host.calls()).toEqual([]);
  await relaunched.press("label:Settings");
  await relaunched.scroll("Connect scale", 250);
  await relaunched.press("Connect scale");
  await relaunched.waitFor("Connected. Step onto the scale and stand still.");
  expect(calls(relaunched, "ble.connect").length).toBe(1);
  expect(await connect(relaunched)).not.toBe(previousSession);
  expect(calls(relaunched, "ble.scan.start")).toEqual([]);
}, 30000);

test("scale mixed: no notification times out and permits direct retry without rescanning", async () => {
  const app = await start(true, true, { available: true, enabled: true }, {}, true);
  const sessionId = await connect(app);
  const clock = app.clock;
  if (!clock) throw new Error("Expected a manual clock");

  await clock.fastForward(30_000);
  await app.waitFor(
    "Connected, but the scale sent no readings. Wake it and reconnect, then step on when prompted.",
  );
  await packet(app, sessionId, STABLE);
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(calls(app, "ble.disconnect").map(data)).toEqual([{ sessionId }]);

  expect(await connect(app)).not.toBe(sessionId);
  expect(calls(app, "ble.scan.start").length).toBe(1);
}, 30000);

test("scale mixed: a failed saved-scale connection offers a fresh scan", async () => {
  let attempts = 0;
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.connect": () => ({ connected: ++attempts === 1 }),
    },
    true,
  );
  const sessionId = await connect(app);
  await packet(app, sessionId, "rCkAaOLCAgAFQAAAAAAAAAAp1RE=");
  const clock = app.clock;
  if (!clock) throw new Error("Expected a manual clock");
  await clock.fastForward(30_000);
  await app.waitFor(
    "No stable weight arrived. Step off, reconnect and wait for the prompt before stepping on again.",
  );
  await app.press("Connect saved scale");
  await app.waitFor(
    "Could not finish the measurement. Check Bluetooth, precise-location and nearby-device permissions, then wake the scale and retry.",
  );
  expect(calls(app, "ble.scan.start").length).toBe(1);
  await app.press("Find another scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === 2);
}, 30000);
