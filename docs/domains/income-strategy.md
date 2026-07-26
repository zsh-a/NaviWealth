# Income Strategy Framework

> 状态（2026-07-26）：已实现股息、Wheel、LEAPS Call 三类 sleeve 的统一组合框架。

## 1. 定位

Income Strategy 是 FinanceOS 的收益策略组合层。它不拥有股息事件、期权交易或
LEAPS 持仓，而是把这些独立事实源投影成同一种只读组合快照：

```text
事实源 → sleeve adapter → sleeve contribution
                         ↓
                 IncomeStrategyAssembler
                         ↓
       portfolio / underlying / cash flow / risk snapshot
```

每个 sleeve 独立维护自己的生命周期。Wheel 仍按 short put、持股、short call
推进；股息按事件与预测推进；LEAPS 是独立的 long-call 持仓。组合层不得把三者
压进同一状态机。

## 2. 扩展契约

新增策略类型时：

1. 在 `IncomeStrategySleeveKind` 增加稳定 wire 值。
2. 在所属 feature 实现 adapter，输出
   `IncomeStrategySleeveContribution(asset, snapshot)`。
3. snapshot 必须区分：
   - `realizedResult`：已实现经济结果；
   - `projectedCash`：尚未发生的预计现金；
   - `cashFlows`：带 actual / declared / estimated / contingent 状态的现金事实；
   - `capitalAtRisk`、市值、Delta 等风险量；
   - 仅供确定性规则使用的只读 facts。
4. 把 contribution 加入 `portfolioIncomeStrategyProvider` 的输入列表。
5. 仅在确有跨 sleeve 冲突时向 assembler 增加协调规则。

Assembler 对同一标的、同一 sleeve 的重复贡献直接失败，避免两个实现同时成为
来源。没有计划但已有真实仓位的 sleeve 仍会展示，并标记 `unplannedSleeve`。

## 3. 计划与事实

`income_strategy_plans` 只保存用户意图和约束：

- 规范资产 id（`<market>:<symbol>`）；
- 任意 sleeve 组合；
- 总资金预算、年度收益目标；
- 最大仓位权重、Wheel 行权预算、LEAPS 成本；
- 是否保留股息仓位、是否允许股票被 call away。

计划不复制持仓、收益或现金流。真实事实仍由股息中心、投资持仓、期权日志和
LEAPS 持仓表负责。计划使用 `fin:income_strategy_plans` 参与通用 row-state sync。

## 4. 统一语义

- 买入 LEAPS 是现金流出和资产转换，不是即时亏损。
- Wheel premium 只有在结果确定后进入已实现结果。
- 股息预测不会伪装成实际到账。
- `capitalAtRisk` 是各 sleeve 的策略资金占用之和，可能包含同一标的的叠加暴露；
  它不是去重后的净资产。
- 无法归属到具体资产的 90 天股息预测保留为 portfolio-level cash flow，不凭空
  猜测资产归属。

## 5. 协调规则

当前确定性规则包括：

- 组合资金预算、Wheel 行权预算、LEAPS 成本和持仓权重超限；
- short put 与 long call 的叠加下跌暴露；
- 要求保留股息但存在 covered call 的中断风险；
- 已实现的股息和 Wheel 收益不足以覆盖未平仓 LEAPS 成本；
- 缺少行情、Delta、临近到期和计划外仓位。

规则只报告事实、证据和严重度，不自动下单。

## 6. 账本闭环

期权交易日志与 LEAPS 持仓是策略事实源，`OptionsJournalLedgerService` 负责以
确定性 journal id 镜像到 FinanceOS 复式账本：

- LEAPS 开仓：建立 option lot 并扣减现金，费用计入 lot 成本；
- 平仓：移除 lot、增加现金并确认资本损益；
- 到期：移除 lot并确认全部成本损失；
- 行权：移除 option lot，将权利金与行权现金共同计入标的股票成本。

编辑采用 upsert，删除会软删除镜像分录。未选择券商和现金账户时保留策略记录，
但不生成账本镜像，避免猜测账户。

## 7. 产品入口

- `/plan/income`：统一收益策略总览、标的轨道、活动流和计划编辑；
- `/plan/income/options`：期权机会、Wheel 和日志的专用工作区；
- Dividend Center：股息事件和预测的专用工作区。

设备 AI 通过 `get_income_strategy_portfolio` 读取与 UI 相同的快照。它必须区分
实际现金、预计现金与已实现结果，并返回原始实体 evidence anchors。
