import { expect, open, test } from "nsh/test";
import type { App, HostMessage, HostOptions } from "nsh/test";

// Independently attributed captures from Mzdyl/ant-afu-welland-scale's
// test_protocol_and_bodycomp.py. They exercise the actual Rust decoder.
const STABLE = "rCmAaOLCAgAFQAAAAAAAAAAp1RE=";
const IMPEDANCE = "rCkCAAIFAdgBgGjiwgAAAAAp1g4=";
const PROFILE = { height_cm: 170, age_years: 23, sex: "male" };
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
  await app.waitUntil(() => calls(app, "ble.write").length === previousWrites + 1);
  const connected = data(calls(app, "ble.connect")[previousWrites]);
  expect(connected.address).toBe(DEVICE.address);
  expect(calls(app, "ble.scan.start").length).toBe(previousScans + (direct ? 0 : 1));
  const write = data(calls(app, "ble.write")[previousWrites]);
  expect(write.sessionId).toBe(connected.sessionId);
  const command = decodeBase64(write.dataBase64 as string);
  expect(command.length).toBe(20);
  expect(command[0]).toBe(0xac);
  expect(command[1]).toBe(0x27);
  expect(command[2]).toBe(0x08);
  expect(command.slice(7, 18)).toEqual([0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  expect(command[18]).toBe(0xdf);
  expect(command[19]).toBe(command.slice(2, 19).reduce((sum, byte) => (sum + byte) & 255, 0));
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
  await packet(app, sessionId, IMPEDANCE);
  expect(app.count("id:scale-preview")).toBe(1);
  expect(calls(app, "ble.write").length).toBe(1);
  await app.press("id:scale-actions >> label:Confirm and save");
  await app.waitFor("Measurement saved");
  expect(app.count("id:scale-panel >> label:Close")).toBe(1);
  // Native callbacks queued after confirmation cannot recreate a saved draft.
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("id:scale-preview")).toBe(false);
  await home(app);
  await app.waitFor("label:Weight, 58.1 kg");
  expect(app.texts().join(" ")).toContain("Body fat");
  await app.press("label:Weight, 58.1 kg");
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
  await app.waitFor("label:Weight, —");
  expect(calls(app, "ble.disconnect").length).toBe(1);
  // The same existing Rust entry remains usable after TSX cancellation.
  await app.press("label:Weight, —");
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
  await app.waitFor("label:Weight, —");
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
  await app.waitFor("label:Weight, —");
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
  await app.waitFor("label:Weight, —");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("A previous measurement is kept on this device. Review it before saving.");
  expect(calls(app, "ble.connect").length).toBe(1);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:Weight, 58.1 kg");
}, 30000);

test("scale mixed: replacing a same-day measurement requires a second explicit confirmation", async () => {
  const app = await start();
  let sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
  await home(app);
  await app.waitFor("label:Weight, 58.1 kg");
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
  await app.waitFor("label:Weight, 61.0 kg");
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
  await app.waitFor("label:Weight, —");
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
  await app.waitFor("label:Weight, —");
}, 30000);

test("scale mixed: stable weight invites the owner to stay on for composition", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  await app.waitFor("Weight is stable. Stay on the scale a little longer.");
  expect(
    app.shows("No valid impedance reading is available. You can still save your weight."),
  ).toBe(false);
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
  await app.press("Measurement details");
  await app.waitFor("Estimated fat-free mass");
  expect(app.texts().join(" ")).toContain("51.20 kg");
  expect(app.texts().join(" ")).toContain("Segal BIA");
}, 30000);

test("scale mixed: composition timeout preserves a weight-only review without restarting for duplicates", async () => {
  const app = await start(true, true, undefined, {}, true);
  const sessionId = await connect(app);
  await packet(app, sessionId, STABLE);
  if (!app.clock) throw new Error("Expected a manual clock");
  await app.clock.fastForward(14_999);
  await packet(app, sessionId, STABLE);
  expect(app.shows("Reading body composition…")).toBe(true);
  await app.clock.fastForward(1);
  await app.waitFor("No valid impedance reading is available. You can still save your weight.");
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
  await app.waitFor("label:Weight, 58.1 kg");
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
  await app.waitFor("label:Weight, —");
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

test("scale mixed: notifications during initialization are replayed only after acknowledgement", async () => {
  let acknowledge: (value: unknown) => void = () => {
    throw new Error("Write has not started");
  };
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.write": () =>
        new Promise<unknown>((resolve) => {
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
  await app.waitFor("label:Weight, —");
}, 30000);

test("scale mixed: rejected initialization discards buffered readings and does not remember the scale", async () => {
  let acknowledge: (value: unknown) => void = () => {
    throw new Error("Write has not started");
  };
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      "ble.write": () =>
        new Promise<unknown>((resolve) => {
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
  await app.waitFor("label:Weight, —");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Find scale");
  expect(app.shows("id:scale-preview")).toBe(false);
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
