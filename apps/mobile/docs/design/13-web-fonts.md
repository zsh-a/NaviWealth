# 13 · Web 字体子集化（FIR-38）

> 中文字体若全量打包会膨胀首屏几十 MB；本文档记录 NaviWealth Web 端字体子集化的实现与运维。

## 决策摘要

| 维度 | 选择 | 理由 |
|------|------|------|
| 基础字体 | **Noto Sans SC Variable**（OFL） | 单文件覆盖 100–900 全权重；OFL 许可允许任意嵌入 / 子集化；`fonts.google.com` 上游稳定，可复现。 |
| 子集工具 | `pyftsubset`（fontTools） | Brotli woff2 输出，对 Variable 字体保留 wght 轴；子集表达力强（unicode / 字形 / GSUB 特性）。 |
| 文件分层 | base + ext 两级 | base 覆盖首屏；ext 走 `unicode-range` 触发延迟下载。 |
| 加载策略 | `<link rel="preload">` + `font-display: swap` | 首屏 woff2 与 `flutter_bootstrap.js` 并行下载；不阻塞首字渲染。 |
| 离线 fallback | `local()` + `font-family` 系统栈 | Mac/Win/Linux 已安装常见 SC 字体的用户直接使用本地，绕过下载；离线首访由系统字体兜底。 |

## 文件清单

```
apps/mobile/
├── tool/
│   ├── build-cn-fonts.sh        # 主入口：venv → 取源 → 扫描 → 子集化 → 校验大小
│   └── cn_font_chars.py         # 扫描 lib/ 抽取 CJK，叠加 ASCII / 标点 / GB 2312
├── assets/fonts/                # 产物（gitignored）
│   ├── app-cn-base.woff2        # 首屏 ≈ 120 KB（预算 ≤ 250 KB）
│   └── app-cn-ext.woff2         # 扩展包 ≈ 1.7 MB（按需）
├── pubspec.yaml                 # 注册 AppCnSans 字体族
├── web/index.html               # @font-face + preload + font-display: swap
├── lib/design_system/tokens/typography_tokens.dart
│                                # fontFamily = 'AppCnSans' + fontFamilyFallback
└── .dart_tool/cn_fonts/         # venv + 源字体缓存（gitignored）
```

## 流水线

```
       lib/**/*.{dart,arb,json,md}
                │
                ▼
        cn_font_chars.py  ──── + ASCII / 标点 / 箭头 / 货币 + GB 2312
                │
        ┌───────┴───────┐
        ▼               ▼
   base.txt         ext.txt
        │               │
   pyftsubset      pyftsubset    ←── NotoSansSC[wght].ttf  (sha256-pinned)
        │               │
        ▼               ▼
 app-cn-base.woff2  app-cn-ext.woff2
        │               │
        └────► assets/fonts/ ────► flutter build web ────► build/web/assets/assets/fonts/
```

## 字符集策略

`cn_font_chars.py` 写两份 `unicode-list`：

- **base** = `ASCII printable` ∪ `Latin-1 currency / sign` ∪ `general punctuation` ∪ `arrows / bullets` ∪ `currency block` ∪ `CJK punctuation (U+3000-303F)` ∪ `halfwidth/fullwidth (U+FF00-FFEF)` ∪ **`lib/` 中出现过的全部 CJK 字符**。
- **ext** = `GB 2312 Level-1 + Level-2`（≈ 6763 字）减去 base 已覆盖的部分。

> 当前扫描产生 156 个真实使用的 CJK 字符；叠加 ASCII / 标点后 base 集合 ~654 个 code points，woff2 产物 ~120 KB。

## @font-face 加载行为

```css
@font-face {
  font-family: 'AppCnSans';
  font-display: swap;
  src: local('PingFang SC'), local('Microsoft YaHei'), …,
       url('assets/assets/fonts/app-cn-base.woff2') format('woff2');
  unicode-range: U+0020-007F, U+3000-303F, U+4E00-9FFF, …;
}
@font-face {
  font-family: 'AppCnSans';
  font-display: swap;
  src: url('assets/assets/fonts/app-cn-ext.woff2') format('woff2');
  unicode-range: U+3400-4DBF, U+4E00-9FFF, U+F900-FAFF, U+20000-2A6DF;
}
```

- `local()` 在 `url()` 之前 → 系统已装的 `PingFang SC` / `Microsoft YaHei` / `Source Han Sans SC` / `Noto Sans SC` 直接命中，零下载。
- `font-display: swap` → 浏览器立即用下一个 `font-family` 渲染（系统 sans-serif），woff2 到达后再 reshape，**不阻塞首屏**。
- 两个 `@font-face` 同名同权重 → 浏览器按 `unicode-range` 决定要拿哪个文件；ext 在 base 不覆盖某字符时才被请求。
- `<link rel="preload" as="font" crossorigin>` → 把 base 文件请求提前到 HTML 解析阶段，不必等到 CSSOM 构建完。

`html, body` 也声明了相同的 fallback 链，覆盖 Flutter 渲染之前 / 渲染之外的浏览器原生文本（loading 占位、错误页等）。

## 与 Flutter 的接线

`pubspec.yaml`：

```yaml
flutter:
  fonts:
    - family: AppCnSans
      fonts:
        - asset: assets/fonts/app-cn-base.woff2
        - asset: assets/fonts/app-cn-ext.woff2
```

`typography_tokens.dart`：

```dart
static const String fontFamilySans = 'AppCnSans';
static const List<String> fontFamilyFallback = <String>[
  'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei',
  'Source Han Sans SC', 'Noto Sans SC', 'sans-serif',
];
```

每个 `TextStyle` 都同时设置 `fontFamily` 与 `fontFamilyFallback`，在 CanvasKit 内部回退到平台字体（与 HTML 一侧一致）。

## 运维

- **本地**：`apps/mobile/tool/build-cn-fonts.sh`，与 `setup-drift-web.sh` 一起在 `flutter run -d chrome` 之前跑一次。源字体与 venv 缓存在 `.dart_tool/cn_fonts/`，重复执行近似 zero-cost。
- **CI**：`.github/workflows/mobile.yml` 的 `build-web` 任务在 `flutter build web` 之前调用脚本；脚本内置 250 KB 预算硬校验（`BASE_BUDGET_BYTES`），超标即失败。
- **升级源字体**：把 `NOTO_SHA256` 设为新的 sha256；脚本会重新拉取并校验。
- **新增 UI 文案**：脚本会自动把新的 CJK 字符纳入 base 子集，下一次 `build-web` 即生效，无需手工维护字符表。
- **真正的高频字符进 base**：如发现某些动态字段（如行情来源名）频繁触发 ext 下载，可在 `cn_font_chars.py` 的 `_ALWAYS_INCLUDE` 中显式补入。

## 验收对照

| 验收项 | 满足方式 |
|------|---------|
| 选定基础字体 | Noto Sans SC Variable（OFL）。 |
| 接入 fontmin / pyftsubset 工具链 | `tool/build-cn-fonts.sh` + `cn_font_chars.py`，CI 集成。 |
| 输出 `app-cn-base.woff2` + 按需扩展包 | base + ext 两级；`unicode-range` 触发懒加载。 |
| `pubspec.yaml` 与 Web 字体注册 | 已注册 `AppCnSans` 字体族，HTML 同步声明 `@font-face`。 |
| `font-display: swap` | base / ext 两个 `@font-face` 块均启用。 |
| 首屏字体下载 ≤ 250 KB | base 实测 ~120 KB，CI 内置硬校验。 |
| 离线 fallback 到系统 SC 字体 | `local()` 优先 + `fontFamilyFallback` + `html, body` font stack 三层兜底。 |

## 后续可选优化

- **Service Worker 缓存**：FIR-36（PWA）落地后让 SW 把两个 woff2 加入 precache，重访 0 延迟。
- **路由级懒加载**：`AI 对话` / `资产详情备注` 等富文本场景如果触发 ext 频繁，可在路由进入时主动 `document.fonts.load('1em AppCnSans')` 预热。
- **Variable 轴裁剪**：如确认 100/200/300/800/900 永远不用，可加 `--variations='wght=400,500,600,700'` 进一步压 base。
