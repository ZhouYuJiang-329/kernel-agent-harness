# Active Context — 当前学习状态（工作记忆）

> 会话启动**必读**本文件；每次学习会话结束更新。
> 告诉 Agent：当前学到哪、下一步做什么。

## 当前主线

- **调度器（sched）**：Linux 7.2-rc6 进程调度器。
  - 已建 87 个知识节点骨架（全部 unknown / 置信度 0）
  - 已确认三条调用链主干：`__schedule`、`try_to_wake_up`、`enqueue_task_fair`（见 `03-Knowledge/sched/dep-graph.md`）
  - 已深度分析 `task_struct`（exploring/70）：`07-Learn/sched/task_struct.md`，含字段分组地图、__state 状态机、双引用计数、current 机制；并确认 fork 创建树 kernel_clone/fork_idle/create_io_thread/vhost_task_create → copy_process → dup_task_struct
  - 阅读路线图：`07-Learn/sched/sched_read_guide.md`（11 分类 + 数据结构主线 + API 检索表）

## 下一步计划

1. 从 `__schedule`（kernel/sched/core.c:7061）开始深度分析，沿调用链深化
2. 可选：沿创建路径深化 `copy_process` 的逐域复制（fork.c:1994 → copy_mm/copy_files/copy_signal）
3. 每完成一个函数：执行捕获流水线（见 `00-System/Capture-Protocol.md`）
4. 先查 `lookup_status.py` 避免重复分析

## 版本锚点

- Linux 7.2-rc6（差异表见 `00-System/Kernel-Version-Notes.md`）
- 注意：`scheduler_tick`→`sched_tick`、`check_preempt_curr`→`wakeup_preempt`、`pick_next_task_fair`→`pick_task_fair`

## 当前开放问题

- OQ-001（MEDIUM）：如何验证函数指针产生的间接调用关系？
- OQ-002（MEDIUM）：task_struct 布局随机化（randomized_struct_fields_start/end）的 GCC plugin 机制如何工作？
