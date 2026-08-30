# 调度器依赖图

```text


__schedule
  ├── pick_next_task (选择下一个要运行的任务)
    ├── __pick_next_task (按调度类优先级遍历 pick_task)
      ├── pick_task_fair (CFS 选择下一个可运行任务)
      └── pick_task_idle (idle 类 pick)
    ├── prev_balance (调度前调平（sched_core 路径）)
    └── put_prev_set_next_task (设置 prev/next 的调度类挂钩)
  ├── context_switch (切换到新任务（含 switch_mm_irqs_off/switch_to/finish_task_switch）)
    ├── prepare_task_switch (切换前准备（perf/kcov/钩子）)
    ├── switch_mm_irqs_off (切换地址空间)
    ├── switch_to (架构级寄存器/栈切换)
    └── finish_task_switch (切换后收尾（解锁/清理）)
  ├── update_rq_clock (更新 rq->clock)
  ├── schedule_debug (调度前一致性检查)
  ├── schedule_idle (CPU 进入 idle 时的调度入口)
  ├── preempt_schedule_common (抢占调度入口)
  ├── put_prev_task (调 put_prev 挂钩（让出前清理）)
  ├── set_next_task (调 set_next 挂钩（选定新任务）)

try_to_wake_up
  ├── ttwu_queue (将唤醒任务入队/迁移)
    └── ttwu_do_activate (唤醒任务并 activate 到运行队列)
  ├── select_task_rq (选择目标 CPU)
  ├── ttwu_do_wakeup (唤醒后处理（标记 TASK_RUNNING）)
  └── wakeup_preempt (检查是否需要抢占当前任务)
    └── resched_curr (给目标 CPU 设置 TIF_NEED_RESCHED)

enqueue_task_fair
  ├── enqueue_entity (将调度实体入 CFS 红黑树)
  ├── place_entity (放置实体（初始化 vruntime）)
  ├── update_curr (更新当前实体的运行时间)
  ├── update_load_avg (更新负载均值（PELT）)
  ├── check_update_overutilized_status (标记 CPU 过载状态)
  └── add_nr_running (更新运行队列可运行计数)

kernel_clone
  └── copy_process (fork/clone 系统调用主入口，创建新任务)
    └── dup_task_struct (复制父 task_struct 并分配内核栈（fork.c:2115 调用）)

fork_idle
  └── copy_process (CPU 热插拔时创建 per-CPU idle 线程)

create_io_thread
  └── copy_process (io_uring 内核线程创建)

vhost_task_create
  └── copy_process (vhost 任务线程创建)
```
