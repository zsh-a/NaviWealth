export interface Device {
 sessionId:string; address:string; name:string; rssi:number;
 manufacturerData:Record<string,string>; serviceUuids:string[]; serviceData?:Record<string,string>;
}
export interface Preview {
 session_id:string; token:string; day:string; measured_at_ms:number;
 device:{id:string;name:string}; existing_kg:number|null;
 measurement:{weight_grams:number;resistance_ohm:number|null;metrics:null|{body_fat_percent:number;muscle_percent:number;water_percent:number};};
}
export interface Start { session_id:string; commands:string[]; }
export interface Palette { canvas:string; surface:string; ink:string; muted:string; line:string; well:string; danger:string; onAction:string; positive:string; scrim:string; }
export interface Connection {sessionId:string;state:string;reason?:string;}
export interface Notification {sessionId:string;dataBase64:string;}
