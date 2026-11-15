import {test,open} from "nsh/test";
test("Native physical Finance validation",async()=>{
 const app=await open("..",{colorScheme:"light",reducedMotion:true});
 await app.waitFor("id:open-record");
 await app.press("id:tab-accounts");
 await app.press("id:open-account-form");
 await app.type("id:account-name","日常银行卡");
 await app.type("id:account-opening","12800");
 await app.press("id:account-save");
 await app.waitFor("text:日常银行卡");
 await app.press("id:open-account-form");
 await app.type("id:account-name","储蓄账户");
 await app.press("id:account-save");
 await app.waitFor("text:储蓄账户");
 await app.press("id:tab-ledger");
 console.log("PHYSICAL_CONTROL_READY");
 await app.wait(300000);
},600000);
