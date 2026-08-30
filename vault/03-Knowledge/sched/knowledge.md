# 调度器知识节点

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|

## 调度主路径

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| __schedule | function | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| schedule | function | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| pick_next_task | function | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| __pick_next_task | function | unknown | 0 | - | - | 2026-08-28 |
| put_prev_task | function | unknown | 0 | - | - | 2026-08-28 |
| set_next_task | function | unknown | 0 | - | - | 2026-08-28 |
| put_prev_set_next_task | function | unknown | 0 | - | - | 2026-08-28 |
| update_rq_clock | function | unknown | 0 | - | - | 2026-08-28 |
| schedule_debug | function | unknown | 0 | - | - | 2026-08-28 |
| schedule_idle | function | unknown | 0 | - | - | 2026-08-28 |
| preempt_schedule_common | function | unknown | 0 | - | - | 2026-08-28 |
| prev_balance | function | unknown | 0 | - | - | 2026-08-28 |

## 上下文切换

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| context_switch | function | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| switch_mm_irqs_off | function | unknown | 0 | - | - | 2026-08-28 |
| switch_to | function | unknown | 0 | - | - | 2026-08-28 |
| finish_task_switch | function | unknown | 0 | - | - | 2026-08-28 |
| prepare_task_switch | function | unknown | 0 | - | - | 2026-08-28 |

## 唤醒路径

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| try_to_wake_up | function | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| ttwu_queue | function | unknown | 0 | - | - | 2026-08-28 |
| ttwu_do_activate | function | unknown | 0 | - | - | 2026-08-28 |
| ttwu_do_wakeup | function | unknown | 0 | - | - | 2026-08-28 |
| wakeup_preempt | function | unknown | 0 | - | - | 2026-08-28 |
| resched_curr | function | unknown | 0 | - | - | 2026-08-28 |
| select_task_rq | function | unknown | 0 | - | - | 2026-08-28 |
| wake_up_process | function | unknown | 0 | - | - | 2026-08-28 |
| wake_up_state | function | unknown | 0 | - | - | 2026-08-28 |
| __wake_up_common | function | unknown | 0 | - | - | 2026-08-28 |
| wake_up_new_task | function | unknown | 0 | - | - | 2026-08-28 |
| default_wake_function | function | unknown | 0 | - | - | 2026-08-28 |

## CFS

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| enqueue_task_fair | function | unknown | 0 | - | - | 2026-08-28 |
| dequeue_task_fair | function | unknown | 0 | - | - | 2026-08-28 |
| pick_task_fair | function | unknown | 0 | - | - | 2026-08-28 |
| pick_next_entity | function | unknown | 0 | - | - | 2026-08-28 |
| put_prev_task_fair | function | unknown | 0 | - | - | 2026-08-28 |
| set_next_task_fair | function | unknown | 0 | - | - | 2026-08-28 |
| task_tick_fair | function | unknown | 0 | - | - | 2026-08-28 |
| update_curr | function | unknown | 0 | - | - | 2026-08-28 |
| update_curr_fair | function | unknown | 0 | - | - | 2026-08-28 |
| enqueue_entity | function | unknown | 0 | - | - | 2026-08-28 |
| dequeue_entity | function | unknown | 0 | - | - | 2026-08-28 |
| place_entity | function | unknown | 0 | - | - | 2026-08-28 |
| update_load_avg | function | unknown | 0 | - | - | 2026-08-28 |
| check_update_overutilized_status | function | unknown | 0 | - | - | 2026-08-28 |
| add_nr_running | function | unknown | 0 | - | - | 2026-08-28 |
| wakeup_preempt_fair | function | unknown | 0 | - | - | 2026-08-28 |
| select_task_rq_fair | function | unknown | 0 | - | - | 2026-08-28 |
| wake_affine | function | unknown | 0 | - | - | 2026-08-28 |
| select_idle_sibling | function | unknown | 0 | - | - | 2026-08-28 |
| entity_tick | function | unknown | 0 | - | - | 2026-08-28 |

## RT

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| enqueue_task_rt | function | unknown | 0 | - | - | 2026-08-28 |
| pick_next_task_rt | function | unknown | 0 | - | - | 2026-08-28 |
| pick_next_rt_entity | function | unknown | 0 | - | - | 2026-08-28 |
| update_curr_rt | function | unknown | 0 | - | - | 2026-08-28 |

## DL

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| enqueue_task_dl | function | unknown | 0 | - | - | 2026-08-28 |
| pick_next_dl_entity | function | unknown | 0 | - | - | 2026-08-28 |
| update_curr_dl | function | unknown | 0 | - | - | 2026-08-28 |
| task_tick_dl | function | unknown | 0 | - | - | 2026-08-28 |

## 负载均衡

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| sched_balance_rq | function | unknown | 0 | - | - | 2026-08-28 |
| sched_balance_newidle | function | unknown | 0 | - | - | 2026-08-28 |
| sched_balance_softirq | function | unknown | 0 | - | - | 2026-08-28 |
| active_load_balance_cpu_stop | function | unknown | 0 | - | - | 2026-08-28 |

## 优先级与策略

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| sched_setscheduler | function | unknown | 0 | - | - | 2026-08-28 |
| sched_setscheduler_nocheck | function | unknown | 0 | - | - | 2026-08-28 |
| __sched_setscheduler | function | unknown | 0 | - | - | 2026-08-28 |
| sched_setattr | function | unknown | 0 | - | - | 2026-08-28 |
| set_user_nice | function | unknown | 0 | - | - | 2026-08-28 |
| normal_prio | function | unknown | 0 | - | - | 2026-08-28 |
| effective_prio | function | unknown | 0 | - | - | 2026-08-28 |
| task_prio | function | unknown | 0 | - | - | 2026-08-28 |

## CPU 亲和性与迁移

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| set_cpus_allowed_ptr | function | unknown | 0 | - | - | 2026-08-28 |
| __set_cpus_allowed_ptr | function | unknown | 0 | - | - | 2026-08-28 |
| migrate_disable | function | unknown | 0 | - | - | 2026-08-28 |

## 生命周期

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| sched_fork | function | unknown | 0 | - | - | 2026-08-28 |
| sched_post_fork | function | unknown | 0 | - | - | 2026-08-28 |
| schedule_tail | function | unknown | 0 | - | - | 2026-08-28 |

## 调度周期

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| sched_tick | function | unknown | 0 | - | - | 2026-08-28 |

## 关键结构体

| 名称 | 类型 | 状态 | 置信度 | 笔记 | 内部文档 | 更新日期 |
|---|---|---|---:|---|---|---|
| task_struct | struct | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| sched_class | struct | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| sched_entity | struct | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| sched_rt_entity | struct | unknown | 0 | - | - | 2026-08-28 |
| sched_dl_entity | struct | unknown | 0 | - | - | 2026-08-28 |
| rq | struct | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| cfs_rq | struct | unknown | 0 | 07-Learn/sched/sched_read_guide.md | - | 2026-08-28 |
| rt_rq | struct | unknown | 0 | - | - | 2026-08-28 |
| dl_rq | struct | unknown | 0 | - | - | 2026-08-28 |
| rt_prio_array | struct | unknown | 0 | - | - | 2026-08-28 |
| sched_attr | struct | unknown | 0 | - | - | 2026-08-28 |
