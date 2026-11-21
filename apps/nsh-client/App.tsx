import { mount, signal, colorScheme, computed, host } from "nsh";
import { Sheet } from "nsh/base";
import { App } from "naviwealth/native";
import { ScalePanel } from "./tsx/ScalePanel";
import { scaleNative } from "./tsx/scale-bridge";
import { forwardShares } from "./tsx/share-bridge";

function MixedApp() {
  forwardShares();
  const open = signal(false);
  const scaleBusy = signal(false);
  const palette = computed(() => scaleNative.palette(colorScheme() === "dark"));
  return (
    <>
      <App
        testMode={host.params.testMode === true}
        scaleEnabled={true}
        onOpenScale={() => open.set(true)}
      />
      <Sheet
        open={open()}
        onOpenChange={(event) => {
          if (!scaleBusy()) open.set(event.open);
        }}
        closeOnEscape={!scaleBusy()}
        closeOnBackdropPress={!scaleBusy()}
        closeOnSwipe={!scaleBusy()}
        popupStyle={{
          backgroundColor: palette().surface,
          borderTopLeftRadius: 32,
          borderTopRightRadius: 32,
        }}
        backdropStyle={{ backgroundColor: palette().scrim }}
      >
        <ScalePanel close={() => open.set(false)} busy={scaleBusy} />
      </Sheet>
    </>
  );
}
mount(MixedApp);
