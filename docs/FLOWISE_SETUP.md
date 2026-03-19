# Flowise Setup & Integration Guide

Flowise runs in its **own dedicated LXC** installed via the Proxmox
community helper script. It is **not** a Docker service inside the
n8n stack. This keeps Flowise independently maintainable and avoids
conflicts with n8n's Docker networking.

**Last updated:** 2026-03-19

---

## LXC Installation

```bash
# On Proxmox host shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/flowise.sh)"
```

Recommended resources:
- **RAM:** 4096 MB
- **CPU:** 4 cores
- **Disk:** 20 GB
- **Hostname:** `flowise`

The helper script installs Node.js and Flowise natively.
Flowise starts automatically on port `3000`.

---

## Post-Install Configuration

### 1. Set Flowise credentials file

Edit `/opt/flowise/.env` (or `/root/.flowise/.env` depending on script version):

```bash
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=<strong_password>
PORT=3000

# Point to infra-postgres on CTI LXC for persistent storage
DATABASE_TYPE=postgres
DATABASE_HOST=<CTI_LXC_IP>
DATABASE_PORT=5432
DATABASE_NAME=flowise
DATABASE_USER=flowise
DATABASE_PASSWORD=<FLOWINTEL_DB_PASSWORD from infra/.env>

# n8n webhook base URL (for Flowise → n8n triggers)
N8N_WEBHOOK_URL=https://n8n.lab.local
```

Restart Flowise after editing:
```bash
systemctl restart flowise
# or: pm2 restart flowise
```

### 2. Add Caddy route

In CaddyManager, add:
```caddy
flowise.lab.local {
    reverse_proxy <FLOWISE_LXC_IP>:3000
    encode gzip
}
```

### 3. Add DNS record

In UniFi local DNS:
```
flowise.lab.local   CNAME   caddy.lab.local
```

### 4. Get Flowise API Key

In Flowise UI → **Settings → API Keys** → Create API Key.
Add this as the `Flowise API` credential in n8n.

---

## Integration Patterns with n8n

### Pattern 1 — n8n as Gateway, Flowise as RAG Brain

For complex multi-turn or document queries (complexity score ≥ 7),
n8n forwards the message to a Flowise chatflow:

```
Telegram/WhatsApp → n8n multi-channel-router
  → complexity scorer
    score ≥ 7 → POST https://flowise.lab.local/api/v1/prediction/<chatflow-id>
                body: { "question": "...", "overrideConfig": { "sessionId": "<chatId>" } }
    score < 7 → tiered-model-router (direct LLM call)
```

n8n HTTP Request node config:
- **Method:** POST
- **URL:** `{{ $vars.FLOWISE_URL }}/api/v1/prediction/<CHATFLOW_ID>`
- **Auth:** `Flowise API` credential
- **Body:** `{ "question": "{{ $json.userMessage }}", "overrideConfig": { "sessionId": "{{ $json.chatId }}" } }`

### Pattern 2 — CTI Document RAG via Flowise

Create a Flowise chatflow that:
1. Uses a **PDF / Text File Loader** pointed at MISP event exports or OpenCTI reports
2. Stores embeddings in `pgvector` (via `infra-postgres`, schema: `flowise_rag`)
3. Exposes a chatflow endpoint that n8n calls for IOC/TTP questions

Embedding model options:
- **Ollama** (`nomic-embed-text`) — fully local, no API cost
- **Google Gemini Embeddings** — cloud, high quality
- **OpenAI text-embedding-3-small** — cloud, cost-effective

In Flowise, connect:
```
[Document Loader] → [Text Splitter] → [Embeddings] → [Postgres PGVector Store]
                                                              ↓
[Chat Model] ← [Conversational Retrieval QA Chain] ← [PGVector Retriever]
```

Postgres connection in Flowise node:
- Host: `<CTI_LXC_IP>`, Port: `5432`, DB: `n8n`, User: `n8n`
- Table: `flowise_rag_documents`

### Pattern 3 — Flowise → n8n Webhook Trigger

In a Flowise chatflow, add a **Custom Tool** node with:
- **Tool Name:** `create_thehive_case`
- **Tool Description:** `Creates a TheHive case from a CTI finding`
- **HTTP Method:** POST
- **URL:** `https://n8n.lab.local/webhook/flowise-thehive-trigger`
- **Body:** `{ "title": "{title}", "description": "{description}", "severity": "{severity}" }`

In n8n, create a **Webhook** trigger workflow at path `/flowise-thehive-trigger`
that calls TheHive API to create the case.

---

## Flowise Chatflow Ideas for CTI

| Chatflow | Description |
|---|---|
| `cti-rag-assistant` | Q&A over MISP events + OpenCTI reports |
| `ioc-enrichment-chat` | Interactive IOC investigation with Cortex |
| `threat-briefing` | Daily brief from OpenCTI indicators |
| `incident-responder` | Guided IR workflow with TheHive integration |
| `osint-researcher` | Web research via SearXNG + Crawl4AI + LLM |
