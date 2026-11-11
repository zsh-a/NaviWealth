# NaviWealth nsh 与 Rust 重写方案

状态：Rust 客户端已实现 FinanceOS 核心财务流程；Android 15（API 35）x86_64 已完成下述原生流程和界面验收。阶段 1/2 的双端完整验收尚未完成；iOS 未验证，其他领域及阶段 3+ 仍待实施。

采用 nsh 纯 Rust 客户端，先交付 iOS、Android，再扩展 Web。
本方案是新客户端的架构与实施基线；现有 Flutter 文档继续描述当前实现。

从新数据库、新数据空间和新接口契约开始。不建设旧数据迁移、旧备份导入、
旧版本兼容、Flutter 双栈桥接或回退路径。旧代码用于理解业务，功能按用户任务重新组织。

## 当前交付范围与证据

本轮范围是 **FinanceOS 核心财务闭环**。默认进入流水，今日／流水／财富／规划构成四个业务入口；助手、设置和可选领域位于全局工作空间入口。用户明确将期权、Wheel／LEAPS 和纸面模拟留待后续。

| 任务 | 当前 Rust 实现 |
|---|---|
| 日常记账 | 账户与期初、收入／支出／跨币种转账、月份与全部时间、搜索与账户／类型筛选、编辑／删除、归档／恢复 |
| 财富与投资 | 资产建档、期初持仓、真实买卖与费用、FIFO 成本／已实现收益、分红、拆股、手动价格和汇率、明确缺口的净资产与发生日历史 |
| 预算与现金安全 | 分类预算与实际流水钻取、周期收支确认／跳过／撤销、贷款合同与本息计划、付款与撤销、30／90 天跑道与独立情景 |
| 配置与长期规划 | 用途→策略→资产目标、100% 权重、独占现金与部分持仓、漂移与真实再平衡成交关联、储蓄目标真实贡献、DCA 到期与实际 Buy 关联、FIRE 假设及情景 |
| 财务运营 | UTF-8 CSV 系统选取与粘贴、逐行更正／分类／排除、重复预览、原子入账与整批撤销、账户对账、财务收件箱、五步月结与历史快照 |
| 连续性 | 离线持久化、加密备份 v2、首次登录数据归属迁移、`fin:` 行状态同步注册、原生导航和未保存草稿保护 |

实现边界：

- `crates/lifeos` 保持领域中立，负责 Decimal Money、HLC、数据库工作线程、SQLCipher、同步与备份。`crates/finance` 负责账本及 `wealth`、`planning`、`operations`；应用适配位于 `apps/client/src/finance*.rs`，界面位于 `screens/`。现有 Flutter 不参与本轮改动。
- 迁移 7/8/9 增加 `fin:wealth_assets`、`fin:wealth_operations`、`fin:planning`、`fin:operations`；Finance 共 10 个同步行族。手动 FX 观察保存在已有 `fin:prices` 中，参与同步和备份；`fx_rates` 仍是设备缓存，启动、恢复、登录及同步后按 owner 重建其手动部分。
- 所有金额与财务计算使用 Decimal；图表仅把坐标转换为浮点。缺失价格／汇率、来源未同步完整或资本超分配时，不显示完整估值或可执行再平衡任务。当前没有自动行情刷新或券商执行。
- 结构化交易、周期、贷款和对账的流水回到原流程修正／撤销，普通记账表单不能覆盖它们。导入撤销要求完整批次回执及一致的 journal/posting 版本；数据未同步完整时保持原状态，等待刷新。
- 投资流水从领域投影保留操作类型，明确买入／卖出／分红／拆股／期初持仓，以及结算与持仓账户；账户箭头只表示真实转账。期初持仓显示成本，拆股显示零现金影响，数量不会作为货币展示。
- 首次登录同时迁移嵌套元数据及确定性身份。原先相同的 journal/posting HLC 映射到同一新版本，不同的原版本保持不同，避免把部分同步误判为完整。普通备注和 UUID 不做文本替换。
- 跑道以真实当前余额为起点；未付的当日／逾期支出在基线扣出，逾期未确认收入不算可用现金。未来收入、FIRE 回报及情景变化均是明确假设。贷款登记的是当前待还本金，不假定资金到账。
- 资产手工估值不改变数量。配置读取跨全部当前 owner 计划检查资金容量，真实卖出／消费后若超分配，允许逐步减少纳入量恢复配置，不阻止真实交易。
- 轻量账户捕获保留底部表单；多字段记录和财务操作使用有标签的完整表单，包含日期选择、数字键盘、保存门禁、原位反馈、失败保留和离开保护。表单依赖冻结，外部刷新不会清空草稿。详情采用原生 push/pop；四个业务根页面保留筛选状态。
- 交互滚动区统一 `KeyboardTaps::Handled`，原生输入显式绑定 light/dark 正文、提示、光标和选区；选择器先收键盘。nsh Java 桥继续使用输入框自身窗口 token 关闭 modal 键盘。
- Android CSV 和备份使用 SAF，CSV 限 10 MB、UTF-8；取消不创建批次，临时文件在成功、失败与取消时清理。打包须包含仓库 Java 桥，使用下方包装脚本。
- 设备 AI、认证和同步接缝保留；认证／同步尚无真实云端往返验收。数据库密钥仍在应用私有 key 文件，Keystore／Keychain 包装待后续平台工作；iOS、Web、ARM 实体机和其他领域不扩大验收声明。

### 本轮核心财务扩展验证

- `rtk cargo test --workspace --no-default-features`：202 项测试、22 个套件通过。
- `rtk cargo clippy --workspace --no-default-features --all-targets -- -D warnings`：通过。
- 覆盖 FIFO 重放与费用、重复及越权防护、预算／本息／到期／目标／配置、同步部分到达的撤销保护、归属迁移、备份恢复、真实表单草稿保护，以及原生引擎 Finance UI 连续操作。
- Android 原生连续 smoke 通过：四个业务标签与设置返回、新建账户、收入／支出／转账、编辑／删除、余额联动与强制停止后重开。独立测试账户的预期余额依次为 19231.50 / 2000.00、19220.00、19300.00；重启后仍为 19300.00 / 2000.00。验证未清空既有数据；随后只清理该次测试流水，原有核心财务数据保持不变。
- 补充原生操作通过：买入与手动估值（数量 10、成本 1000、估值 1200）、预算贡献流水与额度修改、系统 CSV 选择／复核／入账／整批撤销、账户对账和五步月结快照。期权、模拟盘、真实行情和券商执行不包含在内。
- 正常宽度 411dp 的浅色／深色及 360dp、系统字号 1.3 的四个业务页、表单、展开日历已实际截图检查；无效金额保留、继续填写、明确放弃及关闭系统动画时的原位确认均有原生证据。独立全量截图复审后，最后的投资展示修正通过 F9 定向复审（`disposition: ship`）；定向结论不扩大成整体平台或实体设备认证。
- x86_64 与 ARM64 APK 均经仓库 Java 桥包装、签名和 ZIP 16KB 对齐校验；仅 x86_64 模拟器运行已验证。功能验收包使用 `0.2.0 / build 3` 本地调试签名；核心财务发布包由 `client-v0.3.1` 标签构建，版本 `0.3.1 / build 5`，启用仓库固定发布签名。旧客户端调试版须先导出加密备份并保留旧应用，不能直接覆盖安装。
- 原生流程、不同构建的覆盖范围、最终 APK 哈希与截图记录见 `.impeccable/review/finance-core/acceptance.json`；全量复审与最终定向结论分别见同目录 `full-review.md`、`finish-review.md`。Headless 结果不作为原生外观验收；TalkBack、predictive Back、ARM 性能、iOS、Web 和真实云端往返不在上述证据范围内。

### v0.2 日常记账基础的历史验证

以下记录描述此前记账版本，不能代替本轮扩展功能的原生验收。

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
  此前记账基础发布版本为 0.2.0 / build 3，历史产物以 `client-v0.2.0` 工作流为准。
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
