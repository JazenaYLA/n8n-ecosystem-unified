# LLM Provider Configuration

The unified stack is **LLM-agnostic**. All model calls go through n8n's
native credential system. This document covers every supported provider.

**Last updated:** 2026-03-19

---

## Supported Providers

| Provider | Local/Cloud | Best For | Cost |
|---|---|---|---|
| **Ollama** | 🏠 Local | Privacy, no latency, free | Free (compute only) |
| **Google Gemini** | ☁️ Cloud | Fast mid-tier, generous free tier | Free tier + paid |
| **Anthropic Claude** | ☁️ Cloud | Heavy reasoning, CTI analysis | Paid |
| **OpenAI GPT** | ☁️ Cloud | Broad capability, tool use | Paid |
| **OpenRouter** | ☁️ Gateway | Single key for 200+ models | Per-token |
| **Mistral** | ☁️ Cloud | Code, European data residency | Paid |
| **LM Studio** | 🏠 Local | OpenAI-compatible local server | Free |

---

## Ollama (Local)

Install on Proxmox host or a GPU VM/LXC:

```bash
curl -fsSL https://ollama.ai/install.sh | sh

# Recommended models
ollama pull llama3.2           # general chat (3B — fast)
ollama pull llama3.1:8b        # better reasoning
ollama pull mistral            # code + reasoning
ollama pull nomic-embed-text   # embeddings for pgvector
ollama pull mxbai-embed-large  # larger embedding model
```

Bind to all interfaces for LXC access:
```bash
# /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

In n8n, use the **OpenAI-compatible** credential:
- **Base URL:** `http://<HOST_IP>:11434/v1`
- **API Key:** `ollama` (any placeholder)
- **Model:** `llama3.2` (or whichever you pulled)

---

## Google Gemini

1. Go to [aistudio.google.com](https://aistudio.google.com) → Get API Key
2. In n8n → Credentials → New → **Google Gemini(PaLM) API**
3. Paste API key
4. **Credential name:** `Google Gemini`

Recommended models:
- `gemini-1.5-flash` — fast, free tier, good for mid-tier
- `gemini-1.5-pro` — better reasoning
- `gemini-2.0-flash` — latest, fast
- `text-embedding-004` — embeddings

---

## Anthropic Claude

1. [console.anthropic.com](https://console.anthropic.com) → API Keys → Create Key
2. In n8n → Credentials → New → **Anthropic API**
3. **Credential name:** `Anthropic API`

Recommended models:
- `claude-haiku-4-5` — fast, cheap, good for scoring/routing
- `claude-sonnet-4-5` — best balance for CTI analysis
- `claude-opus-4-5` — maximum reasoning

---

## OpenRouter (Multi-Model Gateway)

One API key gives access to 200+ models including free tiers:

1. [openrouter.ai](https://openrouter.ai) → Keys → Create Key
2. In n8n → Credentials → New → **HTTP Header Auth**
   - **Name:** `OpenRouter`
   - **Header:** `Authorization`
   - **Value:** `Bearer sk-or-<your-key>`

Useful free models on OpenRouter:
- `meta-llama/llama-3.1-8b-instruct:free`
- `google/gemini-flash-1.5:free`
- `mistralai/mistral-7b-instruct:free`

---

## Tiered Model Router Logic

The `tiered-model-router` workflow assigns a complexity score (1–10)
to each incoming query and routes to the appropriate tier:

```
Score 1–3  → Tier 1 (Fast/Local)
  Default: Ollama llama3.2
  Fallback: OpenRouter free Llama

Score 4–6  → Tier 2 (Mid)
  Default: Gemini Flash
  Fallback: Claude Haiku

Score 7–10 → Tier 3 (Heavy)
  Default: Claude Sonnet
  Fallback: GPT-4o
```

To use **only OpenRouter** (simplest setup — one credential, all tiers):

```
Tier 1 model: meta-llama/llama-3.1-8b-instruct:free
Tier 2 model: google/gemini-flash-1.5
Tier 3 model: anthropic/claude-sonnet-4-5
```

---

## Embedding Models (for pgvector / RAG)

Used by Flowise chatflows and any n8n vector memory workflows:

| Model | Provider | Dimensions | Notes |
|---|---|---|---|
| `nomic-embed-text` | Ollama (local) | 768 | Free, fast |
| `mxbai-embed-large` | Ollama (local) | 1024 | Higher quality |
| `text-embedding-004` | Google Gemini | 768 | Free tier |
| `text-embedding-3-small` | OpenAI | 1536 | Cost-effective |
