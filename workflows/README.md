# Workflow Directory

This directory organizes all n8n workflows across the unified ecosystem.

## Structure

```
workflows/
├── freddy/      — Freddy Schuetz n8n-claw workflows (pristine, do not modify)
├── shabbir/     — Shabbir OpenClaw Clone monolith (reference source)
└── unified/     — JazenaYLA custom merged workflows
```

## freddy/ — Core Engine (12 workflows)

| Workflow | Purpose |
|---|---|
| `n8n-claw-agent.json` | Main orchestrator agent (68KB) |
| `heartbeat.json` | 15-min proactive task runner |
| `reminder-runner.json` | 1-min reminder queue |
| `reminder-factory.json` | Reminder creation tool |
| `memory-consolidation.json` | Nightly Claude Haiku summarizer |
| `sub-agent-runner.json` | Research / Content / Data agents |
| `mcp-builder.json` | On-demand MCP skill builder (35KB) |
| `mcp-library-manager.json` | MCP skill library CRUD |
| `mcp-client.json` | MCP client connector |
| `agent-library-manager.json` | Agent library CRUD |
| `credential-form.json` | Credential onboarding form |
| `workflow-builder.json` | Dynamic workflow builder |

## shabbir/ — Multi-Channel Reference (1 workflow)

| Workflow | Purpose |
|---|---|
| `n8nClaw.json` | Full monolith: Telegram+WhatsApp+Email+Heartbeat+3 Worker Agents+Document Manager (89KB) |

## unified/ — Our Merged Additions (in development)

| Workflow | Purpose | Status |
|---|---|---|
| `multi-channel-router.json` | Normalize Telegram+WhatsApp+Discord+Slack → common struct | 🔴 TODO |
| `tiered-model-router.json` | Route tasks to Haiku/Sonnet/Opus by complexity | 🔴 TODO |
| `email-manager.json` | Autonomous Gmail manager with security guardrails | 🔴 TODO |

## Source Repos

- Freddy: https://github.com/JazenaYLA/n8n-claw (fork of freddy-schuetz/n8n-claw)
- Shabbir: https://github.com/JazenaYLA/n8nclaw
- Templates/Skills: https://github.com/JazenaYLA/n8n-claw-templates (fork of freddy-schuetz)
