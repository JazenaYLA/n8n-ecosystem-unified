# Communications Channel Environment Variables

This document is the canonical reference for all environment variables required
by the communications channels used in `n8n-ecosystem-unified` and (for gateway
agentic workflows) `YAOC2`.

**Last updated:** 2026-03-24

---

## Telegram

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ Always | Bot token from [@BotFather](https://t.me/BotFather). Used for all Telegram send/receive nodes and as the YAOC2 operator alert channel. |
| `APPROVAL_CHAT_ID` | ✅ Always | Numeric chat ID of the operator/analyst Telegram account or group. Used for approval requests and capability-missing alerts. Get it from [@userinfobot](https://t.me/userinfobot). |

**n8n credential:** Create a `Telegram Bot` credential in n8n Settings → Credentials using `TELEGRAM_BOT_TOKEN`.

> **Note:** Telegram is the **fallback alert channel** for YAOC2. Even if all other channels are unconfigured, Telegram must be set so the operator can receive onboarding guidance.

---

## WhatsApp via Evolution API

| Variable | Required | Description |
|---|---|---|
| `EVOLUTION_API_URL` | ✅ | Base URL of your Evolution API instance, e.g. `http://evolution-api:8082`. No trailing slash. |
| `EVOLUTION_API_KEY` | ✅ | API key configured in Evolution API's own `.env` (`AUTHENTICATION_API_KEY`). |
| `EVOLUTION_INSTANCE_NAME` | ✅ | Instance name created in Evolution for your WhatsApp number, e.g. `yaoc2-wa`. |
| `WHATSAPP_PHONE` | ✅ | Phone number bound to the Evolution instance, digits only, no `+`. e.g. `14155551234`. |

**n8n credential:** Install the `n8n-nodes-evolution-api` community node. Create an `Evolution API` credential with the URL and key above.

**Setup flow:**
1. Deploy Evolution API (Docker Compose in your infra stack).
2. Create an instance via Evolution API UI or REST.
3. Scan the QR code with your WhatsApp number to pair.
4. Set the four env vars above.
5. Create the n8n credential.

---

## Slack

| Variable | Required | Description |
|---|---|---|
| `SLACK_BOT_TOKEN` | ✅ | Bot token starting with `xoxb-`. From Slack app OAuth page after installation. |
| `SLACK_SIGNING_SECRET` | ✅ | Signing secret from Slack app Basic Information page. Used to verify webhook payloads. |
| `SLACK_DEFAULT_CHANNEL` | ✅ | Default channel name or ID, e.g. `#alerts` or `C012AB3CD`. |

**Setup flow:**
1. Create a Slack app at [api.slack.com/apps](https://api.slack.com/apps).
2. Add Bot Token Scopes: `chat:write`, `channels:read`, `channels:history`.
3. Install to workspace → copy Bot User OAuth Token.
4. Copy Signing Secret from Basic Information.
5. Set the three env vars above.

---

## Google Services

### Gemini (Google AI)

| Variable | Required | Description |
|---|---|---|
| `GOOGLE_AI_API_KEY` | ✅ | API key from [aistudio.google.com/apikey](https://aistudio.google.com/apikey). Supports Gemini 1.5 Pro, Gemini 2.0 Flash, etc. |

**n8n credential:** Create a `Google AI` credential using this key.

### Gmail and Google Calendar (OAuth2)

| Variable | Required | Description |
|---|---|---|
| `GOOGLE_OAUTH_CLIENT_ID` | ✅ | OAuth2 client ID from Google Cloud Console. |
| `GOOGLE_OAUTH_CLIENT_SECRET` | ✅ | OAuth2 client secret from Google Cloud Console. |

**Setup flow:**
1. Go to [console.cloud.google.com](https://console.cloud.google.com).
2. Create an OAuth2 app (or reuse existing). Enable Gmail API and/or Google Calendar API.
3. Add `https://your-n8n-instance/rest/oauth2-credential/callback` as an authorized redirect URI.
4. Set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` in n8n env.
5. In n8n Settings → Credentials, create a `Gmail OAuth2` and/or `Google Calendar OAuth2` credential and complete the OAuth flow.

> **Note:** The OAuth access tokens are stored inside n8n's credential store — not in env vars. The env vars here are the *app registration* credentials (client ID/secret). The YAOC2 capability guard uses these as a presence signal.

---

## LLM Providers

### Generic OpenAI-Compatible (OpenAI, Groq, Mistral, OpenRouter, Ollama, LM Studio, LiteLLM, etc.)

| Variable | Required | Description |
|---|---|---|
| `OPENAI_COMPAT_BASE_URL` | ✅ | The `/v1` endpoint of your provider. Examples: `https://api.openai.com/v1`, `https://api.groq.com/openai/v1`, `http://localhost:11434/v1` (Ollama). |
| `OPENAI_COMPAT_KEY` | ✅ | API key for the provider. For local models without auth, use any non-empty string. |

**n8n credential:** Create an `OpenAI` credential and override the **Base URL** field to `{{ $env.OPENAI_COMPAT_BASE_URL }}`. This single credential pattern covers all compatible providers.

### DeepSeek (Native)

| Variable | Required | Description |
|---|---|---|
| `DEEPSEEK_API_KEY` | ✅ | API key from [platform.deepseek.com](https://platform.deepseek.com). Endpoint: `https://api.deepseek.com/v1`. Can also route via `openai-compat`. |

### Anthropic (Claude Native)

| Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | ✅ | API key from [console.anthropic.com](https://console.anthropic.com). For Claude via OpenRouter or LiteLLM, use `openai-compat` instead. |

---

## Minimal Startup Set

For a functioning YAOC2 + n8n-unified deployment, these are the absolute minimum
vars that must be set before any workflow is activated:

```bash
# Telegram (required — fallback alert channel)
TELEGRAM_BOT_TOKEN=
APPROVAL_CHAT_ID=

# At least one LLM provider
OPENAI_COMPAT_BASE_URL=
OPENAI_COMPAT_KEY=
```

All other channels and providers can be added incrementally. The YAOC2 capability
guard will detect missing config at runtime and alert the operator with exact
setup instructions rather than failing silently.

---

## YAOC2 Capability Guard Keys

These variable names map directly to capability keys in YAOC2's guard:

```
telegram       → TELEGRAM_BOT_TOKEN, APPROVAL_CHAT_ID
whatsapp       → EVOLUTION_API_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE_NAME, WHATSAPP_PHONE
slack          → SLACK_BOT_TOKEN, SLACK_SIGNING_SECRET, SLACK_DEFAULT_CHANNEL
google_ai      → GOOGLE_AI_API_KEY
gmail          → GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET
google_calendar→ GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET
openai-compat  → OPENAI_COMPAT_BASE_URL, OPENAI_COMPAT_KEY
deepseek       → DEEPSEEK_API_KEY
anthroponic_direct → ANTHROPIC_API_KEY
```

See [YAOC2/docs/CAPABILITY_ONBOARDING.md](https://github.com/JazenaYLA/YAOC2/blob/main/docs/CAPABILITY_ONBOARDING.md) for full guard documentation.
