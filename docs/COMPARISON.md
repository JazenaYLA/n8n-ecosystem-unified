# OpenClaw vs n8n-claw — Functionality Comparison

> **Reference video:** [Freddy Schuetz walkthrough](https://youtu.be/Wz3GSe0QmSc)  
> **Community thread:** [n8n-claw: OpenClaw in n8n](https://community.n8n.io/t/n8n-claw-openclaw-in-n8n/271756)  
> **n8n-claw source:** [freddy-schuetz/n8n-claw](https://github.com/freddy-schuetz/n8n-claw)

---

## TL;DR

**OpenClaw** is a heavyweight, opaque autonomous assistant (71 directories, 160 dependencies) often requiring dedicated hardware. **n8n-claw** reimplements its core capabilities inside n8n — fully visible, customizable, and self-hosted with a fraction of the resource footprint.

---

## Feature Comparison

| Feature | OpenClaw | n8n-claw | Notes |
|---|---|---|---|
| **Interface** | Multi-channel (web, API) | Telegram (primary) | n8n-claw extensible via additional triggers |
| **LLM Backend** | Multi-model (configurable) | Claude (Anthropic) only | Anthropic API required; no local LLM support out of box |
| **Tiered agent cost control** | ✅ Haiku→Sonnet→Opus routing | ❌ Single model tier | OpenClaw auto-routes by complexity; n8n-claw uses one model |
| **Persistent memory** | ✅ Vector + conversation | ✅ Vector (`memory_long`) + conversation history | Both use pgvector; n8n-claw also has daily log + consolidation |
| **Autonomous task execution** | ✅ 24/7 background agent | ✅ Reminder runner polls every minute | n8n-claw uses scheduled polling vs OpenClaw's event loop |
| **Multi-channel messaging** | ✅ Telegram, WhatsApp, Slack | ✅ Telegram (others addable as n8n triggers) | OpenClaw ships multi-channel; n8n-claw requires manual addition |
| **Voice / media input** | ✅ Voice notes, PDFs, images | ⚠️ Via Crawl4AI + media-handling branch | n8n-claw partial — `feature/media-handling` branch exists |
| **Document management** | ✅ Google Drive native | ❌ Not built-in | Must build as a custom MCP skill |
| **Email management** | ✅ Native email read/send | ✅ `email-bridge` service (IMAP/SMTP REST) | Both support email; n8n-claw uses a sidecar container |
| **Web search** | ✅ Built-in | ✅ SearXNG (self-hosted) + Brave API | n8n-claw defaults to self-hosted SearXNG — no third-party dependency |
| **Web reader / scraping** | ✅ Built-in | ✅ Crawl4AI (headless Chromium) | Crawl4AI outputs clean markdown from any URL |
| **Skill / plugin system** | ✅ ClawHub marketplace | ✅ MCP template library (jsDelivr CDN) | Both extensible; n8n-claw templates are Git-based |
| **Skill installation** | Via ClawHub UI | Via chat command → Library Manager workflow | n8n-claw installs skills by importing n8n workflow JSON |
| **Calendar integration** | ✅ Built-in | ⚠️ Nextcloud CalDAV (optional `.env` vars) | n8n-claw supports CalDAV but not natively configured |
| **Meeting intelligence** | ❌ | ⚠️ Vexa integration (optional) | n8n-claw has Vexa vars in `.env.example` |
| **Expert sub-agents** | ✅ | ✅ Sub-Agent Runner with persona system | n8n-claw ships 3 default agents: research, content, data analyst |
| **MCP server builder** | ❌ | ✅ `mcp-builder` + `mcp-client` workflows | n8n-claw can build new MCP skills via chat prompt |
| **Workflow builder** | ❌ | ✅ `workflow-builder` (Claude Code CLI) | Agent can write and deploy new n8n automations |
| **Project memory** | ⚠️ Basic context | ✅ `project-manager` workflow + `project_memory` table | Persistent structured context per named project |
| **Self-modification** | ❌ | ✅ `Self Modify` tool in agent | Agent can update its own `soul`/`agents` DB entries |
| **Observability / transparency** | ❌ Black box | ✅ Full n8n visual workflow UI | Every execution step visible and debuggable |
| **Deployment complexity** | High (dedicated machine recommended) | Medium (`docker compose up` + `setup.sh`) | n8n-claw ~8 containers vs OpenClaw's 71-dir monolith |
| **Resource requirements** | Mac Mini or equivalent (dedicated) | ~8GB RAM minimum (Crawl4AI = 4GB alone) | Both heavy; n8n-claw lighter but not trivial |
| **Multi-user support** | ✅ | ❌ Single user (Telegram Chat ID locked) | dmo-claw fork adds multi-user for tourism use cases |
| **Open source / inspectable** | ❌ Closed / black box | ✅ Fully open, all logic in n8n workflow JSON | Core advantage of n8n-claw |
| **Self-hosted** | ✅ | ✅ | Both fully self-hosted |
| **Cloud LLM dependency** | Configurable | Required (Anthropic) | OpenClaw more LLM-agnostic |

---

## Key Architectural Differences

### OpenClaw
- Monolithic app with dedicated process management
- Multi-model routing built into core (cost optimization by default)
- 71 directories, 160 npm dependencies
- Ships as a single install requiring dedicated hardware
- Multi-channel out of the box (web UI + messaging)

### n8n-claw
- No custom application code — **everything is n8n workflow nodes**
- Single LLM (Claude) with no automatic tier routing
- ~8 Docker services via compose (n8n, postgres, postgrest, kong, studio, meta, crawl4ai, searxng)
- Config and personality stored in PostgreSQL, read at runtime via PostgREST
- Two-workflow MCP pattern (a workaround for an n8n API bug — see BUILD_NOTES.md)
- Skills installed as n8n workflow imports from a Git-backed CDN catalog

---

## What n8n-claw Does Better

- **Full transparency** — every agent decision is a visible n8n node execution
- **Extensibility** — add any n8n integration as a tool in minutes
- **Self-hosted search** — SearXNG means no Brave/SERP API dependency
- **MCP builder** — agent can scaffold new skill workflows from a chat prompt
- **Workflow builder** — agent writes and deploys new automations autonomously
- **Self-modification** — agent edits its own personality/config via DB
- **Lighter architecture** — no 160-dependency monolith; compose stack only

## What OpenClaw Does Better

- **Multi-model cost routing** — Haiku for simple tasks, Opus for complex (saves API cost)
- **Multi-channel out of the box** — Telegram + WhatsApp + Slack without extra config
- **Multi-user support** — role-based access built into core
- **LLM agnostic** — not locked to Anthropic
- **Media handling** — voice, PDF, image processing more mature
- **Document management** — Google Drive native integration

---

## dmo-claw — Notable Fork Reference

Freddy maintains [dmo-claw](https://github.com/freddy-schuetz/dmo-claw/) as a tourism-sector fork of n8n-claw:

| | n8n-claw | dmo-claw |
|---|---|---|
| Interface | Telegram | OpenWebUI (Webhook) |
| Users | Single user | Multi-user with roles |
| Extra workflows | — | Morning Briefing, Weekly Report, Google Reviews, Instagram Posting |

dmo-claw shows the pattern for multi-user / multi-interface extensions — useful reference for our CTI fork.

---

## Our Fork Priorities (JazenaYLA / CTI Use Case)

Based on the comparison above, the highest-value additions for a CTI/security homelab fork are:

1. **Multi-LLM support** — swap Anthropic for OpenRouter (access to Gemini, Mistral, local models)
2. **CTI skill pack** — MISP webhook ingestion, Wazuh alert triage, OpenCTI enrichment as MCP skills
3. **Proxmox LXC deployment template** — replace the bare-VPS assumption in `setup.sh`
4. **Caddy reverse proxy config** — replace built-in nginx option with Caddy (already in our homelab stack)
5. **Webhook-based multi-channel** — add Slack/Matrix trigger alongside Telegram
6. **Headscale/Tailscale network binding** — restrict n8n access to VPN network only
