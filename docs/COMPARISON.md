# OpenClaw vs n8n-claw Ecosystem — Full Comparison

> **Sources merged from:**
> - [JazenaYLA/n8nclaw IMPLEMENTATION_COMPARISON.md](https://github.com/JazenaYLA/n8nclaw)
> - [freddy-schuetz/n8n-claw](https://github.com/freddy-schuetz/n8n-claw) CLAUDE.md + README
> - Community thread: [n8n-claw: OpenClaw in n8n](https://community.n8n.io/t/n8n-claw-openclaw-in-n8n/271756)
>
> **Last Updated:** March 18, 2026

---

## TL;DR

**OpenClaw** is a heavyweight, opaque autonomous assistant (71 directories, 160 dependencies) often requiring dedicated hardware. **Shabbir's n8nclaw** reimplements it visually in n8n for learning and multi-channel use. **Freddy's n8n-claw** goes further with a production-grade self-hosted system. **Our unified fork** takes the best of all three.

---

## Three-Way Feature Comparison

| Feature | OpenClaw | Shabbir (n8nclaw) | Freddy (n8n-claw) | Our Unified Target |
|---|---|---|---|---|
| **Architecture** | Monolithic app | Visual workflow template | Production self-hosted system | Freddy core + Shabbir modules |
| **Setup** | Dedicated machine | Manual 6-8 steps (~30 min) | Automated `setup.sh` (~15 min) | Automated + CTI extensions |
| **Multi-channel** | ✅ Web + messaging | ✅ Telegram, WhatsApp, Slack | ⚠️ Telegram primary | ✅ Full normalization layer |
| **LLM Routing** | ✅ Multi-model | ✅ Tiered (Haiku→Sonnet→Opus) | ⚠️ Single model (Sonnet) | ✅ Tiered routing added |
| **Persistent memory** | ✅ | ✅ Short + vector | ✅ Short + daily consolidation + RAG | ✅ Automated consolidation |
| **Task management** | ✅ | ✅ Basic (tasks, subtasks) | ✅ Full (priorities, due dates) | ✅ Full |
| **Autonomous execution** | ✅ 24/7 | ✅ Hourly heartbeat | ✅ 15-min heartbeat + Reminder Runner | ✅ 15-min + scheduled actions |
| **Voice / media** | ✅ | ⚠️ Partial (Gemini) | ✅ Full (Whisper + Vision + PDF) | ✅ Full pipeline |
| **Email manager** | ✅ | ✅ Native N8N node | ⚠️ Via MCP skill | ✅ Native + guardrails |
| **Document manager** | ✅ Google Drive | ✅ Native Google Drive | ⚠️ Via MCP | ✅ Native |
| **Web search** | ✅ | Tavily / Perplexity (API keys) | ✅ Self-hosted SearXNG | ✅ SearXNG + optional Perplexity |
| **Web scraping** | ✅ | External | ✅ Crawl4AI (headless Chromium) | ✅ Crawl4AI |
| **MCP skills library** | ✅ ClawHub | ❌ | ✅ 7+ skills, install via chat | ✅ + CTI skill pack |
| **MCP Builder** | ❌ | ❌ | ✅ Build custom skills via chat | ✅ |
| **Workflow Builder** | ❌ | ❌ | ✅ Claude Code CLI | ✅ |
| **Expert sub-agents** | ✅ | ⚠️ Fixed set | ✅ Research, Content, Data Analyst | ✅ + CTI agents |
| **Project memory** | ⚠️ | ❌ | ✅ Persistent markdown docs | ✅ |
| **Self-modification** | ❌ | ❌ | ✅ Agent edits own soul/agents DB | ✅ |
| **Multi-user** | ✅ | ❌ | ❌ (dmo-claw fork has it) | ⚠️ Single user (future) |
| **Alternative LLMs** | ✅ | ❌ | ✅ OpenAI-compatible (Ollama, etc.) | ✅ OpenRouter support |
| **Transparency** | ❌ Black box | ✅ Full visual | ✅ Full visual | ✅ Full visual |
| **Self-hosted** | ✅ | ✅ | ✅ | ✅ |
| **Resource requirements** | Mac Mini dedicated | ~4GB RAM min | ~8GB RAM min (Crawl4AI = 4GB) | ~8GB RAM min |
| **Open source** | ❌ | ✅ | ✅ | ✅ |
| **Production ready** | ✅ | ~70% | ~90% | Target: 95% |

---

## Shabbir vs Freddy — Architecture Philosophy

### Shabbir: "Understandable Autonomy"
```
Goal: System non-programmers can understand
  ├── Visual workflows (see every connection)
  ├── Clear data flow (input → normalize → agent → output)
  ├── Multi-channel from day 1
  ├── Intelligent model routing (cost-optimized)
  └── Modular agents (research, document, email)

Philosophy: "Be transparent about how autonomy works"
Best for: Engineers who want to learn architecture
Strength: Educational value + multi-channel + cost optimization
```

### Freddy: "Production Autonomous System"
```
Goal: Deployable, maintainable AI agent
  ├── Automated setup (single command)
  ├── Infrastructure as code (consistent deployments)
  ├── Extensible via MCP skills (scalable capabilities)
  ├── Enterprise memory (RAG, consolidation, cleanup)
  └── Community-driven evolution (skills + agents catalogs)

Philosophy: "Make autonomy deploy-able and sustainable"
Best for: DevOps/Infrastructure engineers
Strength: Production readiness + community ecosystem
```

---

## What Shabbir Has That Freddy Doesn't

1. **Multi-Channel Out of Box** — Telegram + WhatsApp + Slack unified from day 1
2. **Intelligent Model Routing** — Haiku → Sonnet → Opus saves ~76% token costs
3. **Native Email Manager** — Direct N8N email node, not via MCP
4. **Direct Google Drive Integration** — Native nodes vs MCP abstraction
5. **Educational architecture** — Every node visible, great for understanding

## What Freddy Has That Shabbir Doesn't

1. **Automated One-Command Setup** — `./setup.sh` handles everything
2. **MCP Skills Library** — 7+ pre-built skills, install via chat
3. **MCP Builder** — Agent builds new MCP servers from scratch on demand
4. **Self-Hosted SearXNG** — Zero-cost, zero-API-key web search
5. **Automated Memory Consolidation** — Nightly, Haiku-powered, self-cleaning
6. **Scheduled Actions** — Agent executes code at specific times (not just reminders)
7. **Project Memory** — Persistent project context across sessions
8. **Agent Self-Modification** — Edits own personality/config via DB
9. **Alternative LLM Support** — OpenAI-compatible (Ollama, llama.cpp, OpenRouter)
10. **Enterprise Infrastructure** — PostgREST + Kong API gateway

---

## Merge Strategy for Our Unified Fork

### "Freddy Core + Shabbir Modules" Approach

```
Base: Freddy's automated deployment + infrastructure
  + Shabbir's multi-channel normalization layer
  + Shabbir's tiered model routing (Haiku/Sonnet/Opus)
  + Shabbir's native email + Google Drive integration
  + Our CTI-specific extensions

Result: Single canonical deployment with all features
```

### Implementation Priority

| Priority | Feature | Source | Notes |
|---|---|---|---|
| 🔴 High | Multi-channel normalization | Shabbir | Add to Freddy's trigger layer |
| 🔴 High | Tiered model routing | Shabbir | 76% cost savings |
| 🔴 High | CTI skill pack | Custom | MISP, Wazuh, OpenCTI MCP skills |
| 🟡 Medium | OpenRouter support | Custom | Replace Anthropic-only dependency |
| 🟡 Medium | Native email manager | Shabbir | Alongside Freddy's email-bridge |
| 🟡 Medium | Proxmox LXC deploy template | Custom | Replace bare-VPS assumption |
| 🟡 Medium | Caddy reverse proxy config | Custom | Replace built-in nginx |
| 🟢 Low | Headscale/Tailscale binding | Custom | VPN-only access for homelab |
| 🟢 Low | Multi-user support | dmo-claw | Reference dmo-claw fork |

---

## dmo-claw — Notable Fork Reference

Freddy maintains [dmo-claw](https://github.com/freddy-schuetz/dmo-claw/) for tourism-sector multi-user deployments:

| | n8n-claw | dmo-claw |
|---|---|---|
| Interface | Telegram | OpenWebUI (Webhook) |
| Users | Single user | Multi-user with roles |
| Extra workflows | — | Morning Briefing, Weekly Report, Google Reviews, Instagram Posting |

dmo-claw shows the multi-user / multi-interface pattern — useful reference for future multi-user CTI deployment.

---

## Recommendation

**Don't choose one — merge both strategically.** They represent complementary strengths:

- **Shabbir** = Best for: understanding architecture, multi-channel, cost optimization
- **Freddy** = Best for: production deployment, extensibility, enterprise features
- **Our fork** = Best for: CTI/security homelab with full feature set + infrastructure automation

Our role: bridge both for the infrastructure/cybersecurity community with MISP, Wazuh, OpenCTI integrations and homelab-optimized deployment.
