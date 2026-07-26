# Income Strategy Framework

> 状态（2026-07-26）：股息、Wheel、LEAPS Call 已统一到开放式模块框架。

## 1. 定位与边界

Income Strategy 是 FinanceOS 的收益策略组合层。它不拥有股息事件、持仓、
期权日志或 LEAPS 仓位，只把各自的事实源投影成统一只读快照：

```text
事实源 → IncomeStrategyModule → sleeve contribution ┐
计划   → sleeve intents                             ├→ assembler → rules → UI / AI
汇率   → base-currency valuation                    ┘
```

每个 sleeve 保留自己的生命周期；组合层不建立一个覆盖所有策略的超级状态机。
Wheel、股息和 LEAPS 的写入仍由所属 feature/repository 负责。

## 2. 核心契约

- `IncomeStrategySleeveKind`、`IncomeStrategyCashFlowKind`、
  `IncomeStrategyRiskCode` 是稳定 wire id 值对象，不是封闭 enum。
- `IncomeStrategyModule` 是扩展单元，一次注册贡献数据加载、adapter、规则和 UI
  presentation。
- `IncomeStrategyAssembler` 只负责按 canonical `assetId` 组合、校验和执行注册规则；
  它不知道任何内置 sleeve id。
- 模块详情实现 `IncomeStrategySleeveDetails`；跨模块规则只读取
  `IncomeStrategyExposure`。禁止使用动态 `Map<String, Object?> facts`。
- 同一资产、同一 sleeve 的重复贡献直接失败，防止多个事实源争夺所有权。

新增模块只需：

1. 定义模块自己的 wire id、settings、adapter、details 和规则；
2. 输出 `IncomeStrategySleeveContribution`，金额已经换算为组合基准币；
3. 定义本地化 presentation；
4. 在 `kIncomeStrategyModules` 增加一个注册项并补测试。

无需修改 assembler、共享计划表列、总览页 switch 或 AI 序列化分支。

## 3. 金额与时间语义

所有金额使用 `Money`。每条现金流同时保留：

- `amount`：事实发生时的原币金额；
- `baseAmount`：按事实日期换算的组合基准币金额；缺失汇率时为 `null`；
- `source`：类型化的实体表、实体 id 和证据完整性。

所有汇总只允许对基准币金额求和。缺失 FX、行情或 Delta 会降低
`IncomeStrategyMetricQuality` 并产生规则风险，绝不把不同币种 Decimal 直接相加。

当前已实现结果统一采用 calendar YTD：

- `periodStart = 当年 1 月 1 日`；
- `asOf` 由 provider 注入，测试可固定时间；
- 90 天预测和 YTD 已实现值不会混为一个数字；
- LEAPS 买入是现金流出和资产转换，不是即时亏损；
- Wheel premium 仅在关闭、到期或行权等结果确定后进入已实现值。

## 4. 计划是唯一策略意图源

`income_strategy_plans` 每个 owner + asset 只有一行，稳定行 id 与 asset id 分离。
它只保存：

- canonical `<market>:<symbol>` 资产 id；
- 通用资本预算、年度收入目标、最大仓位权重；
- `sleeveIntentsJson`：模块是否启用及模块自有 typed settings；
- 备注和通用 sync metadata。

Wheel 标的清单已合并为 Wheel intent。`allowPut`、`allowCall`、最大买入价、
最小卖出价、最大行权金额和是否允许被 call away 都属于该 intent。
不存在第二份 `approved_underlyings` 权威表；Options scanner 读取由计划投影出的
`ApprovedUnderlying`。

真实持仓、收益和现金流不复制到计划。没有计划但已有真实仓位仍展示，并由
`UnplannedSleeveRule` 标记。

## 5. 规则层

规则实现 `IncomeStrategyRule`，由模块或 core registry 注册：

- core：计划外 sleeve、资本预算、仓位集中度、年度收入进度；
- coordination：short put + long call 叠加下跌暴露、股息仓位被 call away、
  LEAPS 成本覆盖、LEAPS 成本上限、Wheel 行权预算；
- module：缺失行情、Delta、FX、估值过期、临近到期等。

规则只输出稳定 code、严重度、涉及 sleeves 和结构化 evidence；不自动交易。

## 6. 身份、持久化与同步

- 计划、期权日志、LEAPS 仓位都持久化 canonical `underlyingAssetId`；
- symbol 只用于展示，不用于跨来源 join；
- 同步边界使用 `fin:income_strategy_plans`、`fin:options_trade_journal` 和
  `fin:options_leaps_call_positions`；
- 行情、机会缓存及其它可重算结果保持本地派生数据。

期权和 LEAPS 仍由 `OptionsJournalLedgerService` 以确定性 journal id 镜像到
FinanceOS 复式账本。未选择账户时保留策略事实，但不猜测账本账户。

## 7. 产品入口

- `/plan/income`：统一总览、标的轨道、活动和策略计划；
- `/plan/income/wheel`：Wheel 生命周期专业钻取；
- `/plan/income/options`：期权机会扫描与日志工作区；
- Dividend Center：股息事件和预测工作区。

顶层 Plan 只暴露统一收益策略入口，Wheel 不再作为平级的第二套信息架构。
计划表单按已注册模块渐进展开模块设置；状态、现金流和风险文案由 presentation
registry 本地化，并为未知第三方模块提供稳定 fallback。

设备 AI 的 `get_income_strategy_portfolio` 与 UI 读取同一快照，返回 YTD 周期、
金额质量和原始实体 evidence anchors。
