import { colorScheme, computed, locale, Scroll, Text, View, windowSize } from "nsh";
import type { Signal } from "nsh";
import { Button } from "nsh/base";
import { scaleNative } from "./scale-bridge";
import { copy } from "./scale-copy";
import { createScaleSession } from "./scale-session";
import type { Preview } from "./scale-types";

export function ScalePanel(props: { close: () => void; busy: Signal<boolean> }) {
  const labels = copy[locale().toLowerCase().startsWith("zh") ? "zh" : "en"];
  const palette = computed(() => scaleNative.palette(colorScheme() === "dark"));
  const {
    state,
    devices,
    preview,
    message,
    replacement,
    profileReady,
    profileLoaded,
    scan,
    connect,
    save,
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
  const primaryAction = computed(() => {
    if (state() === "saved") return { label: labels.close, run: leave };
    const reading = preview();
    if (reading) {
      const label = replacement()
        ? labels.replaceSave
        : reading.measurement.metrics
          ? labels.save
          : labels.weightOnly;
      return { label, run: () => void save() };
    }
    if (needsProfile()) return { label: labels.editProfile, run: () => void openProfile() };
    if (!profileLoaded() || !profileReady()) return null;
    switch (state()) {
      case "scanning":
        return { label: labels.scan, run: () => void scan(), disabled: true };
      case "idle":
        return { label: labels.scan, run: () => void scan() };
      case "failed":
        return { label: labels.retry, run: () => void scan() };
      default:
        return null;
    }
  });
  const textStyle = () => ({ fontSize: 16, lineHeight: 23, color: palette().ink });
  const noteStyle = () => ({ fontSize: 14, lineHeight: 21, color: palette().muted });
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
          minHeight: action.primary ? 50 : 44,
          paddingHorizontal: action.primary ? 20 : 12,
          paddingVertical: action.primary ? 12 : 8,
          borderRadius: 25,
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: action.primary
            ? action.disabled
              ? palette().well
              : palette().ink
            : "transparent",
        }}
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
        maxHeight: windowSize().height * 0.85,
        paddingTop: 20,
        paddingBottom: "calc(env(safe-area-inset-bottom) + 20px)",
        paddingHorizontal: 20,
        gap: 16,
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
      <Scroll style={{ flexShrink: 1 }}>
        <View style={{ gap: 16, paddingBottom: 8 }}>
          <If
            when={
              profileLoaded() &&
              profileReady() &&
              state() === "idle" &&
              !message() &&
              !devices().length
            }
          >
            <Text style={textStyle()}>{labels.intro}</Text>
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
            <Text style={textStyle()} android={{ accessibilityLiveRegion: "polite" }}>
              {progress()}
            </Text>
          </If>
          <If when={!preview() && state() !== "saved" && profileReady()}>
            <Each of={devices()} key={(device) => device.address}>
              {(device) => (
                <Button
                  accessibilityLabel={`${labels.connect} ${device().name}`}
                  onPress={() => void connect(device())}
                  disabled={state() === "connecting" || state() === "measuring" || locked()}
                  style={{
                    minHeight: 64,
                    padding: 16,
                    borderRadius: 16,
                    backgroundColor: palette().well,
                  }}
                >
                  <Text style={textStyle()}>{device().name}</Text>
                  <Text style={noteStyle()}>{`${device().rssi} dBm`}</Text>
                </Button>
              )}
            </Each>
          </If>
          <If when={preview()}>
            {(reading: () => Preview) => {
              const kg = () => (reading().measurement.weight_grams / 1000).toFixed(2);
              return (
                <View testID="scale-preview" style={{ gap: 12, paddingVertical: 8 }}>
                  <Text
                    accessibilityLabel={`${labels.weight} ${kg()} kg`}
                    style={{
                      fontSize: 52,
                      lineHeight: 56,
                      fontWeight: 700,
                      fontVariant: ["tabular-nums"],
                      color: palette().ink,
                    }}
                  >
                    {kg()}
                    <Text style={{ fontSize: 16, color: palette().muted }}> kg</Text>
                  </Text>
                  <Text style={noteStyle()}>{`${reading().device.name} · ${reading().day}`}</Text>
                  <If when={reading().measurement.metrics}>
                    {(m: () => NonNullable<Preview["measurement"]["metrics"]>) => {
                      return (
                        <View style={{ gap: 8 }}>
                          <Text
                            style={textStyle()}
                          >{`${labels.fat} ${m().body_fat_percent.toFixed(1)}%`}</Text>
                          <Text
                            style={noteStyle()}
                          >{`${labels.muscle} ${m().muscle_percent.toFixed(1)}% · ${labels.water} ${m().water_percent.toFixed(1)}%`}</Text>
                          <Text style={noteStyle()}>{labels.estimate}</Text>
                        </View>
                      );
                    }}
                  </If>
                  <If when={!reading().measurement.metrics}>
                    <Text style={noteStyle()}>{labels.noImpedance}</Text>
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
          <View testID="scale-actions" style={{ flexShrink: 0, gap: 4 }}>
            <Action
              primary
              label={action().label}
              disabled={locked() || action().disabled}
              run={() => action().run()}
            />
            <If when={preview()}>
              <Action
                label={replacement() ? labels.keep : labels.discard}
                run={() => void cancel()}
                disabled={locked()}
              />
            </If>
          </View>
        )}
      </If>
    </View>
  );
}
