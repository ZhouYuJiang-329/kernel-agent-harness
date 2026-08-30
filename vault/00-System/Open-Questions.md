# Open Questions

## CRITICAL（阻塞学习进展）

暂无。

## MEDIUM（重要但不阻塞）

### OQ-001（MEDIUM）

- **来源**：示例学习流程
- **问题**：如何验证函数指针产生的间接调用关系？
- **相关函数/结构体**：`pick_next_task`
- **当前假设**：需要结合静态调用图、函数指针赋值位置和源码人工核验。
- **建议查询**：使用源码搜索定位回调注册点和实际调用点。

### OQ-002（MEDIUM）

- **问题**：task_struct 布局随机化（randomized_struct_fields_start/end）的 GCC plugin 机制如何工作？随机化后字段间依赖如何保持正确？
- **来源**：2026-08-28 分析 task_struct 时发现
- **相关函数**：task_struct, randomize_layout
- **当前假设**：编译期用 -fplugin=randomize_layout_plugin 重排随机区字段，运行时重排需 KASLR 配合；字段访问靠 READ_ONCE/WRITE_ONCE 不依赖偏移
- **建议查询**：`kernel-graph 查 randomize_layout_plugin 源码或 scripts/gcc-plugins/ 下插件实现`
- **提出日期**：2026-08-30
- **解答日期**：-

## LOW（感兴趣但非当前重点）

暂无。

## 已解答（归档）

暂无。

