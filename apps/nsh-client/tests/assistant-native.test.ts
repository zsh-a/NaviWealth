import { expect, open, test } from "nsh/test";

test("Assistant native visual", async () => {
  for (const colorScheme of ["light", "dark"] as const) {
    const app = await open("..", {
      locale: "en-US",
      width: colorScheme === "light" ? 390 : 360,
      height: colorScheme === "light" ? 844 : 640,
      colorScheme,
      reducedMotion: true,
      network: {},
      host: { params: { testMode: true } },
    });
    await app.waitFor("label:New entry");
    await app.press("text:Assistant");
    await app.waitFor("What would you like to work on?");
    await app.screenshot(`.nsh/assistant-${colorScheme}-chat.png`);
    await app.press("text:Memory & search");
    await app.type("label:Memory text", "Prefer walking for trips under 2 km.");
    await app.press("text:Save memory");
    await app.waitFor("Prefer walking for trips under 2 km.");
    expect(app.shows("Saved memories")).toBe(true);
    await app.screenshot(`.nsh/assistant-${colorScheme}-memory.png`);
  }
});
