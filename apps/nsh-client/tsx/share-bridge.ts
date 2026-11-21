import { Incoming } from "naviwealth/native";
import { host } from "nsh";

/**
 * Forwards each share the Android host copied (`share.received`; NSH keeps
 * it until this listener exists, so a share that launched the app arrives
 * too) to the Rust app, which opens it once: images and text as an unsent
 * capture draft, a statement in its review. Nothing is sent to a model here.
 */
export function forwardShares(): void {
  // Without a host (desktop development) the event never comes.
  host.on<unknown>("share.received", (shared) => {
    Incoming.receive(shared).catch(() => {
      // A malformed share opens nothing.
    });
  });
}
