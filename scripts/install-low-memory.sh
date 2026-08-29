#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_URL="${COOLIFY_INSTALL_URL:-https://cdn.coollabs.io/coolify/install.sh}"
LOW_MEMORY_THRESHOLD_MB="${LOW_MEMORY_THRESHOLD_MB:-1200}"
FORCE_LOW_MEMORY="${COOLIFY_LOW_MEMORY:-auto}"
FORK_IMAGE="${COOLIFY_FORK_IMAGE:-ghcr.io/yopremium21/coolify:low-memory}"
SOURCE_DIR=/data/coolify/source
ENV_FILE="${SOURCE_DIR}/.env"
CUSTOM_COMPOSE="${SOURCE_DIR}/docker-compose.custom.yml"

log() { printf '[coolify-low-memory] %s\n' "$*"; }
fail() { printf '[coolify-low-memory] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run through sudo: curl -fsSL <url> | sudo bash"
command -v curl >/dev/null 2>&1 || fail "curl is required."

mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
[[ -n "${mem_kb}" ]] || fail "Could not detect system memory."
mem_mb=$((mem_kb / 1024))

case "${FORCE_LOW_MEMORY,,}" in
  true|1|yes|on) low_memory=true ;;
  false|0|no|off) low_memory=false ;;
  auto) [[ ${mem_mb} -le ${LOW_MEMORY_THRESHOLD_MB} ]] && low_memory=true || low_memory=false ;;
  *) fail "COOLIFY_LOW_MEMORY must be auto, true, or false." ;;
esac

log "Detected ${mem_mb} MB RAM."
if [[ "${low_memory}" != true ]]; then
  log "RAM is above the low-memory threshold. Running standard Coolify installer."
  exec bash < <(curl -fsSL "${INSTALL_URL}")
fi

log "Low-memory mode enabled."
log "Installing Coolify host prerequisites..."
curl -fsSL "${INSTALL_URL}" | AUTOUPDATE=false bash

[[ -f "${ENV_FILE}" ]] || fail "Coolify .env was not created at ${ENV_FILE}."
command -v docker >/dev/null 2>&1 || fail "Docker was not installed successfully."

log "Checking lightweight image: ${FORK_IMAGE}"
if ! docker pull "${FORK_IMAGE}"; then
  fail "Could not pull ${FORK_IMAGE}. Ensure the GHCR package exists and is public."
fi

cat > "${CUSTOM_COMPOSE}" <<YAML
services:
  coolify:
    image: ${FORK_IMAGE}
    environment:
      PHP_MEMORY_LIMIT: \${PHP_MEMORY_LIMIT:-192M}
      PHP_FPM_PM_CONTROL: \${PHP_FPM_PM_CONTROL:-ondemand}
      PHP_FPM_PM_MAX_CHILDREN: \${PHP_FPM_PM_MAX_CHILDREN:-2}
      PHP_FPM_PM_PROCESS_IDLE_TIMEOUT: \${PHP_FPM_PM_PROCESS_IDLE_TIMEOUT:-10s}
      HORIZON_BALANCE: \${HORIZON_BALANCE:-false}
      HORIZON_MIN_PROCESSES: \${HORIZON_MIN_PROCESSES:-1}
      HORIZON_MAX_PROCESSES: \${HORIZON_MAX_PROCESSES:-1}
      HORIZON_MEMORY_LIMIT: \${HORIZON_MEMORY_LIMIT:-48}
      HORIZON_WORKER_MEMORY: \${HORIZON_WORKER_MEMORY:-96}
      HORIZON_MAX_JOBS: \${HORIZON_MAX_JOBS:-100}
  postgres:
    command:
      - postgres
      - -c
      - shared_buffers=\${POSTGRES_SHARED_BUFFERS:-32MB}
      - -c
      - effective_cache_size=\${POSTGRES_EFFECTIVE_CACHE_SIZE:-128MB}
      - -c
      - work_mem=\${POSTGRES_WORK_MEM:-1MB}
      - -c
      - maintenance_work_mem=\${POSTGRES_MAINTENANCE_WORK_MEM:-16MB}
      - -c
      - max_connections=\${POSTGRES_MAX_CONNECTIONS:-30}
      - -c
      - jit=off
YAML

set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

set_env AUTOUPDATE false
set_env PHP_MEMORY_LIMIT 192M
set_env PHP_FPM_PM_CONTROL ondemand
set_env PHP_FPM_PM_MAX_CHILDREN 2
set_env PHP_FPM_PM_PROCESS_IDLE_TIMEOUT 10s
set_env HORIZON_BALANCE false
set_env HORIZON_MIN_PROCESSES 1
set_env HORIZON_MAX_PROCESSES 1
set_env HORIZON_MEMORY_LIMIT 48
set_env HORIZON_WORKER_MEMORY 96
set_env HORIZON_MAX_JOBS 100
set_env POSTGRES_SHARED_BUFFERS 32MB
set_env POSTGRES_EFFECTIVE_CACHE_SIZE 128MB
set_env POSTGRES_WORK_MEM 1MB
set_env POSTGRES_MAINTENANCE_WORK_MEM 16MB
set_env POSTGRES_MAX_CONNECTIONS 30

log "Starting the lightweight Coolify image..."
docker compose \
  --env-file "${ENV_FILE}" \
  -f "${SOURCE_DIR}/docker-compose.yml" \
  -f "${SOURCE_DIR}/docker-compose.prod.yml" \
  -f "${CUSTOM_COMPOSE}" \
  up -d --remove-orphans

log "Installed ${FORK_IMAGE}."
log "1-2 GB swap is strongly recommended on a 1 GB VPS."
