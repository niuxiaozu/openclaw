#!/usr/bin/env bash
#
# OpenClaw 三人 Agent 团队一键部署脚本
# 部署 Nexus (管家) + Sage (智者) + Forge (锻造)
#
# 使用方式:
#   bash setup-agent-team.sh
#
# 前提条件:
#   1. 已安装 openclaw 并完成 onboarding (openclaw onboard)
#   2. 已设置 ANTHROPIC_API_KEY 环境变量
#   3. 推荐: 设置 GEMINI_API_KEY 环境变量 (用于 web_search, 免费)
#
set -euo pipefail

# ─────────────── 路径常量 ───────────────
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
WS_NEXUS="$OPENCLAW_DIR/workspace-nexus"
WS_SAGE="$OPENCLAW_DIR/workspace-sage"
WS_FORGE="$OPENCLAW_DIR/workspace-forge"
SHARED_KNOWLEDGE="$OPENCLAW_DIR/shared-knowledge"

# ─────────────── 颜色 ───────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─────────────── 前置检查 ───────────────
info "检查前置条件..."

if ! command -v openclaw &>/dev/null; then
  fail "未找到 openclaw 命令。请先安装: npm i -g openclaw"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  fail "未找到 $CONFIG_FILE。请先运行: openclaw onboard"
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  warn "未检测到 ANTHROPIC_API_KEY 环境变量。"
  warn "Nexus/Sage/Forge 需要 Anthropic API Key 才能工作。"
  warn "请在 ~/.openclaw/.env 或 shell profile 中设置: export ANTHROPIC_API_KEY=sk-ant-..."
  echo ""
fi

if [ -z "${GEMINI_API_KEY:-}" ]; then
  warn "未检测到 GEMINI_API_KEY 环境变量。"
  warn "web_search 需要搜索 API Key。推荐 Gemini (免费): https://aistudio.google.com/apikey"
  warn "设置方式: export GEMINI_API_KEY=AIza..."
  echo ""
fi

echo ""
info "===== 开始部署三人 Agent 团队 ====="
echo ""

# ─────────────── 第一步：创建工作空间目录 ───────────────
info "创建工作空间目录..."

mkdir -p "$WS_NEXUS/memory"
mkdir -p "$WS_SAGE/memory"
mkdir -p "$WS_FORGE/memory"
mkdir -p "$SHARED_KNOWLEDGE"/{projects,research,decisions}

ok "工作空间目录创建完成"

# ─────────────── 第二步：写入 Nexus 工作空间文件 ───────────────
info "写入 Nexus 工作空间文件..."

cat > "$WS_NEXUS/IDENTITY.md" << 'NEXUS_IDENTITY'
name: Nexus
emoji: 🧭
NEXUS_IDENTITY

cat > "$WS_NEXUS/SOUL.md" << 'NEXUS_SOUL'
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
NEXUS_SOUL

cat > "$WS_NEXUS/AGENTS.md" << 'NEXUS_AGENTS'
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
NEXUS_AGENTS

cat > "$WS_NEXUS/HEARTBEAT.md" << 'NEXUS_HEARTBEAT'
# 心跳检查

1. 有未完成的子任务？→ 检查进度
2. 有超时的子任务（>10min）？→ 告知用户
3. 无事 → HEARTBEAT_OK
NEXUS_HEARTBEAT

cat > "$WS_NEXUS/TOOLS.md" << 'NEXUS_TOOLS'
# 工具笔记

## web_search
内置搜索工具。用户问"帮我查一下 XX"时直接用。

## web_fetch
抓取网页内容。注意：不能执行 JS，动态页面可能抓不到。
如果抓取失败，考虑使用浏览器工具（如已启用）。

## sessions_spawn
派发任务给其他 Agent：
  sessions_spawn --agentId sage --task "分析..."
  sessions_spawn --agentId forge --task "实现..."

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
NEXUS_TOOLS

ok "Nexus 工作空间文件写入完成"

# ─────────────── 第三步：写入 Sage 工作空间文件 ───────────────
info "写入 Sage 工作空间文件..."

cat > "$WS_SAGE/IDENTITY.md" << 'SAGE_IDENTITY'
name: Sage
emoji: 🦉
SAGE_IDENTITY

cat > "$WS_SAGE/SOUL.md" << 'SAGE_SOUL'
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
SAGE_SOUL

cat > "$WS_SAGE/AGENTS.md" << 'SAGE_AGENTS'
# 工作规范

你是 Sage，被 Nexus 或 Forge 调用来做深度分析。

## 规则
1. 专注思考，不写代码、不操作界面
2. 需要搜索信息用 web_search / web_fetch
3. 完成后清晰总结结论
4. 被 Forge 直接调用时，聚焦回答它的具体问题
SAGE_AGENTS

cat > "$WS_SAGE/HEARTBEAT.md" << 'SAGE_HEARTBEAT'
# 心跳
无需主动巡检。HEARTBEAT_OK
SAGE_HEARTBEAT

cat > "$WS_SAGE/TOOLS.md" << 'SAGE_TOOLS'
# 工具笔记

## web_search
调研时查询互联网信息。

## web_fetch
抓取特定网页内容。不能执行 JS。

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
调研结论存入 research/ 目录。
SAGE_TOOLS

ok "Sage 工作空间文件写入完成"

# ─────────────── 第四步：写入 Forge 工作空间文件 ───────────────
info "写入 Forge 工作空间文件..."

cat > "$WS_FORGE/IDENTITY.md" << 'FORGE_IDENTITY'
name: Forge
emoji: 🔨
FORGE_IDENTITY

cat > "$WS_FORGE/SOUL.md" << 'FORGE_SOUL'
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
FORGE_SOUL

cat > "$WS_FORGE/AGENTS.md" << 'FORGE_AGENTS'
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
FORGE_AGENTS

cat > "$WS_FORGE/HEARTBEAT.md" << 'FORGE_HEARTBEAT'
# 心跳
无需主动巡检。HEARTBEAT_OK
FORGE_HEARTBEAT

cat > "$WS_FORGE/TOOLS.md" << 'FORGE_TOOLS'
# 工具笔记

## web_search / web_fetch
写代码遇到不确定的 API 用法时直接搜索。

## exec
执行 shell 命令。用于运行代码、安装依赖、测试。

## 共享知识库
路径: ~/.openclaw/shared-knowledge/
项目信息存入 projects/ 目录。
FORGE_TOOLS

ok "Forge 工作空间文件写入完成"

# ─────────────── 第五步：创建共享 USER.md ───────────────
info "创建共享 USER.md..."

cat > "$WS_NEXUS/USER.md" << 'SHARED_USER'
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
SHARED_USER

# 符号链接 USER.md 到所有工作空间
for ws in "$WS_SAGE" "$WS_FORGE"; do
  if [ -L "$ws/USER.md" ]; then
    rm "$ws/USER.md"
  elif [ -f "$ws/USER.md" ]; then
    mv "$ws/USER.md" "$ws/USER.md.bak"
    warn "已备份已有的 $ws/USER.md → USER.md.bak"
  fi
  ln -s "$WS_NEXUS/USER.md" "$ws/USER.md"
done

ok "共享 USER.md 创建完成 (符号链接)"

# ─────────────── 第六步：注册 Agent 到 openclaw.json ───────────────
info "注册 Agent 到配置文件..."

# 使用 openclaw agents add（非交互模式）注册 Agent
# 如果已存在则跳过
register_agent() {
  local agent_id="$1"
  local workspace="$2"
  local model="$3"

  if openclaw agents list --json 2>/dev/null | grep -q "\"id\":\"$agent_id\"" 2>/dev/null ||
     openclaw agents list --json 2>/dev/null | grep -q "\"id\": \"$agent_id\"" 2>/dev/null; then
    warn "Agent '$agent_id' 已存在，跳过注册"
    return 0
  fi

  openclaw agents add "$agent_id" \
    --workspace "$workspace" \
    --model "$model" \
    --non-interactive 2>/dev/null || {
      warn "openclaw agents add $agent_id 返回非零，可能已存在"
    }
}

register_agent "nexus" "$WS_NEXUS" "anthropic/claude-sonnet-4-5"
register_agent "sage"  "$WS_SAGE"  "anthropic/claude-opus-4-6"
register_agent "forge" "$WS_FORGE" "anthropic/claude-sonnet-4-5"

ok "Agent 注册完成"

# ─────────────── 第七步：写入完整团队配置 ───────────────
info "写入团队协作配置..."

# 使用 openclaw config set 合并关键配置项
# 注意: openclaw agents add 只写了基本的 id/workspace/model，
# 团队协作的高级配置（subagents、heartbeat、tools、agentToAgent 等）
# 需要通过 config set 或直接编辑 openclaw.json 添加。

# 用 node 来精确合并 JSON 配置，避免 jq 依赖和 JSON5 兼容性问题
node -e '
const fs = require("fs");
const path = require("path");

const configPath = process.argv[1];
let raw = fs.readFileSync(configPath, "utf8");

// 简单的 JSON5 → JSON 清理: 去除注释和尾逗号
raw = raw.replace(/\/\/.*$/gm, "");
raw = raw.replace(/\/\*[\s\S]*?\*\//g, "");
raw = raw.replace(/,(\s*[}\]])/g, "$1");

let config;
try {
  config = JSON.parse(raw);
} catch (e) {
  console.error("无法解析 openclaw.json:", e.message);
  console.error("将创建备份并继续...");
  fs.copyFileSync(configPath, configPath + ".bak");
  config = {};
}

// 备份
fs.copyFileSync(configPath, configPath + ".pre-team-setup.bak");

// 确保 agents.list 存在
if (!config.agents) config.agents = {};
if (!config.agents.list) config.agents.list = [];

// 更新或添加 agent 配置
const agentConfigs = {
  nexus: {
    default: true,
    identity: { name: "Nexus", emoji: "🧭" },
    subagents: { allowAgents: ["sage", "forge"] },
    heartbeat: { every: "30m", activeHours: { start: "08:00", end: "01:00" } }
  },
  sage: {
    identity: { name: "Sage", emoji: "🦉" },
    params: { temperature: 0.3 }
  },
  forge: {
    identity: { name: "Forge", emoji: "🔨" },
    subagents: { allowAgents: ["sage"] },
    tools: { profile: "coding", exec: { enabled: true }, fs: { enabled: true } }
  }
};

for (const [id, extra] of Object.entries(agentConfigs)) {
  const idx = config.agents.list.findIndex(a => a.id === id);
  if (idx >= 0) {
    Object.assign(config.agents.list[idx], extra);
  } else {
    console.log("  Agent " + id + " 未在 list 中找到，将添加基本条目");
    config.agents.list.push({ id, ...extra });
  }
}

// agents.defaults
if (!config.agents.defaults) config.agents.defaults = {};
Object.assign(config.agents.defaults, {
  compaction: { enabled: true, threshold: 50000 },
  subagents: {
    ...(config.agents.defaults.subagents || {}),
    maxConcurrent: 3,
    maxSpawnDepth: 2,
    runTimeoutSeconds: 600
  },
  bootstrapMaxChars: 20000,
  contextPruning: true
});

// tools 配置
if (!config.tools) config.tools = {};

// agentToAgent
config.tools.agentToAgent = {
  enabled: true,
  allow: ["nexus", "sage", "forge"]
};

// sessions visibility
if (!config.tools.sessions) config.tools.sessions = {};
config.tools.sessions.visibility = "all";

// web tools
if (!config.tools.web) config.tools.web = {};
if (!config.tools.web.search) config.tools.web.search = {};
config.tools.web.search.enabled = true;
// 设置 Gemini 为默认搜索提供商（如果还没配置其他的）
if (!config.tools.web.search.provider && !config.tools.web.search.apiKey) {
  config.tools.web.search.provider = "gemini";
}
if (!config.tools.web.fetch) config.tools.web.fetch = {};
config.tools.web.fetch.enabled = true;

// 写回
const output = JSON.stringify(config, null, 2);
fs.writeFileSync(configPath, output + "\n", "utf8");
console.log("  配置写入完成");
' "$CONFIG_FILE"

ok "团队协作配置写入完成"

# ─────────────── 第八步：设置 Agent Identity ───────────────
info "设置 Agent 身份信息..."

openclaw agents set-identity --agent nexus --name "Nexus" 2>/dev/null || true
openclaw agents set-identity --agent sage  --name "Sage"  2>/dev/null || true
openclaw agents set-identity --agent forge --name "Forge" 2>/dev/null || true

ok "Agent 身份设置完成"

# ─────────────── 完成 ───────────────
echo ""
echo "============================================"
echo -e "${GREEN}  三人 Agent 团队部署完成！${NC}"
echo "============================================"
echo ""
echo "  🧭 Nexus (管家)  — Claude Sonnet 4.5"
echo "  🦉 Sage  (智者)  — Claude Opus 4.6"
echo "  🔨 Forge (锻造)  — Claude Sonnet 4.5"
echo ""
echo "  工作空间:"
echo "    Nexus: $WS_NEXUS"
echo "    Sage:  $WS_SAGE"
echo "    Forge: $WS_FORGE"
echo ""
echo "  共享知识库: $SHARED_KNOWLEDGE"
echo "  配置文件:   $CONFIG_FILE"
echo "  配置备份:   ${CONFIG_FILE}.pre-team-setup.bak"
echo ""
echo "============================================"
echo "  接下来你需要做的："
echo "============================================"
echo ""
echo "  1. 设置 API Key (如果还没设置):"
echo ""
echo "     # Anthropic (必需)"
echo "     openclaw config set ANTHROPIC_API_KEY sk-ant-你的key"
echo "     # 或写入 ~/.openclaw/.env:"
echo "     #   ANTHROPIC_API_KEY=sk-ant-你的key"
echo ""
echo "     # Gemini Search (推荐, 免费)"
echo "     # 获取: https://aistudio.google.com/apikey"
echo "     openclaw config set GEMINI_API_KEY AIza你的key"
echo ""
echo "  2. 绑定通信渠道 (选一个):"
echo ""
echo "     # Telegram:"
echo "     openclaw channels login --channel telegram"
echo "     openclaw agents bind nexus telegram:default"
echo ""
echo "     # Discord:"
echo "     openclaw channels login --channel discord"
echo "     openclaw agents bind nexus discord:default"
echo ""
echo "     # 或直接用 Web 界面 (最简单):"
echo "     # 启动后访问 http://localhost:18789"
echo ""
echo "  3. 重启 Gateway 使配置生效:"
echo ""
echo "     openclaw gateway restart"
echo ""
echo "  4. 验证:"
echo ""
echo "     openclaw agents list --bindings"
echo "     openclaw channels status --probe"
echo ""
echo "  5. 测试对话:"
echo ""
echo "     openclaw message send --agent nexus '你好，介绍一下你和你的团队'"
echo ""
echo "============================================"
