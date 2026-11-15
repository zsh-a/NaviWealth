<h1 align="center">NaviWealth</h1>

<p align="center">
  <strong>本地优先的个人财富与健康记录</strong><br>
  一部 Android 手机：记账、持仓、饮食与身体数据，全部留在设备上。
</p>

<p align="center">
  <a href="https://github.com/zsh-a/NaviWealth/releases/latest"><img src="https://img.shields.io/github/v/release/zsh-a/NaviWealth?style=flat-square&label=release" alt="Latest release"></a>
  <a href="https://github.com/zsh-a/NaviWealth/actions/workflows/crates.yml"><img src="https://github.com/zsh-a/NaviWealth/actions/workflows/crates.yml/badge.svg" alt="Rust domain crates CI"></a>
</p>

---

NaviWealth 是一个本地优先的个人应用：复式记账、证券持仓、拍照记餐和 Garmin 身体数据。客户端是 Rust 编写的 [NSH](https://github.com/longbridge/nsh) 应用，业务真相在 `navi-finance` 与 `navi-health` 两个 Rust crate 里。没有账号、没有后端、没有同步——只有设备上的 SQLite 和口令加密的本地备份。

| 本地优先 | 设备端 AI | 为确认而设计 |
|---|---|---|
| 业务数据保存在应用私有目录的 SQLite 中；备份是本地口令加密文件。 | 用你自己的模型密钥直连 Anthropic 或 OpenAI 兼容接口，识别结果只是草稿。 | AI 与导入都只生成待确认记录；写入永远由你确认。 |

## 功能

- **记账**：复式分录（五类账户），支付宝 / 微信 / 招行账单导入，跨币种（CNY / HKD / USD），余额核对与可选月度预算。
- **持仓**：手动录入买卖 / 分红，移动平均成本与损益，证券目录搜索（A股 / 港股 / 美股 / ETF），腾讯行情，历史价格与净资产趋势。
- **健康**：拍照识别记餐、体重记录、Garmin 官方 Personal API（睡眠 / HRV / 静息心率 / 步数等）。
- **回顾**：周 / 月视图、分类支出对比、净资产变化、摄入与体重趋势。

## 仓库结构

```text
apps/nsh-client/            NSH (Rust) 客户端：界面、存储、页面与无头测试
crates/navi-finance/        复式账本、持仓与证券目录的业务真相
crates/navi-health/         餐食识别、营养与 Garmin 数据解析
third_party/agent-runtime/  模型协议与客户端（git submodule）
third_party/market-data-rs/ 行情 SDK（腾讯源）
tool/asset_catalog/         证券目录源数据与构建、校验、发布工具链
```

## 快速开始

```bash
git clone --recursive https://github.com/zsh-a/NaviWealth.git
cd NaviWealth
rustup toolchain install

rtk cargo test --manifest-path apps/nsh-client/Cargo.toml --locked
rtk cargo test --manifest-path crates/navi-finance/Cargo.toml --locked
rtk cargo test --manifest-path crates/navi-health/Cargo.toml --locked
```

Android 调试（含 WSL2 + Windows 模拟器拓扑）见 [Local Development](docs/development/local-development.md)；发布 APK 由 `nsh client` 手动工作流构建签名，使用 `nsh-vX.Y.Z` 标签。

## 文档导航

| 主题 | 文档 |
|---|---|
| 项目总览 | [Documentation Index](docs/index.md) |
| Agent 任务路由 | [Agent Task Map](docs/agent-map.md) |
| 产品范围 | [Product Scope](docs/product/product-scope.md) |
| 路线图 | [NSH Roadmap](docs/roadmap/roadmap-nsh.md) |
| 范围决策 | [Personal Local Scope](docs/architecture/personal-local-scope.md) |
| Agent Runtime | [Current Architecture](docs/architecture/agent-runtime-current.md) |
| 证券目录 | [Catalog Pipeline](tool/asset_catalog/README.md) |
| 本地开发 | [Local Development](docs/development/local-development.md) |

> 历史上的 Flutter 客户端与 Sync v3 后端已于 2026-11-15 退役，源码保留在 `flutter-final` 标签。

## 参与项目

欢迎通过 Issue 提交问题与建议。代码贡献请从 `main` 创建短分支，完成相关测试后提交 Pull Request；分支保护与必需检查见 [Branch Protection](docs/operations/branch-protection.md)。

<p align="center">
  <sub>Build a calmer, more private operating system for personal life.</sub>
</p>
