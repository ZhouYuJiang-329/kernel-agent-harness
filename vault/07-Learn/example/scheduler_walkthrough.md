# 调度流程示例

> 这是一份用于演示 Dashboard 和 Memory 数据格式的简化文档，不代表完整源码分析。

## 一、大白话总览

调度入口需要先选择下一个可运行任务，再完成上下文切换。真实分析中，应使用源码检索工具确认具体实现、调用关系和版本差异。

## 二、示例调用链

```text
schedule
  └── pick_next_task
        └── context_switch
```

## 三、学习状态

| 节点 | 状态 | 说明 |
|---|---|---|
| `schedule` | mastered | 已理解整体职责 |
| `pick_next_task` | exploring | 仍需展开调度类选择逻辑 |
| `context_switch` | unknown | 尚未开始分析 |

## 四、下一步

配置 kernel-graph MCP 后，用真实内核版本重新查询上述函数，并将确认后的直接调用边写入 `dep-graph.md`。

