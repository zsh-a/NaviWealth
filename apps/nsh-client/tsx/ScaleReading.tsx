import { computed, fontScale, reduceMotion, Text, View, windowSize } from "nsh";
import { Button } from "nsh/base";
import type { Signal } from "nsh";
import type { ScaleCopy } from "./scale-copy";
import type { Palette, Preview } from "./scale-types";

/** A review of one measurement. Values and derived masses all come from Rust. */
export function ScaleReading(props: {
  reading: () => Preview;
  phase: () => string;
  replacement: () => boolean;
  retainedDraft: () => boolean;
  detailsOpen: Signal<boolean>;
  palette: () => Palette;
  labels: ScaleCopy;
}) {
  const { reading, palette, labels, detailsOpen } = props;
  const stacked = computed(() => fontScale() > 1.2);
  const detailStacked = computed(() => stacked() || windowSize().width < 360);
  const kg = () => (reading().measurement.weight_grams / 1000).toFixed(2);
  const status = () =>
    reading().measurement.metrics
      ? labels.complete
      : props.phase() === "waiting"
        ? labels.compositionPending
        : props.phase() === "delayed"
          ? labels.compositionDelayed
          : labels.compositionIncomplete;
  const hint = () =>
    reading().measurement.metrics
      ? props.retainedDraft()
        ? labels.draft
        : labels.reviewHint
      : props.phase() === "waiting"
        ? labels.compositionHint
        : props.phase() === "delayed"
          ? labels.compositionDelayedHint
          : labels.noImpedance;
  const noteStyle = () => ({ fontSize: 13, lineHeight: 19, color: palette().muted });

  function Metric(metric: {
    id: string;
    label: string;
    value: string;
    unit?: string;
    mass?: number | null;
  }) {
    return (
      <View testID={metric.id} style={{ flex: 1, minWidth: 0, gap: 6 }}>
        <Text
          style={{
            ...noteStyle(),
            minHeight: !stacked() && windowSize().width < 360 ? 38 : undefined,
          }}
        >
          {metric.label}
        </Text>
        <Text
          accessibilityLabel={`${metric.label} ${metric.value}${metric.unit ?? ""}`}
          style={{
            fontSize: 26,
            lineHeight: 33,
            fontWeight: 500,
            fontVariant: ["tabular-nums"],
            color: palette().ink,
          }}
        >
          {metric.value}
          <Text style={{ fontSize: 14, fontWeight: 400, color: palette().muted }}>
            {metric.unit ? ` ${metric.unit}` : ""}
          </Text>
        </Text>
        <If when={metric.mass != null}>
          <Text style={{ ...noteStyle(), fontVariant: ["tabular-nums"] }}>
            {`${metric.mass?.toFixed(2)} kg`}
          </Text>
        </If>
      </View>
    );
  }

  function Detail(detail: { label: string; value: string }) {
    return (
      <View
        style={{
          flexDirection: detailStacked() ? "column" : "row",
          alignItems: detailStacked() ? "stretch" : "baseline",
          gap: detailStacked() ? 4 : 16,
          paddingVertical: 10,
          borderBottomWidth: 0.5,
          borderColor: palette().line,
        }}
      >
        <Text style={{ ...noteStyle(), flex: detailStacked() ? undefined : 1 }}>
          {detail.label}
        </Text>
        <Text
          style={{
            fontSize: 14,
            lineHeight: 21,
            color: palette().ink,
            fontVariant: ["tabular-nums"],
            flexShrink: 1,
            textAlign: detailStacked() ? "left" : "right",
          }}
        >
          {detail.value}
        </Text>
      </View>
    );
  }

  return (
    <View testID="scale-preview" style={{ gap: 16, paddingVertical: 4 }}>
      <View style={{ gap: 6 }}>
        <View
          style={{
            flexDirection: stacked() ? "column" : "row",
            alignItems: stacked() ? "stretch" : "baseline",
            justifyContent: "space-between",
            gap: 6,
          }}
        >
          <Text
            testID="scale-status"
            android={{ accessibilityLiveRegion: "polite" }}
            style={{
              fontSize: 15,
              lineHeight: 22,
              fontWeight: 600,
              color: palette().ink,
              flex: stacked() ? undefined : 1,
              minWidth: 0,
            }}
          >
            {status()}
          </Text>
          <Text style={{ ...noteStyle(), flexShrink: 0 }}>{reading().day}</Text>
        </View>
        <Text style={noteStyle()}>{hint()}</Text>
      </View>
      <View
        testID="scale-weight-result"
        style={{
          flexDirection: stacked() ? "column" : "row",
          alignItems: stacked() ? "stretch" : "center",
          justifyContent: "space-between",
          gap: 6,
          paddingBottom: 16,
          borderBottomWidth: 0.5,
          borderColor: palette().line,
        }}
      >
        <Text style={{ ...noteStyle(), color: palette().ink }}>{labels.weight}</Text>
        <Text
          accessibilityLabel={`${labels.weight} ${kg()} kg`}
          style={{
            fontSize: fontScale() > 1.4 ? 28 : windowSize().width < 360 ? 34 : 42,
            lineHeight: fontScale() > 1.4 ? 36 : windowSize().width < 360 ? 42 : 52,
            fontWeight: 500,
            fontVariant: ["tabular-nums"],
            color: palette().ink,
          }}
        >
          {kg().split(".")[0]}
          <Text style={{ color: palette().muted }}>.{kg().split(".")[1]}</Text>
          <Text style={{ fontSize: 15, fontWeight: 400, color: palette().muted }}> kg</Text>
        </Text>
      </View>
      <If when={reading().measurement.metrics}>
        {(metrics: () => NonNullable<Preview["measurement"]["metrics"]>) => (
          <View testID="scale-composition" style={{ gap: 16 }}>
            <View style={{ flexDirection: stacked() ? "column" : "row", gap: 20 }}>
              <Metric
                id="scale-fat"
                label={labels.fat}
                value={metrics().body_fat_percent.toFixed(1)}
                unit="%"
                mass={reading().summary.fat_mass_kg}
              />
              <Metric
                id="scale-bmi"
                label={labels.bmi}
                value={reading().summary.bmi?.toFixed(1) ?? "—"}
              />
            </View>
            <View style={{ height: 0.5, backgroundColor: palette().line }} />
            <View style={{ flexDirection: stacked() ? "column" : "row", gap: 20 }}>
              <Metric
                id="scale-muscle"
                label={labels.muscle}
                value={metrics().muscle_percent.toFixed(1)}
                unit="%"
                mass={reading().summary.muscle_mass_kg}
              />
              <Metric
                id="scale-water"
                label={labels.water}
                value={metrics().water_percent.toFixed(1)}
                unit="%"
                mass={reading().summary.water_mass_kg}
              />
            </View>
            <Text style={noteStyle()}>{labels.estimate}</Text>
          </View>
        )}
      </If>
      <Button
        accessibilityLabel={detailsOpen() ? labels.hideDetails : labels.details}
        onPress={() => detailsOpen.set(!detailsOpen())}
        style={{
          minHeight: 48,
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 12,
          borderTopWidth: 0.5,
          borderColor: palette().line,
        }}
        activeStyle={{ opacity: 0.7 }}
      >
        <Text style={{ ...noteStyle(), flex: 1, color: palette().ink }}>
          {detailsOpen() ? labels.hideDetails : labels.details}
        </Text>
        <View
          style={{
            width: 7,
            height: 7,
            marginRight: 3,
            borderRightWidth: 1.5,
            borderBottomWidth: 1.5,
            borderColor: palette().muted,
            transform: [{ rotate: detailsOpen() ? "225deg" : "45deg" }],
            transitionProperty: "transform",
            transitionDuration: reduceMotion() ? 0 : 160,
          }}
        />
      </Button>
      <If when={detailsOpen()}>
        <View testID="scale-evidence" style={{ gap: 2 }}>
          <Text style={noteStyle()}>{`${reading().device.name} · ${reading().day}`}</Text>
          <Detail
            label={labels.profileSnapshot}
            value={`${reading().measurement.profile.height_cm} cm · ${reading().measurement.profile.age_years} ${labels.ageUnit}`}
          />
          <If when={reading().summary.bmi !== null}>
            <Detail label={labels.bmi} value={reading().summary.bmi?.toFixed(2) ?? "—"} />
          </If>
          <Each
            of={[
              { label: labels.fatMass, value: reading().summary.fat_mass_kg },
              { label: labels.leanMass, value: reading().summary.fat_free_mass_kg },
              { label: labels.muscleMass, value: reading().summary.muscle_mass_kg },
              { label: labels.waterMass, value: reading().summary.water_mass_kg },
            ].filter((item) => item.value !== null)}
          >
            {(item) => <Detail label={item().label} value={`${item().value?.toFixed(2)} kg`} />}
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
            <Text style={{ ...noteStyle(), paddingTop: 12 }}>{labels.derivedNote}</Text>
          </If>
        </View>
      </If>
      <If when={props.replacement()}>
        <Text style={{ fontSize: 15, lineHeight: 22, color: palette().ink }}>
          {`${labels.replace} ${reading().existing_kg?.toFixed(1)} kg`}
        </Text>
      </If>
    </View>
  );
}
