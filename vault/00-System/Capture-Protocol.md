# Capture Protocol — 融合捕获协议

> 内核知识捕获流水线：Boujoy 打分/去重 + 内核证据/状态机/依赖图融合。
> 由 `kernel-learning-capture` 技能执行；每个分析完成后必须走完 1-8 步。

## 流程

```
分析完成（含 MCP 证据）
   │
   ├─ 1. 打分
   │      0-3 不存 | 4-5 进 Memory-Queue | 6-8 存知识卡 | 9-10 存卡 + 更新 Hot-Index
   │      内核补充规则：证据缺失的节点 ≤5 分；调用边无证据禁止入图
   │
   ├─ 2. 查重
   │      read Memory-Index + Hot-Index（同主题绝不新建）
   │      → 网关 /api/knowledge/capture 二次去重（相似度 ≥0.62 → 403 带相似卡路径）
   │      → 命中则改为"追加更新记录"到原卡
   │
   ├─ 3. 更新节点  python upsert_node.py {sub} {name} {type} {status} {conf} {note} {evidence}
   ├─ 4. 更新依赖图 python append_dep_edge.py {sub} {parent} {child} "{说明}"（仅确认边）
   ├─ 5. 问答归档  python append_qa.py {sub} {node} {用户提问|AI发现} {q} {bg} {conclusion} {date}
   ├─ 6. 未解问题  python append_question.py {CRITICAL|MEDIUM|LOW} {q} {src} {related} {assumption} {query}
   ├─ 7. 刷新索引  python update_memory.py {sub} {name}（表格统计 + 最近5分析 + OQ 计数）
   └─ 8. 写日志    更新 Learning-Journal.md + Active-Context.md
```

## 打分细则（内核版 Value-Filter）

| 分数 | 处理 | 例子 |
|---|---|---|
| 0-3 | 不保存 | 闲聊、无证据猜测 |
| 4-5 | Memory-Queue.md | 有价值但证据不足/待验证 |
| 6-8 | 存知识卡（knowledge.md 节点 + 07-Learn 笔记） | MCP 确认的函数分析 |
| 9-10 | 存卡 + 更新 Hot-Index | 核心路径完整验证、版本关键差异 |

## 路径约定

| 内容 | 位置 |
|---|---|
| 知识节点表 | vault/03-Knowledge/{subsystem}/knowledge.md |
| 依赖图 | vault/03-Knowledge/{subsystem}/dep-graph.md |
| 问答日志 | vault/03-Knowledge/{subsystem}/qa-log.md |
| 深度笔记 | vault/07-Learn/{subsystem}/ |
| 全库索引 | vault/00-System/Memory-Index.md |
| 开放问题 | vault/00-System/Open-Questions.md |
| 学习日志 | vault/00-System/Learning-Journal.md |
