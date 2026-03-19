#!/usr/bin/env bash
# =============================================================
# n8n-ecosystem-unified — SQLite to Postgres Migration Script
# Run ON the n8n LXC as root
#
# Prerequisites (before running this script):
#   1. infra stack is running on dockge-cti LXC
#   2. infra-postgres is healthy (docker compose ps in infra/)
#   3. You have the N8N_DB_PASSWORD from infra/.env
#   4. n8n LXC can reach dockge-cti LXC on port 5432
#      Test: nc -zv <DOCKGE_CTI_IP> 5432
#   5. You have exported your workflows + credentials from n8n UI
#      Settings -> Export (download backup before migrating)
#
# What this script does:
#   - Appends DB_TYPE=postgresdb + connection vars to /opt/n8n.env
#   - Appends all n8n Variables (CTI URLs, LLM keys, etc.)
#   - Reloads systemd and restarts n8n service
#   - n8n will auto-create its schema on first Postgres boot
#
# After running:
#   - n8n starts fresh on Postgres (workflows/credentials need re-import)
#   - SQLite file preserved at /.n8n/database.sqlite as backup
#   - Run DB migrations: see docs/N8N_CONFIGURATION.md Step 4
# =============================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[migrate]${RESET} $*"; }
warn() { echo -e "${YELLOW}[warn]${RESET} $*"; }
err()  { echo -e "${RED}[error]${RESET} $*" >&2; }

ENV_FILE="/opt/n8n.env"

require_root() {
  [[ $EUID -ne 0 ]] && { err "Run as root"; exit 1; }
}

check_n8n_installed() {
  if [[ ! -f /etc/systemd/system/n8n.service ]]; then
    err "n8n systemd service not found. Install n8n first via Proxmox helper script:"
    err "  bash -c \"\$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)\""
    exit 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    err "/opt/n8n.env not found. Run n8n update once to create it:"
    err "  bash -c \"\$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)\" -- --update"
    exit 1
  fi
}

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local secret="${4:-false}"
  [[ -n "$default" ]] && echo -en "${CYAN}${prompt_text}${RESET} [${default}]: " || echo -en "${CYAN}${prompt_text}${RESET}: "
  if [[ "$secret" == "true" ]]; then read -rs value; echo; else read -r value; fi
  [[ -z "$value" && -n "$default" ]] && value="$default"
  printf -v "$var_name" '%s' "$value"
}

collect_inputs() {
  echo -e "\n${BOLD}=== n8n SQLite -> Postgres Migration ===${RESET}\n"
  warn "Export your workflows + credentials from n8n UI BEFORE proceeding!"
  warn "Settings -> Export -> Download"
  echo ""
  read -rp "Have you exported your n8n backup? (yes/no): " confirmed
  [[ "$confirmed" != "yes" ]] && { warn "Aborting. Please export first."; exit 0; }

  echo -e "\n${BOLD}--- infra-postgres connection (from dockge-cti LXC infra/.env) ---${RESET}"
  prompt DOCKGE_CTI_IP   "dockge-cti LXC IP address"
  prompt N8N_DB_PASSWORD "N8N_DB_PASSWORD (from infra/.env)" "" true

  echo -e "\n${BOLD}--- n8n core settings ---${RESET}"
  prompt N8N_HOST         "n8n hostname or IP for WEBHOOK_URL" "n8n.lab.local"
  prompt N8N_PROTOCOL     "Protocol (http or https)"           "http"
  prompt TIMEZONE         "Timezone"                           "America/Chicago"
  prompt N8N_ENCRYPTION_KEY "N8N_ENCRYPTION_KEY (generate: openssl rand -hex 32)" "$(openssl rand -hex 32)"

  echo -e "\n${BOLD}--- CTI Platform URLs ---${RESET}"
  echo -e "(Leave blank to skip — add to /opt/n8n.env manually later)"
  prompt MISP_URL    "MISP URL (e.g. https://misp.lab.local)"       ""
  prompt OPENCTI_URL "OpenCTI URL"                                   ""
  prompt THEHIVE_URL "TheHive URL"                                   ""
  prompt CORTEX_URL  "Cortex URL"                                    ""
  prompt WAZUH_URL   "Wazuh URL (e.g. https://wazuh.lab.local:55000)" ""
  prompt FLOWISE_URL "Flowise URL (e.g. https://flowise.lab.local)"  ""
  prompt SEARXNG_URL "SearXNG URL (e.g. http://searxng.lab.local)"   "http://searxng.lab.local"

  echo -e "\n${BOLD}--- Messaging ---${RESET}"
  prompt TELEGRAM_BOT_TOKEN      "Telegram Bot Token"         "" true
  prompt TELEGRAM_CHAT_ID        "Telegram Chat ID"           ""
  prompt EVOLUTION_API_URL       "Evolution API URL (blank=skip)" ""
  prompt EVOLUTION_API_KEY       "Evolution API Key (blank=skip)" "" true
  prompt EVOLUTION_INSTANCE_NAME "Evolution instance name (blank=skip)" ""

  echo -e "\n${BOLD}--- LLM Provider API Keys ---${RESET}"
  echo -e "(All optional — add in n8n Credentials UI instead if preferred)"
  prompt OPENROUTER_API_KEY "OpenRouter API Key" "" true
  prompt ANTHROPIC_API_KEY  "Anthropic API Key"  "" true
  prompt GOOGLE_AI_API_KEY  "Google Gemini API Key" "" true
  prompt OLLAMA_URL         "Ollama URL (e.g. http://<HOST>:11434, blank=skip)" ""
}

test_postgres_connectivity() {
  log "Testing connectivity to infra-postgres at ${DOCKGE_CTI_IP}:5432..."
  if ! command -v nc &>/dev/null; then
    apt-get install -y -qq netcat-openbsd
  fi
  if nc -zv "$DOCKGE_CTI_IP" 5432 2>/dev/null; then
    log "Postgres reachable."
  else
    err "Cannot reach ${DOCKGE_CTI_IP}:5432 — check:"
    err "  1. infra stack is running on dockge-cti LXC"
    err "  2. Firewall / inter-VLAN routing allows this LXC to reach dockge-cti:5432"
    err "  3. infra-postgres ports: - \"5432:5432\" is in infra docker-compose.yml"
    exit 1
  fi
}

backup_sqlite() {
  if [[ -f /.n8n/database.sqlite ]]; then
    local backup="/.n8n/database.sqlite.backup.$(date +%Y%m%d_%H%M%S)"
    cp /.n8n/database.sqlite "$backup"
    log "SQLite backup saved: $backup"
  fi
}

write_env() {
  log "Appending Postgres + configuration vars to $ENV_FILE ..."

  # Check if DB_TYPE already set — idempotent
  if grep -q '^DB_TYPE=' "$ENV_FILE"; then
    warn "DB_TYPE already set in $ENV_FILE — removing old DB block first"
    sed -i '/^DB_TYPE=/d;/^DB_POSTGRESDB_/d' "$ENV_FILE"
  fi

  cat >> "$ENV_FILE" <<EOF

# ── Postgres Migration (added by migrate-to-postgres.sh $(date)) ──
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${DOCKGE_CTI_IP}
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}

# ── n8n Core ─────────────────────────────────────────────────
WEBHOOK_URL=${N8N_PROTOCOL}://${N8N_HOST}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
GENERIC_TIMEZONE=${TIMEZONE}
N8N_LOG_LEVEL=info
N8N_RUNNERS_ENABLED=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_METRICS=true
N8N_AI_ENABLED=true
EXECUTIONS_PROCESS=main
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

# ── CTI Platform URLs (used as n8n Variables) ─────────────────
MISP_URL=${MISP_URL:-}
OPENCTI_URL=${OPENCTI_URL:-}
THEHIVE_URL=${THEHIVE_URL:-}
CORTEX_URL=${CORTEX_URL:-}
WAZUH_URL=${WAZUH_URL:-}
FLOWISE_URL=${FLOWISE_URL:-}
SEARXNG_URL=${SEARXNG_URL:-}

# ── Messaging ─────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}
EVOLUTION_API_URL=${EVOLUTION_API_URL:-}
EVOLUTION_API_KEY=${EVOLUTION_API_KEY:-}
EVOLUTION_INSTANCE_NAME=${EVOLUTION_INSTANCE_NAME:-}

# ── LLM Providers ─────────────────────────────────────────────
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_AI_API_KEY=${GOOGLE_AI_API_KEY:-}
OLLAMA_URL=${OLLAMA_URL:-}
EOF

  chmod 600 "$ENV_FILE"
  log "$ENV_FILE updated."
}

restart_n8n() {
  log "Reloading systemd and restarting n8n..."
  systemctl daemon-reload
  systemctl restart n8n
  log "Waiting for n8n to come up on Postgres..."
  local retries=30
  while ! curl -sf http://localhost:5678/healthz &>/dev/null; do
    sleep 3
    retries=$((retries - 1))
    [[ $retries -le 0 ]] && {
      err "n8n did not respond after 90s. Check logs:"
      err "  journalctl -u n8n -n 50 --no-pager"
      exit 1
    }
  done
  log "n8n is up and running on Postgres!"
}

print_next_steps() {
  echo -e "\n${BOLD}${GREEN}=== Migration Complete ===${RESET}\n"
  echo -e "  n8n: ${CYAN}http://$(hostname -I | awk '{print $1}'):5678${RESET}"
  echo -e ""
  echo -e "${BOLD}Required next steps:${RESET}"
  echo -e "  1. Run DB migrations (pgvector extensions + schema):"
  echo -e "     See docs/N8N_CONFIGURATION.md Step 4"
  echo -e "  2. Open n8n UI and complete first-boot account setup"
  echo -e "  3. Settings -> API -> Create API Key"
  echo -e "  4. Set n8n Variables (CTI URLs, Telegram ID etc.)"
  echo -e "     See docs/N8N_CONFIGURATION.md Step 2"
  echo -e "  5. Create Credentials in n8n UI"
  echo -e "     See docs/N8N_CONFIGURATION.md Step 3"
  echo -e "  6. Import workflows from workflows/unified/"
  echo -e "  7. Re-import any workflows/credentials from your SQLite backup"
  echo -e ""
  echo -e "${BOLD}SQLite backup:${RESET} /.n8n/database.sqlite.backup.*"
  echo -e "${BOLD}Live env file:${RESET} /opt/n8n.env"
  echo -e "${BOLD}Service logs:${RESET}  journalctl -u n8n -f"
}

main() {
  require_root
  check_n8n_installed
  collect_inputs
  test_postgres_connectivity
  backup_sqlite
  write_env
  restart_n8n
  print_next_steps
}

main "$@"
