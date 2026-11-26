import {
  colorScheme,
  computed,
  fontScale,
  locale,
  reduceMotion,
  Scroll,
  signal,
  Text,
  View,
  windowSize,
} from "nsh";
import type { Signal } from "nsh";
import { Button, Toggle, ToggleGroup } from "nsh/base";
import { scaleNative } from "./scale-bridge";
import { copy } from "./scale-copy";
import { ScaleReading } from "./ScaleReading";
import { createScaleSession } from "./scale-session";
import type { Preview } from "./scale-types";

export function ScalePanel(props: { close: () => void; busy: Signal<boolean> }) {
  const labels = copy[locale().toLowerCase().startsWith("zh") ? "zh" : "en"];
  const palette = computed(() => scaleNative.palette(colorScheme() === "dark"));
  const detailsOpen = signal(false);
  const algorithmsOpen = signal(false);
  const {
    state,
    devices,
    remembered,
    finding,
    processing,
    recalculating,
    algorithms,
    selectedAlgorithm,
    activeAlgorithm,
    chooseAlgorithm,
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
  const currentAlgorithm = computed(
    () =>
      preview()?.algorithm ??
      activeAlgorithm() ??
      algorithms().find((option) => option.id === selectedAlgorithm()),
  );
  const algorithmLocked = computed(
    () =>
      locked() ||
      processing() ||
      !profileLoaded() ||
      (!preview() && (state() === "connecting" || state() === "measuring")),
  );
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
      if (reading.algorithm_unavailable && !replacement()) {
        return {
          label: labels.chooseAlgorithm,
          run: () => algorithmsOpen.set(true),
          disabled: processing(),
        };
      }
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
              : palette().action
            : "transparent",
        }}
        activeStyle={
          action.primary ? { backgroundColor: palette().actionPressed } : { opacity: 0.76 }
        }
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
          {preview() ? labels.results : labels.title}
        </Text>
        <If when={state() !== "saved"}>
          <Action label={labels.close} run={leave} disabled={locked()} />
        </If>
      </View>
      <Scroll style={{ flexShrink: 1, flexGrow: 1 }}>
        <View style={{ gap: 24, paddingBottom: 8 }}>
          <If
            when={
              profileReady() &&
              state() !== "failed" &&
              !preview()?.measurement.metrics &&
              state() !== "saved"
            }
          >
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
          <If when={currentAlgorithm() && state() !== "saved"}>
            <View testID="scale-algorithms" style={{ gap: 8 }}>
              <Button
                accessibilityLabel={
                  algorithmsOpen() ? labels.hideAlgorithms : labels.chooseAlgorithm
                }
                onPress={() => algorithmsOpen.set(!algorithmsOpen())}
                disabled={locked()}
                style={{
                  minHeight: 52,
                  flexDirection: "row",
                  alignItems: "center",
                  gap: 12,
                  paddingVertical: 8,
                  borderBottomWidth: 0.5,
                  borderColor: palette().line,
                }}
                activeStyle={{ opacity: 0.7 }}
              >
                <View
                  style={{
                    flex: 1,
                    minWidth: 0,
                    gap: 4,
                    flexDirection: fontScale() > 1.2 ? "column" : "row",
                    justifyContent: "space-between",
                  }}
                >
                  <Text style={noteStyle()}>{labels.algorithm}</Text>
                  <View
                    style={{
                      flexDirection: "row",
                      gap: 6,
                      flexShrink: 1,
                      flexWrap: "wrap",
                      alignItems: "baseline",
                    }}
                  >
                    <Text style={{ ...textStyle(), fontWeight: 500 }}>
                      {currentAlgorithm()?.name}
                    </Text>
                    <If when={currentAlgorithm()?.experimental}>
                      <Text style={noteStyle()}>{labels.experimental}</Text>
                    </If>
                  </View>
                </View>
                <View
                  style={{
                    width: 7,
                    height: 7,
                    marginRight: 3,
                    borderRightWidth: 1.5,
                    borderBottomWidth: 1.5,
                    borderColor: palette().muted,
                    transform: [{ rotate: algorithmsOpen() ? "225deg" : "45deg" }],
                  }}
                />
              </Button>
              <If when={algorithmsOpen()}>
                <ToggleGroup testID="scale-algorithm-options" style={{ gap: 4 }}>
                  <Text style={noteStyle()}>
                    {preview() ? labels.draftAlgorithmHint : labels.defaultAlgorithmHint}
                  </Text>
                  <Each of={algorithms()} key={(option) => option.id}>
                    {(option) => (
                      <Toggle
                        accessibilityLabel={`${labels.chooseAlgorithm}: ${option().name}`}
                        pressed={currentAlgorithm()?.id === option().id}
                        onChange={() => {
                          // The controlled choice stays selected; pressing it again closes the picker.
                          void chooseAlgorithm(option().id).then(() => {
                            if (currentAlgorithm()?.id === option().id) algorithmsOpen.set(false);
                          });
                        }}
                        disabled={algorithmLocked()}
                        style={{
                          minHeight: 64,
                          paddingVertical: 12,
                          flexDirection: "row",
                          gap: 12,
                          borderBottomWidth: 0.5,
                          borderColor: palette().line,
                        }}
                        activeStyle={{ opacity: 0.7 }}
                      >
                        <View
                          style={{
                            width: 18,
                            height: 18,
                            marginTop: 3,
                            borderRadius: 9,
                            borderWidth: 1,
                            borderColor: palette().muted,
                            alignItems: "center",
                            justifyContent: "center",
                          }}
                        >
                          <If when={currentAlgorithm()?.id === option().id}>
                            <View
                              style={{
                                width: 8,
                                height: 8,
                                borderRadius: 4,
                                backgroundColor: palette().ink,
                              }}
                            />
                          </If>
                        </View>
                        <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
                          <Text
                            style={{
                              ...textStyle(),
                              fontWeight: currentAlgorithm()?.id === option().id ? 600 : 400,
                            }}
                          >
                            {option().name}
                          </Text>
                          <If when={option().experimental}>
                            <Text style={{ ...noteStyle(), fontSize: 12.5 }}>
                              {labels.experimental}
                            </Text>
                          </If>
                          <Text style={noteStyle()}>{option().description}</Text>
                          <If when={currentAlgorithm()?.id === option().id}>
                            <Text style={noteStyle()}>{labels.selectedAlgorithm}</Text>
                          </If>
                        </View>
                      </Toggle>
                    )}
                  </Each>
                </ToggleGroup>
              </If>
              <If when={recalculating()}>
                <Text android={{ accessibilityLiveRegion: "polite" }} style={noteStyle()}>
                  {labels.recalculating}
                </Text>
              </If>
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
          <If when={message() !== "" && !(preview() && message() === labels.draft)}>
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
          <If when={progress() && !preview()}>
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
            {(reading: () => Preview) => (
              <ScaleReading
                reading={reading}
                phase={compositionPhase}
                replacement={replacement}
                retainedDraft={() => message() === labels.draft}
                recalculating={recalculating}
                detailsOpen={detailsOpen}
                palette={palette}
                labels={labels}
              />
            )}
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
