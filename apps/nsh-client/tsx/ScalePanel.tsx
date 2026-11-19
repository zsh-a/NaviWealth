import {
  colorScheme,
  computed,
  locale,
  reduceMotion,
  Scroll,
  signal,
  Text,
  View,
  windowSize,
} from "nsh";
import type { Signal } from "nsh";
import { Button } from "nsh/base";
import { scaleNative } from "./scale-bridge";
import { copy } from "./scale-copy";
import { createScaleSession } from "./scale-session";
import type { Preview } from "./scale-types";

export function ScalePanel(props: { close: () => void; busy: Signal<boolean> }) {
  const labels = copy[locale().toLowerCase().startsWith("zh") ? "zh" : "en"];
  const palette = computed(() => scaleNative.palette(colorScheme() === "dark"));
  const detailsOpen = signal(false);
  const {
    state,
    devices,
    remembered,
    finding,
    processing,
    compositionPhase,
    preview,
    liveReading,
    message,
    replacement,
    profileReady,
    profileLoaded,
    scan,
    connect,
    save,
    remeasure,
    leave,
    cancel,
    openProfile,
  } = createScaleSession(labels, props.close, props.busy);
  const locked = props.busy;
  const progress = computed(() => {
    switch (state()) {
      case "scanning":
        return labels.scanning;
      case "connecting":
        return labels.connecting;
      case "measuring":
        return labels.measuring;
      default:
        return "";
    }
  });
  const needsProfile = computed(() => profileLoaded() && !profileReady() && !preview());
  const useRemembered = computed(() => remembered() !== null && !finding());
  const stage = computed(() => {
    if (preview()?.measurement.metrics || state() === "saved") return 3;
    if (preview()) return 2;
    if (state() === "measuring") return 1;
    return 0;
  });
  const primaryAction = computed(() => {
    if (state() === "saved") return { label: labels.close, run: leave };
    const reading = preview();
    if (reading) {
      if (!reading.measurement.metrics && compositionPhase() === "waiting" && !replacement()) {
        return { label: labels.compositionPending, run: () => {}, disabled: true };
      }
      if (!reading.measurement.metrics && !replacement()) {
        return {
          label: profileReady() ? labels.remeasure : labels.editProfile,
          run: () => void (profileReady() ? remeasure() : openProfile()),
          disabled: processing(),
        };
      }
      const label = replacement() ? labels.replaceSave : labels.save;
      return { label, run: () => void save(), disabled: processing() };
    }
    if (needsProfile()) return { label: labels.editProfile, run: () => void openProfile() };
    if (!profileLoaded() || !profileReady()) return null;
    switch (state()) {
      case "scanning":
        return { label: labels.scan, run: () => void scan(), disabled: true };
      case "idle":
      case "failed":
        if (useRemembered()) return { label: labels.connectSaved, run: () => void connect() };
        return { label: state() === "failed" ? labels.retry : labels.scan, run: () => void scan() };
      default:
        return null;
    }
  });
  const textStyle = () => ({ fontSize: 16, lineHeight: 23, color: palette().ink });
  const noteStyle = () => ({ fontSize: 14, lineHeight: 21, color: palette().muted });
  function Metric(metric: { label: string; value: string }) {
    return (
      <View style={{ flex: 1, gap: 6 }}>
        <Text
          style={{
            fontSize: 24,
            lineHeight: 30,
            fontWeight: 600,
            fontVariant: ["tabular-nums"],
            color: palette().ink,
          }}
        >
          {metric.value}
          <Text style={{ fontSize: 14, fontWeight: 400, color: palette().muted }}> %</Text>
        </Text>
        <Text style={{ fontSize: 12.5, lineHeight: 18, color: palette().muted }}>
          {metric.label}
        </Text>
      </View>
    );
  }
  function Detail(detail: { label: string; value: string }) {
    return (
      <View
        style={{
          flexDirection: "row",
          justifyContent: "space-between",
          gap: 16,
          paddingVertical: 8,
        }}
      >
        <Text style={{ ...noteStyle(), flex: 1 }}>{detail.label}</Text>
        <Text style={{ ...textStyle(), fontVariant: ["tabular-nums"] }}>{detail.value}</Text>
      </View>
    );
  }
  function Action(action: {
    label: string;
    run: () => void;
    primary?: boolean;
    disabled?: boolean;
  }) {
    return (
      <Button
        accessibilityLabel={action.label}
        disabled={action.disabled}
        onPress={action.run}
        style={{
          minHeight: action.primary ? 52 : 48,
          paddingHorizontal: action.primary ? 20 : 12,
          paddingVertical: action.primary ? 12 : 8,
          borderRadius: 26,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: action.primary
            ? action.disabled
              ? palette().well
              : palette().ink
            : "transparent",
        }}
        activeStyle={{ opacity: 0.76 }}
      >
        <Text
          style={{
            fontSize: 16,
            lineHeight: 23,
            fontWeight: 600,
            color: action.disabled
              ? palette().muted
              : action.primary
                ? palette().onAction
                : palette().ink,
          }}
        >
          {action.label}
        </Text>
      </Button>
    );
  }
  return (
    <View
      testID="scale-panel"
      style={{
        minHeight: Math.min(460, windowSize().height * 0.75),
        maxHeight: windowSize().height * 0.85,
        paddingTop: 16,
        paddingBottom: "calc(env(safe-area-inset-bottom) + 16px)",
        paddingHorizontal: 24,
        gap: 20,
      }}
    >
      <View
        style={{
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 12,
        }}
      >
        <Text
          role="header"
          style={{ fontSize: 20, lineHeight: 26, fontWeight: 600, color: palette().ink, flex: 1 }}
        >
          {labels.title}
        </Text>
        <If when={state() !== "saved"}>
          <Action label={labels.close} run={leave} disabled={locked()} />
        </If>
      </View>
      <Scroll style={{ flexShrink: 1, flexGrow: 1 }}>
        <View style={{ gap: 24, paddingBottom: 8 }}>
          <If when={profileReady() && state() !== "failed"}>
            <View testID="scale-stages" style={{ flexDirection: "row", gap: 12 }}>
              <Each of={[labels.stageConnect, labels.stageWeight, labels.stageComposition]}>
                {(label, index) => (
                  <View style={{ flex: 1, gap: 8 }}>
                    <View
                      style={{
                        height: 3,
                        borderRadius: 2,
                        backgroundColor: stage() > index() ? palette().positive : palette().line,
                        transitionProperty: "background-color",
                        transitionDuration: reduceMotion() ? 0 : 180,
                      }}
                    />
                    <Text
                      style={{
                        fontSize: 12.5,
                        lineHeight: 18,
                        color: stage() > index() ? palette().ink : palette().muted,
                      }}
                    >
                      {label()}
                    </Text>
                  </View>
                )}
              </Each>
            </View>
          </If>
          <If
            when={
              profileLoaded() &&
              profileReady() &&
              state() === "idle" &&
              !message() &&
              !devices().length
            }
          >
            <View style={{ gap: 8 }}>
              <Text style={{ fontSize: 24, lineHeight: 32, fontWeight: 600, color: palette().ink }}>
                {labels.ready}
              </Text>
              <Text style={noteStyle()}>{labels.readyHint}</Text>
            </View>
          </If>
          <If when={useRemembered() && (state() === "idle" || state() === "failed")}>
            <View
              style={{
                paddingVertical: 16,
                gap: 6,
                borderTopWidth: 1,
                borderBottomWidth: 1,
                borderColor: palette().line,
              }}
            >
              <Text style={{ ...textStyle(), fontWeight: 600 }}>{remembered()?.name}</Text>
              <Text style={noteStyle()}>{labels.deviceKept}</Text>
            </View>
          </If>
          <If when={needsProfile()}>
            <Text style={textStyle()}>{labels.profile}</Text>
          </If>
          <If when={message() !== ""}>
            <Text
              testID="scale-message"
              android={{ accessibilityLiveRegion: "polite" }}
              style={{
                ...(state() === "saved" ? textStyle() : noteStyle()),
                fontWeight: state() === "saved" ? 600 : 400,
                color:
                  state() === "failed" || message() === labels.saveFailed
                    ? palette().danger
                    : state() === "saved"
                      ? palette().ink
                      : palette().muted,
              }}
            >
              {message()}
            </Text>
          </If>
          <If when={progress()}>
            <View style={{ gap: 8 }}>
              <Text
                style={{ fontSize: 24, lineHeight: 32, fontWeight: 600, color: palette().ink }}
                android={{ accessibilityLiveRegion: "polite" }}
              >
                {progress()}
              </Text>
              <If when={state() === "measuring"}>
                <Text style={noteStyle()}>{labels.connectedHint}</Text>
              </If>
            </View>
          </If>
          <If when={liveReading() && !preview()}>
            <View testID="scale-live-reading" style={{ gap: 8 }}>
              <Text style={noteStyle()}>{labels.liveWeight}</Text>
              <Text
                accessibilityLabel={`${labels.liveWeight} ${((liveReading()?.weight_grams ?? 0) / 1000).toFixed(2)} kg`}
                style={{
                  fontSize: 56,
                  lineHeight: 66,
                  fontWeight: 600,
                  fontVariant: ["tabular-nums"],
                  color: palette().ink,
                }}
              >
                {((liveReading()?.weight_grams ?? 0) / 1000).toFixed(2)}
                <Text style={{ fontSize: 20, fontWeight: 400, color: palette().muted }}> kg</Text>
              </Text>
              <Text style={noteStyle()}>{labels.liveHint}</Text>
            </View>
          </If>
          <If when={!preview() && state() !== "saved" && profileReady()}>
            <Each of={devices()} key={(device) => device.address}>
              {(device) => (
                <Button
                  accessibilityLabel={`${labels.connect} ${device().name}`}
                  onPress={() => void connect(device())}
                  disabled={state() === "connecting" || state() === "measuring" || locked()}
                  style={{
                    minHeight: 80,
                    paddingVertical: 16,
                    borderBottomWidth: 1,
                    borderColor: palette().line,
                    gap: 6,
                  }}
                >
                  <Text style={{ ...textStyle(), fontWeight: 600 }}>{device().name}</Text>
                  <Text style={noteStyle()}>
                    {device().rssi >= -75 ? labels.signalNear : labels.signalFar}
                  </Text>
                </Button>
              )}
            </Each>
          </If>
          <If when={preview()}>
            {(reading: () => Preview) => {
              const kg = () => (reading().measurement.weight_grams / 1000).toFixed(2);
              return (
                <View testID="scale-preview" style={{ gap: 20, paddingVertical: 8 }}>
                  <View style={{ gap: 8 }}>
                    <Text
                      testID="scale-status"
                      android={{ accessibilityLiveRegion: "polite" }}
                      style={{
                        fontSize: 24,
                        lineHeight: 32,
                        fontWeight: 600,
                        color: palette().ink,
                      }}
                    >
                      {reading().measurement.metrics
                        ? labels.complete
                        : compositionPhase() === "waiting"
                          ? labels.compositionPending
                          : compositionPhase() === "delayed"
                            ? labels.compositionDelayed
                            : labels.compositionIncomplete}
                    </Text>
                    <Text style={noteStyle()}>
                      {reading().measurement.metrics
                        ? labels.reviewHint
                        : compositionPhase() === "waiting"
                          ? labels.compositionHint
                          : compositionPhase() === "delayed"
                            ? labels.compositionDelayedHint
                            : labels.noImpedance}
                    </Text>
                  </View>
                  <Text style={noteStyle()}>{labels.weight}</Text>
                  <Text
                    accessibilityLabel={`${labels.weight} ${kg()} kg`}
                    style={{
                      fontSize: 56,
                      lineHeight: 66,
                      fontWeight: 600,
                      fontVariant: ["tabular-nums"],
                      color: palette().ink,
                    }}
                  >
                    {kg().split(".")[0]}
                    <Text style={{ color: palette().muted }}>.{kg().split(".")[1]}</Text>
                    <Text style={{ fontSize: 20, fontWeight: 400, color: palette().muted }}>
                      {" "}
                      kg
                    </Text>
                  </Text>
                  <If when={reading().measurement.metrics}>
                    {(m: () => NonNullable<Preview["measurement"]["metrics"]>) => {
                      return (
                        <View
                          style={{
                            gap: 16,
                            borderTopWidth: 1,
                            borderColor: palette().line,
                            paddingTop: 20,
                          }}
                        >
                          <View style={{ flexDirection: "row", gap: 12 }}>
                            <Metric label={labels.fat} value={m().body_fat_percent.toFixed(1)} />
                            <Metric label={labels.muscle} value={m().muscle_percent.toFixed(1)} />
                            <Metric label={labels.water} value={m().water_percent.toFixed(1)} />
                          </View>
                          <Text style={{ fontSize: 12.5, lineHeight: 19, color: palette().muted }}>
                            {labels.estimate}
                          </Text>
                        </View>
                      );
                    }}
                  </If>
                  <Button
                    accessibilityLabel={detailsOpen() ? labels.hideDetails : labels.details}
                    onPress={() => detailsOpen.set(!detailsOpen())}
                    style={{ minHeight: 48, justifyContent: "center", alignItems: "flex-start" }}
                  >
                    <Text style={noteStyle()}>
                      {detailsOpen() ? labels.hideDetails : labels.details}
                    </Text>
                  </Button>
                  <If when={detailsOpen()}>
                    <View
                      style={{
                        gap: 4,
                        borderTopWidth: 1,
                        borderColor: palette().line,
                        paddingTop: 12,
                      }}
                    >
                      <Text
                        style={noteStyle()}
                      >{`${reading().device.name} · ${reading().day}`}</Text>
                      <Detail
                        label={labels.profileSnapshot}
                        value={`${reading().measurement.profile.height_cm} cm · ${reading().measurement.profile.age_years} ${labels.ageUnit}`}
                      />
                      <If when={reading().summary.bmi !== null}>
                        <Detail
                          label={labels.bmi}
                          value={reading().summary.bmi?.toFixed(2) ?? "—"}
                        />
                      </If>
                      <Each
                        of={[
                          { label: labels.fatMass, value: reading().summary.fat_mass_kg },
                          { label: labels.leanMass, value: reading().summary.fat_free_mass_kg },
                          { label: labels.muscleMass, value: reading().summary.muscle_mass_kg },
                          { label: labels.waterMass, value: reading().summary.water_mass_kg },
                        ].filter((item) => item.value !== null)}
                      >
                        {(item) => (
                          <Detail label={item().label} value={`${item().value?.toFixed(2)} kg`} />
                        )}
                      </Each>
                      <If when={reading().measurement.resistance_ohm !== null}>
                        <Detail
                          label={labels.impedance}
                          value={`${reading().measurement.resistance_ohm?.toFixed(1)} Ω`}
                        />
                      </If>
                      <If when={reading().measurement.metrics}>
                        <Detail
                          label={labels.estimateModel}
                          value={
                            reading().measurement.metrics?.model.startsWith("segal")
                              ? "Segal BIA"
                              : (reading().measurement.metrics?.model ?? "—")
                          }
                        />
                        <Text style={{ ...noteStyle(), paddingTop: 8 }}>{labels.derivedNote}</Text>
                      </If>
                    </View>
                  </If>
                  <If when={replacement()}>
                    <Text
                      style={textStyle()}
                    >{`${labels.replace} ${reading().existing_kg?.toFixed(1)} kg`}</Text>
                  </If>
                </View>
              );
            }}
          </If>
        </View>
      </Scroll>
      <If when={primaryAction()}>
        {(action) => (
          <View
            testID="scale-actions"
            style={{
              flexShrink: 0,
              gap: 4,
              borderTopWidth: 1,
              borderColor: palette().line,
              paddingTop: 16,
            }}
          >
            <Action
              primary
              label={action().label}
              disabled={locked() || action().disabled}
              run={() => action().run()}
            />
            <If when={preview() && !preview()?.measurement.metrics && !replacement()}>
              <Action
                label={labels.weightOnly}
                run={() => void save()}
                disabled={locked() || processing()}
              />
            </If>
            <If when={preview()}>
              <Action
                label={replacement() ? labels.keep : labels.discard}
                run={() => void cancel()}
                disabled={locked()}
              />
            </If>
            <If when={!preview() && state() !== "saved" && !useRemembered()}>
              <Text
                style={{
                  fontSize: 12.5,
                  lineHeight: 19,
                  textAlign: "center",
                  color: palette().muted,
                  paddingTop: 8,
                }}
              >
                {labels.privacyHint}
              </Text>
            </If>
            <If
              when={
                !preview() &&
                !needsProfile() &&
                useRemembered() &&
                (state() === "idle" || state() === "failed")
              }
            >
              <Action label={labels.findAnother} run={() => void scan()} disabled={locked()} />
            </If>
          </View>
        )}
      </If>
    </View>
  );
}
