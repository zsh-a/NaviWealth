import { expect, open, test } from "nsh/test";

// The Android host announces a copied share as `share.received`; the TSX
// entry forwards it to Rust, which opens it once and never sends it to a
// model. Text needs no copied file, so it exercises the whole bridge here.
async function start() {
  const app = await open("..", {
    locale: "en-US",
    platform: "android",
    reducedMotion: true,
    width: 390,
    height: 844,
    storage: {},
    network: {},
    host: { params: { testMode: true }, handlers: {} },
  });
  await app.waitFor("label:Conversation");
  return app;
}

test("share mixed: shared text opens an unsent conversation", async () => {
  const app = await start();
  await app.host.send("share.received", { text: "Taxi 18 yuan", files: [] });
  await app.waitFor("label:Message");
  await app.waitFor("text:Taxi 18 yuan");
  expect(app.shows("Review before saving")).toBe(false);
  expect(app.shows("Confirm and save")).toBe(false);
  expect(app.shows("Editing selected record")).toBe(false);
});

test("share mixed: an empty or malformed share opens nothing", async () => {
  const app = await start();
  await app.host.send("share.received", { files: "nope" });
  await app.host.send("share.received", { text: "", files: [] });
  await app.waitFor("text:/^Can't open what was shared/");
  expect(app.shows("label:Message")).toBe(false);
});

test("share mixed: a share waits while a page covers the home, then opens", async () => {
  const app = await start();
  await app.press("label:Settings");
  await app.waitFor("Devices & connections");
  await app.host.send("share.received", { text: "Parking 6 yuan", files: [] });
  await app.waitFor("Devices & connections");
  expect(app.shows("label:Message")).toBe(false);
  await app.press("label:Back");
  await app.waitFor("label:Message");
  await app.waitFor("text:Parking 6 yuan");
});
