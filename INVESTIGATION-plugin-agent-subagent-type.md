# Investigation: Plugin Agents and Task Tool's subagent_type

## Question

> Claude Code で「プラグインエージェントは Task ツールの subagent_type に登録されず、明示的に呼び出せない」は本当か？

## Answer: False (partially)

Plugin agents **CAN** be registered in the Task tool's `subagent_type` — but only when the plugin is **installed**. The observed behavior was caused by the `claude-slack` plugin not being installed, not by an architectural limitation.

## Evidence

Error message when attempting `Task(subagent_type="claude-slack-status")`:

```
Error: Agent type 'claude-slack-status' not found. Available agents:
  Bash, general-purpose, statusline-setup, Explore, Plan, claude-code-guide,
  plugin-dev:agent-creator, plugin-dev:skill-reviewer, plugin-dev:plugin-validator
```

Note: `plugin-dev:agent-creator`, `plugin-dev:skill-reviewer`, `plugin-dev:plugin-validator` are **plugin agents** and they ARE registered. This proves plugin agents can be subagent_types.

## Source Code Analysis (cli.js v2.1.49)

### Agent Loading Pipeline

```
YF1 (main loader)
├── aGA()        → Built-in agents (Bash, general-purpose, Explore, Plan, etc.)
├── oK1()        → Plugin agents (from INSTALLED plugins via lY())
└── hp("agents") → User/project agents (.claude/agents/*.md)
    ↓
YI() → Deduplication by agentType (later sources override earlier)
    ↓
activeAgents → Used by Task tool's subagent_type enum
```

### Key Function: oK1 (Plugin Agent Loader)

```javascript
// Pseudocode from minified cli.js
oK1 = memoize(async () => {
  const { enabled } = await loadInstalledPlugins();  // lY()
  const agents = [];
  for (const plugin of enabled) {
    if (plugin.agentsPath) {
      agents.push(...loadAgentsFromDir(plugin.agentsPath, plugin.name, plugin.source));
    }
  }
  return agents;
});
```

Critical: `lY()` only returns **installed** plugins, not plugins that merely exist as source code.

### Key Function: YI (Priority/Dedup)

```javascript
function YI(allAgents) {
  // Groups in priority order (later wins)
  const groups = [builtIn, plugin, userSettings, projectSettings, flagSettings, policySettings];
  const map = new Map();
  for (const group of groups) {
    for (const agent of group) {
      map.set(agent.agentType, agent);
    }
  }
  return Array.from(map.values());
}
```

Plugin agents have higher priority than built-in agents. Policy-defined agents have the highest priority.

### Agent Naming Convention

Plugin agents use colon-separated namespacing: `{plugin-name}:{agent-name}`

Example: Plugin `plugin-dev` with agent `agent-creator` → `plugin-dev:agent-creator`

## Root Cause

| Plugin | Agents exist? | Installed? | Agents registered? |
|--------|:---:|:---:|:---:|
| `plugin-dev` | Yes | Yes (built-in) | Yes |
| `claude-slack` | Yes (in repo) | No (development only) | No |

The `claude-slack` plugin's agent files are correctly structured:

```
plugins/claude-slack/agents/
├── claude-slack-config.md   # name: claude-slack-config
├── claude-slack-on.md       # name: claude-slack-on
├── claude-slack-off.md      # name: claude-slack-off
└── claude-slack-status.md   # name: claude-slack-status
```

But since the plugin is not installed (only exists as source code being developed), `oK1()` → `lY()` does not include it.

## How to Fix

To make `claude-slack` agents available as subagent_types:

1. **Install the plugin** via settings or marketplace
2. Once installed, agents will be available as:
   - `claude-slack:claude-slack-config`
   - `claude-slack:claude-slack-on`
   - `claude-slack:claude-slack-off`
   - `claude-slack:claude-slack-status`

## Summary

| Claim | Verdict |
|-------|---------|
| Plugin agents are not registered in subagent_type | **False** — `plugin-dev:*` agents prove otherwise |
| Plugin agents cannot be explicitly invoked | **False** — they can via `plugin-name:agent-name` format |
| `claude-slack-status` cannot be invoked | **True** — but because the plugin isn't installed, not an architectural limitation |
