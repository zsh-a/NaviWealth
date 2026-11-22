import { Scale } from "naviwealth/native";
import { host } from "nsh";
import type {
  AlgorithmId,
  AlgorithmOption,
  Algorithms,
  Composition,
  LiveReading,
  MeasurementSummary,
  Connection,
  Device,
  Notification,
  Palette,
  Preview,
  ScaleIdentity,
  ScaleUpdate,
  Start,
} from "./scale-types";

const MAX_NOTIFICATION_BASE64_LENGTH = 256;
const PERMISSION_TIMEOUT_MS = 60_000;
const CONNECT_TIMEOUT_MS = 30_000;
const WRITE_TIMEOUT_MS = 15_000;

interface BluetoothStatus {
  available: boolean;
  enabled: boolean;
  permissionGranted?: boolean;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isString);
}

function isStringRecord(value: unknown): value is Record<string, string> {
  return isRecord(value) && Object.values(value).every(isString);
}

function isSessionEvent(value: unknown): value is Record<string, unknown> & { sessionId: string } {
  return isRecord(value) && isString(value.sessionId) && value.sessionId.length > 0;
}

function isDevice(value: unknown): value is Device {
  return (
    isSessionEvent(value) &&
    isString(value.address) &&
    isString(value.name) &&
    isNumber(value.rssi) &&
    isStringRecord(value.manufacturerData) &&
    isStringArray(value.serviceUuids) &&
    (value.serviceData === undefined || isStringRecord(value.serviceData))
  );
}

function isConnection(value: unknown): value is Connection {
  return (
    isSessionEvent(value) &&
    (value.state === "connecting" ||
      value.state === "ready" ||
      value.state === "disconnected" ||
      value.state === "scan_stopped") &&
    (value.reason === undefined || isString(value.reason))
  );
}

function isComposition(value: unknown): value is Composition {
  return (
    isRecord(value) &&
    isNumber(value.body_fat_percent) &&
    isNumber(value.muscle_percent) &&
    isNumber(value.water_percent) &&
    isString(value.model)
  );
}

function isLiveReading(value: unknown): value is LiveReading {
  return (
    isRecord(value) &&
    isNumber(value.weight_grams) &&
    Number.isInteger(value.weight_grams) &&
    value.weight_grams >= 0 &&
    value.weight_grams <= 0x3ffff &&
    typeof value.stable === "boolean"
  );
}

function isSummary(value: unknown): value is MeasurementSummary {
  return (
    isRecord(value) &&
    ["bmi", "fat_mass_kg", "fat_free_mass_kg", "muscle_mass_kg", "water_mass_kg"].every(
      (key) => value[key] === null || isNumber(value[key]),
    )
  );
}

function isIdentity(value: unknown): value is ScaleIdentity {
  return isRecord(value) && isString(value.id) && isString(value.name);
}

function isAlgorithmId(value: unknown): value is AlgorithmId {
  return value === "segal" || value === "wu2015" || value === "sun2003";
}

function isAlgorithm(value: unknown): value is AlgorithmOption {
  return (
    isRecord(value) &&
    isAlgorithmId(value.id) &&
    isString(value.name) &&
    isString(value.description) &&
    typeof value.experimental === "boolean"
  );
}

function readIdentity(value: unknown): ScaleIdentity | null {
  if (value === null || isIdentity(value)) return value;
  throw new Error("invalid_scale_identity");
}

function isPreview(value: unknown): value is Preview {
  if (!isRecord(value)) return false;
  const { device, measurement } = value;
  return (
    isAlgorithm(value.algorithm) &&
    typeof value.algorithm_unavailable === "boolean" &&
    isString(value.session_id) &&
    isString(value.token) &&
    isString(value.day) &&
    isNumber(value.measured_at_ms) &&
    (value.existing_kg === null || isNumber(value.existing_kg)) &&
    isIdentity(device) &&
    isRecord(measurement) &&
    isString(measurement.algorithm_version) &&
    isRecord(measurement.profile) &&
    isNumber(measurement.profile.height_cm) &&
    isNumber(measurement.profile.age_years) &&
    (measurement.profile.sex === "male" || measurement.profile.sex === "female") &&
    isSummary(value.summary) &&
    isNumber(measurement.weight_grams) &&
    (measurement.resistance_ohm === null || isNumber(measurement.resistance_ohm)) &&
    (measurement.metrics === null || isComposition(measurement.metrics))
  );
}

function readPreview(value: unknown): Preview | null {
  if (value === null || isPreview(value)) return value;
  throw new Error("invalid_scale_preview");
}

const paletteKeys = {
  canvas: true,
  surface: true,
  ink: true,
  muted: true,
  line: true,
  well: true,
  danger: true,
  action: true,
  actionPressed: true,
  onAction: true,
  positive: true,
  scrim: true,
} satisfies Record<Exclude<keyof Palette, "sheetRadius">, true>;

function isPalette(value: unknown): value is Palette {
  return (
    isRecord(value) &&
    isNumber(value.sheetRadius) &&
    Object.keys(paletteKeys).every((key) => isString(value[key]))
  );
}

export const scaleNative = {
  async algorithms(): Promise<Algorithms> {
    const value = await Scale.algorithms();
    if (
      !isRecord(value) ||
      !isAlgorithmId(value.selected) ||
      !Array.isArray(value.options) ||
      !value.options.every(isAlgorithm) ||
      new Set(value.options.map((option) => option.id)).size !== value.options.length ||
      !value.options.some((option) => option.id === value.selected)
    ) {
      throw new Error("invalid_scale_algorithms");
    }
    return { selected: value.selected, options: value.options };
  },
  setAlgorithm: (id: AlgorithmId) => Scale.setAlgorithm(id),
  async reestimate(sessionId: string, token: string, id: AlgorithmId): Promise<Preview> {
    const value = readPreview(await Scale.reestimate(sessionId, token, id));
    if (!value || value.session_id !== sessionId || value.algorithm.id !== id) {
      throw new Error("invalid_scale_reestimate");
    }
    return value;
  },
  palette(dark: boolean): Palette {
    const value = Scale.palette(dark);
    if (!isPalette(value)) throw new Error("invalid_scale_palette");
    return value;
  },
  profileReady: () => Scale.profileReady(),
  openProfile: () => Scale.openProfile(),
  remembered: async () => readIdentity(await Scale.remembered()),
  remember: async (sessionId: string) => readIdentity(await Scale.remember(sessionId)),
  async begin(device?: Device): Promise<Start> {
    const value = device ? await Scale.begin(device) : await Scale.beginRemembered();
    if (!isRecord(value) || !isString(value.session_id) || !value.session_id) {
      throw new Error("invalid_scale_start");
    }
    const { session_id, address, commands } = value;
    if (!isString(address) || !address || !isStringArray(commands) || commands.length === 0) {
      await Scale.invalidate(session_id);
      throw new Error("invalid_scale_start");
    }
    return { session_id, address, commands };
  },
  async feed(sessionId: string, dataBase64: string): Promise<ScaleUpdate> {
    const value = await Scale.feed(sessionId, dataBase64);
    if (!isRecord(value)) throw new Error("invalid_scale_update");
    const { reading } = value;
    if (reading !== null && !isLiveReading(reading)) throw new Error("invalid_scale_reading");
    return { preview: readPreview(value.preview), reading };
  },
  async pending(): Promise<Preview | null> {
    return readPreview(await Scale.pending());
  },
  async confirm(sessionId: string, token: string, replaceExisting: boolean): Promise<void> {
    await Scale.confirm(sessionId, token, replaceExisting);
  },
  pause: (sessionId: string) => Scale.pause(sessionId),
  cancel: (sessionId: string) => Scale.cancel(sessionId),
  invalidate: (sessionId: string) => Scale.invalidate(sessionId),
};

function requireAcknowledgement(value: unknown, key: "started" | "connected" | "written"): void {
  if (!isRecord(value) || value[key] !== true) throw new Error(`invalid_ble_${key}_ack`);
}

export const scaleBle = {
  available: () => host.available(),
  async status(): Promise<BluetoothStatus> {
    const value = await host.call<unknown>("ble.status", {});
    if (
      !isRecord(value) ||
      typeof value.available !== "boolean" ||
      typeof value.enabled !== "boolean" ||
      (value.permissionGranted !== undefined && typeof value.permissionGranted !== "boolean")
    ) {
      throw new Error("invalid_bluetooth_status");
    }
    const { available, enabled, permissionGranted } = value;
    return { available, enabled, permissionGranted };
  },
  async startScan(sessionId: string, timeoutMs: number): Promise<void> {
    const reply = await host.call<unknown>(
      "ble.scan.start",
      { sessionId, timeoutMs },
      { timeout: PERMISSION_TIMEOUT_MS },
    );
    requireAcknowledgement(reply, "started");
  },
  async stopScan(sessionId: string): Promise<void> {
    await host.call("ble.scan.stop", { sessionId });
  },
  async connect(sessionId: string, address: string): Promise<void> {
    const reply = await host.call<unknown>(
      "ble.connect",
      { sessionId, address },
      { timeout: CONNECT_TIMEOUT_MS },
    );
    requireAcknowledgement(reply, "connected");
  },
  async disconnect(sessionId: string): Promise<void> {
    await host.call("ble.disconnect", { sessionId });
  },
  async write(sessionId: string, dataBase64: string): Promise<void> {
    const reply = await host.call<unknown>(
      "ble.write",
      { sessionId, dataBase64 },
      { timeout: WRITE_TIMEOUT_MS },
    );
    requireAcknowledgement(reply, "written");
  },
  onDevice(listener: (device: Device) => void): () => void {
    return host.on<unknown>("ble.device", (value) => {
      if (isDevice(value)) listener(value);
    });
  },
  onConnection(listener: (connection: Connection) => void): () => void {
    return host.on<unknown>("ble.connection", (value) => {
      if (isConnection(value)) listener(value);
    });
  },
  onNotification(listener: (notification: Notification) => void): () => void {
    return host.on<unknown>("ble.notification", (value) => {
      if (!isSessionEvent(value)) return;
      const { sessionId, dataBase64 } = value;
      // Surface malformed payloads with their session so the caller can invalidate the draft.
      listener({
        sessionId,
        dataBase64:
          isString(dataBase64) && dataBase64.length <= MAX_NOTIFICATION_BASE64_LENGTH
            ? dataBase64
            : null,
      });
    });
  },
  onError(listener: (event: { sessionId: string }) => void): () => void {
    return host.on<unknown>("ble.error", (value) => {
      if (isSessionEvent(value)) listener(value);
    });
  },
};
