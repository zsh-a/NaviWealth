import { expect, open, test } from "nsh/test";
import type { App, HostMessage, HostOptions } from "nsh/test";

// Independently attributed captures from Mzdyl/ant-afu-welland-scale's
// test_protocol_and_bodycomp.py. They exercise the actual Rust decoder.
const STABLE = "rCmAaOLCAgAFQAAAAAAAAAAp1RE=";
const IMPEDANCE = "rCkCAAIFAdgBgGjiwgAAAAAp1g4=";
const PROFILE = { height_cm: 170, age_years: 23, sex: "male" };
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
): Promise<App> {
  const app = await open("..", {
    clock: manualClock ? {} : undefined,
    locale: "en-US",
    platform: "android",
    reducedMotion: true,
    width: 390,
    height: 844,
    storage: { "settings.v1": JSON.stringify(profile ? PROFILE : {}) },
    network: {},
    host: {
      params: { testMode: true },
      handlers: withHost
        ? { ...handlers, "ble.status": status, ...overrides }
        : { "ble.status": { available: false, enabled: false } },
    },
  });
  await app.waitFor("label:New entry");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("id:scale-panel");
  return app;
}
async function connect(app: App, waitForAcknowledgement = true): Promise<string> {
  const previousScans = calls(app, "ble.scan.start").length;
  const previousWrites = calls(app, "ble.write").length;
  await app.press("Find scale");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === previousScans + 1);
  const scanId = data(calls(app, "ble.scan.start")[previousScans]).sessionId;
  await app.host.send("ble.device", { ...DEVICE, sessionId: scanId });
  const pressed = app.press("label:Connect AFU-WL-TZ-A1");
  // The test server awaits a function handler while serving this press.
  // Pending-write tests deliberately keep that host reply unresolved.
  if (waitForAcknowledgement) await pressed;
  else void pressed.catch(() => {});
  await app.waitUntil(() => calls(app, "ble.write").length === previousWrites + 1);
  const connected = data(calls(app, "ble.connect")[previousWrites]);
  const write = data(calls(app, "ble.write")[previousWrites]);
  expect(write.sessionId).toBe(connected.sessionId);
  const command = decodeBase64(write.dataBase64 as string);
  expect(command.length).toBe(20);
  expect(command[0]).toBe(0xac);
  expect(command[1]).toBe(0x27);
  expect(command[9]).toBe(170);
  expect(command[12]).toBe(23);
  expect(command[13]).toBe(1);
  expect(command[18]).toBe(0xd0);
  expect(command[19]).toBe(command.slice(2, 19).reduce((sum, byte) => (sum + byte) & 255, 0));
  if (waitForAcknowledgement) {
    await app.waitFor("Stand still on the scale. Reading weight and impedance…");
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
  await app.waitFor("Save weight only");
  expect(app.shows("Confirm and save")).toBe(false);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  expect(app.shows("label:Weight 58.05 kg")).toBe(true);
  expect(app.texts().join(" ")).toContain("Estimated body fat");
  await packet(app, sessionId, IMPEDANCE);
  expect(app.count("id:scale-preview")).toBe(1);
  expect(calls(app, "ble.write").length).toBe(1);
  await app.press("Confirm and save");
  await app.waitFor("Measurement saved");
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

test("scale mixed: missing body profile offers existing Rust settings before any hardware calls", async () => {
  const app = await start(false);
  await app.waitFor("Open body profile");
  expect(app.shows("Find scale")).toBe(false);
  expect(app.host.calls().length).toBe(0);
  await app.press("Open body profile");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.waitFor("label:Height");
  await app.waitFor("label:Age");
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
  await app.waitFor("Find scale");
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
  await app.waitFor("Try again");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  await home(app);
  await app.waitFor("label:Weight, —");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Find scale");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("A previous measurement is kept on this device. Review it before saving.")).toBe(
    false,
  );
}, 30000);

test("scale mixed: notifications before initialization acknowledgement cannot create a save token", async () => {
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
  acknowledge({ written: true });
  await app.waitFor("Stand still on the scale. Reading weight and impedance…");
  expect(app.shows("id:scale-preview")).toBe(false);
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  await app.waitFor("Confirm and save");
  await app.press("Discard measurement");
  await app.waitFor("id:scale-panel", { state: "gone" });
  await app.press("label:Back");
  await app.waitFor("label:Weight, —");
}, 30000);

test("scale mixed: rejected initialization cannot leave a recoverable uninitialized draft", async () => {
  const app = await start(
    true,
    true,
    { available: true, enabled: true },
    {
      // The separate pending-ack test covers early notifications. Fail this
      // operation directly so the test server has no unresolved press/host RPC
      // when we navigate away from the failed connection.
      "ble.write": () => {
        throw new Error("Synthetic initialization write failure");
      },
    },
  );
  const sessionId = await connect(app, false);
  await app.waitFor("Try again");
  // Late notifications after initialization failure cannot revive the draft.
  await packet(app, sessionId, STABLE);
  await packet(app, sessionId, IMPEDANCE);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("id:scale-preview")).toBe(false);
  await home(app);
  await app.waitFor("label:Weight, —");
  await app.press("label:Settings");
  await app.scroll("Connect scale", 250);
  await app.press("Connect scale");
  await app.waitFor("Find scale");
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
}, 30000);

test("scale mixed: waiting for a stable weight times out and permits a fresh scan", async () => {
  const app = await start(true, true, { available: true, enabled: true }, {}, true);
  const sessionId = await connect(app);
  const clock = app.clock;
  if (!clock) throw new Error("Expected a manual clock");

  await clock.fastForward(30_000);
  await app.waitFor("No stable weight arrived. Step off the scale, wake it and try again.");
  await packet(app, sessionId, STABLE);
  expect(app.shows("id:scale-preview")).toBe(false);
  expect(calls(app, "ble.disconnect").map(data)).toEqual([{ sessionId }]);

  const previousScans = calls(app, "ble.scan.start").length;
  await app.press("Try again");
  await app.waitUntil(() => calls(app, "ble.scan.start").length === previousScans + 1);
}, 30000);
