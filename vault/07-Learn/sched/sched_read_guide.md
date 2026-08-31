# Linux 进程调度器 内核代码阅读需求文档

> 基于：Linux 7.2-rc6 `kernel/sched/`（core.c / fair.c / rt.c / deadline.c / idle.c / stop_task.c / wait.c / syscalls.c）
> 生成时间：2026-08-28
> 说明：本次没有工程 C 代码可扫描，直接以调度器子系统源码为阅读对象；所有文件路径和行号均由 kernel-graph MCP 确认。

## 概览：涉及的内核子系统

调度器（Scheduler）是 Linux 内核中最复杂的子系统之一，负责回答三个核心问题：**何时切换（when）**、**切换给谁（who）**、**怎样切换（how）**。

本阅读指南覆盖调度器的完整主线：

- **调度主路径**：`schedule` → `__schedule` → 选择下一个任务（`pick_next_task`）→ 上下文切换（`context_switch`）
- **调度类体系**：`sched_class` 抽象出 CFS / RT / Deadline / Stop / Idle 五种调度类，各有独立的 enqueue/pick/tick 实现
- **唤醒路径**：`try_to_wake_up` 负责把睡眠任务放回运行队列，是调度的另一半入口
- **周期调度**：时钟中断触发 `sched_tick`，逐 tick 推进时间片与 vruntime
- **负载均衡**：`sched_balance_*` 在 CPU 间迁移任务，保证多核利用率
- **优先级与策略**：`sched_setscheduler` / `set_user_nice` 等系统调用修改任务调度属性
- **上下文切换**：`switch_to` / `switch_mm_irqs_off` 完成寄存器、栈和地址空间的切换

**版本差异提示**：本版本（7.2-rc6）中周期调度函数已由 `scheduler_tick` **改名为 `sched_tick`**（`kernel/sched/core.c:5762`），`check_preempt_curr` 也重构为 `wakeup_preempt` 接口。阅读旧资料时注意函数名差异。

## 关键数据结构阅读主线

1. `task_struct`（`include/linux/sched.h:826`）：任务级调度状态入口，连接 `policy`（`sched.h:929`）、`se` 调度实体（`sched.h:880`）和 `sched_class` 指针（`sched.h:887`）。
2. `sched_class`（`kernel/sched/sched.h:2585`）：调度类函数指针分发表，是 `__schedule` 统一调用 CFS/RT/DL/idle 的关键抽象，字段级细节见后续函数分析。
3. `sched_entity`（`include/linux/sched.h:575`）：CFS 调度实体，核心字段 `vruntime` 决定公平性排序，`sum_exec_runtime` 记录累计运行时间。
4. `rq`（`kernel/sched/sched.h:1135`）：每 CPU 运行队列，内嵌 `cfs`/`rt`/`dl` 三个子队列，`nr_running` 记录可运行任务数。
5. `cfs_rq`（`kernel/sched/sched.h:680`）：CFS 运行队列，`tasks_timeline` 红黑树按 vruntime 排序，`curr` 指向当前执行实体。
6. `rt_rq`（`kernel/sched/sched.h:840`）+ `rt_prio_array`（`kernel/sched/sched.h:311`）：RT 用 `MAX_RT_PRIO` 个优先级链表数组组织任务。
7. `dl_rq`（`kernel/sched/sched.h:875`）+ `sched_dl_entity`（`include/linux/sched.h:644`）：Deadline 按绝对截止时间 `deadline` 排序，`dl_runtime`/`dl_deadline` 描述带宽。

## 分类详解

### 分类一：调度主路径（core.c）

**阅读目标**：
1. 如何从进程主动让出 CPU 到完成切换？（`schedule` → `__schedule` 的完整流程）
2. `__schedule` 如何通过 `sched_class` 选择下一个任务，并按优先级遍历各调度类？
3. `pick_next_task` 与 `__pick_next_task` 的关系？sched_core 版本（core.c:6215）与普通版本（core.c:6670）有何区别？
4. `put_prev_task` / `set_next_task` 这两个钩子在切换中做什么？
5. 抢占式调度（`preempt_schedule_common`）与主动让出（`schedule`）的入口差异？
6. CPU 进入 idle（`schedule_idle`）时如何选择 idle 任务？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 7316 | `schedule()` 显式让出 CPU 入口 |
| kernel/sched/core.c | 7061 | `__schedule()` 调度主循环：选任务 + 切换 |
| kernel/sched/core.c | 6123 | `__pick_next_task()` 按调度类优先级遍历 pick |
| kernel/sched/core.c | 6215 | `pick_next_task()` sched_core 版本（core scheduling） |
| kernel/sched/core.c | 6670 | `pick_next_task()` 普通包装，转调 `__pick_next_task` |
| kernel/sched/core.c | 5450 | `context_switch()` 上下文切换框架 |
| kernel/sched/core.c | 7395 | `preempt_schedule_common()` 抢占调度入口 |
| kernel/sched/core.c | 7341 | `schedule_idle()` CPU 进入 idle 时的调度 |
| kernel/sched/core.c | 860 | `update_rq_clock()` 更新 rq 时钟 |
| kernel/sched/sched.h | 2737 | `put_prev_task` / `set_next_task` 调度类钩子定义 |

**已有学习笔记**：无（本次为首次建立路线图）。

---

### 分类二：上下文切换（context switch）

**阅读目标**：
1. `context_switch` 如何分三步完成切换：`switch_mm_irqs_off`（地址空间）→ `switch_to`（寄存器/栈）→ `finish_task_switch`（收尾）？
2. `switch_to` 为什么不是普通函数调用（特殊的参数传递约定）？
3. `finish_task_switch` 何时解锁 rq、何时处理 `task_dead`？
4. `schedule_tail` 在新任务首次运行时的作用（对称式切换的"从哪回来"）？
5. 懒 TLB（lazy TLB）在 `enter_lazy_tlb` 中如何优化同地址空间切换？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 5450 | `context_switch()` 切换总框架 |
| kernel/sched/core.c | 5318 | `finish_task_switch()` 切换后收尾 |
| kernel/sched/core.c | 5420 | `schedule_tail()` 新任务首次运行的恢复点 |
| kernel/sched/core.c | 7564 | `default_wake_function` 默认唤醒回调 |
| arch/x86/kernel/process_64.c | 609 | `__switch_to()` x86 寄存器级切换 |

**已有学习笔记**：无。

---

### 分类三：CFS 公平调度（fair.c）

**阅读目标**：
1. CFS 如何用"虚拟运行时间 vruntime"实现公平？`place_entity` 如何初始化新任务的 vruntime？
2. `enqueue_entity` / `dequeue_entity` 如何操作 `cfs_rq` 的红黑树？
3. `pick_next_entity` 如何选最左（最小 vruntime）节点，且考虑 `wakeup_preempt_fair` 的抢占？
4. `update_curr` 如何计算当前任务消耗的时间并推进 vruntime？
5. `task_tick_fair` 每次时钟 tick 做什么（检查时间片/触发抢占）？
6. `update_load_avg` 如何通过 PELT 算法维护负载均值？
7. `select_task_rq_fair` / `wake_affine` / `select_idle_sibling` 在唤醒时如何选目标 CPU？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/fair.c | 7801 | `enqueue_task_fair()` CFS 入队入口 |
| kernel/sched/fair.c | 8036 | `dequeue_task_fair()` CFS 出队入口 |
| kernel/sched/fair.c | 9912 | `pick_task_fair()` CFS 选择下一个任务 |
| kernel/sched/fair.c | 6375 | `pick_next_entity()` 从红黑树选最左实体 |
| kernel/sched/fair.c | 1985 | `update_curr()` 更新运行时间与 vruntime |
| kernel/sched/fair.c | 9770 | `wakeup_preempt_fair()` 唤醒抢占判断 |
| kernel/sched/fair.c | 14851 | `task_tick_fair()` 周期 tick 处理 |
| kernel/sched/fair.c | 9543 | `select_task_rq_fair()` 唤醒目标 CPU 选择 |
| kernel/sched/fair.c | 8274 | `wake_affine()` 唤醒亲和性 |
| kernel/sched/fair.c | 8800 | `select_idle_sibling()` 找空闲兄弟 CPU |
| kernel/sched/fair.c | 15033 | `set_next_task_fair()` 设定下一个任务 |

**已有学习笔记**：无。

---

### 分类四：RT 实时调度（rt.c）

**版本差异提示**：`rt_sched_class` 由宏 `DEFINE_SCHED_CLASS(rt)` 在 `rt.c:2601` 展开定义（文档早期版本标注 2602 为字段起始行）。`wakeup_preempt_rt` 使用 `rq->donor`（core scheduling 概念）而非 `rq->curr`。push 除唤醒路径外，还通过 `rto_push_irq_work_func`（irq_work）异步触发。

**阅读目标**：
1. RT 任务如何按 `MAX_RT_PRIO`（100）级优先级数组 `rt_prio_array`（`queue[MAX_RT_PRIO]` 的 `list_head` 数组）组织？SCHED_FIFO 与 SCHED_RR 的区别？
2. 入队全链路：`enqueue_task_rt` → `enqueue_rt_entity` → `__enqueue_rt_entity` 如何把任务挂到对应优先级链表，并同步维护 `inc_rt_prio` / `inc_rt_tasks` 计数与 pushable plist（`enqueue_pushable_task`）？
3. 选任务全链路：`pick_task_rt` / `_pick_next_task_rt` / `pick_next_rt_entity` 如何选最高优先级任务？`put_prev_task_rt` / `set_next_task_rt` 两个钩子分别做什么？
4. SCHED_RR 时间片：`task_tick_rt` 如何递减 `sched_rt_entity.time_slice`、到期后放到队尾？`get_rr_interval_rt` 的时间片长度从哪来（`sched_rr_timeslice`）？`yield_task_rt` 让出时如何排到队尾？
5. 唤醒抢占：`wakeup_preempt_rt` 为何只在更高优先级时 `resched_curr`？`check_preempt_equal_prio` 如何应对"等优先级 + 当前可迁移/新任务不可迁移"场景（触发 push 让出 CPU）？`select_task_rq_rt` 如何选目标 CPU？
6. push/pull 负载均衡（RT 特有，解决"空闲 CPU 饿死高优先级任务"）：`task_woken_rt`（唤醒后）与 `balance_rt`（运行时）分别在什么时机触发 `push_rt_tasks` / `pull_rt_task`？`pushable_tasks` plist、`pick_highest_pushable_task` / `pick_next_pushable_task`、`find_lowest_rq` 如何配合？overload 标记（`rt_set_overload` / `rt_overloaded`）如何跨 CPU 传播，`tell_cpu_to_push` + `rto_push_irq_work_func` 怎么异步通知远端？
7. RT 带宽控制（throttling）：`sched_rt_runtime_exceeded` / `rt_rq_throttled` / `do_sched_rt_period_timer` 如何限制 RT 任务占用带宽、防止饿死 CFS？（`rt_se_boosted` 涉及 rtmutex 优先级继承）
8. `DEFINE_SCHED_CLASS(rt)` 分发表（rt.c:2601）各回调字段如何映射到 rt.c 各函数？`switched_to_rt` / `switched_from_rt` / `prio_changed_rt` 在策略/优先级切换时做什么？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/rt.c | 1435 | `enqueue_task_rt()` RT 入队入口 |
| kernel/sched/rt.c | 1331 | `__enqueue_rt_entity()` 实际挂入 rt_prio_array 链表 |
| kernel/sched/rt.c | 1403 | `enqueue_rt_entity()` 实体级入队（含 pushable 维护） |
| kernel/sched/rt.c | 1455 | `dequeue_task_rt()` RT 出队入口 |
| kernel/sched/rt.c | 1682 | `pick_next_rt_entity()` 选最高优先级实体 |
| kernel/sched/rt.c | 1700 | `_pick_next_task_rt()` pick 循环内部实现 |
| kernel/sched/rt.c | 1715 | `pick_task_rt()` 调度类 pick 回调 |
| kernel/sched/rt.c | 1656 | `set_next_task_rt()` 设定下一个任务 |
| kernel/sched/rt.c | 1727 | `put_prev_task_rt()` 放回上一个任务 |
| kernel/sched/rt.c | 974 | `update_curr_rt()` RT 运行时间更新 |
| kernel/sched/rt.c | 1079 | `inc_rt_prio()` 维护 RT 优先级计数（dec 在 1090） |
| kernel/sched/rt.c | 397 | `enqueue_pushable_task()` pushable plist 入队（dequeue 在 413） |
| kernel/sched/rt.c | 2540 | `task_tick_rt()` RR 时间片轮转（SCHED_FIFO 不递减） |
| kernel/sched/rt.c | 2574 | `get_rr_interval_rt()` RR 时间片长度 |
| kernel/sched/rt.c | 1496 | `yield_task_rt()` 让出 CPU，排到队尾 |
| kernel/sched/rt.c | 1625 | `wakeup_preempt_rt()` 唤醒抢占判断 |
| kernel/sched/rt.c | 1576 | `check_preempt_equal_prio()` 等优先级抢占处理 |
| kernel/sched/rt.c | 1503 | `select_task_rq_rt()` RT 目标 CPU 选择 |
| kernel/sched/rt.c | 2373 | `task_woken_rt()` 唤醒后触发 push |
| kernel/sched/rt.c | 2077 | `push_rt_tasks()` 把任务推给空闲/低优先级 CPU |
| kernel/sched/rt.c | 1959 | `push_rt_task()` 单个任务推送核心 |
| kernel/sched/rt.c | 1756 | `pick_highest_pushable_task()` 选可推送的最高优先级任务 |
| kernel/sched/rt.c | 1774 | `find_lowest_rq()` 找最低负载/优先级最低 CPU（锁版在 1896） |
| kernel/sched/rt.c | 1599 | `balance_rt()` 运行时均衡（pull 触发点） |
| kernel/sched/rt.c | 2260 | `pull_rt_task()` 拉取高优先级任务 |
| kernel/sched/rt.c | 333 | `need_pull_rt_task()` 是否需要 pull 判断 |
| kernel/sched/rt.c | 339 | `rt_overloaded()` RT overload 判断（set/clear 在 344/363） |
| kernel/sched/rt.c | 2189 | `tell_cpu_to_push()` irq_work 通知远端 push |
| kernel/sched/rt.c | 2223 | `rto_push_irq_work_func()` 异步 push 执行体 |
| kernel/sched/rt.c | 863 | `sched_rt_runtime_exceeded()` RT 带宽超限检查 |
| kernel/sched/rt.c | 778 | `do_sched_rt_period_timer()` RT 周期定时器（重放 runtime） |
| kernel/sched/rt.c | 564 | `rt_rq_throttled()` RT 队列限流状态 |
| kernel/sched/rt.c | 569 | `rt_se_boosted()` RT 优先级提升（rtmutex 继承） |
| kernel/sched/rt.c | 2442 | `switched_to_rt()` 切换为 RT 策略 |
| kernel/sched/rt.c | 2470 | `prio_changed_rt()` 优先级改变处理 |
| kernel/sched/rt.c | 2601 | `DEFINE_SCHED_CLASS(rt)` rt_sched_class 分发表 |
| include/linux/sched.h | 623 | `struct sched_rt_entity`（time_slice / run_list / on_rq） |
| include/linux/sched/prio.h | 16 | `MAX_RT_PRIO 100` 优先级常量 |

**已有学习笔记**：无。

---

### 分类五：Deadline 调度（deadline.c）

**阅读目标**：
1. SCHED_DEADLINE 如何用 `dl_runtime`/`dl_deadline`/`dl_period` 描述任务带宽？
2. `enqueue_task_dl` 如何按绝对截止时间插入 `dl_rq` 的红黑树？
3. `update_curr_dl` 如何消耗 runtime，耗尽后被 throttle（限流）？
4. `dl_timer` 何时重放 runtime（下个周期）？
5. GEDF（全局最早截止优先）与 CPU 迁移的相互作用？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/deadline.c | 2486 | `enqueue_task_dl()` DL 入队 |
| kernel/sched/deadline.c | 2129 | `update_curr_dl()` DL runtime 消耗 |
| kernel/sched/deadline.c | 2801 | `pick_next_dl_entity()` 选最早截止实体 |
| kernel/sched/deadline.c | 3646 | `dl_sched_class` 定义 |

**已有学习笔记**：无。

---

### 分类六：唤醒路径（wait.c + core.c）

**阅读目标**：
1. `try_to_wake_up` 的完整流程：状态检查 → 选择目标 CPU → 入队 → 抢占检查？
2. `ttwu_queue` 与 `ttwu_do_activate` 的关系？wakelist 优化是什么？
3. `select_task_rq` 如何按调度类分派 CPU 选择（CFS 的 `select_task_rq_fair` vs RT 的 `select_task_rq_rt`）？
4. `wakeup_preempt` 如何决定唤醒任务是否抢占当前任务（最终 `resched_curr` 设 TIF_NEED_RESCHED）？
5. `__wake_up_common` 与 waitqueue 的机制（`autoremove_wake_function` / `default_wake_function`）？
6. `wake_up_process` vs `wake_up_new_task` 的场景区别？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 4251 | `try_to_wake_up()` 唤醒主路径 |
| kernel/sched/core.c | 4545 | `wake_up_process()` 唤醒可运行任务 |
| kernel/sched/core.c | 4551 | `wake_up_state()` 带状态过滤的唤醒 |
| kernel/sched/core.c | 4941 | `wake_up_new_task()` 唤醒新 fork 任务 |
| kernel/sched/core.c | 3804 | `ttwu_do_activate()` 入队激活 |
| kernel/sched/core.c | 2283 | `wakeup_preempt()` 抢占判断 |
| kernel/sched/core.c | 1231 | `resched_curr()` 设置重调度标志 |
| kernel/sched/core.c | 3613 | `select_task_rq()` 目标 CPU 选择入口 |
| kernel/sched/wait.c | 92 | `__wake_up_common()` waitqueue 唤醒核心 |
| kernel/sched/wait.c | 401 | `autoremove_wake_function()` 自动移除 waitqueue 项 |

**已有学习笔记**：无。

---

### 分类七：周期调度（sched_tick）

**阅读目标**：
1. 时钟中断如何触发 `sched_tick`？它调用哪个调度类的 `task_tick` 回调？
2. CFS 的 `entity_tick` 如何逐 tick 更新 vruntime 并检查是否该抢占？
3. `sched_can_stop_tick` 与 NOHZ（无时钟）的关系？
4. `sched_clock_tick` 与 `update_rq_clock` 在 tick 中的角色？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 5762 | `sched_tick()` 周期调度入口（原 scheduler_tick，已改名） |
| kernel/sched/fair.c | 6412 | `entity_tick()` CFS 逐 tick 处理 |
| kernel/sched/clock.c | 418 | `sched_clock_tick()` 调度时钟推进 |
| kernel/sched/core.c | 1426 | `sched_can_stop_tick()` NOHZ 判断 |

**已有学习笔记**：无。

---

### 分类八：负载均衡（fair.c）

**阅读目标**：
1. 负载均衡的三个触发点：`sched_balance_softirq`（周期）、`sched_balance_newidle`（新 idle）、`sched_balance_rq`（唤醒时）如何配合？
2. `sched_domain` 层次结构如何决定迁移范围（NUMA 节点 → LLC → SMT）？
3. `misfit_task_load` 与 overutilized 状态如何触发 EAS（能耗感知）迁移？
4. 主动迁移（`active_load_balance_cpu_stop`）与被动迁移的区别？
5. `_nohz_idle_balance` 如何利用空闲 CPU 做均衡？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/fair.c | 13269 | `sched_balance_rq()` 运行时均衡 |
| kernel/sched/fair.c | 14345 | `sched_balance_newidle()` 新 idle 均衡 |
| kernel/sched/fair.c | 14497 | `sched_balance_softirq()` 周期 softirq 均衡 |
| kernel/sched/fair.c | 14156 | `_nohz_idle_balance()` NOHZ 空闲均衡 |
| kernel/sched/fair.c | 13606 | `active_load_balance_cpu_stop()` 主动迁移 |
| kernel/sched/fair.c | 11225 | `__sched_balance_update_blocked_averages()` 阻塞负载更新 |

**已有学习笔记**：无。

---

### 分类九：优先级与调度策略（syscalls.c）

**阅读目标**：
1. `sched_setscheduler` vs `sched_setscheduler_nocheck` 的区别？什么时候用哪个？
2. `sched_setattr` 与 `sched_attr` 结构体如何提供更细粒度的控制（nice/prio/deadline/uclamp）？
3. `normal_prio` / `effective_prio` 如何计算静态与动态优先级？
4. `set_user_nice` 如何修改 nice 值并重新计算权重？
5. 优先级范围：RT（0-99）与 CFS（100-139）如何用 `MAX_PRIO` 划分？
6. `sched_setaffinity` / `sched_getaffinity` 如何管理 CPU 亲和性？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/syscalls.c | 758 | `sched_setscheduler()` 设置调度策略 |
| kernel/sched/syscalls.c | 788 | `sched_setscheduler_nocheck()` 无权限检查版本 |
| kernel/sched/syscalls.c | 493 | `__sched_setscheduler()` 核心实现 |
| kernel/sched/syscalls.c | 764 | `sched_setattr()` 细粒度调度属性 |
| kernel/sched/syscalls.c | 65 | `set_user_nice()` 修改 nice 值 |
| kernel/sched/syscalls.c | 40 | `normal_prio()` 静态优先级计算 |
| kernel/sched/syscalls.c | 52 | `effective_prio()` 动态优先级计算 |
| kernel/sched/syscalls.c | 170 | `task_prio()` 获取任务优先级 |
| kernel/sched/syscalls.c | 1197 | `sched_setaffinity()` 设置 CPU 亲和性 |
| include/uapi/linux/sched/types.h | 98 | `struct sched_attr` UAPI 定义 |
| include/linux/sched/prio.h | 16-19 | `MAX_RT_PRIO`/`MAX_PRIO` 优先级常量 |

**已有学习笔记**：无。

---

### 分类十：CPU 亲和性与迁移（core.c）

**阅读目标**：
1. `set_cpus_allowed_ptr` 与 `__set_cpus_allowed_ptr` 的关系？如何迁移任务到新 CPU？
2. `migrate_disable` 如何暂时阻止任务迁移（配合 preempt_disable）？
3. `select_task_rq` 如何在唤醒时选择最优 CPU（fair/rt/dl 各有实现）？
4. `sched_cpu_starting` 在 CPU 热插拔时的调度器初始化？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 3215 | `set_cpus_allowed_ptr()` 修改 CPU 亲和性 |
| kernel/sched/core.c | 3197 | `__set_cpus_allowed_ptr()` 实际迁移逻辑 |
| kernel/sched/core.c | 2480 | `migrate_disable()` 禁用迁移 |
| kernel/sched/core.c | 3613 | `select_task_rq()` CPU 选择入口 |
| kernel/sched/core.c | 8768 | `sched_cpu_starting()` CPU 上线调度初始化 |

**已有学习笔记**：无。

---

### 分类十一：任务生命周期（fork/exec/exit）

**阅读目标**：
1. `sched_fork` 如何初始化新任务的调度实体（继承 vs 清零）？
2. `wake_up_new_task` 如何把新 fork 的任务放入运行队列？
3. `sched_post_fork` 与 `sched_fork` 的分工？
4. 任务退出时 `__schedule` 中的 `task_dead` 分支如何回收调度状态？

**关键源文件**：

| 文件 | 行号 | 重点关注 |
|------|------|---------|
| kernel/sched/core.c | 4803 | `sched_fork()` fork 时调度初始化 |
| kernel/sched/core.c | 4911 | `sched_post_fork()` fork 后调度设置 |
| kernel/sched/core.c | 4941 | `wake_up_new_task()` 唤醒新任务 |
| kernel/sched/core.c | 5420 | `schedule_tail()` 新任务首跑恢复 |

**已有学习笔记**：无。

---

## 阅读顺序建议

```
阶段 1（必读，3-4 天）：调度主路径 + 上下文切换
  收获：能完整讲出"进程让出 CPU → 选择下一个 → 切换"的全过程，
        理解 __schedule / pick_next_task / context_switch 的核心职责。

阶段 2（必读，3-4 天）：CFS 公平调度
  收获：理解 vruntime 公平算法、红黑树入队出队、唤醒抢占判断，
        能读懂 enqueue_task_fair / update_curr / pick_next_entity。

阶段 3（必读，2-3 天）：唤醒路径 + 优先级与策略
  收获：理解 try_to_wake_up 全流程、sched_setscheduler 系统调用，
        打通"用户态设置调度策略 → 内核重新分派调度类"的链路。

阶段 4（必读，2-3 天）：RT / Deadline 调度类 + 周期调度
  收获：能对比 CFS/RT/DL 三种调度类的入队/选择/时间片处理差异，
        理解 sched_tick 如何驱动各调度类。

阶段 5（按需，2-3 天）：负载均衡 + CPU 亲和性 + 生命周期
  收获：理解多核负载均衡的三入口和迁移机制，
        能解释 cpu affinity、任务迁移与热插拔行为。
```

## API 快速检索

| API / 结构体 | 头文件 | 实现文件 | 行号 | 一句话说明 |
|------------|--------|---------|------|-----------|
| schedule | include/linux/sched.h | kernel/sched/core.c | 7316 | 显式让出 CPU 的调度入口 |
| __schedule | - | kernel/sched/core.c | 7061 | 调度主循环：选任务 + 切换 |
| pick_next_task | kernel/sched/sched.h | kernel/sched/core.c | 6215/6670 | 选择下一个任务（sched_core / 普通） |
| __pick_next_task | kernel/sched/sched.h | kernel/sched/core.c | 6123 | 按调度类优先级遍历 pick_task |
| context_switch | - | kernel/sched/core.c | 5450 | 上下文切换框架 |
| finish_task_switch | - | kernel/sched/core.c | 5318 | 切换后收尾 |
| schedule_tail | - | kernel/sched/core.c | 5420 | 新任务首次运行恢复点 |
| preempt_schedule_common | - | kernel/sched/core.c | 7395 | 抢占调度入口 |
| schedule_idle | - | kernel/sched/core.c | 7341 | CPU 进入 idle 时的调度 |
| update_rq_clock | - | kernel/sched/core.c | 860 | 更新 rq 时钟 |
| try_to_wake_up | kernel/sched/sched.h | kernel/sched/core.c | 4251 | 唤醒主路径 |
| wake_up_process | kernel/sched/sched.h | kernel/sched/core.c | 4545 | 唤醒任务 |
| wake_up_state | kernel/sched/sched.h | kernel/sched/core.c | 4551 | 按状态过滤唤醒 |
| wake_up_new_task | kernel/sched/sched.h | kernel/sched/core.c | 4941 | 唤醒新 fork 任务 |
| wakeup_preempt | - | kernel/sched/core.c | 2283 | 唤醒抢占判断 |
| resched_curr | - | kernel/sched/core.c | 1231 | 设置 TIF_NEED_RESCHED |
| select_task_rq | - | kernel/sched/core.c | 3613 | 选择目标 CPU |
| sched_tick | - | kernel/sched/core.c | 5762 | 周期调度（原 scheduler_tick） |
| __wake_up_common | linux/wait.h | kernel/sched/wait.c | 92 | waitqueue 唤醒核心 |
| autoremove_wake_function | linux/wait.h | kernel/sched/wait.c | 401 | 自动移除 waitqueue 项 |
| default_wake_function | - | kernel/sched/core.c | 7564 | 默认唤醒回调 |
| enqueue_task_fair | - | kernel/sched/fair.c | 7801 | CFS 入队入口 |
| dequeue_task_fair | - | kernel/sched/fair.c | 8036 | CFS 出队入口 |
| pick_task_fair | - | kernel/sched/fair.c | 9912 | CFS 选择任务 |
| pick_next_entity | - | kernel/sched/fair.c | 6375 | 红黑树最左实体 |
| update_curr | - | kernel/sched/fair.c | 1985 | 更新 vruntime |
| task_tick_fair | - | kernel/sched/fair.c | 14851 | CFS 周期 tick |
| wakeup_preempt_fair | - | kernel/sched/fair.c | 9770 | CFS 唤醒抢占 |
| select_task_rq_fair | - | kernel/sched/fair.c | 9543 | CFS 目标 CPU |
| wake_affine | - | kernel/sched/fair.c | 8274 | 唤醒亲和性 |
| select_idle_sibling | - | kernel/sched/fair.c | 8800 | 找空闲兄弟 CPU |
| enqueue_task_rt | - | kernel/sched/rt.c | 1435 | RT 入队入口 |
| __enqueue_rt_entity | - | kernel/sched/rt.c | 1331 | 实际挂入 rt_prio_array 链表 |
| enqueue_rt_entity | - | kernel/sched/rt.c | 1403 | 实体级入队（含 pushable 维护） |
| dequeue_task_rt | - | kernel/sched/rt.c | 1455 | RT 出队入口 |
| pick_next_rt_entity | - | kernel/sched/rt.c | 1682 | 选最高优先级 RT 实体 |
| pick_task_rt | - | kernel/sched/rt.c | 1715 | RT 调度类 pick 回调 |
| _pick_next_task_rt | - | kernel/sched/rt.c | 1700 | pick 循环内部实现 |
| set_next_task_rt | - | kernel/sched/rt.c | 1656 | RT 设定下一任务 |
| put_prev_task_rt | - | kernel/sched/rt.c | 1727 | RT 放回前一任务 |
| update_curr_rt | - | kernel/sched/rt.c | 974 | RT 运行时间更新 |
| task_tick_rt | - | kernel/sched/rt.c | 2540 | RR 时间片轮转 |
| get_rr_interval_rt | - | kernel/sched/rt.c | 2574 | RR 时间片长度 |
| yield_task_rt | - | kernel/sched/rt.c | 1496 | RT 让出 CPU |
| wakeup_preempt_rt | - | kernel/sched/rt.c | 1625 | RT 唤醒抢占 |
| check_preempt_equal_prio | - | kernel/sched/rt.c | 1576 | 等优先级抢占处理 |
| select_task_rq_rt | - | kernel/sched/rt.c | 1503 | RT 目标 CPU 选择 |
| task_woken_rt | - | kernel/sched/rt.c | 2373 | 唤醒后触发 push |
| push_rt_tasks | - | kernel/sched/rt.c | 2077 | RT push 负载均衡 |
| push_rt_task | - | kernel/sched/rt.c | 1959 | 单个 RT 任务推送 |
| pull_rt_task | - | kernel/sched/rt.c | 2260 | RT pull 负载均衡 |
| balance_rt | - | kernel/sched/rt.c | 1599 | RT 运行时均衡（pull 触发点） |
| find_lowest_rq | - | kernel/sched/rt.c | 1774 | 找最低负载 CPU（锁版 1896） |
| rt_sched_class | - | kernel/sched/rt.c | 2601 | RT 调度类分发表（DEFINE_SCHED_CLASS 宏） |
| sched_rt_entity | - | include/linux/sched.h | 623 | RT 调度实体 |
| rt_prio_array | - | kernel/sched/sched.h | 311 | RT 优先级数组 |
| enqueue_task_dl | - | kernel/sched/deadline.c | 2486 | DL 入队 |
| update_curr_dl | - | kernel/sched/deadline.c | 2129 | DL runtime 消耗 |
| pick_next_dl_entity | - | kernel/sched/deadline.c | 2801 | 选最早截止 DL |
| sched_balance_rq | - | kernel/sched/fair.c | 13269 | 运行时负载均衡 |
| sched_balance_newidle | - | kernel/sched/fair.c | 14345 | 新 idle 均衡 |
| sched_balance_softirq | - | kernel/sched/fair.c | 14497 | 周期均衡 |
| sched_setscheduler | linux/sched.h | kernel/sched/syscalls.c | 758 | 设置调度策略 |
| sched_setscheduler_nocheck | linux/sched.h | kernel/sched/syscalls.c | 788 | 无权限检查版本 |
| sched_setattr | linux/sched.h | kernel/sched/syscalls.c | 764 | 细粒度调度属性 |
| set_user_nice | linux/sched.h | kernel/sched/syscalls.c | 65 | 修改 nice 值 |
| normal_prio | - | kernel/sched/syscalls.c | 40 | 静态优先级 |
| effective_prio | - | kernel/sched/syscalls.c | 52 | 动态优先级 |
| set_cpus_allowed_ptr | linux/sched.h | kernel/sched/core.c | 3215 | 修改 CPU 亲和性 |
| migrate_disable | linux/sched.h | kernel/sched/core.c | 2480 | 禁用任务迁移 |
| sched_fork | - | kernel/sched/core.c | 4803 | fork 调度初始化 |
| sched_post_fork | - | kernel/sched/core.c | 4911 | fork 后调度设置 |
| task_struct | - | include/linux/sched.h | 826 | 进程描述符 |
| sched_class | - | kernel/sched/sched.h | 2585 | 调度类分发表 |
| sched_entity | - | include/linux/sched.h | 575 | CFS 调度实体 |
| sched_rt_entity | - | include/linux/sched.h | 623 | RT 调度实体 |
| sched_dl_entity | - | include/linux/sched.h | 644 | DL 调度实体 |
| rq | - | kernel/sched/sched.h | 1135 | 每 CPU 运行队列 |
| cfs_rq | - | kernel/sched/sched.h | 680 | CFS 运行队列 |
| rt_rq | - | kernel/sched/sched.h | 840 | RT 运行队列 |
| dl_rq | - | kernel/sched/sched.h | 875 | DL 运行队列 |
| rt_prio_array | - | kernel/sched/sched.h | 311 | RT 优先级数组 |
| sched_attr | linux/sched/types.h | include/uapi/linux/sched/types.h | 98 | 调度属性 UAPI |
