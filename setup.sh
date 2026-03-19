#!/usr/bin/env bash
# =============================================================
# n8n-ecosystem-unified — Setup Script
# Proxmox LXC / Debian 12 (bookworm) edition
#
# What this script does:
#   1. Installs Docker inside the n8n LXC
#   2. Generates secrets and writes .env
#   3. Updates searxng/settings.yml with generated secret key
#   4. Starts the n8n Docker stack (n8n + email-bridge + crawl4ai)
#
# DATABASE: This stack uses infra-postgres on the CTI LXC.
# Run migrations AFTER this script:
#   See docs/N8N_CONFIGURATION.md Step 4
#
# FLOWISE: Installed separately via Proxmox helper script.
#   See docs/FLOWISE_SETUP.md
#
# SEARXNG: Deployed as a separate Dockge stack.
#   See docs/SEARXNG_SETUP.md
# =============================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$BASEDIR/.env"

log()  { echo -e "${GREEN}[setup]${RESET} $*"; }
warn() { echo -e "${YELLOW}[warn]${RESET} $*"; }
err()  { echo -e "${RED}[error]${RESET} $*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo bash setup.sh"
    exit 1
  fi
}

check_proxmox_lxc() {
  if grep -q 'container=lxc' /proc/1/environ 2>/dev/null || [ -f /run/container_type ]; then
    log "Proxmox LXC detected."
    if ! grep -q 'nesting=1' /proc/mounts 2>/dev/null; then
      warn "LXC nesting may not be enabled. If Docker fails:"
      warn "  pct set <CTID> --features nesting=1  (on Proxmox host)"
    fi
  fi
}

install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  log "Docker installed."
}

generate_secrets() {
  log "Generating secrets..."
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  SEARXNG_SECRET_KEY=$(openssl rand -hex 32)
  log "Secrets generated."
}

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local secret="${4:-false}"

  if [[ -n "$default" ]]; then
    echo -en "${CYAN}${prompt_text}${RESET} [${default}]: "
  else
    echo -en "${CYAN}${prompt_text}${RESET}: "
  fi

  if [[ "$secret" == "true" ]]; then
    read -rs value; echo
  else
    read -r value
  fi

  [[ -z "$value" && -n "$default" ]] && value="$default"
  printf -v "$var_name" '%s' "$value"
}

collect_inputs() {
  echo -e "\n${BOLD}=== n8n-ecosystem-unified Setup ===${RESET}\n"
  echo -e "This script sets up the n8n LXC stack."
  echo -e "You will need your CTI LXC IP and n8n DB password from infra/.env.\n"

  prompt N8N_HOST       "n8n hostname (e.g. n8n.lab.local)"        "n8n.lab.local"
  prompt N8N_PROTOCOL   "Protocol (http or https)"                  "http"
  prompt TIMEZONE       "Timezone"                                  "America/Chicago"

  echo -e "\n${BOLD}--- CTI LXC Database ---${RESET}"
  prompt CTI_LXC_IP     "CTI LXC IP address (infra-postgres host)"
  prompt N8N_DB_PASSWORD "n8n database password (from infra/.env)" "" true

  echo -e "\n${BOLD}--- Messaging ---${RESET}"
  prompt TELEGRAM_BOT_TOKEN  "Telegram Bot Token"  "" true
  prompt TELEGRAM_CHAT_ID    "Telegram Chat ID"
  prompt EVOLUTION_API_URL       "Evolution API URL (leave blank to skip)"          ""
  prompt EVOLUTION_API_KEY       "Evolution API Key (leave blank to skip)"          "" true
  prompt EVOLUTION_INSTANCE_NAME "Evolution instance name (leave blank to skip)"    ""

  echo -e "\n${BOLD}--- LLM Providers (add more in n8n UI after setup) ---${RESET}"
  prompt OPENROUTER_API_KEY  "OpenRouter API Key (recommended gateway)" "" true
  prompt ANTHROPIC_API_KEY   "Anthropic API Key (optional)"             "" true
  prompt GOOGLE_AI_API_KEY   "Google Gemini API Key (optional)"         "" true
  prompt OLLAMA_URL          "Ollama URL (e.g. http://192.168.x.x:11434, leave blank to skip)" ""

  echo -e "\n${BOLD}--- CTI Platform URLs (configure credentials in n8n UI after setup) ---${RESET}"
  prompt MISP_URL     "MISP URL (e.g. https://misp.lab.local)"     ""
  prompt OPENCTI_URL  "OpenCTI URL"                                 ""
  prompt THEHIVE_URL  "TheHive URL"                                 ""
  prompt CORTEX_URL   "Cortex URL"                                  ""
  prompt WAZUH_URL    "Wazuh URL"                                   ""
  prompt FLOWISE_URL  "Flowise URL (e.g. https://flowise.lab.local)" ""
}

write_env() {
  log "Writing .env..."
  cat > "$ENV_FILE" <<EOF
# Generated by setup.sh on $(date)
# DO NOT commit this file — it is listed in .gitignore

# ── n8n Core ─────────────────────────────────────────────────
N8N_HOST=${N8N_HOST}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_WEBHOOK_URL=${N8N_PROTOCOL}://${N8N_HOST}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
TIMEZONE=${TIMEZONE}

# ── Database (infra-postgres on CTI LXC) ─────────────────────
CTI_LXC_IP=${CTI_LXC_IP}
N8N_DB_PASSWORD=${N8N_DB_PASSWORD}

# ── PostgREST (set same value as in infra/.env) ───────────────
POSTGREST_URL=http://postgrest.lab.local
# Generate: openssl rand -hex 32
N8N_POSTGREST_JWT_SECRET=

# ── Messaging ────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
EVOLUTION_API_URL=${EVOLUTION_API_URL:-}
EVOLUTION_API_KEY=${EVOLUTION_API_KEY:-}
EVOLUTION_INSTANCE_NAME=${EVOLUTION_INSTANCE_NAME:-}

# ── LLM Providers ────────────────────────────────────────────
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_AI_API_KEY=${GOOGLE_AI_API_KEY:-}
OLLAMA_URL=${OLLAMA_URL:-}

# ── CTI Platform URLs ─────────────────────────────────────────
MISP_URL=${MISP_URL:-}
OPENCTI_URL=${OPENCTI_URL:-}
THEHIVE_URL=${THEHIVE_URL:-}
CORTEX_URL=${CORTEX_URL:-}
WAZUH_URL=${WAZUH_URL:-}
FLOWISE_URL=${FLOWISE_URL:-}
SEARXNG_URL=http://searxng.lab.local

# ── SearXNG ───────────────────────────────────────────────────
SEARXNG_SECRET_KEY=${SEARXNG_SECRET_KEY}

# ── Credential names (must match n8n credential names exactly) ─
N8N_CREDENTIAL_TELEGRAM=Telegram Bot
N8N_CREDENTIAL_OPENROUTER=OpenRouter
N8N_CREDENTIAL_ANTHROPIC=Anthropic API
N8N_CREDENTIAL_GOOGLE=Google Gemini
N8N_CREDENTIAL_OLLAMA=Ollama Local
N8N_CREDENTIAL_POSTGRES=n8n Postgres
N8N_CREDENTIAL_FLOWISE=Flowise API
EOF
  chmod 600 "$ENV_FILE"
  log ".env written to $ENV_FILE"
}

update_searxng_settings() {
  local settings="$BASEDIR/searxng/settings.yml"
  if [ -f "$settings" ]; then
    sed -i "s|REPLACE_WITH_openssl_rand_hex_32|${SEARXNG_SECRET_KEY}|g" "$settings"
    log "SearXNG settings.yml updated with generated secret key."
  else
    warn "searxng/settings.yml not found — SearXNG secret key not injected."
    warn "Deploy SearXNG separately: see docs/SEARXNG_SETUP.md"
  fi
}

start_stack() {
  log "Starting n8n Docker stack..."
  cd "$BASEDIR"
  docker compose pull --quiet
  docker compose up -d
  log "Stack started. Waiting for n8n..."
  local retries=30
  while ! curl -sf http://localhost:5678/healthz &>/dev/null; do
    sleep 3
    retries=$((retries-1))
    [[ $retries -le 0 ]] && { warn "n8n not responding after 90s. Check: docker compose logs n8n"; break; }
  done
  log "n8n is up."
}

print_next_steps() {
  echo -e "\n${BOLD}${GREEN}=== Setup Complete ===${RESET}\n"
  echo -e "  n8n:  ${CYAN}http://${N8N_HOST}:5678${RESET} (or via Caddy: ${N8N_PROTOCOL}://${N8N_HOST})"
  echo -e ""
  echo -e "${BOLD}Required next steps:${RESET}"
  echo -e "  1. Add Caddy routes for n8n.lab.local — see docs/CADDY_ROUTES.md"
  echo -e "  2. Add DNS CNAMEs in UniFi — see docs/CADDY_ROUTES.md"
  echo -e "  3. Run DB migrations against infra-postgres — see docs/N8N_CONFIGURATION.md Step 4"
  echo -e "  4. Open n8n and complete first-boot setup"
  echo -e "  5. Set n8n Variables and Credentials — see docs/N8N_CONFIGURATION.md"
  echo -e "  6. Import workflows from workflows/unified/"
  echo -e "  7. Install Flowise on its own LXC — see docs/FLOWISE_SETUP.md"
  echo -e "  8. Deploy SearXNG stack — see docs/SEARXNG_SETUP.md"
  echo -e ""
  echo -e "${BOLD}Full docs:${RESET} docs/"
}

main() {
  require_root
  check_proxmox_lxc
  collect_inputs
  generate_secrets
  write_env
  update_searxng_settings
  install_docker
  start_stack
  print_next_steps
}

main "$@"
