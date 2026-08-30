# Kernel-Agent-Harness 记忆架构设计

> 目标：为 `kernel-agent-harness`（DeepSeek Harness 环境，不运行 Claude）设计一套融合记忆系统。
> 融合对象：
> - **Boujoy Harness 的 PKM**：文件即知识、00-System 规则层、Active-Context 工作记忆、捕获流水线（打分/去重/压缩）、知识搜索
> - **kernel-learning-agent 的内核体系**：知识节点状态机（unknown/exploring/mastered/questioned + 置信度）、依赖图、开放问题、问答日志、学习日志、**证据纪律**（MCP 确认、禁止编造）、版本差异追踪
>
> 关键约束：无 Claude hooks（PostToolUse 不存在）、无 Claude 技能调用语法；全部由 dsh 的机制承载：
> 技能自动加载（description 匹配）、MCP 工具、Agent 预设（persona）、会话持久化/压缩、Boujoy 网关（搜索/媒体/UI）。

---

## 1. 设计原则

1. **文件即知识**：所有记忆是 vault 里的 Markdown，可被 Obsidian/任何工具编辑，永不锁死。
2. **证据驱动**：函数/结构体/调用边/行号必须由 kernel-graph MCP 确认；无证据不写入 dep-graph；间接调用标"待验证"。
3. **状态可演进**：知识节点带状态机 + 置信度，先建骨架、逐点深化，避免"一次讲完不复查"。
4. **无 Claude 依赖**：hook 自动化 → 技能流程强制；bash → python；斜杠调用 → 对话点名/自动匹配。
5. **分层解耦**：数据（vault）、规则（00-System）、操作（scripts）、能力（skills/MCP/preset）四层分离。

---

## 2. 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│ 能力层  kernel-expert 预设(persona) · skills · kernel-graph MCP │
├─────────────────────────────────────────────────────────────┤
│ 操作层  home/scripts/*.py · home/skills/*/scripts/*.py        │
│         (upsert_node / count_stats / lookup_status /          │
│          append_dep_edge / append_question / ... )            │
├─────────────────────────────────────────────────────────────┤
│ 规则层  vault/00-System/  （宪法 + 捕获协议 + 版本表 + 索引）   │
├─────────────────────────────────────────────────────────────┤
│ 数据层  vault/01-07  （知识节点 · 依赖图 · 问答 · 问题 · 笔记） │
└─────────────────────────────────────────────────────────────┘
        ▲                                    │
        └──── Boujoy 网关（搜索/阅读/媒体）────┘
        （dsh 会话记忆/压缩在能力层之下独立运行）
```

---

## 3. Vault 目录结构（融合版）

```
kernel-agent-harness\vault\
├── 00-System\                        ← 规则与工作记忆（会话启动必读）
│   ├── Active-Context.md              工作记忆：当前学到哪、下一步做什么
│   ├── Memory-Index.md                全库索引：子系统表 + 统计 + 最近分析（≈ 旧 MEMORY.md）
│   ├── Hot-Index.md                   热知识索引（高频复用节点）
│   ├── Memory-Queue.md                待处理队列（证据不足/低分候选）
│   ├── Open-Questions.md              开放问题（CRITICAL/MEDIUM/LOW + 已解答归档）
│   ├── Learning-Journal.md            学习日志（按日期）
│   ├── Kernel-Version-Notes.md        ⭐ 内核版本差异表（7.2-rc6 API 改名）
│   ├── Evidence-Rules.md              ⭐ 证据纪律（MCP 确认、禁编造、间接调用标记）
│   ├── Capture-Protocol.md            ⭐ 融合捕获协议（打分 + 状态机 + 去重）
│   ├── Knowledge-Card-Template.md     知识卡模板（Boujoy）
│   └── Cleanup-Candidates.md          清理候选（Boujoy 生成）
├── 01-Inbox\                          收件箱（未分类）
├── 02-Projects\
│   └── Linux-Kernel\                  内核学习项目（项目上下文、目标、路线）
├── 03-Knowledge\                       ← 内核知识节点（替代旧 memory/{subsystem}/）
│   ├── sched\
│   │   ├── knowledge.md               知识节点表（状态机表格）
│   │   ├── dep-graph.md               依赖图（仅证据确认的边）
│   │   └── qa-log.md                  问答日志
│   ├── mm\  fs\  net\  ...            其他子系统（按需 init_module 创建）
│   └── unclassified\                  暂存区（未归类节点）
├── 04-Content\                        内容资料（非知识卡的长文）
├── 05-Prompts\
│   └── Boujoy-Harness\
│       ├── Experts\                   内核专家卡（sched 专家、mm 专家…，可一键调度）
│       └── Styles\                    输出风格（中文 + ASCII 调用树 + 证据引用）
├── 06-Business\                       预留
├── 07-Learn\                           ← 深度笔记（替代旧 learn/）
│   ├── sched\  (sched_read_guide.md, _index.md, ...)
│   └── ...
├── 98-Skills\                         技能说明（vault 内文档，可选）
└── 99-Logs\                           运行日志
```

> 说明：`00-System` 是 Boujoy 的受保护根；`03-Knowledge` 映射 Boujoy 的 capture 分类（knowledge）；每个子系统目录同时含节点表/依赖图/问答三件套（内核体系特征）。

---

## 4. 记忆分层

| 层 | 载体 | 维护者 | 读写时机 |
| --- | --- | --- | --- |
| 会话记忆（短期） | dsh session JSONL | dsh 引擎 | 自动：每次对话；compaction 自动压缩长会话 |
| 工作记忆（当下） | `00-System/Active-Context.md` | 模型（技能/预设指令） | 会话启动读；每次分析后更新 |
| 节点记忆（长期） | `03-Knowledge/{sub}/knowledge.md` | upsert_node.py | 分析完成时更新状态/置信度/笔记路径 |
| 图记忆 | `03-Knowledge/{sub}/dep-graph.md` | append_dep_edge.py | 仅 MCP 确认的新边 |
| 问答记忆 | `03-Knowledge/{sub}/qa-log.md` | append_qa.py | 重要问答发生时 |
| 问题记忆 | `00-System/Open-Questions.md` | append_question.py / resolve_question.py | 发现未解问题时；解答后归档 |
| 索引记忆 | `00-System/Memory-Index.md` | update_memory.py + count_stats.py | 每次捕获后刷新 |
| 日志记忆 | `00-System/Learning-Journal.md` | 模型 | 每次学习会话结束 |
| 版本记忆 | `00-System/Kernel-Version-Notes.md` | 模型（证据确认后） | 发现 API 差异时 |
| 热记忆 | `00-System/Hot-Index.md` | 模型 | 节点转 mastered / 高频复用时 |

---

## 5. 内核知识节点模型（状态机）

knowledge.md 表格 schema（沿用内核体系，兼容 Boujoy 搜索）：

```markdown
## CFS
| 名称 | 类型 | 状态 | 置信度 | 证据 | 笔记 | 更新日期 |
|------|------|------|--------|------|------|---------|
| enqueue_task_fair | function | exploring | 60 | kernel/sched/fair.c:6000 | 07-Learn/sched/... | 2026-08-30 |
```

- **状态机**：`unknown(无分析) → exploring(已分析未完全) → mastered(置信度≥80) / questioned(存疑)`；置信度 0-100。
- **证据列**（新增，内核特色）：MCP 确认的文件:行号，无证据填 `-`。
- **分析前查重**：`lookup_status.py <name>` → unknown/not_found=完整分析；exploring=补充；mastered=复用；questioned=先查 Open-Questions。

---

## 6. 融合捕获流水线（Capture-Protocol）

> 由 Boujoy 捕获器（打分/去重/压缩）+ 内核状态机（证据/依赖图/问答）融合。

```
分析完成（含 MCP 证据）
   │
   ├─ 1. 打分（按 Capture-Protocol 内核版）
   │      0-3 不存 | 4-5 进 Memory-Queue | 6-8 存知识卡 | 9-10 存卡 + 更新 Hot-Index
   │      内核补充规则：证据缺失的节点 ≤5 分；调用边无证据禁止入图
   │
   ├─ 2. 查重
   │      read Memory-Index + Hot-Index（同主题绝不新建）
   │      → 网关 /api/knowledge/capture 二次去重（Jaccard ≥0.62 → 403 带相似卡路径）
   │      → 命中则改为"追加更新记录"到原卡
   │
   ├─ 3. 更新节点  upsert_node.py {sub} {name} {type} {status} {conf} {note} {evidence}
   ├─ 4. 更新依赖图 append_dep_edge.py {sub} {parent} {child} "{说明}"   （仅确认边）
   ├─ 5. 问答归档  append_qa.py {sub} {node} 用户提问|AI发现 {q} {bg} {conclusion} {date}
   ├─ 6. 未解问题  append_question.py {CRITICAL|MEDIUM|LOW} {q} {src} {related} {assumption} {query}
   ├─ 7. 刷新索引  update_memory.py {sub} {name}   （表格统计 + 最近5分析 + OQ 计数）
   └─ 8. 写日志    Learning-Journal.md 追加条目；更新 Active-Context.md
```

**与纯 Boujoy 捕获器的差异**：多了证据列、依赖图、问答/问题归档、状态机——这些是内核学习的刚需，Boujoy 通用捕获器没有；保留 Boujoy 的去重/压缩/受保护写入。

---

## 7. 会话工作流（无 hooks 的替代方案）

> Claude 的 PostToolUse hook（写 learn/ 自动触发 capture）在 dsh 不存在。
> 替代机制：**流程由技能/预设强制** —— 由 `kernel-learning-capture` 技能指令 + kernel-expert 预设 persona 约束。

```
会话启动
  1. persona（kernel-expert 预设）指示：读 Active-Context.md + Open-Questions.md + Kernel-Version-Notes.md
  2. 模型自动加载匹配技能（description 命中）或用户点名

分析阶段
  3. lookup_status.py 查节点状态 → 决定深度
  4. kernel-graph MCP 查定义/调用链（证据）
  5. 写深度笔记到 07-Learn/{sub}/ （此动作后，技能指令要求：必须执行捕获流水线）

捕获阶段（kernel-learning-capture 技能流程，替代 hook）
  6. 执行第 6 节流水线 1-8 步

会话结束
  7. 更新 Active-Context.md（下次学到哪）+ Learning-Journal.md
```

---

## 8. 工具与脚本映射

| 旧（Claude 环境 bash） | 新（dsh 环境 python） | 位置 |
| --- | --- | --- |
| upsert_node.sh | `upsert_node.py` | home/scripts/ |
| count_stats.sh | `count_stats.py` | home/scripts/ |
| lookup_status.sh | `lookup_status.py` | home/scripts/ |
| append_dep_edge.sh | `append_dep_edge.py` | home/skills/kernel-learning-capture/scripts/ |
| append_question.sh | `append_question.py` | 同上 |
| resolve_question.sh | `resolve_question.py` | 同上 |
| update_memory.sh | `update_memory.py` | 同上 |
| append_qa.sh | `append_qa.py` | home/skills/kernel-qa-log/scripts/ |
| init_module.sh | `init_module.py` | home/skills/add-learning-module/scripts/ |
| init_agent.sh | `init_agent.py` | 同上 |
| reclassify.sh | `reclassify.py` | 同上 |
| update_claude_md.sh | `update_claude_md.py`（目标改为 Memory-Index/Active-Context） | 同上 |
| find_changed_files.sh | `find_changed_files.py` | home/skills/obsidian-sync/scripts/ |

**路径锚点**：脚本统一以 `home`（runtime/DeepSeekHarness/home）为根；vault 数据经 `../../vault` 或待定路径访问（路径确认后统一修改，见 §12）。

---

## 9. 技能角色映射（13 → dsh）

| 技能 | dsh 中的角色 | 调整 |
| --- | --- | --- |
| kernel-code-analyzer | 函数/结构体深度分析（MCP 证据） | 正文改 python 调用；加"证据列"要求 |
| kernel-reading-guide | 模块阅读路线图 | 输出到 07-Learn/ |
| kernel-concept-mapper | 算法/硬件背景补充 | 不变 |
| kernel-learning-capture | 捕获流水线执行器 | **替代 hook**：写 07-Learn 后必须执行 8 步 |
| kernel-learning-synthesizer | 笔记综合（术语表/矩阵/索引） | 输出到 00-System 索引 |
| kernel-doc-comprehension-coach | 理解验收问答 | 不变 |
| kernel-impact-analyzer | 变更影响分析 | classify_impact.py 已可用（python） |
| kernel-qa-log | 问答归档 | append_qa.py |
| kernel-progress-report | 进度报告 | count_stats.py + generate_tree.py |
| add-learning-module | 新子系统初始化 | init_module.py 创建 03-Knowledge 三件套 + 07-Learn |
| obsidian-sync | 同步到 Obsidian（可选） | find_changed_files.py |
| drawio-diagram-generator | 绘图 | 不变 |
| show-progress | Dashboard | 依赖 dashboard/（见 §13 路线图） |

---

## 10. 内核版本记忆（Kernel-Version-Notes.md）⭐

内核学习最大痛点：API 随版本变动。该文件为常驻规则，捕获协议要求"引用具体函数前先对版本"：

```markdown
# Kernel Version Notes — Linux 7.2-rc6
## 已确认差异（kernel-graph MCP 验证）
| 旧 API | 新 API | 位置 | 确认日期 |
|---|---|---|---|
| scheduler_tick | sched_tick | kernel/sched/core.c:5762 | 2026-08-28 |
| check_preempt_curr | wakeup_preempt | kernel/sched/ | 2026-08-28 |
| pick_next_task_fair | pick_task_fair | kernel/sched/fair.c:9912 | 2026-08-28 |
| sched_balance_*（重构） | 见注释 | kernel/sched/ | 2026-08-28 |
## 待验证差异
```

---

## 11. 与 Boujoy UI 的集成点

- **知识浏览**：Boujoy 知识页自动索引 vault（路径/内容/媒体），`/api/knowledge/search` CJK 检索 → 内核知识卡可搜索
- **阅读器**：`/api/knowledge/file` 读任意 md（含 dep-graph、阅读指南）
- **专家调度**：`05-Prompts/Boujoy-Harness/Experts/` 放内核专家卡，Boujoy "调用阵容"一键调度
- **风格**：`Styles/` 定义输出风格（中文+ASCII 树+证据引用）
- **媒体**：会话内图片/视频预览（内核图、视频笔记）
- **捕获 API**：`/api/knowledge/capture`（网关去重兜底）继续由捕获流水线调用

---

## 12. 迁移步骤（从 kernel-learning-agent → kernel-agent-harness）

1. **复制数据**：
   - `.claude/memory/MEMORY.md` → `vault/00-System/Memory-Index.md`（改内部链接路径）
   - `.claude/memory/open-questions.md` → `vault/00-System/Open-Questions.md`
   - `.claude/memory/learning-journal.md` → `vault/00-System/Learning-Journal.md`
   - `.claude/memory/{sched,example}/` → `vault/03-Knowledge/{sched,example}/`（knowledge.md/dep-graph.md/qa-log.md）
   - `learn/` → `vault/07-Learn/`
   - journal 中的版本发现 → 建 `Kernel-Version-Notes.md`
2. **建规则文件**：Evidence-Rules.md、Capture-Protocol.md（从 CLAUDE.md 原则 + Boujoy 捕获器合并）、Active-Context.md（初始：调度器 87 节点待深化）
3. **确认路径**：统一脚本锚点与 vault 的相对路径（当前待定项）
4. **建预设**：`home/.agent-presets/kernel-expert/`（persona 内置宪法要点）
5. **技能就位**：home/skills 已复制 + 已转 python（§8）；正文路径待统一
6. **初始化**：`init_module.py sched "调度器" __schedule pick_next_task ...` 重建骨架（或直接迁移现有数据，二选一）

---

## 13. 路线图 / 待定项

- [ ] **路径统一**：脚本锚点 vs vault 位置（本设计 §8/§12.3）
- [ ] **kernel-expert 预设**：persona 编写（宪法 + 输出风格）
- [ ] **dashboard 接入**：`dashboard/`（Python server + 160KB HTML 图谱）改造成 Boujoy 自定义页（网关接口 + UI 页），或独立进程 + 端口
- [ ] **hooks 替代验证**：确认 capture 流程在技能指令下被稳定触发（对话纪律 vs 强制指令）
- [ ] **skills 入 vault**：评估把技能移到 `vault/.agents/skills/`（随库版本化、自动发现）还是留在 home/skills
- [ ] **git 策略**：vault 纳入 git 跟踪（当前 runtime/ 被 .gitignore）；建议 vault 独立跟踪或调整 .gitignore

---

## 附：为什么这样融合

- **保留内核体系**：证据纪律、状态机、依赖图、版本表是内核学习的核心竞争力，Boujoy 通用 PKM 不具备
- **吸收 Boujoy**：去重流水线、Active-Context 工作记忆、知识搜索、专家/风格调度、媒体支持——补全内核体系的 UI/检索/工作记忆短板
- **去掉 Claude 依赖**：hooks → 技能流程；bash → python；调用方式 → dsh 自然语言/自动加载
- **分层清晰**：数据/规则/操作/能力四层独立，任何一层都可单独演进（比如换 UI、换 MCP、加子系统）
