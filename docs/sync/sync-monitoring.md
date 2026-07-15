# Sync v3 Monitoring Baseline

本文定义生产环境 `POST /sync` 与 `POST /sync/reset-domain` 的当前观测基线。
协议行为见 [`sync-v3.md`](./sync-v3.md)，人工验证流程见
[`sync-e2e-manual.md`](./sync-e2e-manual.md)。

## 数据来源

| 来源 | 用途 |
|---|---|
| Cloudflare Workers Analytics | 路由状态码、请求率、wall-clock latency |
| `wrangler tail` | `[SYNC]` 结构化请求日志 |
| D1 Metrics | `sync_rows` 与 `sync_domain_generations` 的读写量 |
| Mobile diagnostics | 最近同步状态、cursor、outbox 与 domain generation |

当前 `POST /sync` 日志格式：

```text
[SYNC] status=200 code=ok dur_ms=12 pushed=3 pulled=8 more=false slow=false dropped_push=0 dropped_pull=0
```

下游解析器应依赖字段名，不依赖字段顺序。`slow=true` 表示 `dur_ms` 超过服务端阈值。

## 基线目标

| 指标 | 目标 |
|---|---|
| `POST /sync` p95 latency | <= 300 ms |
| `POST /sync` p99 latency | <= 600 ms |
| `POST /sync/reset-domain` p95 latency | <= 500 ms |
| `slow=true` 比例 | <= 5% / 1 h |
| 5xx 比例 | <= 0.5% / 1 h |
| `dropped_push` / `dropped_pull` | 正常为 0；非零必须能由域权限或 generation mismatch 解释 |
| cursor lag | 活跃设备 <= 60 s |

## 告警

| 级别 | 条件 | 含义 |
|---|---|---|
| P1 | `/sync` 5xx >= 5% 持续 5 分钟 | 同步不可用 |
| P1 | `slow=true` >= 25% 持续 10 分钟 | D1 或 Worker 延迟异常 |
| P2 | 401 >= 2% 持续 30 分钟 | JWT 或刷新流程异常 |
| P2 | 单设备 outbox > 200 持续 1 小时 | accepted ack 未推进或客户端循环失败 |
| P2 | reset 后仍接受旧 generation 行 | 永久删除安全边界失效 |
| P3 | protocol version 426 >= 0.1% / 24 h | 客户端与服务端版本不一致 |

## 排查顺序

1. 用 `wrangler tail` 按 `code`、`slow`、`dropped_push` 和 `dropped_pull` 聚类。
2. 确认请求/响应的 `domain_generations` 与客户端本地值一致。
3. 检查 `accepted` 是否覆盖客户端准备清除的 outbox pointers；客户端只能清除明确
   ack 的行。
4. 在 D1 Metrics 检查 `sync_rows` 和 `sync_domain_generations` 是否出现扫描或写入突增。
5. reset 竞态问题要同时核对 generation 增量、域前缀物理删除和 stale row 拒绝。

## 发布前检查

- 空同步、push+pull、分页、tombstone 和 accepted ack 用例通过。
- 四个域前缀的权限过滤与 generation mismatch 用例通过。
- `reset-domain` 在离线旧设备恢复后不会复活已删除数据。
- 结构化日志不包含 row payload、凭证或个人财务/健康数据。
