# NaviWealth

个人财务管理软件 — 全资产类别支持、投资跟踪、组合分析、FIRE 追踪、再平衡提醒、AI 财务助手。

跨端：iOS / Android / Web。本地优先 + 云同步（Cloudflare Workers + Rust + D1）。

---

## 仓库结构

```
naviwealth/
├── apps/
│   ├── mobile/      # Flutter 三端 App（FIR-2 / FIR-14 ...）
│   └── backend/     # Cloudflare Workers + Rust（FIR-28 / FIR-32 / FIR-36 ...）
└── .github/workflows/
    ├── mobile.yml   # Flutter analyze + test + web build
    └── backend.yml  # cargo fmt / clippy / check（wasm32-unknown-unknown）
```

任务编号 `FIR-N` 对应 Multica 看板上的 issue。

---

## 本地开发

### Flutter

```bash
cd apps/mobile
flutter pub get
flutter test
flutter run                   # 默认设备
flutter run -d chrome         # Web
```

### 后端（Cloudflare Workers + Rust）

需要 `rustup target add wasm32-unknown-unknown` 和 `npm i -g wrangler`。

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown
wrangler dev                  # 本地 + D1 模拟
wrangler deploy               # 推到 *.workers.dev
```

健康检查：

- `GET /health`     — 服务存活
- `GET /health/db`  — D1 绑定可达

---

## 技术决策（来自 FIR-1 讨论）

- 三端：iOS / Android / Web
- 同步：最终一致性（前台立即拉取 + 30s 轮询，无 WebSocket）
- 后端：Cloudflare Workers + Rust（workers-rs），D1 存储
- 加密：暂不做端到端加密（仅个人使用）
- 认证：单用户 JWT，无注册端点
- 不上架：Web 走 Cloudflare Pages，移动端 sideload / TestFlight 内部组

---

## 贡献流程

1. 在 Multica 看板上认领任务（FIR-N）。
2. 从 `main` 拉分支：`feature/fir-<N>-<short>`。
3. 提交并推送，CI 通过后开 PR。
