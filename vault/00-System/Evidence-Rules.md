# Evidence Rules — 证据纪律（内核分析宪法）

> 本文件是内核知识体系的**最高约束**。任何写入 vault 的知识必须遵守。

## 核心原则

1. **证据优先**：涉及具体函数、结构体、源码路径、行号或调用关系时，**必须先用 kernel-graph MCP 确认**（find_definition / find_callers / find_callees / call_chain_up / call_chain_down / find_struct / search_functions / functions_in_file）。
2. **禁止编造**：没有查询证据时，不写具体路径、行号和调用边。无法确认的内容：
   - 知识节点表"证据"列填 `-`
   - 置信度不超过 40
   - 标 `questioned` 或写入 `Memory-Queue.md` 等待验证
3. **间接调用标记**：静态分析无法确认的函数指针和间接调用，标"待验证"，并建议记入 `Open-Questions.md`。
4. **版本一致**：引用 API 前先查 `Kernel-Version-Notes.md`；外部文档与源码不一致时，**以当前源码为准**，并把差异记入版本表。
5. **调用边入图门槛**：只有 MCP 确认的直接调用关系才能写入 `dep-graph.md`；分析推导的边写注释但不得作为正式边。

## 节点状态与置信度

| 状态 | 含义 | 置信度 |
| --- | --- | --- |
| unknown | 未分析（骨架节点） | 0 |
| exploring | 已分析但不完整/未全部验证 | 40-79 |
| mastered | 核心路径验证完毕 | ≥80 |
| questioned | 有疑问/证据矛盾 | 任意 |

## 分析前检查

```bash
python lookup_status.py <function-or-struct>
```
- `unknown` / `not_found` → 完整分析
- `exploring` → 优先补充调用链、设计动机、边界条件
- `mastered` → 先复用已有笔记，避免重复分析
- `questioned` → 优先查看关联开放问题
