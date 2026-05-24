# LifeOS Phase D 启动决策 (ADR-2026-05-24)

> **Status**: Adopted (2026-05-24)
> **Scope**: 触发 `lifeos-architecture-northstar.md` §4 Phase D。选定 HealthOS 作为第二域。

---

## Context

NaviWealth 自 v0.5.x 起,FinanceOS 域已稳定 ship(34 个 device tool / FIRE OS Phase 0–5 / Income Planner P0–P4 / sync v2 row-state / IA contract 锁定)。`roadmap-next.md` §3 / §4 列出的下一程 / 中期工作虽未关完,但已不构成"必须做"的强信号——剩余 §3.2/§3.6 收尾、§4 M-2 UI wire-up 都属于已立项功能的最后一公里。

战略上面临的真问题不是"FinanceOS 还能加什么功能",而是:

- FIRE 后真正的复利不在金钱,在身体 / 时间 / 知识 / 决策结构
- 单点 SaaS 在 solo + AI-native 时代不再是合理回报
- 现有技术栈(Flutter + Rust backend + 设备 AI runtime + sync v2 row-state + Memory Layer 留窗)已经接近"个人数字基础设施"的形态,缺的是显式承认

继续把 NaviWealth 当"finance app"做,会持续浪费 shell 层(`core/ai/` / `core/sync/` / `core/auth/`)已经是跨域中立的事实——它们等于在为一个从未到来的第二域闲置。

---

## Decision

1. **Phase D 启动**:northstar §4 触发条件成立。项目重新定位为 **Personal LifeOS**,FinanceOS 是第一个域。
2. **第二域选 HealthOS**(不是 TimeOS / Knowledge / Living)。
3. **一次只加一个域**:HealthOS 稳定 dogfood ≥ 6 个月前**不**启动第三域。

---

## Why HealthOS first

| 候选 | 选 / 不选 | 理由 |
|---|---|---|
| **HealthOS** | ✅ 选 | 数据连续(HealthKit / Health Connect 已聚合);AI-native 天然(长期趋势是 LLM 强项);单人 dogfood 即可验证;**FIRE 后最大资产是身体**,优先级最高 |
| TimeOS | ❌ 不选 | "Energy-aware orchestration" 需要 HealthOS 数据(睡眠 / HRV)才有意义;时序倒挂 |
| KnowledgeOS | ❌ 不选 | Memory Layer 通电 ≠ 独立域;Obsidian 已经 ship 这块,做了等于复刻 |
| LivingOS | ❌ 不选 | 触发条件未到(没在认真考虑跨城/跨国居住) |

---

## Why not parallel

Solo 维护成本 ≈ 域数 × shell 抖动。HealthOS 是第一次让 shell 被真实第二域压一遍,**必须独占注意力**完成。第三域是 shell 已被验证后的边际成本,完全不同。

---

## Constraints (重申 northstar)

- **Local-first**:不引入云 AI relay。Health 数据默认不离设备(除非用户显式开启 sync)
- **No full pivot**:Rust 只用在 Memory Layer embedder + tokenizer + 未来 sync E2EE。**不做** AppFlowy 式宽口径 FFI(详见 `lifeos-shell.md` §10)
- **FinanceOS 不停摆**:Phase D-1 期间 FinanceOS 进入 maintenance mode,只接 P0 bug;新功能等 D-2 完成
- **Solo 节奏**:无量化 deadline,每个 phase 完成才解锁下一个

---

## Consequences

- ✅ shell 层的跨域中立性从"理论"变成"被使用"——Memory Layer / sync row family / AI tool 分层 / chat composition 全部被 HealthOS 真实压测
- ✅ northstar §4 的 8 个 Phase D 必做项从"未来才碰"变成"现在的工作"(详见 `lifeos-shell.md` §2)
- ⚠️ northstar §1.8 + roadmap §6.1 "不写 LifeOS 路线图"条款**部分放宽**——允许写 shell SSOT + 已触发域 SSOT,但仍禁止写跨多域路线图 / 季度目标 / 未触发域设计
- ⚠️ NaviWealth 产品定位、CLAUDE.md、roadmap-next §0/§6/§10 需要全部更新(本批 commit 一并落地)
- ❌ Phase D-1 期间 FinanceOS 新功能(roadmap §3.2/§3.6 尾巴、§4 M-2/M-3/M-4)冻结到 D-2 完成后

---

## Related docs

- 架构边界: `lifeos-architecture-northstar.md` (§4 已更新为"已启动")
- 跨域 shell SSOT: `lifeos-shell.md`
- HealthOS 域 SSOT: `healthos-domain.md`
- Finance 域路线 + Phase D 状态指针: `roadmap-next.md` §10
