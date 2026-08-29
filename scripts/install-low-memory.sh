#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOW_MEMORY_THRESHOLD_MB="${LOW_MEMORY_THRESHOLD_MB:-1200}"
FORCE_LOW_MEMORY="${COOLIFY_LOW_MEMORY:-auto}"

log() { printf '[coolify-low-memory] %s\n' "$*"; }
fail() { printf '[coolify-low-memory] ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this installer as root (for example: sudo bash scripts/install-low-memory.sh)."
fi

mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
[[ -n "${mem_kb}" ]] || fail "Could not detect total system memory."
mem_mb=$((mem_kb / 1024))

case "${FORCE_LOW_MEMORY,,}" in
  true|1|yes|on) low_memory=true ;;
  false|0|no|off) low_memory=false ;;
  auto) [[ ${mem_mb} -le ${LOW_MEMORY_THRESHOLD_MB} ]] && low_memory=true || low_memory=false ;;
  *) fail "COOLIFY_LOW_MEMORY must be auto, true, or false." ;;
esac

log "Detected ${mem_mb} MB RAM."
if [[ "${low_memory}" == true ]]; then
  log "Low-memory mode will be enabled (threshold: ${LOW_MEMORY_THRESHOLD_MB} MB)."
else
  log "RAM is above the low-memory threshold; standard Coolify install will be used."
fi

bash "${ROOT_DIR}/scripts/install.sh" "$@"

if [[ "${low_memory}" != true ]]; then
  exit 0
fi

SOURCE_DIR=/data/coolify/source
ENV_FILE="${SOURCE_DIR}/.env"
CUSTOM_COMPOSE="${SOURCE_DIR}/docker-compose.custom.yml"

[[ -d "${SOURCE_DIR}" ]] || fail "Coolify source directory was not created."
[[ -f "${ENV_FILE}" ]] || fail "Coolify .env file was not created."

install -m 0644 "${ROOT_DIR}/docker-compose.low-memory.yml" "${CUSTOM_COMPOSE}"

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
set_env HORIZON_MEMORY_LIMIT 48
set_env HORIZON_WORKER_MEMORY 96
set_env HORIZON_MAX_JOBS 100

log "Installed low-memory compose overlay and environment settings."
log "Restarting Coolify with the low-memory profile..."

docker compose \
  --env-file "${ENV_FILE}" \
  -f "${SOURCE_DIR}/docker-compose.yml" \
  -f "${SOURCE_DIR}/docker-compose.prod.yml" \
  -f "${CUSTOM_COMPOSE}" \
  up -d --remove-orphans

log "Low-memory Coolify installation complete."
log "For a 1 GB VPS, 1-2 GB of swap is strongly recommended."
