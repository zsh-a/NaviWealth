import { mount, signal, colorScheme, computed, host } from "nsh";
import { Sheet } from "nsh/base";
import { App, Scale } from "naviwealth/native";
import { ScalePanel } from "./tsx/ScalePanel";
import type { Palette } from "./tsx/scale-types";

function MixedApp() {
 const open = signal(false);
 const palette = computed(()=>Scale.palette(colorScheme()==="dark") as unknown as Palette);
 return <>
   <App testMode={host.params.testMode===true} scaleEnabled={true} onOpenScale={()=>open.set(true)}/>
   <Sheet open={open()} onOpenChange={event=>open.set(event.open)} closeOnSwipe
     popupStyle={{backgroundColor:palette().surface,borderTopLeftRadius:32,borderTopRightRadius:32}}
     backdropStyle={{backgroundColor:palette().scrim}}>
     <ScalePanel close={()=>open.set(false)}/>
   </Sheet>
 </>;
}
mount(MixedApp);
