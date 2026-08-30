# task_struct 详解

> 源码位置：`include/linux/sched.h:826-1670`
> 一句话职责：内核中**一个可调度执行单元（线程）的全部档案**——身份、状态、调度、资源、亲属关系、统计一网打尽；`struct task_struct` 是内核被引用最频繁、被 `current` 宏直接定位的核心结构体。

---

## 一、大白话总览 + 设计模型

### （a）为什么要设计它？

操作系统要同时"假装"让无数个程序并行运行，就必须为每个执行流保存一份**完整现场**：它跑到哪了（寄存器）、它的优先级、它有哪些文件/内存/信号、谁生它、它生了谁。如果没有 task_struct，CPU 切换任务时不知道把现场存到哪里、也不知道下一个任务是谁。

反向看：**没有 task_struct，就根本没有"任务"这个概念**——内核里一切"每个线程一份"的数据，要么塞进 task_struct，要么从 task_struct 出发经指针找到。

### （b）如果让你自己设计它，第一反应应该是什么？

1. **一句话降级**：task_struct 就是内核给每个线程开的"人事档案 + 户口本 + 病历单"——登记身份、记录状态、挂靠资源、追踪亲属。

2. **最小模型**：最少需要四类字段：
   - **身份**：一个整数 ID（pid）
   - **状态**：一个整数 state（运行/睡眠/僵尸）
   - **现场**：一份寄存器/栈的保存处（thread）
   - **资源**：指向内存（mm）、文件表（files）、信号（signal）的指针

   ```
   task_struct（一张档案卡）
     ├─ pid: 42           ← 身份：我是谁
     ├─ state: RUNNING    ← 状态：我现在能不能跑
     ├─ thread: {...}     ← 现场：寄存器/栈存这里
     ├─ mm ──→ 地址空间
     ├─ files ──→ 打开的文件表
     └─ signal ──→ 信号处理器
   ```

3. **核心数据对象**（角色类比）：

   | 对象 | 类比 | 在这件事里的角色 |
   |---|---|---|
   | `__state` | 红绿灯 | 能否上 CPU、能否被唤醒的开关（0=RUNNING） |
   | `se/rt/dl` | 参赛卡片 | 三个调度类各自给这张卡登记的"参赛信息"（vruntime、时限等） |
   | `sched_class` | 裁判员手册指针 | 指向"这个任务归哪个调度类管"的方法表 |
   | `mm` | 地图 | 进程地址空间（线程间共享，指向同一个 mm） |
   | `real_parent/children` | 族谱 | 进程树的父子/兄弟/组长关系 |
   | `usage/rcu_users` | 借阅计数器 | 谁还在引用这张卡，引用清零才能销毁 |

4. **真实复杂度从哪里来**：
   - **功能爆炸**：一个结构体要服务调度、内存、文件、信号、审计、BPF、perf、cgroup、NUMA、调试器……每个子系统都想往里面塞字段 → 超过 800 行、约 150+ 字段
   - **并发**：多 CPU 同时读写同一任务的状态 → 每个状态位都有对应的锁/原子/屏障协议
   - **性能**：task_struct 是热路径对象，必须 64 字节对齐、前部放调度关键字段、支持布局随机化抗攻击
   - **ABI/兼容**：`personality` 字段专门模拟旧版 Linux 行为；`comm` 要保证 NUL 结尾
   - **生命周期**：任务退出不是瞬间销毁，要经过僵尸→回收，还要等 RCU 读者 → 双引用计数

5. **如果自己实现，大概步骤**：
   - 正常路径：`fork()` → 分配一张新卡（dup_task_struct）→ 逐字段复制/重置 → 挂进全局 task 链表 + PID 哈希 → 入队等调度 → 运行 → 退出 → 通知父进程 → 引用清零后释放
   - 特殊分支：失败回滚（dup_task_struct 的错误路径反向释放）、pid 复用、退出后父进程没 wait（变僵尸）、kthread（没有 mm）
   - 要同步维护的账本：全局 `tasks` 链表、PID 哈希表、`children/sibling` 族谱、每个调度类的队列、引用计数

6. **源码阅读 checklist**（读字段时对照）：
   - 这是"身份/状态/统计/链接"哪一类字段？
   - 谁初始化它？（fork 时 or 运行时）
   - 谁读它、谁写它？（调度器 / 信号 / 内存子系统）
   - 它和别的字段有什么不变量？（如 `mm == NULL` ⇔ 内核线程）
   - 它是被锁保护，还是靠原子/屏障？（`__state` 靠 WRITE_ONCE + 屏障）

### （c）它是怎么设计的？

- **一个对象，多份"登记"**：把调度信息拆成 `se`（CFS 实体）、`rt`（RT 实体）、`dl`（DL 实体）三个子结构 + `sched_class` 方法表指针，而不是把所有调度字段平铺——不同任务只用得上其中一个，且调度类可扩展（如 `CONFIG_SCHED_CLASS_EXT` 的 scx）。
- **用指针省内存**：`mm/files/fs/signal/sighand` 全是共享指针，线程组共享同一份，COW（写时复制）语义由引用计数承担。
- **热区优先 + 随机化**：`randomized_struct_fields_start/end` 把可随机化部分夹在中间，调度关键字段放在前面（注释明说 "Only scheduling-critical items should be added above here"），整体 `aligned(64)` 对齐 cacheline。
- **双引用计数**：`usage`（普通引用）和 `rcu_users`（RCU 保护的用户态可见引用）分别计数，让"用户态还能看到"和"调度器还用着"两种生命周期解耦。

### （d）它处理哪几种情况？

task_struct 是一份"档案"，其"情况"体现在**生命周期阶段**：

```
情况一：创建（fork/clone/kernel_thread）
  → 做：dup_task_struct 复制父卡 → copy_process 逐域重置/初始化 → 入 PID 哈希、挂族谱
  → 为什么：新任务要和父任务共享资源（mm/files）又要有独立身份（pid/state）

情况二：就绪/运行（调度）
  → 做：入队（on_rq=1）→ 被 pick → on_cpu=1 → 切换现场
  → 为什么：状态位驱动调度器的"选谁上 CPU"决策

情况三：睡眠（等待事件）
  → 做：set_current_state(TASK_UNINTERRUPTIBLE) → __schedule 让出 CPU
  → 为什么：写状态必须先于条件检查（set_current_state 带屏障），否则与唤醒方竞争

情况四：唤醒（事件到达）
  → 做：try_to_wake_up 校验 state 匹配 → 写 TASK_WAKING → 入队 → 置 TASK_RUNNING
  → 为什么：TASK_WAKING 中间态让 ttwu 可以先释放 pi_lock 再入队

情况五：退出/僵尸/回收
  → 做：exit_state=EXIT_ZOMBIE → 通知父进程 → 父 wait → EXIT_DEAD → 引用清零释放
  → 为什么：父进程要读到退出码，所以尸体不能立刻销毁
```

---

## 二、字段功能域分组地图

task_struct 没有控制流，用**功能域分组**代替骨架。定义顺序即源码顺序，可随机化部分在 `randomized_struct_fields_start`（sched.h:843）与 `end`（sched.h:1669）之间。

```text
struct task_struct
│
├─ 0 现场与入口（结构体头部，固定不可随机化）
│     thread_info（CONFIG_THREAD_INFO_IN_TASK 下必须第一字段）
│     __state / saved_state
│     randomized_struct_fields_start ← 随机化区开始
│
├─ 1 调度核心区（热路径）
│     stack / usage / flags / ptrace
│     on_cpu / on_rq / is_blocked
│     wake_entry / wakee_flips / last_wakee / recent_used_cpu / wake_cpu
│     prio / static_prio / normal_prio / rt_priority
│     se / rt / dl / dl_server / sched_class
│     stats / policy / cpus_ptr / cpus_mask / migration_*
│     sched_info / 各 sched_* 位字段
│
├─ 2 身份与族谱
│     pid / tgid / thread_pid / pid_links[PIDTYPE_MAX]
│     real_parent / parent / children / sibling / group_leader
│     ptraced / ptrace_entry / vfork_done / set_child_tid / clear_child_tid
│
├─ 3 资源指针
│     mm / active_mm / exec_state
│     fs / files / nsproxy
│     signal / sighand / blocked / pending / sas_ss_*
│     real_cred / cred / ptracer_cred / comm
│
├─ 4 时间与统计
│     utime / stime / gtime / prev_cputime
│     nvcsw / nivcsw / start_time / start_boottime
│     min_flt / maj_flt / posix_cputimers
│
├─ 5 同步与并发控制
│     alloc_lock / pi_lock / wake_q
│     blocked_on / blocked_lock / blocked_donor（7.x 阻塞代理）
│     task_works / restart_block
│
├─ 6 退出路径
│     exit_state / exit_code / exit_signal / pdeath_signal / jobctl
│     rcu / rcu_users / pagefault_disabled
│
├─ 7 子系统挂钩（按 CONFIG 编译裁剪）
│     seccomp / rseq / mm_cid / futex / perf_event_ctxp
│     cgroups / mems_allowed / numa_* / bpf_storage / kcov_* / audit_context
│     thread（架构现场，随机化区末尾，固定位置）
│
└─ randomized_struct_fields_end ← 随机化区结束
```

---

## 三、快速定位

- **子系统**：进程管理（kernel/fork.c、kernel/exit.c）+ 调度器（kernel/sched/）的公共核心数据结构；定义在头文件 `include/linux/sched.h`。
- **核心职责**：描述内核中一个可调度执行单元（用户线程或内核线程）的完整状态。
- **源码位置**：`include/linux/sched.h:826-1670`（Linux 7.2-rc6）

---

## 四、宏观地位分析

### （a）所属层次

```text
┌────────────────────────────────────────────────┐
│ 用户态：clone()/fork()/vfork()/execve()         │
└──────────────┬─────────────────────────────────┘
               ▼
┌────────────────────────────────────────────────┐
│ 系统调用层：kernel_clone → copy_process          │ ← 创建
│ 调度入口：__schedule → context_switch → switch_to│ ← 切换
│ 唤醒入口：try_to_wake_up                        │ ← 状态机
└──────────────┬─────────────────────────────────┘
               ▼
┌────────────────────────────────────────────────┐
│ [struct task_struct —— 本分析对象]               │
│ 被 current（每 CPU 一个指针）直接定位            │
└───┬────────┬────────┬────────┬────────┬────────┘
    ▼        ▼        ▼        ▼        ▼
 调度器   内存管理  文件系统  信号处理  PID/进程树
 (se/rq)  (mm)     (files)  (signal) (pid_links)
```

### （b）触发场景

1. **用户执行 `fork()`/`clone()`**：syscall → `kernel_clone` → `copy_process`（fork.c:1994）→ `dup_task_struct`（fork.c:914）复制一份新 task_struct → `copy_process` 逐域初始化 → 新任务诞生。**这是 task_struct 唯一的"出生"路径**（另有 `fork_idle` 为每个 CPU 创建 idle 线程、`create_io_thread` 为 io_uring、`vhost_task_create` 为 vhost）。
2. **时钟中断/调度决策**：`__schedule` 每被调用一次就围绕 `prev`/`next` 两个 task_struct 工作——读 `prev->on_rq`、改 `prev->__state`、经 `sched_class` 方法表操作 `se`。
3. **事件唤醒睡眠任务**：`try_to_wake_up`（core.c:4251）读 `p->__state` 判断状态是否匹配、写 `TASK_WAKING` 中间态、操作 `p->on_rq/on_cpu`。
4. **任务退出**：`do_exit` → `exit_notify`（唤醒父进程）→ 父进程 `wait4()` 回收，`exit_state` 从 `EXIT_ZOMBIE` 走到 `EXIT_DEAD`，引用计数归零后销毁。

### （c）解决什么问题

没有 task_struct（或它有 bug）的后果：
- 无法区分"谁是谁"——PID 关系、进程树全部失效；
- 调度器失去"下一任务"的依据——on_rq/on_cpu 错乱会导致任务丢失（双重入队）或永不唤醒（状态竞争丢失唤醒）；
- 内存/文件引用计数错乱 → use-after-free 或泄漏；
- `__state` 写序错误（无屏障）→ 经典"lost wakeup"竞态：任务睡着后唤醒信号永远错过。

---

## 五、生命周期调用链

### （a）向上：task_struct 如何被创建/切换/销毁

```text
创建路径（fork 家族）
  sys_clone/sys_fork/sys_vfork ──► kernel_clone
                                     └── copy_process                    // fork.c:1994
                                           ├── dup_task_struct            // fork.c:2115 调用；定义 fork.c:914
                                           │     ├── alloc_task_struct_node // 分配 task_struct 本体
                                           │     ├── arch_dup_task_struct   // 复制架构现场（thread）
                                           │     └── alloc_thread_stack_node// 分配内核栈
                                           ├── copy_exec_state
                                           └── ...（copy_mm/copy_files/copy_signal/... 逐域复制）

  其他创建入口（均直接调 copy_process，MCP 确认）
  fork_idle ──► copy_process        // 每 CPU idle 线程（idle_init 触发）
  create_io_thread ──► copy_process // io_uring 内核线程
  vhost_task_create ──► copy_process

运行路径（调度）
  schedule()/preempt_schedule ──► __schedule            // core.c:7061
                                     └── context_switch
                                           └── switch_to（架构现场切换：thread 字段）

唤醒路径（状态机）
  任意事件 ──► wake_up_process ──► try_to_wake_up        // core.c:4251，读写 __state/on_rq/on_cpu

销毁路径
  do_exit ──► exit_notify（wake_up_process 唤醒父进程）
           ──► release_task ──► __exit_signal
           ──► put_task_struct（usage/rcu_users 双双归零后 free）
```

### （b）向下：task_struct 自身不"调用"什么，但它被谁读写

```text
[task_struct 字段]             读写方
  __state        ←─ set_current_state/__set_current_state/set_special_state（sched.h:240-269）
  __state        ←─ try_to_wake_up（写 TASK_WAKING / 置 TASK_RUNNING）
  on_rq/on_cpu   ←─ enqueue_task/deactivate_task/__schedule
  se/rt/dl       ←─ 各调度类：enqueue_task_fair、pick_task_fair、update_curr 等
  sched_class    ←─ __schedule 的 pick_next_task/put_prev_task 分发
  mm/active_mm   ←─ context_switch → switch_mm_irqs_off
  pid/tgid       ←─ alloc_pid / PID 哈希表（pid_links）
  real_parent    ←─ fork/exit 时维护族谱
  cred           ←─ commit_creds/override_creds（COW 语义）
  usage/rcu_users←─ get_task_struct/put_task_struct
```

---

## 六、逐字段详解（按功能域）

### 6.1 现场与入口（结构体头部，sched.h:826-843）

```c
#ifdef CONFIG_THREAD_INFO_IN_TASK
	struct thread_info thread_info;   // 必须第一字段（当前线程信息，含标志位/CPU/地址空间等）
#endif
	unsigned int __state;              // 任务状态（TASK_* 宏），调度状态机核心
	unsigned int saved_state;          // "spinlock sleeper" 的保存状态（PREEMPT_RT 睡眠锁用）
```

- `thread_info`：x86 等架构把 thread_info 嵌入 task_struct 头部（`CONFIG_THREAD_INFO_IN_TASK`），`current_thread_info()` 由 `current` 直接算出，注释明确要求**必须是第一字段**（sched.h:827-833）。
- `__state`：调度器视角的状态。`TASK_RUNNING=0`（sched.h:107），其余为睡眠/特殊状态。**注意与 `exit_state` 完全分开**——sched.h:100-104 注释警告：一个管"能否运行"，一个管"是否退出"，误改一个不会碰另一个。
- `saved_state`：PREEMPT_RT 下"睡眠自旋锁"阻塞时保存原状态，锁获取后恢复（sched.h:271-287 注释）。

### 6.2 调度核心区（sched.h:843-1052，热路径）

```c
	randomized_struct_fields_start     // 随机化区开始（GCC plugin 可重排其间字段）
	void *stack;                       // 指向内核栈（可 vmalloc 分配，CONFIG_VMAP_STACK）
	refcount_t usage;                  // 任务引用计数（get_task_struct/put_task_struct）
	unsigned int flags;                // PF_* 每任务标志（PF_KTHREAD 等）
	unsigned int ptrace;               // PT_* ptrace 标志
	u8 on_cpu;                         // 1=正在某 CPU 上运行（switch_to 时置位）
	u8 on_rq;                          // 1=在运行队列上（enqueue/deactivate 切换）
	u8 is_blocked;                     // 1=阻塞在某锁上（7.x 阻塞代理机制）
	struct __call_single_node wake_entry; // 唤醒列表节点（跨 CPU 唤醒队列）
	unsigned int wakee_flips;          // waker/wakee 关系翻转计数（唤醒亲和性）
	unsigned long wakee_flip_decay_ts;
	struct task_struct *last_wakee;    // 上次唤醒谁（wake-affine 优化）
	int recent_used_cpu;               // 最近用过的 CPU（wake-affine 快速查找）
	int wake_cpu;                      // 唤醒时的目标 CPU
	int prio;                          // 动态优先级（调度用）
	int static_prio;                   // 静态优先级（nice 值换算）
	int normal_prio;                   // 静态+RT 加成后的优先级
	unsigned int rt_priority;          // RT 优先级（1-99）
	struct sched_entity se;            // CFS 调度实体（vruntime、负载等）
	struct sched_rt_entity rt;         // RT 调度实体
	struct sched_dl_entity dl;         // DL 调度实体
	struct sched_dl_entity *dl_server; // DL server（带宽借用机制）
	const struct sched_class *sched_class; // 方法表指针：此任务归哪个调度类
	struct sched_statistics stats;     // 调度统计（运行/等待时间）
	unsigned int policy;               // SCHED_NORMAL/FIFO/RR/BATCH/IDLE/DEADLINE
	unsigned long max_allowed_capacity; // 任务允许的最大 CPU 容量（异构/大小核）
	int nr_cpus_allowed;               // cpus_ptr 指向的 CPU 数
	const cpumask_t *cpus_ptr;         // 有效 CPU 掩码指针
	cpumask_t *user_cpus_ptr;          // 用户设置的 CPU 亲和掩码（sched_setaffinity）
	cpumask_t cpus_mask;               // 实际 CPU 亲和掩码（默认指向它）
	void *migration_pending;           // 迁移请求（stop_one_cpu）
	unsigned short migration_disabled; // 迁移被禁用计数
	unsigned short migration_flags;    // MDF_* 迁移标志
```

**关键设计**：
- `on_cpu`/`on_rq` 是一对"是否在 CPU / 是否在队列"指示位，`try_to_wake_up` 靠它们的读序（smp_rmb + 控制依赖获取）避免丢失唤醒（core.c:4300-4349 注释详细推演了三种竞争场景）。
- `cpus_ptr` 默认指向内嵌的 `cpus_mask`（dup_task_struct fork.c:963-964 处理），用户 setaffinity 时指向 `user_cpus_ptr`——省一个指针级别的间接。
- `prio` 三个层次：`static_prio`（用户设定）→ `normal_prio`（加 RT 规则）→ `prio`（实际调度用，可能被优先级继承临时提升）。

位字段区（sched.h:988-1067）：

```c
	unsigned sched_reset_on_fork:1;   // fork 时重置调度参数
	unsigned sched_contributes_to_load:1; // 计入 CPU 负载
	unsigned sched_migrated:1;
	unsigned sched_task_hot:1;        // 任务"热"（cache 亲和，迁移惩罚）
	unsigned :0;                      // 强制对齐下一字段
	unsigned sched_remote_wakeup:1;   // 远程唤醒标记（wakelist 路径专用，见长注释）
	unsigned in_execve:1;             // 正在 execve（TOMOYO 用它）
	unsigned in_iowait:1;             // 在等待 IO（计入 iowait 统计）
	...
	unsigned long atomic_flags;       // 需要原子访问的标志（PFA_*）
```

- `sched_remote_wakeup` 的位置有讲究：它不在调度器锁保护的字里，而是靠 `on_cpu` 的内存序保证可见（sched.h:998-1010 注释给了一段 5 行重排序推演）。

### 6.3 身份与族谱（sched.h:1071-1120）

```c
	pid_t pid;                        // 线程 ID（每个线程独立）
	pid_t tgid;                       // 线程组 ID（进程 ID；主线程 pid==tgid）
	struct task_struct __rcu *real_parent; // 真实父进程（生我的）
	struct task_struct __rcu *parent;     // SIGCHLD/wait 接收者（可能被 ptrace 重定向）
	struct list_head children;        // 我的孩子链表
	struct list_head sibling;         // 我在父亲孩子链表里的节点
	struct task_struct *group_leader; // 线程组组长
	struct list_head ptraced;         // 我 ptrace 的对象
	struct list_head ptrace_entry;    // 我在父亲 ptraced 链表里的节点
	struct pid *thread_pid;           // PID 对象（引用计数 + 哈希）
	struct hlist_node pid_links[PIDTYPE_MAX]; // PID 类型哈希链（PIDTYPE_PID/TGID/PGID/SID）
	struct list_head thread_node;     // 线程组内链表
	struct completion *vfork_done;    // vfork 等待完成
	int __user *set_child_tid;        // CLONE_CHILD_SETTID 用户态地址
	int __user *clear_child_tid;      // CLONE_CHILD_CLEARTID（线程退出时清 0）
```

**关键设计**：`real_parent` 与 `parent` 分离——ptrace 调试时 `parent` 指向 tracer，但 `real_parent` 始终是生物学父亲；`pid_links[PIDTYPE_MAX]` 让同一个 task_struct 同时挂在 PID/TGID/PGID/SID 四条哈希链上。

### 6.4 资源指针（sched.h:971-974, 1183-1219, 1158-1181）

```c
	struct mm_struct *mm;             // 用户地址空间（内核线程为 NULL）
	struct mm_struct *active_mm;      // 内核线程借用"上一次的 mm"（省切换）
	struct task_exec_state __rcu *exec_state; // 执行状态（7.x 新字段）
	...
	const struct cred __rcu *ptracer_cred; // ptrace 附加时的凭据
	const struct cred __rcu *real_cred;    // 客观凭据（真正身份）
	const struct cred __rcu *cred;         // 主观/有效凭据（可 override）
	char comm[TASK_COMM_LEN];         // 可执行文件名（set_task_comm 保证 NUL 结尾）
	struct fs_struct *fs;             // 文件系统上下文（根目录/cwd/umask）
	struct files_struct *files;       // 打开的文件表
	struct nsproxy *nsproxy;          // 命名空间（mnt/pid/net/ipc/uts/user）
	struct signal_struct *signal;     // 进程级信号信息（组共享）
	struct sighand_struct __rcu *sighand; // 信号处理函数表（组共享）
	sigset_t blocked;                 // 当前阻塞的信号集
	sigset_t real_blocked;
	sigset_t saved_sigmask;
	struct sigpending pending;        // 待处理信号队列
	unsigned long sas_ss_sp;          // 信号备用栈（sigaltstack）
	size_t sas_ss_size;
	unsigned int sas_ss_flags;
	struct callback_head *task_works; // task work 链表（返回用户态前执行）
```

**关键设计**：
- `mm == NULL` ⇔ 内核线程；`active_mm` 是内核线程借用普通进程 mm 的优化，避免地址空间切换（context_switch 时用）。
- `cred` 三指针 COW：`real_cred` 是"我是谁"，`cred` 是"我以谁的身份干活"（setuid/override 时分开）。
- 线程组共享 `signal/sighand`，但 `blocked/pending` 每线程一份。

### 6.5 时间与统计（sched.h:1122-1152）

```c
	u64 utime; stime; gtime;          // 用户/内核/客体时间
	struct prev_cputime prev_cputime; // 上次记账时间点
	unsigned long nvcsw;              // 自愿上下文切换次数
	unsigned long nivcsw;             // 非自愿上下文切换次数
	u64 start_time;                   // 单调时钟的启动时间（nsec）
	u64 start_boottime;               // 启动时钟时间
	unsigned long min_flt; maj_flt;   // 小/大缺页计数
	struct posix_cputimers posix_cputimers; // POSIX CPU 定时器
```

### 6.6 同步与并发控制（sched.h:1235-1260）

```c
	spinlock_t alloc_lock;            // 保护 mm/files/fs 等资源指针的分配/释放
	raw_spinlock_t pi_lock;           // 保护优先级继承（PI）数据结构
	struct wake_q_node wake_q;        // 延迟唤醒队列节点
	struct mutex *blocked_on;         // 当前阻塞在哪个 mutex（7.x）
	raw_spinlock_t blocked_lock;
	struct task_struct *blocked_donor;// 谁在为我提升优先级（代理执行 back-link）
```

- `pi_lock` 是调度器与 PI 的"总闸"，`try_to_wake_up` 也用它串行化状态读写（core.c:4292 `scoped_guard (raw_spinlock_irqsave, &p->pi_lock)`）。
- `blocked_on/blocked_donor` 是 7.x 的**阻塞代理/优先级提升**机制字段，在 `schedule()` 的 `find_proxy_task()` 中设置（sched.h:1255-1260 注释）。

### 6.7 退出路径（sched.h:976-982, 1581-1583）

```c
	int exit_state;                   // EXIT_ZOMBIE/EXIT_DEAD（与 __state 隔离）
	int exit_code;                    // 退出码（wait4 读取）
	int exit_signal;                  // 退出时发给父进程的信号（默认 SIGCHLD）
	int pdeath_signal;                // 父进程死亡时发给我的信号
	unsigned long jobctl;             // JOBCTL_* 工作控制位（siglock 保护）
	...
	struct rcu_head rcu;              // RCU 回调（延迟释放 task_struct）
	refcount_t rcu_users;             // RCU 用户引用（用户态可见生命周期）
	int pagefault_disabled;
```

- **双引用计数**（dup_task_struct fork.c:967-973 设定初值）：`rcu_users = 2`（一个给用户态可见状态、一个给调度器），`usage = 1`（给 RCU）。释放顺序：先 `rcu_users` 归零触发 `call_rcu` 延迟回收，`rcu` 回调里再 `put_task_struct` 让 `usage` 归零真正 free。

### 6.8 子系统挂钩（CONFIG 裁剪，选讲）

```c
	struct seccomp seccomp;           // seccomp 过滤器
	struct syscall_user_dispatch syscall_dispatch; // 用户态系统调用分发
	struct futex_sched_data futex;    // futex 调度数据
	struct rseq_data rseq;            // restartable sequences
	struct sched_mm_cid mm_cid;       // mm 关联的 CPU 上下文 ID（cache 亲和）
	struct tlbflush_unmap_batch tlb_ubc; // TLB flush 批处理
	struct page_frag task_frag;       // 每任务页碎片缓存（网络/文件分配用）
	int nr_dirtied; nr_dirtied_pause; // 脏页节流
	unsigned long dirty_paused_when;
	u64 timer_slack_ns;               // poll/select 超时取整
	u64 default_timer_slack_ns;
	...
	struct thread_struct thread;      // 架构 CPU 现场（寄存器等），随机化区末尾
} __attribute__ ((aligned (64)));     // 64 字节对齐，配合 cacheline
```

---

## 七、关键概念补充

### 7.1 `current` 宏：每 CPU 一个指针

`current` 不是遍历得到的，而是**每 CPU 变量**（x86: `arch/x86/include/asm/current.h:15`）：

```c
DECLARE_PER_CPU_CACHE_HOT(struct task_struct *, current_task);
static __always_inline struct task_struct *get_current(void)
{
	return this_cpu_read_stable(current_task);
}
#define current get_current()
```

上下文切换时 `switch_to` 更新该 per-cpu 变量，所以任何时刻 `current` 就是"正在本 CPU 上跑的那个 task_struct"。`task_thread_info()` 从 `current->thread_info` 取出线程信息。

### 7.2 `__state` 状态机与内存序

| 状态 | 值 | 含义 |
|---|---|---|
| `TASK_RUNNING` | 0x0 | 可运行（唯一"活着且能跑"状态） |
| `TASK_INTERRUPTIBLE` | 0x1 | 可中断睡眠 |
| `TASK_UNINTERRUPTIBLE` | 0x2 | 不可中断睡眠 |
| `__TASK_STOPPED` | 0x4 | 停止（SIGSTOP） |
| `__TASK_TRACED` | 0x8 | 被 ptrace 跟踪 |
| `TASK_PARKED` | 0x40 | 停放（kthread park） |
| `TASK_WAKING` | 0x200 | 唤醒中间态 |
| `TASK_NEW` | 0x800 | 新建未入队 |
| `TASK_KILLABLE` | 0x102 | 可杀睡眠（WAKEKILL\|UNINT） |
| `EXIT_ZOMBIE/DEAD` | 0x20/0x10 | **exit_state** 专用（与 __state 隔离） |

写状态的三条规则（sched.h:203-269）：
- `set_current_state()` 用 `smp_store_mb`——**写状态必须带全屏障**，与 `try_to_wake_up` 在 `pi_lock` 后 `smp_mb__after_spinlock` 配对，防 lost wakeup；
- `__set_current_state()` 只 `WRITE_ONCE`——在锁保护下不需要屏障时用；
- `set_special_state()` 关中断 + `pi_lock`——用于不能走常规等待循环的特殊状态（STOPPED/TRACED/PARKED），防 TASK_RUNNING 写与状态写竞争。

唤醒侧：`try_to_wake_up` 状态匹配后先写 `p->__state = TASK_WAKING`（core.c:4357），解锁后再真正入队置 RUNNING——中间态允许 `ttwu_queue_wakelist` 在释放 `pi_lock` 后安全入队。

用户态可见状态字符（sched.h:1715-1727）：`"RSDTtXZPI"` —— R=Running, S=Interruptible, D=Uninterruptible, T=Stopped, t=Traced, X=Dead, Z=Zombie, P=Parked, I=Idle。

### 7.3 引用计数：为什么是两个

| 引用 | 保护对象 | 谁持有 | 归零后 |
|---|---|---|---|
| `usage` | 结构体内存本身 | RCU 回调、get_task_struct 各持有者 | 真正 `free_task_struct` |
| `rcu_users` | "用户态还能看到这个任务"的窗口 | fork 时 2（用户态可见 + 调度器） | 触发 `call_rcu` 延迟回收，`rcu` 回调里释放 `usage` |

好处：任务在 RCU 读侧临界区内被引用时不必阻塞 `put_task_struct`，`rcu_users` 先归零走 RCU 延迟，普通读者（如遍历 tasks 链表）安全。

### 7.4 布局随机化（`randomized_struct_fields_start/end`）

结构体中段字段会被 GCC 的 `-fplugin=randomize_layout_plugin` 在**编译期随机重排**（防基于固定偏移的内核攻击），调度关键字段放在随机区之前，`thread` 放最后，`aligned(64)` 保证 cacheline 对齐。随机区字段之间**不能依赖相对偏移**，这也是为什么 `on_rq`/`on_cpu` 的读写全部走 READ_ONCE/WRITE_ONCE 并依赖显式屏障而非相邻性。

---

## 附：关键证据索引

| 证据 | 位置 |
|---|---|
| task_struct 定义（约 844 行） | include/linux/sched.h:826-1670 |
| TASK_* 状态宏 | include/linux/sched.h:107-150 |
| set_current_state 宏族 | include/linux/sched.h:240-269 |
| 状态字符映射 | include/linux/sched.h:1688-1727 |
| current 宏（per-cpu） | arch/x86/include/asm/current.h:15-28 |
| init_task（0 号进程） | init/init_task.c:105 |
| dup_task_struct | kernel/fork.c:914-1025 |
| copy_process（copy_process→dup_task_struct 于 fork.c:2115） | kernel/fork.c:1994 |
| try_to_wake_up 状态机 | kernel/sched/core.c:4251-4400 |
| copy_process 直接调用者（MCP） | kernel_clone / fork_idle / create_io_thread / vhost_task_create |

*分析基于 Linux 7.2-rc6，证据全部来自 kernel-graph MCP 与源码阅读。*
