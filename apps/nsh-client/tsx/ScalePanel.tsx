import { cleanup, colorScheme, computed, host, signal, Text, View, Scroll, lifecycle, effect, windowSize, locale, untracked } from "nsh";
import { Button } from "nsh/base";
import { Scale } from "naviwealth/native";
import { copy } from "./scale-copy";
import type { Connection, Device, Notification, Palette, Preview, Start } from "./scale-types";

export function ScalePanel(props:{close:()=>void}) {
 const c = copy[locale().toLowerCase().startsWith("zh")?"zh":"en"];
 const palette = computed(() => Scale.palette(colorScheme()==="dark") as unknown as Palette);
 const state = signal<"idle"|"scanning"|"connecting"|"measuring"|"review"|"failed"|"saved">("idle");
 const devices = signal<Device[]>([]), preview = signal<Preview|null>(null), message = signal("");
 const replacement = signal(false), saving = signal(false);
 const profileReady = signal(false);
 let liveId = "", scanId = "", generation = 0, scanTimer:ReturnType<typeof setTimeout>|undefined;
 let disposed = false, initialized = false;
 const textStyle = () => ({fontSize:16,lineHeight:23,color:palette().ink});
 const noteStyle = () => ({fontSize:14,lineHeight:21,color:palette().muted});
 const halt = () => {
   generation++; initialized=false;
   if(scanTimer) clearTimeout(scanTimer);
   const scan=scanId; scanId="";
   const live=liveId; liveId="";
   if(scan) void host.call("ble.scan.stop",{sessionId:scan}).catch(()=>{});
   if(live) { void Scale.pause(live).catch(()=>{}); void host.call("ble.disconnect",{sessionId:live}).catch(()=>{}); }
 };
 const leave = () => { if(saving()) return; halt(); props.close(); };
 const cancel = async () => {
   if(saving()) return false;
   const id=liveId || preview()?.session_id;
   halt();
   try {
     if(id) await Scale.cancel(id);
     if(!disposed) props.close();
     return true;
   } catch {
     if(!disposed) {message.set(c.saveFailed);state.set(preview()?"review":"failed");}
     return false;
   }
 };
 const invalidate = (text:string) => {
   const id=liveId || preview()?.session_id;
   preview.set(null); replacement.set(false); halt();
   if(id) void Scale.cancel(id).catch(()=>{});
   fail(text);
 };
 function fail(text:string) { message.set(text); state.set("failed"); }
 function Action(p:{label:string;run:()=>void;primary?:boolean;disabled?:boolean}) {
   return <Button accessibilityLabel={p.label} disabled={p.disabled} onPress={p.run}
     style={{minHeight:50,paddingHorizontal:20,paddingVertical:12,borderRadius:25,alignItems:"center",justifyContent:"center",backgroundColor:p.primary?palette().ink:palette().well}}>
       <Text style={{fontSize:16,lineHeight:23,fontWeight:600,color:p.primary?palette().onAction:palette().ink}}>{p.label}</Text>
     </Button>;
 }
 async function scan() {
   if(saving()) return;
   const prior=preview()?.session_id; halt(); if(prior) {void Scale.cancel(prior).catch(()=>{});}
   preview.set(null); replacement.set(false); devices.set([]);message.set("");
   const attempt=generation;
   scanId=`scan-${Date.now()}-${attempt}`;
   if(!host.available()) { fail(c.unsupported); return; }
   state.set("scanning");
   try {
     const status=await host.call<{available:boolean;enabled:boolean;permissionGranted?:boolean}>("ble.status",{});
     if(disposed||attempt!==generation) return;
     if(!status.available) {fail(c.unsupported);return;}
     if(status.permissionGranted===true&&!status.enabled) {fail(c.failed);return;}
     await host.call("ble.scan.start",{sessionId:scanId,timeoutMs:12000},{timeout:60000});
     if(disposed||attempt!==generation) return;
     scanTimer=setTimeout(()=>{
       if(attempt!==generation||disposed) return;
       const id=scanId;scanId="";void host.call("ble.scan.stop",{sessionId:id}).catch(()=>{});
       state.set("idle");message.set(devices().length?c.stopped:c.empty);
     },12500);
   } catch { if(!disposed&&attempt===generation) {halt();fail(c.failed);} }
 }
 async function connect(device:Device) {
   if(saving()||state()==="connecting"||liveId) return;
   halt();const attempt=generation;
   preview.set(null);message.set("");replacement.set(false);state.set("connecting");
   try {
     const start=await Scale.begin(device) as unknown as Start;
     if(disposed||attempt!==generation) {void Scale.cancel(start.session_id).catch(()=>{});return;}
     liveId=start.session_id;
     await host.call("ble.connect",{sessionId:liveId,address:device.address},{timeout:30000});
     if(disposed||attempt!==generation) return;
     for(const dataBase64 of start.commands) {
       await host.call("ble.write",{sessionId:liveId,dataBase64},{timeout:15000});
       if(disposed||attempt!==generation) return;
     }
     initialized=true;
     state.set("measuring");
   } catch { if(!disposed&&attempt===generation) invalidate(c.failed); }
 }
 async function save() {
   const reviewed=preview();if(!reviewed||saving())return;
   // A paused/reopened review is valid without a connection. A live attempt
   // must finish its profile/time initialization before it can be confirmed.
   if(liveId&&!initialized) return;
   if(reviewed.existing_kg!==null&&!replacement()) {replacement.set(true);return;}
   saving.set(true);
   try {
     await Scale.confirm(reviewed.session_id,reviewed.token,replacement());
     if(disposed) return;
     halt(); preview.set(null);message.set(c.saved);state.set("saved");
   } catch(error) {
     if(disposed) return;
     const code=error instanceof Error?error.message:String(error);
     if(code==="storage_unavailable"||code.endsWith(": storage_unavailable")) {
       // Rust rolled back the transaction and retained this exact draft.
       halt();message.set(c.saveFailed);state.set("review");
     } else {
       preview.set(null);replacement.set(false);halt();message.set(c.stale);state.set("failed");
     }
   } finally {if(!disposed)saving.set(false);}
 }

 const stops = [
   host.on<unknown>("ble.device",v=>{
     if(!v||typeof v!=="object")return;const d=v as Device;
     if(d.sessionId!==scanId||typeof d.address!=="string"||typeof d.name!=="string"||!d.name.startsWith("AFU-WL"))return;
     devices.set([...devices().filter(x=>x.address!==d.address),d].slice(0,16));
   }),
   host.on<Connection>("ble.connection",e=>{
     if(e.sessionId===scanId&&e.state==="scan_stopped") {state.set("idle");message.set(devices().length?c.stopped:c.empty);return;}
     if(e.sessionId!==liveId)return;
     if(e.state==="disconnected") {
       if(!initialized) {invalidate(c.failed);return;}
       const id=liveId;liveId="";initialized=false;generation++;void Scale.pause(id).catch(()=>{});
       if(!saving()) {message.set(c.disconnected);state.set(preview()?"review":"failed");}
     }
   }),
   host.on<Notification>("ble.notification",async e=>{
     if(!liveId||e.sessionId!==liveId||!initialized||saving())return;
     if(typeof e.dataBase64!=="string"||e.dataBase64.length>256){invalidate(c.packet);return;}
     const id=liveId, attempt=generation;
     try { const result=await Scale.feed(id,e.dataBase64) as unknown as Preview|null;
       if(disposed||attempt!==generation||id!==liveId||saving()) return;
       const previous=preview();
       if(!result||previous?.session_id!==result.session_id||previous?.token!==result.token) replacement.set(false);
       preview.set(result);state.set(result?"review":"measuring");message.set("");
     } catch {if(disposed||attempt!==generation||saving())return;invalidate(c.packet);}
   }),
   host.on<{sessionId:string}>("ble.error",e=>{
     if(e.sessionId!==liveId&&e.sessionId!==scanId)return;
     if(liveId&&!initialized) {invalidate(c.failed);return;}
     halt();if(!saving())fail(c.failed);
   }),
 ];
 // A runtime permission dialog makes Android inactive, not backgrounded.
 // Keep that explicit permission request alive; native onStop still closes BLE.
 effect(()=>{if(lifecycle()==="background") untracked(()=>{halt();if(!saving()){message.set(c.disconnected);state.set(preview()?"review":"idle");}});});
 cleanup(()=>{disposed=true;halt();stops.forEach(stop=>stop());});
 // Read saved evidence only after the Rust root initialized its database.
 void (async()=>{
   try {const ready=await Scale.profileReady();if(!disposed)profileReady.set(ready);
     const initial=generation;
     const kept=await Scale.pending() as unknown as Preview|null;
     if(!disposed&&initial===generation&&kept){preview.set(kept);state.set("review");message.set(c.draft);}
   } catch {if(!disposed)fail(c.failed);}
 })();
 return <View testID="scale-panel" style={{maxHeight:windowSize().height*0.85,paddingTop:20,paddingBottom:"calc(env(safe-area-inset-bottom) + 20px)",paddingHorizontal:20,gap:16}}>
   <View style={{flexDirection:"row",alignItems:"center",justifyContent:"space-between",gap:12}}>
     <Text role="header" style={{fontSize:20,lineHeight:26,fontWeight:600,color:palette().ink,flex:1}}>{c.title}</Text>
     <Action label={c.close} run={leave} disabled={saving()}/>
   </View>
   <Scroll style={{flexShrink:1}}><View style={{gap:16,paddingBottom:8}}>
     <Text style={noteStyle()}>{c.intro}</Text>
     <If when={!profileReady()}><Text style={textStyle()}>{c.profile}</Text><Action label={c.editProfile} run={()=>void (async()=>{if(await cancel())await Scale.openProfile();})()}/></If>
     <If when={message()!==""}><Text testID="scale-message" style={{...noteStyle(),color:state()==="failed"||message()===c.saveFailed?palette().danger:palette().muted}}>{message()}</Text></If>
     <If when={state()==="scanning"||state()==="connecting"||state()==="measuring"}>
       <Text style={textStyle()}>{state()==="scanning"?c.scanning:state()==="connecting"?c.connecting:c.measuring}</Text>
     </If>
     <If when={!preview()&&state()!=="saved"&&profileReady()}>
       <Each of={devices()} key={d=>d.address}>{item=>{ const d=item; return <Button accessibilityLabel={`${c.connect} ${d().name}`} onPress={()=>void connect(d())} disabled={state()==="connecting"||state()==="measuring"}
         style={{minHeight:64,padding:16,borderRadius:16,backgroundColor:palette().well}}><Text style={textStyle()}>{d().name}</Text><Text style={noteStyle()}>{`${d().rssi} dBm`}</Text></Button>; }}</Each>
     </If>
     <If when={preview()}>{()=>{
       const reading=()=>preview()!;
       return <View testID="scale-preview" style={{gap:12,paddingVertical:8}}>
         <Text style={noteStyle()}>{`${reading().device.name} · ${reading().day}`}</Text>
         <Text accessibilityLabel={`${c.weight} ${(reading().measurement.weight_grams/1000).toFixed(2)} kg`} style={{fontSize:44,lineHeight:48,fontWeight:700,color:palette().ink}}>{(reading().measurement.weight_grams/1000).toFixed(2)}<Text style={{fontSize:16,color:palette().muted}}> kg</Text></Text>
         <If when={reading().measurement.metrics}>{()=>{
           const m=()=>reading().measurement.metrics!;
           return <View style={{gap:8}}>
             <Text style={textStyle()}>{`${c.fat} ${m().body_fat_percent.toFixed(1)}%`}</Text>
             <Text style={noteStyle()}>{`${c.muscle} ${m().muscle_percent.toFixed(1)}% · ${c.water} ${m().water_percent.toFixed(1)}%`}</Text>
             <Text style={noteStyle()}>{c.estimate}</Text>
           </View>;
         }}</If>
         <If when={!reading().measurement.metrics}><Text style={noteStyle()}>{c.noImpedance}</Text></If>
         <If when={replacement()}><Text style={textStyle()}>{`${c.replace} ${reading().existing_kg?.toFixed(1)} kg`}</Text></If>
         <Action primary disabled={saving()} label={replacement()?c.replaceSave:reading().measurement.metrics?c.save:c.weightOnly} run={()=>void save()}/>
         <If when={replacement()}><Action label={c.keep} run={()=>void cancel()} disabled={saving()}/></If>
         <If when={!replacement()}><Action label={c.discard} run={()=>void cancel()} disabled={saving()}/></If>
       </View>;
     }}</If>
   </View></Scroll>
   <If when={!preview()&&state()!=="saved"&&state()!=="connecting"&&state()!=="measuring"&&profileReady()}>
     <Action primary label={state()==="failed"?c.retry:c.scan} disabled={state()==="scanning"} run={()=>void scan()}/>
   </If>
   <If when={state()==="saved"}><Action primary label={c.close} run={leave}/></If>
 </View>;
}
