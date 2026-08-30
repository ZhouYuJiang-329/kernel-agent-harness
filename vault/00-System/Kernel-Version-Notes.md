# Kernel Version Notes — Linux 7.2-rc6

> 版本差异是内核学习最大坑点。引用任何 API 前先查本表。
> 所有条目必须经 kernel-graph MCP 确认后写入。

## 已确认差异

| 旧 API | 新 API | 位置 | 确认日期 | 备注 |
|---|---|---|---|---|
| scheduler_tick | sched_tick | kernel/sched/core.c:5762 | 2026-08-28 | 周期调度函数改名 |
| check_preempt_curr | wakeup_preempt | kernel/sched/ | 2026-08-28 | 抢占检查重构 |
| pick_next_task_fair | pick_task_fair | kernel/sched/fair.c:9912 | 2026-08-28 | CFS pick 入口改名 |
| sched_balance_rq / newidle / softirq | （重构） | kernel/sched/ | 2026-08-28 | 负载均衡接口重构 |

## 待验证差异

（空——发现后先记录于此，验证后移入上表）
