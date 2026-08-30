# Workspace Overview — 工作区总览

> 内核学习工作区：基于源码证据建立可持续演进的 Linux 内核知识体系。
> 学习目标：调度器 → 内存管理 → 文件系统 → 网络，逐子系统深化。
> 默认语言：中文。

> 学习领域：进程调度器（sched） + 待扩展

## 技术上下文速查

### sched 关键路径

```text
__schedule
  ├── pick_next_task → __pick_next_task → pick_task_fair（CFS）
  ├── context_switch（switch_mm_irqs_off / switch_to / finish_task_switch）
  └── update_rq_clock / schedule_debug / schedule_idle

try_to_wake_up
  ├── ttwu_queue → ttwu_do_activate
  ├── select_task_rq / ttwu_do_wakeup
  └── wakeup_preempt → resched_curr

enqueue_task_fair
  ├── enqueue_entity → place_entity（vruntime）
  ├── update_curr / update_load_avg（PELT）
  └── add_nr_running
```

- 本地源码：`<kernel-source-root>/kernel/sched/`（7.2-rc6）
- 版本注意：`sched_tick`（旧 scheduler_tick）、`wakeup_preempt`（旧 check_preempt_curr）、`pick_task_fair`（旧 pick_next_task_fair）

## 关键数据结构

- `task_struct` → `se`（sched_entity）、`policy`、`sched_class` 指针
- `sched_class`：调度类函数指针分发表
- `sched_entity`：vruntime / sum_exec_runtime
- `rq`：每 CPU 运行队列（cfs / rt / dl 子队列）
- `cfs_rq`：红黑树按 vruntime 排序
