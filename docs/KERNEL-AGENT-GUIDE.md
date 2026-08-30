# Kernel-Agent-Harness 内核学习助手 — 功能全景与开发指南

> 本文档梳理当前内核学习助手的完整能力（Agent 侧 / 记忆侧 / 可视化侧 / 数据侧），
> 并给出后续功能路线图与开发实践指导。最后更新：2026-08-30。

---

## 1. 系统定位与架构

**是什么**：Boujoy Harness（@deepseek-ai/dsh 0.1.1-rc.2 第三方包装）的内核魔改版 ——
一个带可视化仪表盘、记忆系统、专用技能与本地代码图谱数据库的 **Linux 内核学习 Agent**。

**架构（单向数据流）**：

```
┌─────────────────────────────────────────────────────────────┐
│  Web UI（web/index.html + app.js + app.css，punk 风格）       │
│  · 聊天 / 专家 / 监控 / 新闻 / 知识库 / 内核学习 Dashboard      │
└──────────────┬──────────────────────────────────────────────┘
               │ HTTP (127.0.0.1:8876)
┌──────────────▼──────────────────────────────────────────────┐
│  Gateway（web/boujoy_server.py，Python 标准库）               │
│  · /api/kernel/* 16 个内核端点 + dsh RPC 代理 + 静态文件服务     │
└──────────────┬──────────────────────────────────────────────┘
               │ RPC
┌──────────────▼──────────────────────────────────────────────┐
│  dsh runtime（runtime/DeepSeekHarness/）                      │
│  · kernel-expert 预设（人格+证据纪律）                         │
│  · 14 个内核 skills（Python 版脚本）                           │
│  · kernel-graph MCP（本地 sqlite，420 万调用边）               │
│  · capture-reminder 插件（PostToolUse 等价物）                │
└──────────────┬──────────────────────────────────────────────┘
               │ 读写
┌──────────────▼──────────────────────────────────────────────┐
│  vault/（git 版本化知识库）+ D:\claude配置\kernel-graph\ 数据库 │
│  00-System 记忆 · 03-Knowledge 知识节点 · 07-Learn 深度笔记     │
└─────────────────────────────────────────────────────────────┘
```

- 端口：Web/Gateway `8876`，dsh 引擎 `3280/3281`（通用版实例为 `8766/3180/3181`）
- 无构建步骤：静态文件（html/js/css）每次请求现读；改动网关需重启
- 两个实例并存：通用 `boujoy-harness` + 内核 `kernel-agent-harness`（本系统）

---

## 2. 已实现功能全景

### 2.1 Agent 侧（runtime/DeepSeekHarness/home/）

#### kernel-expert 预设（`.agent-presets/kernel-expert/agent.cordis.yml`）

基于 dsh **标准预设完整复制**（工具/技能/计划/委派组全保留），仅替换 persona：

- 会话开始必读 `00-System/Active-Context.md` 与 `Open-Questions.md`
- **证据纪律**（最高约束）：无证据不编造路径/行号/调用边；无法确认标「待验证」
- 分析走 kernel-graph MCP 取证据 → 写 `07-Learn/{子系统}/` 深度笔记
- 写完笔记必须执行捕获流水线（Capture-Protocol 1-8 步）
- 注意：dsh 预设是**全量替换**，新会话默认 standard 预设，需手动切到 kernel-expert

#### 14 个 Skills（`skills/`，bash 脚本已全部转换为 Python）

| Skill | 触发场景 | 职责 / 输出 |
|---|---|---|
| `add-learning-module` | 「我要开始学 X」「start learning X」 | 新建学习板块：`init_module.py` 原子创建 knowledge/dep-graph/qa-log/_index，更新 Memory-Index + Workspace-Overview |
| `kernel-reading-guide` | 「帮我梳理内核代码」 | 生成阅读路线图 `{key}_read_guide.md`：分类、关键源文件、数据结构主线、阅读顺序、API 检索表（MCP 必须） |
| `kernel-code-analyzer` | 粘贴内核代码片段 | 三维度深度分析：逐行/结构详解、宏观定位、完整调用链 |
| `kernel-concept-mapper` | 被理论/术语卡住 | 概念梳理（硬件术语→代码符号对照，标注「待验证」） |
| `kernel-doc-comprehension-coach` | 「我读懂了吗」 | 对学习文档提问考察理解程度 |
| `kernel-impact-analyzer` | 「改这个安全吗」「影响分析」 | 修改函数/字段影响范围分级报告 |
| `kernel-learning-capture` | 「记录这个」或自动 | 执行 Capture-Protocol：打分→去重→更新节点/依赖图/问答/索引 |
| `kernel-learning-synthesizer` | 「总结这个模块」 | 模块级理解框架：术语表/状态矩阵/路径索引/字段字典 |
| `kernel-progress-report` | 「我学到哪了」 | 结构化进度报告：掌握统计、知识树、开放问题、下一步建议 |
| `kernel-qa-log` | 「记录这个问题」 | 问答归档到 `qa-log.md`（用户提问 + AI 发现均可） |
| `kernel-graph-visualize` | 「画调用图谱」 | 用 MCP 证据在对话里画 ASCII 调用树 |
| `drawio-diagram-generator` | 需要图形化 | 从源码/日志生成 .drawio 图 |
| `obsidian-sync` | 「同步 obsidian」 | 07-Learn 笔记同步到 Obsidian（双向链接） |
| `show-progress` | 「打开面板」 | 打开本 dashboard 网页 |

#### kernel-graph MCP（`D:\claude配置\kernel-graph\mcp_server.py`）

本地 sqlite（stdio），12 个工具：

| 工具 | 用途 |
|---|---|
| `find_definition` | 函数定义位置（文件+行号） |
| `find_callers` / `find_callees` | 直接调用者 / 被调用者 |
| `call_chain_down` / `call_chain_up` | 调用链（可指定深度） |
| `find_struct` | 结构体定义与字段列表 |
| `find_struct_writers` | 写该结构体/字段的代码位置 |
| `search_functions` | 函数名模糊搜索 |
| `call_path_between` | 两函数间最短路径（双向 BFS） |
| `functions_in_file` | 文件内函数清单 |
| `find_indirect_callers` | 间接调用者（函数指针） |
| `get_code_snippet` | 源码片段（文件+行号） |

#### capture-reminder 插件（`profiles/node_modules/@kernel/capture-reminder/`）

dsh 版 PostToolUse hook：监听 `tools/post-execute`，当模型写完 `07-Learn` 笔记后，
通过 `createUserMessage` 注入用户通知，提醒执行捕获流水线。
⚠️ **已装配但尚未实测**（见 §4）。

#### 支撑脚本

- `home/scripts/`：`upsert_node.py`（更新知识节点）、`count_stats.py`、`lookup_status.py`
- skill 内脚本：`init_module.py`、`update_claude_md.py`、`append_dep_edge.py`、`append_qa.py`、
  `append_question.py`、`update_memory.py`、`reclassify.py` 等（bash + python 双版本）

### 2.2 记忆侧（vault/，git 版本化）

#### 目录结构

```
vault/
├── 00-System/          记忆中枢（13 文件）
│   ├── Active-Context.md        当前学习状态（工作记忆，会话必读）
│   ├── Memory-Index.md          全库索引（子系统列表/焦点/知识状态）
│   ├── Open-Questions.md        开放问题（CRITICAL/MEDIUM/LOW）
│   ├── Learning-Journal.md      学习日志（时间线）
│   ├── Kernel-Version-Notes.md  内核版本差异记忆（7.2-rc6）
│   ├── Evidence-Rules.md        证据纪律（内核分析宪法）
│   ├── Capture-Protocol.md      捕获流水线 1-8 步 + 打分细则
│   ├── Hot-Index.md             热知识索引
│   ├── Memory-Queue.md          待处理队列（4-5 分暂存）
│   ├── Workspace-Overview.md    工作区总览
│   ├── Knowledge-Card-Template.md / Cleanup-Candidates.md / Quick-Notes.md
├── 01-Inbox/ 02-Projects/ 04-Content/ 05-Prompts/ 06-Business/ 98-Skills/ 99-Logs/
├── 03-Knowledge/{子系统}/       知识节点（每子系统 3 文件）
│   ├── knowledge.md     节点表：名称|类型|状态|置信度|笔记|内部文档|更新日期
│   ├── dep-graph.md     依赖图（文本调用树，仅确认边）
│   └── qa-log.md        问答日志（按节点分组的 Q-### 条目）
└── 07-Learn/{子系统}/           深度笔记（_index.md 入口 + 阅读指南 + 函数详解）
```

#### 知识节点状态机

`unknown → exploring → mastered`（+ 特殊态 `questioned`）；置信度 0-100，无证据 ≤50。

#### 捕获流水线（Capture-Protocol 1-8 步，每个分析完成后必走）

```
分析完成（含 MCP 证据）
 ├─ 1. 打分    0-3 不存 | 4-5 Memory-Queue | 6-8 知识卡 | 9-10 卡+Hot-Index
 ├─ 2. 查重    Memory-Index + 网关 /api/knowledge/capture（相似度≥0.62 → 403 合并）
 ├─ 3. 节点    upsert_node.py {sub} {name} {type} {status} {conf} {note} {evidence}
 ├─ 4. 依赖图  append_dep_edge.py（仅确认边）
 ├─ 5. 问答    append_qa.py（用户提问|AI 发现）
 ├─ 6. 未解问题 append_question.py
 ├─ 7. 索引    update_memory.py
 └─ 8. 日志    Learning-Journal.md + Active-Context.md
```

### 2.3 可视化侧（Dashboard「内核学习」页，6 大块）

| 板块 | 能力 |
|---|---|
| **总览** | 子系统/节点/边/开放问题/热索引统计卡，一键刷新 |
| **调用图谱** | 8 模式：径向图谱 / 深链追踪 / 最短路径 / 结构体 / 热函数 / 同文件 / 间接调用 / 双函数对比；深度分层着色（acid/blue/cyan/pink）；正则过滤 + 隐藏低度；点击节点居中；展开/合并；历史前进后退；导出到 vault |
| **节点列表** | 全节点表 + 状态过滤（全部/mastered/exploring/unknown/questioned） |
| **问答日志** | 全量 + 全部/待解决/已解决过滤 |
| **学习文档** | 左侧目录树（子系统折叠、子目录层级、mtime 排序）+ 右侧阅读区；**懒加载正文**（列表只带元数据）；**全文搜索**（服务端、命中行高亮）；mermaid 流程图渲染 + 点击全屏；笔记内相对 `.md` 链接点击跳转 |
| **随时记** | 全局浮动 ✎ 按钮（所有页面可见）→ 弹框速记，Enter 保存，写 `00-System/Quick-Notes.md`（QN-### 编号） |

#### Gateway 内核端点（web/boujoy_server.py，共 16 个）

`/api/kernel/stats` · `graph` · `chain` · `path` · `node` · `structs` · `hot` ·
`filegraph` · `indirect` · `nodes` · `qa` · `docs`（列表/单篇）· `docs/search` ·
`quicknotes`（GET+POST CRUD）· `export`（POST 导出图谱到 07-Learn/kernel-graph/）

### 2.4 数据侧（kernel-graph 数据库）

- 来源：`E:\work\kernel\linux` 源码树解析（Linux **7.2-rc6**）
- 规模：functions 71.8 万 · calls 420.9 万（caller/callee/file/line）· structs 72.3 万 · field_assignments 42.6 万（966MB sqlite）
- 已知数据缺口：部分间接调用/宏展开边缺失（如 `do_fork` 无出边），路径查询空时需换同文件启发或手动确认

### 2.5 演进轨迹（git 21 commits）

初始 fork → 记忆架构融合 → 会话修复 → 数据路径对齐 → Dashboard V1-V3（图谱/深链/工具箱/历史/导出）
→ 节点/随时记/问答 → 标签页导航 + 浮动随时记 → 学习文档（mermaid/懒加载/搜索）。详见 `git log`。

---

## 3. 使用手册

### 3.1 日常学习闭环

```
① 开新会话 → 手动选 kernel-expert 预设
② 学新领域：说「我要开始学 mm」→ add-learning-module 自动搭目录 + 更新索引
③ 梳理路线：说「帮我梳理 mm 的代码」→ kernel-reading-guide 生成阅读指南
④ 深度分析：粘贴代码/指定函数 → kernel-code-analyzer（MCP 取证）
⑤ 自动沉淀：capture 流水线写 knowledge/dep-graph/qa-log + 记忆索引
⑥ 随时补充：dashboard 随时记速记；问答日志归档疑问
⑦ 复盘进度：说「我学到哪了」→ kernel-progress-report；或看 dashboard
```

### 3.2 启动 / 维护

- 启动：`启动 Boujoy Harness.cmd`（内核实例）；端口 8876
- 网关改动生效：写 `restart.request` 到 `.state/Boujoy/BoujoyHarness/Windows/{实例}/`（约 15-20s 恢复）
- 静态文件（web/）改动：刷新页面即生效，无需重启
- 提交知识库：vault/ 由 git 管理，`git add vault/ && git commit`

---

## 4. 当前已知缺口 / Tradeoff

| 项 | 状态 | 影响 |
|---|---|---|
| capture-reminder 插件 | ⚠️ 已装配未实测 | 自动化捕获最后一环未验证；建议先手动确认分析后是否注入提醒 |
| 预设手动切换 | 每次会话需选 kernel-expert | 忘记选则 agent 不读记忆、不强制证据 |
| runtime/ 不在 git | gitignored | 换机/重装需重新铺 skills/preset/插件/配置 |
| 内核版本固定 | DB 为 7.2-rc6 | 内核升级需重新解析数据库 |
| 学习文档 mermaid | 已有渲染能力，暂无真实笔记含图 | 需要 agent 在笔记中写 ` ```mermaid ` 块验证 |
| 内容覆盖 | 仅 sched 有实质产物（example 为模板） | 其他子系统按 3.1 流程生长 |
| dsh 无 hooks | 用插件 + 注入通知模拟 PostToolUse | 依赖模型自觉执行 capture（有 persona 约束兜底） |

---

## 5. 后续功能建议（路线图）

### P0 — 近期该做（就绪度提升）

1. **实测 capture-reminder**：让 agent 分析 `__schedule`，验证分析后自动触发捕获提醒；
   若失败，排查 `tools/post-execute` 事件负载与注入通知格式。
2. **默认预设 = kernel-expert**：研究 dsh 是否有"会话默认预设"配置（如配置文件中指定），
   省去每次手动选择；否则在 UI 加"记住上次预设"。
3. **mermaid 真实笔记**：让 agent 在下一份深度笔记中画一张流程图（如 `__schedule` 主路径），
   端到端验证渲染/全屏。
4. **图谱 ↔ 文档联动**：从 07-Learn 笔记的调用链代码块提取边，在「调用图谱」里叠加显示
   "笔记中记录的调用链"（原版 dashboard 有 `parse_call_chains_from_learn` 可参考）。

### P1 — 生长期（内容量上来后）

5. **搜索索引**：文档/节点到数百时，为 `docs/search` 与知识库搜索加内存索引或 sqlite FTS。
6. **一键备份/快照**：dashboard 加「提交知识库」按钮（调 git commit），或导出 zip。
7. **学习日志 tab**：把 Learning-Journal.md 渲染成时间线（日期/做了什么/产出），
   与问答日志并列。
8. **随时记类型化**：支持 问题/笔记/待整理 三种类型（原版 dashboard 格式），
   类型进入 Quick-Notes.md 行内标记，捕获时按类型分流。
9. **会话上下文延续**：新会话自动把 Active-Context/Open-Questions/最近 5 条分析
   注入上下文（persona 已要求读，可再加强制性：preset 里把读取列为 Step 0）。

### P2 — 进阶

10. **多版本内核对比**：kernel-graph DB 支持多版本（如 6.x/7.x），`find_definition` 返回
    版本差异，Kernel-Version-Notes 自动生成差异报告。
11. **影响分析可视化**：kernel-impact-analyzer 的分级报告渲染成影响波及图（调用者树高亮）。
12. **学习路径推荐**：基于 dep-graph 拓扑 + 节点状态，推荐"下一个该学的函数"。
13. **移动端访问**：Boujoy 已有手机配对（access code），内核 dashboard 响应式已部分适配。
14. **双实例合并**：通用实例与内核实例的知识/记录互导（records 与知识卡）。

---

## 6. 开发指南

### 6.1 代码结构

```
kernel-agent-harness/
├── web/                        前端 + 网关
│   ├── index.html              UI 结构（kernel-dash 区、随时记弹框、mermaid dialog）
│   ├── app.js                  全部前端逻辑（含 markdown() 渲染器、图谱 d3 渲染）
│   ├── app.css                 punk 风格样式
│   ├── boujoy_server.py        Python 网关（RPC 代理 + /api/kernel/* 端点）
│   └── vendor/                 本地化依赖（d3.min.js、mermaid.min.js）
├── windows/Start-Boujoy.ps1    启动脚本（端口/环境）
├── runtime/DeepSeekHarness/    实际 dsh 运行时（gitignored）
│   └── home/                   配置：skills/、.agent-presets/、profiles/、scripts/
├── vault/                      知识库（git 版本化）
└── docs/                       设计文档（MEMORY-DESIGN.md、本指南）
```

### 6.2 改动流程

1. **静态文件**（index.html/app.js/app.css/vendor）：改完刷新页面即可，无需重启
2. **网关**（boujoy_server.py）：`python -c "import ast; ast.parse(open('web/boujoy_server.py',encoding='utf-8').read())"` 查语法 → 写 `restart.request` 重启 → 用 Invoke-WebRequest 自测端点
3. **前端**：`node --check web/app.js`；改 HTML 结构后检查 div 配平
4. **runtime**：改动 skills/preset/插件后重启引擎（restart.request 同路径）
5. **自测**：每个端点 curl/Invoke-WebRequest 一次（含错误分支：越界路径、空查询、非法参数）

### 6.3 开发纪律

- **预设是全量替换**：改 kernel-expert 预设时必须以标准预设为基底复制，否则丢工具/技能
- **记忆格式即协议**：knowledge.md 表头、Quick-Notes.md 行格式、qa-log.md 字段是
  agent 与 dashboard 共享的协议，改动需两侧同步（gateway 解析 + skill 脚本写入）
- **沙箱注意**：dsh 沙箱下 npm/spawn 受限（EPERM）、Invoke-WebRequest TLS 异常（用 node fetch）；
  runtime 安装依赖直接复制运行实例的 node_modules 更稳
- **git 纪律**：runtime/、.state/、.npm-cache/ 不入库；vault/ 入库（它就是知识库本体）
- **新增端点模式**：`_kernel_xxx()` 方法 + do_GET 路由 + app.js `jsonFetch` 调用 + 自测，
  保持三层一致（参考现有 16 个端点的写法）

### 6.4 测试清单（改完一轮功能后的回归项）

- [ ] `/api/kernel/stats|graph|chain|path|node|structs|hot|filegraph|indirect|nodes|qa|docs|docs/search|quicknotes` 均返回 200
- [ ] 路径越界防护：`docs?path=../xx` 返回「路径越界/非法路径」
- [ ] 新会话 RPC 前 ensureSession 正常（预设/skills 可列出）
- [ ] dashboard 六个板块各自加载、过滤、刷新正常
- [ ] 随时记增/勾选/删闭环；Quick-Notes.md 落盘格式正确
- [ ] 学习文档：懒加载、搜索命中、相对链接跳转、mermaid 渲染
- [ ] 图谱 8 模式查询 + 导出到 vault

---

## 附：一句话总结

> 一套「有证据纪律的 Agent + 版本化记忆 + 本地调用图数据库 + 可生长 Dashboard」的内核学习系统。
> 目前已具备**持续使用**条件，剩余工作集中在**自动化最后一环的实测**与**内容生长**。
