export interface Device {
  sessionId: string;
  address: string;
  name: string;
  rssi: number;
  manufacturerData: Record<string, string>;
  serviceUuids: string[];
  serviceData?: Record<string, string>;
}

export interface ScaleIdentity {
  id: string;
  name: string;
}

export interface LiveReading {
  weight_grams: number;
  stable: boolean;
}

export interface ScaleUpdate {
  preview: Preview | null;
  reading: LiveReading | null;
}

export type AlgorithmId = "segal" | "wu2015" | "sun2003";

export interface AlgorithmOption {
  id: AlgorithmId;
  name: string;
  description: string;
  experimental: boolean;
}

export interface Algorithms {
  selected: AlgorithmId;
  options: AlgorithmOption[];
}

export interface Preview {
  algorithm: AlgorithmOption;
  algorithm_unavailable: boolean;
  session_id: string;
  token: string;
  day: string;
  measured_at_ms: number;
  device: ScaleIdentity;
  existing_kg: number | null;
  summary: MeasurementSummary;
  measurement: {
    algorithm_version: string;
    weight_grams: number;
    resistance_ohm: number | null;
    metrics: Composition | null;
    profile: { height_cm: number; age_years: number; sex: "male" | "female" };
  };
}

export interface MeasurementSummary {
  bmi: number | null;
  fat_mass_kg: number | null;
  fat_free_mass_kg: number | null;
  muscle_mass_kg: number | null;
  water_mass_kg: number | null;
}

export interface Composition {
  body_fat_percent: number;
  muscle_percent: number;
  water_percent: number;
  model: string;
}

export interface Start {
  session_id: string;
  address: string;
  commands: string[];
}

export interface Palette {
  canvas: string;
  surface: string;
  ink: string;
  muted: string;
  line: string;
  well: string;
  danger: string;
  action: string;
  actionPressed: string;
  onAction: string;
  positive: string;
  scrim: string;
  sheetRadius: number;
}

export interface Connection {
  sessionId: string;
  state: "connecting" | "ready" | "disconnected" | "scan_stopped";
  reason?: string;
}

export interface Notification {
  sessionId: string;
  /** Null means the identified session sent an invalid payload. */
  dataBase64: string | null;
}
