#!/usr/bin/env bash
set -Eeuo pipefail

OFFICIAL_INSTALL_URL="${COOLIFY_INSTALL_URL:-https://cdn.coollabs.io/coolify/install.sh}"
LOW_MEMORY_THRESHOLD_MB="${LOW_MEMORY_THRESHOLD_MB:-1200}"
FORCE_LOW_MEMORY="${COOLIFY_LOW_MEMORY:-auto}"
SOURCE_DIR="/data/coolify/source"
ENV_FILE="${SOURCE_DIR}/.env"
CUSTOM_COMPOSE="${SOURCE_DIR}/docker-compose.custom.yml"

log() { printf '[coolify-low-memory] %s\n' "$*"; }
fail() { printf '[coolify-low-memory] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run through sudo, e.g. curl -fsSL <url> | sudo bash"
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
if [[ "${low_memory}" == true ]]; then
  log "Low-memory mode enabled (threshold ${LOW_MEMORY_THRESHOLD_MB} MB)."
else
  log "Using standard Coolify settings."
fi

log "Running official Coolify installer..."
curl -fsSL "${OFFICIAL_INSTALL_URL}" | bash

[[ "${low_memory}" == true ]] || exit 0
[[ -f "${ENV_FILE}" ]] || fail "Coolify .env was not created at ${ENV_FILE}."

cat > "${CUSTOM_COMPOSE}" <<'YAML'
services:
  coolify:
    environment:
      PHP_MEMORY_LIMIT: ${PHP_MEMORY_LIMIT:-192M}
      PHP_FPM_PM_CONTROL: ${PHP_FPM_PM_CONTROL:-ondemand}
      PHP_FPM_PM_MAX_CHILDREN: ${PHP_FPM_PM_MAX_CHILDREN:-2}
      PHP_FPM_PM_PROCESS_IDLE_TIMEOUT: ${PHP_FPM_PM_PROCESS_IDLE_TIMEOUT:-10s}
      HORIZON_BALANCE: ${HORIZON_BALANCE:-false}
      HORIZON_MIN_PROCESSES: ${HORIZON_MIN_PROCESSES:-1}
      HORIZON_MAX_PROCESSES: ${HORIZON_MAX_PROCESSES:-1}
  postgres:
    command:
      - postgres
      - -c
      - shared_buffers=${POSTGRES_SHARED_BUFFERS:-32MB}
      - -c
      - effective_cache_size=${POSTGRES_EFFECTIVE_CACHE_SIZE:-128MB}
      - -c
      - work_mem=${POSTGRES_WORK_MEM:-1MB}
      - -c
      - maintenance_work_mem=${POSTGRES_MAINTENANCE_WORK_MEM:-16MB}
      - -c
      - max_connections=${POSTGRES_MAX_CONNECTIONS:-30}
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

set_env PHP_MEMORY_LIMIT 192M
set_env PHP_FPM_PM_CONTROL ondemand
set_env PHP_FPM_PM_MAX_CHILDREN 2
set_env PHP_FPM_PM_PROCESS_IDLE_TIMEOUT 10s
set_env HORIZON_BALANCE false
set_env HORIZON_MIN_PROCESSES 1
set_env HORIZON_MAX_PROCESSES 1
set_env POSTGRES_SHARED_BUFFERS 32MB
set_env POSTGRES_EFFECTIVE_CACHE_SIZE 128MB
set_env POSTGRES_WORK_MEM 1MB
set_env POSTGRES_MAINTENANCE_WORK_MEM 16MB
set_env POSTGRES_MAX_CONNECTIONS 30

log "Applying low-memory Docker Compose override..."
docker compose \
  --env-file "${ENV_FILE}" \
  -f "${SOURCE_DIR}/docker-compose.yml" \
  -f "${SOURCE_DIR}/docker-compose.prod.yml" \
  -f "${CUSTOM_COMPOSE}" \
  up -d --remove-orphans

log "Low-memory Coolify installation complete."
log "Recommended for a 1 GB VPS: configure 1-2 GB swap on the host."
