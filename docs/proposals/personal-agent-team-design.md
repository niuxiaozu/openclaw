# OpenClaw 个人全能 Agent 团队设计方案 (v3)

> 初步设想阶段 — 2026-03-05 (v3 基于源码验证修订)
>
> 目标：基于 OpenClaw 构建一支为个人 PC 全面服务的 AI Agent 团队。
> 本版只部署三人核心团队 **Nexus / Sage / Forge**，附带一键部署脚本。

---

## 一、源码验证后的关键事实

在正式设计前，先摆几个从源码和文档中确认的事实，避免"脑补"出 OpenClaw 不支持的功能。

### 1.1 联网工具的真实情况

OpenClaw 内置两个联网工具：

| 工具 | 文件 | 需要 API Key？ | 能抓动态页面？ |
|------|------|:-------------:|:------------:|
| `web_search` | `src/agents/tools/web-search.ts` | **是** — 需要 Brave/Perplexity/Gemini/Grok/Kimi 其中之一的 API Key | N/A（搜索 API） |
| `web_fetch` | `src/agents/tools/web-fetch.ts` | 否（可选 Firecrawl 回退） | **否** — 纯 HTTP GET，不执行 JS |

**`web_search` 需要 API Key**，但选项很多：
- **Gemini**（推荐）：用 Google AI Studio 免费 API Key，背后是 Google Search，效果好
- Brave Search：需付费计划
- Perplexity：付费 API

**`web_fetch` 不能抓动态页面**，但有两个升级路径：
- 配置 **Firecrawl**（`FIRECRAWL_API_KEY`）做回退，Firecrawl 自带 JS 渲染
- 使用内置 **Browser 工具**（`src/agents/tools/browser-tool.ts`）做完整浏览器自动化

**内置 Browser 工具**（不是第三方 Skill）：
- 跑一个独立的 Chrome/Brave/Edge 实例，与你的日常浏览器隔离
- 支持打开标签页、点击、输入、截图、导出 PDF
- 配置在 `browser` 字段下，命令行 `openclaw browser start`

**结论**：所有 Agent 都天然可以用 `web_search` + `web_fetch`（内置工具，不是 Skill），
只要配了搜索 API Key。Browser 工具也是内置的，不需要从 ClawHub 安装。
之前方案中提到的 `tavily-search`、`browser-use` 等是 ClawHub 第三方 Skill，
v3 不依赖它们，全部使用内置工具。

### 1.2 心跳机制的真实工作方式

从 `src/infra/heartbeat-runner.ts` 和 `src/auto-reply/heartbeat.ts` 确认：

**心跳是什么**：定时触发的自动对话。Gateway 按配置的间隔（如 30 分钟）向指定 Agent 发送一条合成的用户消息。

**工作流程**：
1. 定时器到期 → 检查 HEARTBEAT.md 是否存在且非空
2. 如果存在 → 发送内置 prompt（"Read HEARTBEAT.md if it exists..."）作为用户消息
3. Agent 正常执行一轮对话（读取 HEARTBEAT.md 内容，执行检查清单）
4. 如果回复是 `HEARTBEAT_OK`（无事发生）→ 丢弃回复，不打扰用户
5. 如果有实质内容 → 按 `target` 配置投递（发消息给用户、发到某个频道等）

**关键点**：
- HEARTBEAT.md **不是 prompt**，是工作空间上下文文件。内置 prompt 让模型去读它。
- 心跳复用 Agent 的主会话，不创建新会话。
- 心跳完全自主运行，不需要用户发消息触发。
- **没有"仅心跳"模式** — 配了心跳的 Agent 仍然会响应用户消息。

### 1.3 关于 Echo（后台守卫）的可行性

**事实**：OpenClaw 没有内置的"仅心跳、不响应用户消息"的 Agent 模式。

要实现 Echo 这样的纯后台 Agent，需要确保没有消息路由到它：
- 不在 `bindings` 中给 Echo 绑定任何通信渠道
- Echo 只通过心跳运行 + 被其他 Agent 通过 `sessions_spawn` 调用

这种模式**技术上可行**（不绑定渠道就不会收到用户消息），
但在 v3 中不部署 Echo — 先跑通三人团队再说。

### 1.4 中心化 vs 去中心化

**源码事实**：
- `subagents.allowAgents` 控制哪些 Agent 可以被 spawn（默认为空 = 不能 spawn 任何人）
- `maxSpawnDepth` 默认为 1，意味着被 spawn 的 Agent 不能再 spawn 别人
- 设为 2 则允许一层嵌套
- `agentToAgent.enabled` + `allow` 控制 `sessions_send` 直接通信

**分析**：

| 方案 | 优点 | 缺点 |
|------|------|------|
| **纯中心化**（只有 Nexus 能调度） | 流程清晰、不会混乱、token 可控 | 所有协作都要绕回 Nexus，低效 |
| **纯去中心化**（人人可调度人人） | 灵活、Agent 间可直接协作 | 容易循环、token 失控、职责混乱 |
| **有限去中心化**（推荐） | 兼顾灵活和可控 | 需要仔细配置 allowAgents |

**v3 采用有限去中心化**：
- Nexus 可以调度 Sage 和 Forge
- Forge 可以调度 Sage（遇到架构问题直接问）
- Sage 不调度任何人（思考者不需要执行力）
- `maxSpawnDepth: 2` — 允许 Nexus → Forge → Sage 的链式调用

---

## 二、v3 三人团队架构

```
                      ┌─────────────┐
                      │  你（用户）  │
                      └──────┬──────┘
                             │ 唯一沟通入口
                      ┌──────▼──────┐
                      │   Nexus     │ Claude Sonnet 4.5
                      │ 管家+日常   │ 闲聊/简单问题自己答
                      │ 可调度 ↓    │ 复杂任务路由下去
                      └──┬──────┬───┘
                         │      │
               ┌─────────▼┐  ┌─▼─────────┐
               │   Sage   │  │   Forge   │
               │  智者    │  │  锻造     │
               │  Opus    │  │  Sonnet   │
               │  深度思考│  │  全栈工程 │
               └──────────┘  └─────┬─────┘
                                   │ 遇到架构问题可直接问
                             ┌─────▼─────┐
                             │   Sage    │
                             └───────────┘
```

### Agent 定义

| Agent | 模型 | 定位 | 调度权限 |
|-------|------|------|---------|
| **Nexus** | Claude Sonnet 4.5 | 用户入口。闲聊自己答，复杂任务分发。 | 可 spawn Sage、Forge |
| **Sage** | Claude Opus 4.6 | 深度思考。方案设计、技术调研、复杂分析。 | 不 spawn 任何人 |
| **Forge** | Claude Sonnet 4.5 | 全栈工程。写代码、造工具、改配置。 | 可 spawn Sage |

**所有 Agent 都能联网**：`web_search` 和 `web_fetch` 是内置工具（在 `tools` 配置中通过 profile 或 allow 列表启用），
配了搜索 API Key 后全员可用。不需要通过某个特定 Agent 中转。

---

## 三、工作空间文件完整内容

### 3.1 共享文件：USER.md

所有 Agent 通过符号链接共享同一份。初始内容如下，使用中由 Agent 自动积累补充。

```markdown
# 用户信息

## 基本信息
- 职业：程序员
- 语言偏好：中文
- 技术栈：（使用中积累）

## 偏好
- 沟通风格：直接，不废话
- 代码风格：（使用中积累）

## 硬件环境
- GPU: NVIDIA RTX 4070 (12GB VRAM)
- 操作系统：（启动后自动检测补充）

## 注意事项
（使用中积累）
```

### 3.2 Nexus 工作空间文件

**IDENTITY.md**
```markdown
name: Nexus
emoji: 🧭
```

**SOUL.md**
```markdown
# Nexus

你是用户唯一的 AI 助手入口。

## 性格
- 高效直接，不啰嗦
- 聊天时自然随和
- 有判断力：什么事自己干、什么事叫人
- 说中文

## 核心工作方式
简单的事自己干（闲聊、问答、翻译、搜索、格式化）。
需要深度思考的派 Sage，需要写代码造东西的派 Forge。
复合任务拆成步骤分别派发。
结果验收后用简洁的语言汇报用户。
```

**AGENTS.md**
```markdown
# 团队与工作规范

## 可用 Agent
| ID | 擅长 | 何时调用 |
|----|------|----------|
| sage | 深度分析、方案设计、复杂推理 | 需要长时间思考的任务 |
| forge | 写代码、造工具、工程实现 | 需要产出代码/文件的任务 |

## 自己处理的（不派发）
- 闲聊、问候
- 简单问答、翻译、解释概念
- 搜索+简短回答（用 web_search）
- 文本格式化、计算

## 派发规则
- 用 sessions_spawn 派发，任务描述包含完整上下文
- 复合任务分步骤，验收一步再派下一步
- 汇报时提炼关键信息
- 超大型开发任务：先让 Sage 出方案，再让 Forge 实现
```

**HEARTBEAT.md**
```markdown
# 心跳检查

1. 有未完成的子任务？→ 检查进度
2. 有超时的子任务（>10min）？→ 告知用户
3. 无事 → HEARTBEAT_OK
```

**TOOLS.md**
```markdown
# 工具笔记

## web_search
内置搜索工具。用户问"帮我查一下 XX"时直接用。

## web_fetch
抓取网页内容。注意：不能执行 JS，动态页面可能抓不到。
如果抓取失败，告知用户并建议使用浏览器工具。

## browser（如已启用）
内置浏览器自动化。可以打开网页、点击、输入、截图。
用于需要登录或动态页面的操作。

## sessions_spawn
派发任务给其他 Agent：
  sessions_spawn --agentId sage --task "分析..."
  sessions_spawn --agentId forge --task "实现..."

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
```

### 3.3 Sage 工作空间文件

**IDENTITY.md**
```markdown
name: Sage
emoji: 🦉
```

**SOUL.md**
```markdown
# Sage

你是团队里思考最深的成员。

## 性格
- 严谨、有条理
- 给方案时列出优劣权衡
- 不确定时直说
- 说中文

## 工作方式
- 先理清问题本质再展开分析
- 方案附推理过程和置信度
- 不需要深度分析的问题快速回答，不过度展开

## 产出格式
- 方案设计：问题分析 → 可选方案 → 推荐+理由+风险
- 技术调研：背景 → 选项对比 → 结论
- 问题诊断：现象 → 假设 → 验证方法 → 最可能原因
```

**AGENTS.md**
```markdown
# 工作规范

你是 Sage，被 Nexus 或 Forge 调用来做深度分析。

## 规则
1. 专注思考，不写代码、不操作界面
2. 需要搜索信息用 web_search / web_fetch
3. 完成后清晰总结结论
4. 被 Forge 直接调用时，聚焦回答它的具体问题
```

**HEARTBEAT.md**
```markdown
# 心跳
无需主动巡检。HEARTBEAT_OK
```

**TOOLS.md**
```markdown
# 工具笔记

## web_search
调研时查询互联网信息。

## web_fetch
抓取特定网页内容。不能执行 JS。

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
调研结论存入 research/ 目录。
```

### 3.4 Forge 工作空间文件

**IDENTITY.md**
```markdown
name: Forge
emoji: 🔨
```

**SOUL.md**
```markdown
# Forge

你是团队的全栈工程师。

## 性格
- 实干高效，代码质量意识强
- 先理解需求再动手
- 架构不确定时主动提出（可以直接问 Sage）
- 说中文

## 工作方式
- 小任务直接写
- 大任务先列计划分步实现
- 写完做基本自测
- 代码能直接跑，不写伪代码

## 技术栈
- 遵循 USER.md 中记录的偏好
- 无偏好时：TypeScript > Python > Go
```

**AGENTS.md**
```markdown
# 工作规范

你是 Forge，被 Nexus 调用来做工程实现。

## 规则
1. 需求不明确时列出假设供确认
2. 架构级决策不确定时，spawn Sage 帮忙评估
3. 代码确保能运行
4. 修改现有项目先读懂再动手

## 可请求的 Agent
- sage — 架构决策、方案评估
  sessions_spawn --agentId sage --task "评估方案..."

## 搜索能力
你可以直接用 web_search 和 web_fetch 查文档和搜索用法。
```

**HEARTBEAT.md**
```markdown
# 心跳
无需主动巡检。HEARTBEAT_OK
```

**TOOLS.md**
```markdown
# 工具笔记

## web_search / web_fetch
写代码遇到不确定的 API 用法时直接搜索。

## exec
执行 shell 命令。用于运行代码、安装依赖、测试。

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
项目信息存入 projects/ 目录。
```

---

## 四、完整 openclaw.json 配置

```json5
{
  agents: {
    defaults: {
      compaction: { enabled: true, threshold: 50000 },
      subagents: {
        maxConcurrent: 3,
        maxSpawnDepth: 2,
        runTimeoutSeconds: 600
      },
      bootstrapMaxChars: 20000,
      contextPruning: true
    },
    list: [
      {
        id: "nexus",
        default: true,
        model: "anthropic/claude-sonnet-4-5",
        workspace: "~/.openclaw/workspace-nexus",
        identity: { name: "Nexus", emoji: "🧭" },
        subagents: {
          allowAgents: ["sage", "forge"]
        },
        heartbeat: {
          every: "30m",
          activeHours: { start: "08:00", end: "01:00" }
        }
      },
      {
        id: "sage",
        model: "anthropic/claude-opus-4-6",
        workspace: "~/.openclaw/workspace-sage",
        identity: { name: "Sage", emoji: "🦉" },
        params: { temperature: 0.3 }
      },
      {
        id: "forge",
        model: "anthropic/claude-sonnet-4-5",
        workspace: "~/.openclaw/workspace-forge",
        identity: { name: "Forge", emoji: "🔨" },
        subagents: {
          allowAgents: ["sage"]
        },
        tools: {
          profile: "coding",
          exec: { enabled: true },
          fs: { enabled: true }
        }
      }
    ]
  },

  tools: {
    agentToAgent: {
      enabled: true,
      allow: ["nexus", "sage", "forge"]
    },
    sessions: {
      visibility: "all"
    },
    web: {
      search: {
        enabled: true,
        // 搜索提供商（推荐 Gemini — 免费，Google Search 质量）
        // API Key 通过环境变量设置，见部署脚本
        provider: "gemini"
      },
      fetch: {
        enabled: true
      }
    }
  },

  // 浏览器工具（可选，需要时启用）
  browser: {
    enabled: true,
    defaultProfile: "openclaw",
    headless: false
  }

  // bindings 在部署脚本中根据用户选择的渠道配置
}
```

---

## 五、中心化 vs 去中心化的选择

v3 采用**有限去中心化**，理由如下：

**纯中心化的问题**：
当 Forge 写代码遇到架构问题，流程是 Forge → 汇报 Nexus → Nexus 问 Sage → Sage 回复 Nexus → Nexus 转给 Forge。
四次通信、三个 Agent 消耗 token、Nexus 做了没有价值的中转。

**有限去中心化**：
Forge 遇到架构问题 → 直接 spawn Sage。两次通信、两个 Agent、无冗余中转。

**防失控措施**：
- `maxSpawnDepth: 2` 限制最大调用深度
- Sage 不能 spawn 任何人（没有 `subagents.allowAgents`）
- `maxPingPongTurns` 限制 sessions_send 来回次数
- 只有 Nexus 面向用户，Sage/Forge 的回复最终通过 Nexus 呈现

---

## 六、一键部署脚本

见同目录下的 `setup-agent-team.sh`，执行方式：

```bash
bash ~/.openclaw/setup-agent-team.sh
```

脚本会：
1. 创建三个 Agent（nexus / sage / forge）
2. 创建所有工作空间目录
3. 写入所有 SOUL.md / AGENTS.md / IDENTITY.md / HEARTBEAT.md / TOOLS.md / USER.md
4. USER.md 通过符号链接共享
5. 创建共享知识库目录
6. 合并配置到 openclaw.json
7. 提示你设置 API Key 和通信渠道

---

## 七、后续扩展路线

### Phase 2 — 加入 Lens（界面操作）

当需要浏览器自动化和桌面 GUI 控制时：
- 加入 Lens Agent，配置 Browser 工具
- Forge 和 Sage 可以 spawn Lens
- 从 ClawHub 安装桌面控制 Skill（如 `computer-use`、`midscene`）

### Phase 3 — 加入 Echo（后台守卫）

当团队稳定后：
- 加入 Echo Agent，不绑定任何通信渠道
- 配置心跳做记忆整理、文件清理、系统监控
- 使用便宜模型（DeepSeek Chat）

### Phase 4 — 自进化

- Agent 通过 self-improvement 优化自己的 SOUL.md
- 积累 USER.md 和 MEMORY.md
- 开发自定义 Skill

---

*v3 — 2026-03-05*
*核心变化：纠正联网工具认知；基于源码验证心跳机制；砍掉 Echo/Lens 先做三人团队；有限去中心化；附一键部署脚本。*
