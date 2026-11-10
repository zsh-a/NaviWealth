# NaviWealth nsh 与 Rust 重写方案

状态：阶段 1（技术验证）与阶段 2（最小业务闭环）的工程骨架已落地；真机验收与阶段 3+ 待实施。

采用 nsh 纯 Rust 客户端，先交付 iOS、Android，再扩展 Web。
本方案是新客户端的架构与实施基线；现有 Flutter 文档继续描述当前实现。

从新数据库、新数据空间和新接口契约开始。不建设旧数据迁移、旧备份导入、
旧版本兼容、Flutter 双栈桥接或回退路径。旧代码用于理解业务，功能按用户任务重新组织。

## 实施进度（阶段 1+2，已交付）

- 根 Cargo workspace：`apps/client`（nsh 应用）、`crates/lifeos`（领域中立）、
  `crates/finance`（财务领域）、`crates/platform`（平台接缝 stub）。
  `apps/backend` 与 `third_party/*` 保持独立 workspace，本轮未改动。
- `crates/lifeos`：Money（rust_decimal + 币种，十进制字符串）、HLC（对齐 Flutter
  `hlc.dart` 语义）、独立 DB 工作线程（rusqlite，SQLCipher feature，migrations 从
  user_version 1 起）、KeyStore 接缝（桌面文件回退）、同步引擎（outbox 脏指针、
  LWW、accepted acks、游标、领域重置代次）、加密备份 v2（argon2id +
  chacha20poly1305，`naviwealth.bak.v2`，不做旧版兼容）。
- `crates/finance`：Beancount 式账本（journal_entries + postings，Σweight=0，
  容差 1e-6，padding 跳过）、账户树与系统种子账户、expense/income/transfer/
  opening_balance builders（正数额 + Flutter 符号约定）、复式平衡校验、
  仓储写入与 outbox 同事务提交、`fin:` 表同步注册。
- `apps/client`：四标签外壳（账户/账本/智能/设置）、账户表单（底部弹层）、
  记一笔（整页 dialog）、账本流、设备 AI 聊天（嵌入 `third_party/agent-runtime`
  的 ChatTurnRunner + agent-llm，流式 delta 渲染）、设置页（后端地址、注册/登录、
  立即同步、LlmProfile、加密备份导出/恢复）、澄白 theme.json。
- tokio→引擎线程桥：nsh 信号仅限引擎线程；后台任务（AI 流式、同步、认证、备份）
  经 tokio mpsc + 引擎线程泵回传（`apps/client/src/bridge.rs`）。
- 测试：HLC/金额/复式平衡/事务原子性/备份往返/同步引擎（fake 传输：推送、LWW、
  tombstone、游标推进、代次重置）共 50 项 cargo 测试；headless UI 测试
  （nsh-testing）覆盖外壳渲染、建账→期初→记一笔→账本可见、mock AI 流式。

构建与验证命令：

```bash
cargo test --workspace --no-default-features     # 全部单元 + headless UI 测试
cargo clippy --workspace --no-default-features --all-targets
cd apps/client && nsh run                        # 桌面运行（Linux 需 GTK 4.14+）
nsh run --target ios / --target android          # 真机（Android 需 SDK build-tools；iOS 需 Mac+Xcode）
```

已知边界：Linux 桌面 runner 需要 GTK 4.14+（无 GTK 的环境用
`--no-default-features` 跑 lib 与测试）；Web 目标依赖阶段 5 的浏览器存储替换
rusqlite，本轮不可构建；SQLCipher 需 `--features sqlcipher`（client 默认启用，
依赖 perl/cc 的 vendored 构建）。

## 架构

界面 → 应用用例 → 领域模型与仓储接口；基础设施实现存储、同步和平台能力。

```text
apps/client/              nsh 入口、应用组合、页面、设计系统
apps/backend/             Rust Workers 与 D1
crates/lifeos/            领域中立契约、存储、同步、备份、记忆
crates/finance/           财务模型、用例、仓储与 AI 工具
crates/health/            健康领域
crates/knowledge/         知识领域
crates/execution/         执行领域
crates/platform/          iOS 与 Android 系统适配
third_party/              复用 Agent Runtime 与 market-data-rs
```

以上为目标目录，按阶段创建实际需要的模块。

- Finance 常开，其他领域按需启用；应用入口统一注册导航、工具、Agent 和生命周期。
- 领域模型与计算独立于 nsh；领域之间不直接依赖，跨领域组合放在应用层。
- 基础设施保持领域中立；业务表由所属领域的仓储访问。
- Agent Runtime 保持通用，应用 Host 负责权限、确认、事务和业务副作用。

## 技术选型

| 职责 | 方案 |
|---|---|
| 界面与状态 | `nsh-core`、`nsh-base`，使用 Signals 与 Resource |
| 异步 | nsh 驱动界面任务，应用级 `tokio` 处理后台 I/O，通过消息返回结果 |
| 数据库 | `rusqlite` + SQLCipher，显式 SQL，独立数据库工作线程 |
| 金额 | `rust_decimal` + 领域自有 `Money`，明确精度、舍入和溢出规则 |
| 契约与错误 | `serde`、`serde_json`、`thiserror` |
| 网络 | 普通请求使用 nsh `fetch`；行情与 AI 复用现有 Rust SDK |
| 系统接入 | Apple 使用薄 Swift 或 `objc2` 适配，Android 使用 Kotlin + `jni` |
| 日志与测试 | `tracing`、`proptest`、`nsh-testing` |

锁定 nsh 稳定发布、Rust 工具链与依赖版本。首版使用纯 Rust UI，
平台代码仅处理系统能力。先保持少量 crate，按实际依赖拆分。

## 数据与 AI

- 本地数据库是业务事实来源，schema 从 1 开始；业务写入与同步 outbox 原子提交。
- 同步采用按行状态、LWW、接受确认与领域重置代次；客户端和后端按同一新契约交付。
- 金额通过十进制字符串序列化；行情缓存由 Finance 管理，SDK 缓存关闭。
- 新版提供自己的加密备份与恢复；密钥保存在 Keychain 或 Android Keystore。
- 直接集成现有 Agent Runtime，复用工具、Proposal、会话与恢复语义；AI 写入经用户确认。
- AI 编排驻设备，模型请求使用用户配置直连供应商；记忆保留来源，向量可重建。
- 语音与健康能力通过平台接口接入；音频处理留在原生路径。
- 开发环境启用详细结构化日志，排除密钥、财务明细、健康内容与语音文本。

## 界面

延续澄白视觉体系，统一金额、列表、表单、筛选、图表与状态组件。
导航、返回手势、键盘和权限交互遵循平台习惯。复杂录入使用完整页面，
轻量录入使用底部弹层；支持中英文、深色、大字号、隐私遮罩和减少动态效果。

## 实施顺序

| 阶段 | 交付与验收 |
|---|---|
| 1. 技术验证 | 双端真机跑通账户列表、记录表单、加密存储、AI 流式输出和健康授权 |
| 2. 最小业务闭环 | 注册与导航、账本与账户、离线写入、重启恢复、同步、备份恢复 |
| 3. 领域完善 | 资产与估值、规划与期权收入，以及 Knowledge、Execution、Health 的核心流程 |
| 4. 智能与发布 | 领域工具、Agent、记忆、语音与系统集成，完成双端真机验收 |
| 5. Web | 复用 Rust 领域层，使用 nsh WASM 与浏览器存储；排除 AI Runtime 和 Health 集成 |

各阶段以可运行的完整流程交付。首版验收覆盖金额与币种不变量、事务原子性、
同步重试与删除、备份恢复、AI 确认，以及双端权限、生命周期和性能。
Web 完成后移除 Flutter、FRB 及其专属构建链。

参考：[nsh Rust 开发](https://nsh.dev/docs/rust/)、[nsh Web](https://nsh.dev/docs/web/)、
[nsh 测试](https://nsh.dev/docs/testing-and-trace/)。
