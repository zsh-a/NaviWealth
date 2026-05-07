# NaviWealth 产品路线图（Roadmap）

> 文档版本：2026-05-08 · 当前应用版本：0.2.5
> 分析基础：仓库现状全量扫描（feature 模块、backend 路由、同步协议、测试覆盖、git 历史 FIR-1 ~ FIR-134）。
> 本路线图是**方向性参考**，不是承诺；优先级会随用户反馈与开发节奏调整。

---

## 0. 当前状态速览

| 维度 | 现状 |
|------|------|
| 平台覆盖 | iOS / Android / Web（PWA 完成，桌面端 Shell 在做：FIR-106） |
| 核心域 | 资产 / 账户 / 投资 / 负债 / 支出 / FIRE / 再平衡 / 分析 / AI 助手 已上线 |
| 同步 | Sync Protocol v1.0 已冻结（轮询 30s，HLC + OpLog + 行级 LWW） |
| 后端 | Cloudflare Workers + D1，路由极简（health/auth/me/sync/ai） |
| 测试 | 62 个 `*_test.dart`，分布不均；E2E sync 框架存在但未落地 |
| 国际化 | en + zh；设计稿提及 ja 尚未支持 |
| 安全 | 原生端 SQLCipher；Web 端为 sqlite3 WASM（弱于原生）；JWT HS256 单用户 |

**优势**：投资模块（35 文件，FIFO/LIFO/avg、FX PnL、税务）、AI 对话（22 文件，SSE 流 + 提案/确认）、分析（集中度风险、基准对比）。
**缺口**：`me/`、`more/` 仅占位；`plan/`、`portfolio/` 是薄壳；活动 Feed 单薄；后端 AI 工具中成本基础是粗略近似；Web 安全与 a11y 自动化空白。

---

## 1. 短期（1–2 个月）— 补完已有功能 / 还技术债

目标：把"已经摆上去但还没做完"的部分收尾，让 0.3.x 系列功能闭环。

### 1.1 补完占位模块
- **`features/me/`、`features/more/`**：当前目录为空，需明确产品定位（个人中心？设置入口？快捷面板？）；与 `settings/`、`activity/` 的边界要画清，避免重复。
- **`features/plan/`**：目前只是路由壳（2 个文件），转发到 FIRE / analytics / rebalance。建议要么做成统一的"理财规划工作台"（goal-driven 视图），要么直接合并入 FIRE，删除该模块。
- **`features/portfolio/`**：作为 `assets/` 的薄包装存在；评估能否合并，或将其升级为"组合视角"（按账户/币种/资产类别多维聚合）。

### 1.2 仪表盘洞察补全
- `lib/features/home/data/dashboard_insights_provider.dart:7` 的 TODO："Add more insights when providers are available"。
- 待 providers 成熟后接入：本月支出/上月对比、净资产周/月变化、风险告警 Top-N、再平衡偏离提醒、AI 生成的每周摘要。

### 1.3 后端 AI 工具落地
- `apps/backend/src/ai/tools.rs`：成本基础（FIFO/LIFO）目前是粗略近似，需把客户端的持仓引擎移植到 Worker，或定义"客户端先算、提案携带证据"的协作协议。
- 跨币种合并：当前未做自动 FX 汇总；要支持多币种组合的总览查询。
- 写入提案 `apps/backend/src/ai/proposals.rs` 的 guardrails 需要补充更细的 schema 校验与冲突回退路径。

### 1.4 活动 Feed（`features/activity/`）
- 仅 4 个 UI 文件 + 1 个 domain 模型，缺少筛选（按账户、按时间、按事件类型）、分页、空状态/加载骨架、跳转到详情。
- 缺 data/repository 层；建议明确：activity 是 oplog 投影还是独立事件流。

### 1.5 Web 端体验补齐
- 备份/恢复：`file_saver_stub.dart` / `file_saver_web.dart` 还是 stub，需走 File System Access API（Chromium）+ 下载兜底。
- 安全：Web 端 sqlite3 WASM 没有 SQLCipher 等价方案；至少加上"敏感字段（密码/TOTP）应用层加密"或显式提示用户 Web 端不存敏感凭证。
- 路径策略：核对 `docs/web-routing.md` 检查清单，确保所有 deep link 都能直达。

### 1.6 测试空白补齐
- 没有测试目录的 feature：`me`、`more`、`plan`、`portfolio`。
- 测试明显偏薄的：`activity`（1 个测试）、`home`（仅 domain 测试，无 widget 测试）。
- 文档（`docs/sync-e2e-manual.md`、CLAUDE.md）提到的 `SyncCluster` / `VirtualDevice` E2E 框架尚未在 `test/features/` 落地，需要至少 3–5 个端到端用例：双设备并发写、离线追赶、墓碑同步、HLC 时钟漂移、冲突 LWW。

---

## 2. 中期（3–6 个月）— 扩展产品能力

目标：把 NaviWealth 从"看 + 记"升级到"规划 + 决策"。

### 2.1 预算与现金流（新模块）
当前文档目录中**无预算/现金流/计划交易/告警**的对应实现。建议引入 `features/budget/`：
- 月度/周度预算编排（按 expense 分类）；
- 实时进度条 + 超支预警；
- 计划交易（recurring transactions）：工资、订阅、还款、定投；
- 现金流瀑布图（与 FIRE 模块联动）。

### 2.2 投资进阶
- 观察列表 / 关注池（watchlist），与 `data/market/` 复用行情通道；
- 分红与拆股事件流（目前 `features/investment/` 偏交易，事件流薄弱）；
- 税务报表导出（年度总结、已实现盈亏 + 股息），目前有 `features/investment` 内的 tax 模块但缺导出能力；
- 自动定投策略（DCA）模拟与回测（与 rebalance 引擎联动）。

### 2.3 多币种与汇率体验
- 设置中的手动 FX 汇率 → 自动拉取 + 历史汇率曲线；
- `domain/currency_converter` 已有，需要 UI 层在所有金额展示位置统一展示原币 + 折算（hover/tap toggling）；
- 后端聚合接口支持 base currency 切换实时刷新。

### 2.4 桌面端 Shell 完整化
基于近期 FIR-87（命令面板）、FIR-106（侧边栏 + 列偏好）的方向：
- 命令面板覆盖主要导航与"快速记账""新交易""跳转账户"等高频动作；
- master-detail 布局在 accounts / assets / investments 全面铺开；
- 键盘快捷键体系（参考 `core/shortcuts/`）补全并在帮助页可发现。

### 2.5 AI 助手能力升级
- 从"对单条问题回答"扩展到"带上下文的财务顾问"：会话级 memory（已有 multi-session）+ 用户画像（消费习惯、风险偏好）；
- 提案系统（FIR-60/66）增加批量提案与回滚（撤销最近 N 个 AI 写入）；
- 工具调用可视化升级：长任务进度、引用证据（哪些交易/账户支撑了这个结论）。

### 2.6 可观测性与运营
- 客户端崩溃 / 性能埋点（已无方案；最简方案：opt-in，本地 + 上报到 Workers）；
- 后端 metrics：`docs/sync-monitoring.md` 已有基线，把告警接入 Cloudflare Analytics + 邮件/Slack。

---

## 3. 长期（6–12 个月+）— 平台化与差异化

### 3.1 同步协议 v2（解冻）
当前 v1 是轮询 + 行级 LWW，文档 `docs/sync-protocol.md` 已明确以下为 out-of-scope：
- 端到端加密（FIR-31）；
- WebSocket / SSE 实时推送（FIR-33）；
- 字段级 LWW（目前是行级）。
长期需要重新评估：
- **E2EE**：服务端零知识，密钥派生自登录密码 + 设备认证；
- **实时推送**：Cloudflare Durable Objects + WebSocket，把 30s 轮询降到秒级；
- **冲突可读化**：冲突历史给用户可见，必要时提供合并 UI。

### 3.2 多用户 / 协作
当前后端是 single-user JWT，无注册端点。长期方向：
- 家庭账户（共享部分账户、保留私密账户的可见性控制）；
- 财务顾问只读视图（导出加密报表 + 签名链接）。

### 3.3 数据导入生态
- 银行 CSV / OFX / QIF 导入；
- 经纪商对接（从地区开始：美股 IBKR、港股富途、A 股 Tushare/同花顺导出）；
- 支付平台（支付宝/微信账单解析）。

### 3.4 国际化扩展
- 增加 ja（设计稿 §1.4 已提到 textScaleFactor 检查）、zh-Hant、ko；
- 区域化：日期/数字/货币展示按 locale，而不仅是 base currency；
- 货币列表覆盖完整 ISO 4217（目前未审计完整度）。

### 3.5 高级分析
- 因子分析（Beta、行业暴露、地理暴露）；
- Monte Carlo 报表导出（FIRE 已有，需要可分享版本）；
- 与基准（标普、沪深 300、自定义篮子）的对比已有，可加滚动相关性 / 回撤分析。

---

## 4. 跨领域工程项

这些不是单一 feature，但会影响所有功能的可信度。

### 4.1 测试
- **覆盖率**：当前目标 60%（项目）/ 70%（patch），需检查 `me`、`more`、`plan`、`portfolio`、`activity` 是否在 codecov ignore 之外；
- **黄金图测试（visual regression）**：`docs/visual-baseline/` 已有规划（FIR-113），需要在 CI 落地（platform pinned，每个主页面至少 1 个 golden）；
- **E2E sync**：见 §1.6；
- **a11y 自动化**：`docs/design/12-usability-self-check.md §7` 提到引入 `dart_a11y` 或自定义 Semantics 校验器，目前是手工 checklist。

### 4.2 性能
- Web 包体：`docs/web-bundle.md` 有基线，需把 deferred imports 覆盖率写进 CI 阈值（每页首屏 ≤ X KB）；
- 大账户/大持仓场景压测：100k+ journal entries 的 Drift 查询、滚动 + 图表渲染基准；
- 启动时间：冷启动 → 仪表盘可交互的预算（目标：原生 < 1.5s，Web < 3s）。

### 4.3 可访问性 & 可用性
- Semantics labels 全量审计（特别是图表、自定义手势区）；
- 触达区 ≥ 44×44dp 自动校验；
- 文字缩放至 130% / 150% 不破版（设计稿要求）。

### 4.4 安全
- Web 端敏感数据存储模型重审（见 §1.5）；
- JWT 刷新窗口、设备撤销链路压测（已有 FIR-29/30/37 基础）；
- 依赖审计：`security.yml` 已周扫 + 锁文件变更触发，可加 SBOM 产出。

---

## 5. 已知技术债

| 债务 | 文件/位置 | 影响 |
|------|----------|------|
| Backend 成本基础粗略近似 | `apps/backend/src/ai/tools.rs:34-39` | AI 提案对成本基础类问题的回答可能与客户端不一致 |
| Web 端弱于原生的存储加密 | `core/db/connection_*.dart` | Web 端不应承诺与原生同等的安全等级 |
| `me/` `more/` 空目录 | `lib/features/me/`、`lib/features/more/` | 占位含义不明，影响新人理解 |
| `plan/` `portfolio/` 薄壳 | `lib/features/plan/`、`lib/features/portfolio/` | 模块边界与 FIRE/assets 重叠 |
| 单一后端路由表无 domain endpoint | `apps/backend/src/routes/` | 所有非 sync 查询走 oplog 物化，未来扩展可能撞瓶颈 |
| Activity Feed 缺 data 层 | `lib/features/activity/` | 难以扩展过滤/分页/事件类型 |

---

## 6. 明确不做（Out of Scope，至少近 6 个月）

- 加密货币交易撮合 / DEX 对接（仅作为持仓资产呈现）；
- 社交化（晒账本、跟单）；
- 信贷 / 借贷撮合等金融业务（合规风险）；
- 自托管后端打包（Cloudflare Workers 是当前唯一目标）。

---

## 7. 优先级排序（建议）

按"价值 / 完成度"两个维度，建议下一阶段优先做：

1. **【收尾】** 补完仪表盘洞察 + activity feed → 用户每日打开就能看到的体验提升 (§1.2 / §1.4)
2. **【收尾】** `me`/`more`/`plan`/`portfolio` 的产品定位决策 + 合并或落地 (§1.1)
3. **【拓展】** 预算 + 计划交易模块 → 当前最显著的产品空白 (§2.1)
4. **【深耕】** 多币种全局体验 → 已有 domain 基础，UI 层贯通即可获得显著体感 (§2.3)
5. **【基础】** E2E sync 测试 + visual regression 上 CI → 让后续大改不再心虚 (§4.1)

剩余项可在 §1–4 的 backlog 中按 FIR 编号细化跟踪。

---

## 附：与现有文档的关系

- 本文档是**方向**；具体实现细节看 `docs/sync-protocol.md`、`docs/web-routing.md`、`docs/visual-baseline/`、`apps/mobile/README.md`。
- 任务级别跟踪走 FIR-XXX 编号（见 CLAUDE.md 中的引用方式）。
- 路线图调整请提交 PR 同时更新本文件顶部的"文档版本"。
