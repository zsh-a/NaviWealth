# 14 · 图表库 / Charts

> 选型、统一封装接口、主题接入、性能基准、钻取交互。
>
> 与 06-Analytics、07-FIRE、08-Rebalance、04-资产详情 中所有曲线 / 柱 / 饼图相关。

## 1. 选型对比

| 维度 | `fl_chart` 0.69+ | `syncfusion_flutter_charts` 27+ |
|------|------------------|----------------------------------|
| 许可 | MIT，免费商用 | 商用需 license（Community License 限年收入 < $1M / < 5 人） |
| 包体积（mobile release） | ~120 KB（已含） | ~1.8 MB（多 chart 类型 + 全套 axis） |
| 图表类型 | 折线 / 柱 / 饼 / 雷达 / 散点 | 30+，含 K 线、Funnel、Gauge、Range |
| 自定义渲染 | 完全开放 `CustomPainter` 风格 API | 高，但依赖官方 builder hook |
| 性能（5y 日线 ≈ 1800 点） | 流畅（≥ 55 fps，关闭曲线插值后） | 流畅（内置 `dataPointAnimationDuration`，可视区裁剪） |
| Web 支持 | 一等公民（Canvas / CanvasKit 一致） | 支持，但部分图表 SVG fallback |
| 维护节奏 | 高频小版本 | 季度大版本 + 持续修补 |
| 文档 / 社区 | 中等，README + cookbook | 完善，含示例工作台 |
| 主题接入 | 无内置 token，需用户传入 `Color` | 内置 ThemeData，但仍需手动桥接到我们的 `MarketColors` |

### 决策

**选择 `fl_chart` 作为基础渲染层。** 理由：

1. **许可干净。** NaviWealth 走开源 / 自托管路线，不引入需要登记 + 续期的商用依赖；后续若要发个人版 + 团队版双轨，许可成本会再翻倍。
2. **包体积。** Web 首屏 JavaScript 预算为 gzip ≤ 800 KB（见 `../web-bundle.md`），多出 ~1.7 MB 不可接受。
3. **够用。** 当前所有页面（Dashboard / Analytics / FIRE / Rebalance / Asset Detail）只需要 line / bar / pie / area / stacked，fl_chart 全部覆盖。
4. **可替换。** 通过 `lib/design_system/charts/` 的统一封装层屏蔽底层 API；将来真正出现 Syncfusion 才有的图表（Funnel / Gauge / OHLC），只需新增一个 `syncfusion` adapter，业务代码无感。

**何时重新考虑 Syncfusion：**
- 出现需要 OHLC / K 线 / Funnel / TreeMap 的场景（目前路线图无）
- fl_chart 性能在 ≥ 50k 点场景下出现卡顿，且降采样无法满足产品需求
- 公司形态变更，可承担每席位年费

## 2. 统一封装接口

封装目录：`lib/design_system/charts/`。设计目标：

- **数据先行。** 业务代码只构造 `ChartSeries` / `CategorySeries` / `Slice`，不直接接触 `LineChartBarData` 等底层类型。
- **主题自动接入。** 颜色序列、坐标轴 / tooltip 字号、网格颜色全部来自 `Theme.of(context)` + `MarketColors` + `SemanticColors`。业务代码不能传 `Color` 字面量。
- **可选项稀疏。** 默认参数覆盖 90% 用例；高级定制通过 `customize: (data) => data.copyWith(...)` 钩子下沉到 fl_chart。
- **可访问性。** 所有图表接受 `semanticLabel`，并在 mode == `colorblind` 时自动叠加 dash / shape 区分。

### 2.1 数据模型

```dart
/// 一条折线 / 面积 / 堆叠柱里的「序列」
class ChartSeries {
  final String name;
  final List<ChartPoint> points;     // X 是时间戳或离散索引
  final SeriesIntent intent;         // primary / benchmark / projection / muted
  final SeriesEmphasis emphasis;     // line | area | dashed | dotted
}

class ChartPoint {
  final double x;        // 时间戳 ms 或 类目索引
  final double y;
  final Object? meta;    // 透传给 tooltip / drill-down callback
}

/// 离散类目（柱状图、饼图）
class CategorySeries {
  final String name;
  final List<CategoryDatum> data;
  final SeriesIntent intent;
}

class CategoryDatum {
  final String label;
  final double value;
  final Color? color;    // 仅在调色板冲突时显式覆盖
  final Object? meta;
}

/// 饼图切片
class Slice {
  final String label;
  final double value;
  final Color? color;
  final Object? meta;
}
```

`SeriesIntent` 决定颜色与字重，跟 `MarketColors` / `ColorScheme` 双向映射：

| Intent | 颜色来源 | 用途 |
|--------|----------|------|
| `primary` | `colorScheme.primary` | 用户自己组合的曲线 |
| `benchmark` | `accentSequence[i]` | 对照基准（沪深 300、S&P 500） |
| `projection` | `colorScheme.tertiary`（虚线） | 模型预测（车辆折旧、FIRE 预测） |
| `muted` | `colorScheme.onSurfaceVariant` | 上下文参考（去年同期、目标线） |
| `up` / `down` | `MarketColors.up` / `down` | 直方图涨跌、贡献度归因 |

调色板序列 `accentSequence` 在 `chart_palette.dart` 中定义，不进 `ColorPalette` —— 这些颜色只用于图表，不用于 UI 控件。

### 2.2 公开组件

```dart
NwLineChart(
  series: [...],
  xAxis: TimeAxis(format: AxisDateFormat.monthYear),
  yAxis: ValueAxis.currency(currency: 'CNY'),
  drillDown: ChartDrillDown.point((point) => ...),
)

NwAreaChart(
  series: [...],            // 单序列 → 自动加 12% alpha 填充；多序列 → 顺序堆叠
  stacked: true,
)

NwBarChart(
  groups: [...],            // 每组若干 bar；stacked: true 时上下堆叠
  stacked: false,
  yAxis: ValueAxis.percent(),
)

NwPieChart(
  slices: [...],
  hole: 0.6,                // donut；0 = 实心
  drillDown: ChartDrillDown.slice((slice) => ...),
)
```

未来若新增 Scatter / Radar，加新组件即可，不动现有 API。

### 2.3 主题接入细节

- **网格 / 边框：** `SemanticColors.divider`（已是色板里淡的颜色）
- **轴标签字体：** `TypographyTokens.numericCaption`（带 tabular figures）
- **Tooltip 背景：** `colorScheme.inverseSurface`，前景 `colorScheme.onInverseSurface`
- **空数据态：** 渲染 `EmptyChartPlaceholder`，避免业务代码自己写 if/else
- **暗色：** 不需特别处理，所有颜色源都是 `ThemeExtension`，跟随 `Theme.of`

### 2.4 大数据降采样

公开工具函数 `downsampleLttb(points, targetCount)`（[Largest-Triangle-Three-Buckets](https://skemman.is/handle/1946/15343) 算法）。所有 `Nw*Chart` 在 `points.length > 500` 且未禁用时自动调用 `downsampleLttb(points, 500)`。

- 算法是 O(n)，1800 点 → 500 点 < 0.5 ms
- 保留首点 / 末点 / 局部极值，视觉上无可见差异
- 业务代码可通过 `downsample: false` 关闭（如审计需要原始密度）
- tooltip / drill-down 的 `meta` 对象会用最近邻还原，不会丢

性能基准见 § 4。

## 3. 钻取交互（Drill-Down）

钻取是 finance 应用的核心：用户点曲线某段 → 看那段时间组合切片；点饼图某块 → 看该大类下的明细。

### 3.1 模型

```dart
sealed class ChartDrillDown {
  const factory ChartDrillDown.point(ValueChanged<ChartPoint> onTap) = _PointDrillDown;
  const factory ChartDrillDown.range(ValueChanged<DateTimeRange> onRange) = _RangeDrillDown;
  const factory ChartDrillDown.slice(ValueChanged<Slice> onTap) = _SliceDrillDown;
  const factory ChartDrillDown.bar(ValueChanged<CategoryDatum> onTap) = _BarDrillDown;
}
```

封装层把 fl_chart 的 `LineTouchData` / `PieTouchData` / `BarTouchData` 桥接到这个 callback。业务代码不需要碰 `FlTouchEvent`。

### 3.2 行为约定

- **单击：** 触发 `onTap` / `onRange`。Mobile 即点即响；Desktop 鼠标点击。
- **长按 + 拖动（mobile）/ 框选拖动（desktop）：** 触发 `range` 钻取，参数是 `DateTimeRange`。封装层负责将像素 → 数据点反向映射。
- **触觉：** 单击触发轻量 `HapticFeedback.selectionClick()`（仅在 platform == iOS / Android）。
- **可访问性：** 暴露 `onSemanticDrillDown`，`TalkBack/VoiceOver` 听到「轴: 2025-03，值: ¥123,456」。

### 3.3 视觉

- 选中点：直径 +2，颜色 `intent` 的 container 变体
- range 框选：`SemanticColors.scrim` 上覆，边界 `colorScheme.primary`

## 4. 性能基准

`test/design_system/charts/chart_performance_benchmark.dart` 在 build 时运行：

| 场景 | 数据量 | 目标 | 实测（M2 macOS, profile mode 模拟） |
|------|--------|------|-------------------------------------|
| 折线（默认降采样开） | 1800 点 → 500 | 首帧 ≤ 16 ms | ✅ ~6 ms |
| 折线（降采样关） | 1800 点 | 首帧 ≤ 32 ms | ✅ ~14 ms |
| 双序列 + 基准 | 1800 + 1800 | 首帧 ≤ 32 ms | ✅ ~12 ms（降采样后） |
| 堆叠柱 | 24 组 × 5 序列 | 首帧 ≤ 16 ms | ✅ ~3 ms |
| 饼图 | 12 切片 | 首帧 ≤ 8 ms | ✅ ~2 ms |
| LTTB 降采样 | 10k → 500 | 单次 ≤ 5 ms | ✅ ~1.2 ms |

数字会随设备波动；CI 中的断言只校验「不超过预算 4×」，避免回归引入 30 倍劣化时无人发现。

## 5. 与设计 Token 的同步

- `chart_palette.dart` 的 `accentSequence` 与 `06-analytics.md` 第 6 节"颜色序列"一一对应
- 所有可被业务直接传入的颜色都通过 `SeriesIntent` 枚举或 `MarketColors`，禁止裸 `Color`
- `pubspec.yaml` 中固定 `fl_chart: ^0.69.2`，升级走 RFC

## 6. 替换底层渲染器的成本评估

如果将来确需切到 syncfusion：

1. 新建 `lib/design_system/charts/_syncfusion_adapter/` 镜像 `_fl_chart_adapter/` 的目录结构
2. 在 `Nw*Chart` 内部按 `ChartRenderer.of(context)` 选择实现
3. 所有业务调用方零改动
4. 测试需要补一组 syncfusion-specific 场景

预计成本：每种图表 1-2 人日 + 主题桥 1 人日 + 集成 1 人日 = 总计 ~10 人日。
