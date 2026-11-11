# NaviWealth nsh 与 Rust 重写方案

状态：Rust 客户端已实现 FinanceOS 日常记账闭环；Android 15（API 35）x86_64 原生包装 APK 已验证核心记账与重启流程。阶段 1/2 的双端完整验收尚未完成；iOS 未验证，阶段 3+ 待实施。

采用 nsh 纯 Rust 客户端，先交付 iOS、Android，再扩展 Web。
本方案是新客户端的架构与实施基线；现有 Flutter 文档继续描述当前实现。

从新数据库、新数据空间和新接口契约开始。不建设旧数据迁移、旧备份导入、
旧版本兼容、Flutter 双栈桥接或回退路径。旧代码用于理解业务，功能按用户任务重新组织。

## 当前交付范围与证据

本轮完整业务范围是 **FinanceOS 日常记账**，默认进入流水，快速录入始终可见。
范围包含账户与期初余额、收入、支出、转账、按月与全部时间流水、搜索与账户/类型筛选、
记录详情与编辑/删除、账户资料编辑与归档/恢复、离线保存与重启恢复、加密备份导出/恢复。
投资估值、预算/FIRE、期权收入以及其他领域的完整界面与验收不在本轮范围内。

- 根 Cargo workspace：`apps/client`（nsh 应用）、`crates/lifeos`（领域中立）、
  `crates/finance`（财务领域）、`crates/platform`（平台接缝）。现有 Flutter 应用不参与本轮重写。
- `crates/lifeos`：Money（rust_decimal + 明确币种、十进制字符串）、HLC、独立数据库
  工作线程（rusqlite、SQLCipher feature、显式迁移）、行状态同步引擎与加密备份 v2
  （argon2id + chacha20poly1305，`naviwealth.bak.v2`，不做旧版兼容）。
- `crates/finance`：复式 journal/postings、账户与分类、日常记账查询和写入仓储、
  平衡校验、写入与 outbox 同事务提交、`fin:` 同步注册。金额与余额不经过浮点转换。
- `apps/client`：以流水为默认入口；平面日期分组、按币种的月度收支、搜索与紧凑筛选弹层；
  完整记录详情和带未保存保护的整页编辑器；账户详情与带保护的账户表单底部弹层。
  底部弹层有遮罩和系统底部安全区留白，提交期间阻止重复写入，失败保留输入。
  原生输入通过 `ui::themed_input()` 显式绑定正文、提示、光标和选区的 light/dark 角色；
  恢复失败显示中文操作建议和共享错误样式，技术细节仅写入 debug 日志；最终删除确认
  使用 destructive 按钮。
  含操作项的滚动区统一使用 `ui::interactive_scroll()` / `KeyboardTaps::Handled`，
  避免 Android 输入框保留焦点时吞掉按钮与选择器的点击。选择器打开前请求收起键盘；
  Android 桥使用当前输入框所属窗口的 token 关闭 modal 内的键盘。重新打包后已验证
  连续录入与重开编辑器可响应，并验证选择器一次点击收起真实键盘。
- Android 备份通过 SAF 系统文件选择器导出和重新选择文件导入，再确认恢复；
  保留本机副本。生产式打包必须包含仓库内 Java 文档桥，不能直接用普通 `nsh package`
  代替下方包装脚本。当前数据库密钥位于应用私有目录的 key 文件；尚未接入
  Android Keystore / Apple Keychain 包装。
- 认证、同步、设备 AI 与可选领域的代码接缝保留。同步测试使用 fake 传输；
  认证和同步没有完成真实云端往返验收，不以它们作为本轮在线可用性的证据。

### 已执行验证

- `rtk cargo test --workspace --no-default-features`：141 个测试、20 个测试套件通过，
  覆盖领域/仓储、事务、同步、备份和 headless UI，包括输入焦点保留及编辑器重开后的
  滚动区点击策略回归。
- `rtk cargo clippy --workspace --no-default-features --all-targets -- -D warnings`：通过。
- Android 15 / API 35 x86_64 模拟器，包含 Java 文档桥的 APK：完整原生 smoke CLI
  退出码 0，结构化证据 `status: passed`。同一进程连续创建期初 12800 与 0 的两个
  账户，收入 8500、支出 68.50、转账 2000 后余额分别为 19231.50 与 2000.00；
  将支出改为 80 后为 19220.00；确认删除后为 19300.00；最后强制停止并重开，
  余额仍为 19300.00 / 2000.00。没有使用补点或中途重启绕过点击问题。
  证据：`.impeccable/review/native-smoke-evidence.json`，截图来自真实 `screencap`。
- 包含最新 Java 窗口修复的 APK 另外通过键盘定向验收：金额输入时
  `mInputShown=true`，一次账户选择器触发后为 `false`；取消与脏表单放弃各一次点击响应。
- Android SAF 完整恢复已通过：导出加密 `.bak` 到外部 Downloads，系统选择器重新
  选中该文件；错误口令被拒绝且当时来源账户余额 19300.00 不变；正确口令与明确覆盖
  确认后恢复成功，界面回到备份内 DailyBank 19220.00 / Savings 2000.00 的原始快照。
  恢复确认、错误口令和成功状态有原生截图证据。
- 账户归档→恢复原生往返已通过；最终 APK 定向验收确认账户详情可直接进入编辑，
  保存改名、脏表单取消/放弃正常；空账户红色删除确认支持保留与实际删除。
- 最终深色输入截图已检查流水搜索、记录金额/日期/提示、账户已填文字/提示/光标与
  遮盖的口令输入。恢复错误已显示中文操作建议，且同一文件正确口令重试成功。
  完整业务 smoke 与最后 UI 修复后的定向验收分别保留证据，未用旧截图代替最终状态。
- 360dp 宽度、系统字号 1.3 的原生流水与账户页已实际截图检查：金额完整，
  长账户名可换行。该证据覆盖这两个场景，不等于所有页面或字号组合均已验收。
- 本轮原生验收使用 `com.naviwealth.client` 的 0.1.1 / build 2 验证包，min SDK 28、
  target SDK 35；ARM64 包装 APK 已构建，但尚未在 ARM 实体机运行。
  本轮发布版本为 0.2.0 / build 3，发布产物以 `client-v0.2.0` 工作流为准。
- 原生验收清单、最终 APK 哈希与 22 张稳定截图见
  `.impeccable/review/native-acceptance.json`。模拟器不等于实体硬件；TalkBack、
  predictive Back、平板、ARM 性能与真实云端验收不在上述证据范围内。
- 最终设计复审在 `.impeccable/review/finish-review.md` 给出 `disposition: ship`，
  仅针对本轮深色输入、恢复错误、账户删除/编辑三项修复；不是第二轮完整界面认证，
  也不扩大前述平台与证据范围。
- iOS 未修改、未验证；Web 目标尚未实现。构建成功不代表整体可发布。

### 构建与复验

从仓库根目录执行，Android 需要 SDK platform 35、build-tools 35+、JDK 17+、
NDK、Rust Android targets 和 nsh 0.4.0；工具链环境参见 CI。

```bash
rtk cargo test --workspace --no-default-features
rtk cargo clippy --workspace --no-default-features --all-targets -- -D warnings
rtk bash tool/build-client-android.sh --abi arm64-v8a  # ARM Android 包，包含 SAF 桥
rtk bash tool/build-client-android.sh --abi x86_64     # Android 模拟器包
rtk adb -s <明确的测试设备序列号> install -r apps/client/.nsh/out/NaviWealth.apk
rtk python3 tool/client_android_smoke.py --serial <明确的测试设备序列号>
```

`client_android_smoke.py` 是可复验工具：在明确指定的测试设备上创建唯一命名的合成
账户与流水，检查收入/支出/转账、编辑/删除及重启余额；本次完整运行已通过。
默认保留已有数据。只有显式追加 `--reset`
才会清空该包的本地数据。脚本将截图与结构化证据写入 `--output`（默认
`/tmp/naviwealth-android-smoke`）。它不代替 SAF 完整恢复或外观检查。

Linux 桌面运行需要 GTK 4.14+；可在 `apps/client` 执行 `rtk nsh run`。
无 GTK 的环境可使用上述 `--no-default-features` 测试。客户端默认启用 SQLCipher，
vendored 构建需要 perl/cc；Web 仍依赖后续浏览器存储适配，当前不可据此声称可构建。

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
| 系统接入 | Android 当前使用 Java 文档桥 + `jni`；Apple 薄 Swift / `objc2` 接缝待实施与验收 |
| 日志与测试 | `tracing`、`proptest`、`nsh-testing` |

锁定 nsh 稳定发布、Rust 工具链与依赖版本。首版使用纯 Rust UI，
平台代码仅处理系统能力。先保持少量 crate，按实际依赖拆分。

## 数据与 AI

- 本地数据库是业务事实来源，schema 从 1 开始；业务写入与同步 outbox 原子提交。
- 同步采用按行状态、LWW、接受确认与领域重置代次；客户端和后端按同一新契约交付。
- 金额通过十进制字符串序列化；行情缓存由 Finance 管理，SDK 缓存关闭。
- 新版提供自己的加密备份与恢复；当前数据库密钥使用应用私有 key 文件，
  Keychain / Android Keystore 包装属于后续平台工作。
- 直接集成现有 Agent Runtime，复用工具、Proposal、会话与恢复语义；AI 写入经用户确认。
- AI 编排驻设备，模型请求使用用户配置直连供应商；记忆保留来源，向量可重建。
- 语音与健康能力通过平台接口接入；音频处理留在原生路径。
- 开发环境启用详细结构化日志，排除密钥、财务明细、健康内容与语音文本。

## 界面

延续澄白视觉体系，统一金额、列表、表单、筛选、图表与状态组件。
导航、返回手势、键盘和权限交互遵循平台习惯。复杂录入使用完整页面，
轻量录入使用底部弹层。当前 Rust 日常界面为中文并使用 light/dark 主题；
中英文完整本地化、隐私遮罩、减少动态效果与完整大字号矩阵仍需按平台补齐并验证。
新 Rust 界面规范见 `apps/client/DESIGN.md`；Flutter 根设计规范不受本轮修改影响。

## 实施顺序

| 阶段 | 交付与验收 |
|---|---|
| 1. 技术验证 | 双端真机跑通账户列表、记录表单、加密存储、AI 流式输出和健康授权 |
| 2. 最小业务闭环 | 注册与导航、账本与账户、离线写入、重启恢复、同步、备份恢复 |
| 3. 领域完善 | 资产与估值、规划与期权收入，以及 Knowledge、Execution、Health 的核心流程 |
| 4. 智能与发布 | 领域工具、Agent、记忆、语音与系统集成，完成双端真机验收 |
| 5. Web | 复用 Rust 领域层，使用 nsh WASM 与浏览器存储；排除 AI Runtime 和 Health 集成 |

上表是目标验收，不代表阶段已经全部完成；当前证据与缺口以上方清单为准。
各阶段以可运行的完整流程交付。首版验收覆盖金额与币种不变量、事务原子性、
同步重试与删除、备份恢复、AI 确认，以及双端权限、生命周期和性能。
Web 完成后移除 Flutter、FRB 及其专属构建链。

参考：[nsh Rust 开发](https://nsh.dev/docs/rust/)、[nsh Web](https://nsh.dev/docs/web/)、
[nsh 测试](https://nsh.dev/docs/testing-and-trace/)。
