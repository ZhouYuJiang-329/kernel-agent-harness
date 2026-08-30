# Learning Journal

## 2026-08-28

**学习内容**：
- 为"进程调度器"建立学习板块：基于 Linux 7.2-rc6 源码，用 kernel-graph MCP 确认了调度器核心 API/结构体的真实位置。
- 生成阅读指南 `07-Learn/sched/sched_read_guide.md`（11 个分类 + 关键数据结构主线 + 阅读顺序 + API 检索表）。
- 初始化调度器依赖图骨架：`__schedule` / `pick_next_task` / `try_to_wake_up` / `context_switch` / `enqueue_task_fair` 五条主线的直接调用边。
- 在 `03-Knowledge/sched/knowledge.md` 建立 66 个 unknown 节点（初始置信度 0）。

**关键版本发现**：
- 7.2-rc6 中 `scheduler_tick` 改名为 `sched_tick`（core.c:5762）；`check_preempt_curr` 重构为 `wakeup_preempt`。
- CFS 的 pick 入口是 `pick_task_fair`（fair.c:9912），`pick_next_task_fair` 不再存在。
- 负载均衡接口重构为 `sched_balance_rq` / `sched_balance_newidle` / `sched_balance_softirq`。

**新增笔记**：
- `07-Learn/sched/sched_read_guide.md`

**知识状态变化**：
- 新建 `sched` 子系统：66 个节点全部 `unknown`，待 `kernel-code-analyzer` 逐个深化。

**下次建议**：
- 从调度主路径开始深度分析 `__schedule`（core.c:7061），再顺调用链深化 `pick_next_task` 与 `context_switch`。

## 2026-01-01

**学习内容**：
- 初始化示例模块和长期记忆结构。
- 演示知识节点状态及依赖关系。

**新增笔记**：
- `07-Learn/example/scheduler_walkthrough.md`

**知识状态变化**：
- `schedule` → mastered
- `pick_next_task` → exploring

**新增开放问题**：
- OQ-001：如何验证函数指针产生的间接调用关系？

**下次建议**：
- 使用真实源码检索工具替换示例节点。

