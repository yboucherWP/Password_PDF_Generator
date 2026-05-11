#!/usr/bin/env bash
set -euo pipefail

APP_NAME="password-pdf-generator"
SERVICE_NAME="${PASSWORD_PDF_SERVICE_NAME:-${SERVICE_NAME:-password-pdf-generator}}"
SERVICE_USER="${PASSWORD_PDF_SERVICE_USER:-${SERVICE_USER:-passwordpdf}}"
SERVICE_ROOT="${PASSWORD_PDF_SERVICE_ROOT:-${SERVICE_ROOT:-/opt/services/${APP_NAME}}}"
APP_DIR="${PASSWORD_PDF_APP_DIR:-${APP_DIR:-${SERVICE_ROOT}/app}}"
VENV_DIR="${PASSWORD_PDF_VENV_DIR:-${VENV_DIR:-${SERVICE_ROOT}/.venv}}"
CONFIG_DIR="${PASSWORD_PDF_CONFIG_DIR:-${CONFIG_DIR:-${SERVICE_ROOT}/config}}"
DATA_DIR="${PASSWORD_PDF_DATA_DIR:-${DATA_DIR:-${SERVICE_ROOT}/data}}"
LOG_DIR="${PASSWORD_PDF_LOG_DIR:-${LOG_DIR:-${SERVICE_ROOT}/logs}}"
CONFIG_PATH="${PASSWORD_PDF_CONFIG_PATH:-${CONFIG_PATH:-${CONFIG_DIR}/brand_settings.json}}"
ENV_FILE="${PASSWORD_PDF_ENV_FILE:-${ENV_FILE:-${CONFIG_DIR}/${APP_NAME}.env}}"
META_FILE="${PASSWORD_PDF_META_FILE:-${META_FILE:-${CONFIG_DIR}/install-meta.env}}"
REPO_URL="${PASSWORD_PDF_REPO_URL:-${REPO_URL:-https://github.com/yboucherWP/Password_PDF_Generator.git}}"
REPO_REF="${PASSWORD_PDF_REPO_REF:-${REPO_REF:-main}}"
PORT="${PASSWORD_PDF_PORT:-${PORT:-8000}}"
HOST="${PASSWORD_PDF_HOST:-${HOST:-}}"
API_KEY="${PASSWORD_PDF_API_KEY:-${WIFI_PDF_API_KEY:-}}"
ENABLE_WORKDRIVE="${PASSWORD_PDF_ENABLE_WORKDRIVE:-}"
ZOHO_REGION="${PASSWORD_PDF_ZOHO_REGION:-com}"
UFW_MODE="${PASSWORD_PDF_CONFIGURE_UFW:-auto}"
INSTALL_OWNER="${PASSWORD_PDF_INSTALL_OWNER:-${SUDO_USER:-$(id -un)}}"
INSTALL_OWNER_HOME="${PASSWORD_PDF_OWNER_HOME:-}"
PATHS_FILE="${PASSWORD_PDF_PATHS_FILE:-${CONFIG_DIR}/paths.txt}"
CADDY_FILE="${PASSWORD_PDF_CADDY_FILE:-${CADDY_FILE:-/etc/caddy/conf.d/webhooks.caddy}}"
CADDY_ROUTES_DIR="${PASSWORD_PDF_CADDY_ROUTES_DIR:-${CADDY_ROUTES_DIR:-/etc/caddy/conf.d/webhooks.routes}}"
CADDY_ROUTE_FILE="${PASSWORD_PDF_CADDY_ROUTE_FILE:-${CADDY_ROUTE_FILE:-${CADDY_ROUTES_DIR}/${SERVICE_NAME}.caddy}}"
LEGACY_APP_DIR="${PASSWORD_PDF_LEGACY_APP_DIR:-/opt/password-pdf-generator}"
LEGACY_DATA_DIR="${PASSWORD_PDF_LEGACY_DATA_DIR:-/var/lib/password-pdf-generator}"
LEGACY_CONFIG_PATH="${PASSWORD_PDF_LEGACY_CONFIG_PATH:-/etc/password-pdf-generator/brand_settings.json}"
LEGACY_ENV_FILE="${PASSWORD_PDF_LEGACY_ENV_FILE:-/etc/password-pdf-generator.env}"
API_KEY_SOURCE=""
GENERATED_API_KEY=""

log() {
  printf '[%s] %s\n' "${APP_NAME}" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "${APP_NAME}" "$*" >&2
  exit 1
}

generate_secret() {
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
}

read_env_value_from_file() {
  local file_path="$1"
  local key_name="$2"

  if [[ ! -f "$file_path" ]]; then
    return 1
  fi

  python3 - "$file_path" "$key_name" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
for raw_line in path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    current_key, value = line.split("=", 1)
    if current_key.strip() == key:
        print(value.strip())
        raise SystemExit(0)
raise SystemExit(1)
PY
}

initialize_context() {
  if [[ -z "$INSTALL_OWNER_HOME" ]]; then
    if command -v getent >/dev/null 2>&1; then
      INSTALL_OWNER_HOME="$(getent passwd "$INSTALL_OWNER" | cut -d: -f6 || true)"
    fi
    if [[ -z "$INSTALL_OWNER_HOME" ]]; then
      if [[ "$INSTALL_OWNER" == "root" ]]; then
        INSTALL_OWNER_HOME="/root"
      else
        INSTALL_OWNER_HOME="/home/${INSTALL_OWNER}"
      fi
    fi
  fi
}

prompt() {
  local var_name="$1"
  local message="$2"
  local secret="${3:-false}"
  local default_value="${4:-}"
  local current_value="${!var_name:-}"

  if [[ -n "${current_value}" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    printf -v "$var_name" '%s' "$default_value"
    return
  fi

  local answer
  if [[ "$secret" == "true" ]]; then
    if [[ -n "$default_value" ]]; then
      read -r -s -p "${message} [press Enter to use generated value]: " answer
      printf '\n'
      printf -v "$var_name" '%s' "${answer:-$default_value}"
    else
      read -r -s -p "${message}: " answer
      printf '\n'
      printf -v "$var_name" '%s' "$answer"
    fi
  else
    if [[ -n "$default_value" ]]; then
      read -r -p "${message} [${default_value}]: " answer
      printf -v "$var_name" '%s' "${answer:-$default_value}"
    else
      read -r -p "${message}: " answer
      printf -v "$var_name" '%s' "$answer"
    fi
  fi
}

prompt_yes_no() {
  local var_name="$1"
  local message="$2"
  local default_value="${3:-false}"
  local current_value="${!var_name:-}"

  if [[ -n "$current_value" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    printf -v "$var_name" '%s' "$default_value"
    return
  fi

  local suffix="y/N"
  if [[ "$default_value" == "true" ]]; then
    suffix="Y/n"
  fi

  local answer
  read -r -p "${message} [${suffix}]: " answer
  answer="${answer,,}"
  case "$answer" in
    y|yes) printf -v "$var_name" '%s' "true" ;;
    n|no) printf -v "$var_name" '%s' "false" ;;
    "") printf -v "$var_name" '%s' "$default_value" ;;
    *) fail "Invalid response for ${message}" ;;
  esac
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this installer as root. Example: sudo bash <(curl -fsSL https://raw.githubusercontent.com/yboucherWP/Password_PDF_Generator/main/install.sh)"
  fi
}

ensure_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y git curl ca-certificates openssl python3 python3-venv python3-pip caddy ufw
}

ensure_user_and_dirs() {
  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$SERVICE_ROOT" --shell /usr/sbin/nologin "$SERVICE_USER"
  fi

  mkdir -p "$SERVICE_ROOT" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR" "$LOG_DIR"
  chmod 755 "$SERVICE_ROOT" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi
  return 1
}

select_service_port() {
  local preferred_port="$1"
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  local chosen_port="$preferred_port"

  if [[ -f "$service_file" ]] && grep -Fq -- "--port ${preferred_port}" "$service_file"; then
    PORT="$preferred_port"
    return
  fi

  while port_in_use "$chosen_port"; do
    chosen_port="$((chosen_port + 1))"
  done

  if [[ "$chosen_port" != "$preferred_port" ]]; then
    log "Port ${preferred_port} is already in use. Using ${chosen_port} instead."
  fi

  PORT="$chosen_port"
}

migrate_legacy_layout() {
  if [[ ! -f "$CONFIG_PATH" && -f "$LEGACY_CONFIG_PATH" ]]; then
    log "Migrating legacy config from ${LEGACY_CONFIG_PATH}"
    cp "$LEGACY_CONFIG_PATH" "$CONFIG_PATH"
  fi

  if [[ ! -f "$ENV_FILE" && -f "$LEGACY_ENV_FILE" ]]; then
    log "Migrating legacy env file from ${LEGACY_ENV_FILE}"
    cp "$LEGACY_ENV_FILE" "$ENV_FILE"
  fi

  if [[ -d "$LEGACY_DATA_DIR" ]] && [[ -z "$(find "$DATA_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    log "Migrating legacy data from ${LEGACY_DATA_DIR}"
    cp -a "${LEGACY_DATA_DIR}/." "$DATA_DIR/"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
  fi
}

prepare_api_key() {
  local current_key=""

  if [[ -n "$API_KEY" ]]; then
    API_KEY_SOURCE="provided"
    return
  fi

  if current_key="$(read_env_value_from_file "$ENV_FILE" "WIFI_PDF_API_KEY" 2>/dev/null)"; then
    API_KEY="$current_key"
    API_KEY_SOURCE="existing"
    return
  fi

  if current_key="$(read_env_value_from_file "$LEGACY_ENV_FILE" "WIFI_PDF_API_KEY" 2>/dev/null)"; then
    API_KEY="$current_key"
    API_KEY_SOURCE="existing"
    return
  fi

  API_KEY="$(generate_secret)"
  GENERATED_API_KEY="$API_KEY"
  API_KEY_SOURCE="generated"
}

sync_repo() {
  mkdir -p "$(dirname "$APP_DIR")"
  if [[ -d "${APP_DIR}/.git" ]]; then
    log "Updating existing repo in ${APP_DIR}"
    git config --global --add safe.directory "${APP_DIR}"
    git -C "$APP_DIR" fetch --prune origin
    git -C "$APP_DIR" checkout "$REPO_REF"
    git -C "$APP_DIR" reset --hard "origin/${REPO_REF}"
  else
    log "Cloning repo into ${APP_DIR}"
    rm -rf "$APP_DIR"
    git clone --branch "$REPO_REF" "$REPO_URL" "$APP_DIR"
  fi
}

install_python_deps() {
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" "$VENV_DIR"
}

configure_runtime_json() {
  local workdrive_api_base
  local workdrive_accounts_base
  local crm_api_base

  case "$ZOHO_REGION" in
    com)
      workdrive_api_base="https://www.zohoapis.com/workdrive/api/v1"
      workdrive_accounts_base="https://accounts.zoho.com/oauth/v2/token"
      crm_api_base="https://www.zohoapis.com/crm/v7"
      ;;
    eu)
      workdrive_api_base="https://www.zohoapis.eu/workdrive/api/v1"
      workdrive_accounts_base="https://accounts.zoho.eu/oauth/v2/token"
      crm_api_base="https://www.zohoapis.eu/crm/v7"
      ;;
    in)
      workdrive_api_base="https://www.zohoapis.in/workdrive/api/v1"
      workdrive_accounts_base="https://accounts.zoho.in/oauth/v2/token"
      crm_api_base="https://www.zohoapis.in/crm/v7"
      ;;
    com.au)
      workdrive_api_base="https://www.zohoapis.com.au/workdrive/api/v1"
      workdrive_accounts_base="https://accounts.zoho.com.au/oauth/v2/token"
      crm_api_base="https://www.zohoapis.com.au/crm/v7"
      ;;
    *)
      fail "Unsupported PASSWORD_PDF_ZOHO_REGION: ${ZOHO_REGION}"
      ;;
  esac

  if [[ ! -f "$CONFIG_PATH" ]]; then
    cp "${APP_DIR}/config/wifi_pdf/brand_settings.json" "$CONFIG_PATH"
  fi

  DATA_OUTPUT_DIR="${DATA_DIR}/output/pdf/wifi" \
  CONFIG_PATH="$CONFIG_PATH" \
  WORKDRIVE_ENABLED="$ENABLE_WORKDRIVE" \
  WORKDRIVE_API_BASE="$workdrive_api_base" \
  WORKDRIVE_ACCOUNTS_BASE="$workdrive_accounts_base" \
  CRM_API_BASE="$crm_api_base" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ["CONFIG_PATH"])
data = json.loads(config_path.read_text(encoding="utf-8"))
data["output"]["root_dir"] = os.environ["DATA_OUTPUT_DIR"]
data["workdrive"]["enabled"] = os.environ["WORKDRIVE_ENABLED"].lower() == "true"
data["workdrive"]["api_base_url"] = os.environ["WORKDRIVE_API_BASE"]
data["workdrive"]["accounts_base_url"] = os.environ["WORKDRIVE_ACCOUNTS_BASE"]
data.setdefault("crm", {})
data["crm"]["api_base_url"] = os.environ["CRM_API_BASE"]
data["workdrive"].pop("parent_folder_id", None)
config_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  chmod 644 "$CONFIG_PATH"
}

write_env_file() {
  ENV_FILE="$ENV_FILE" \
  WIFI_PDF_API_KEY="$API_KEY" \
  ZOHO_WORKDRIVE_CLIENT_ID="${ZOHO_WORKDRIVE_CLIENT_ID:-}" \
  ZOHO_WORKDRIVE_CLIENT_SECRET="${ZOHO_WORKDRIVE_CLIENT_SECRET:-}" \
  ZOHO_WORKDRIVE_REFRESH_TOKEN="${ZOHO_WORKDRIVE_REFRESH_TOKEN:-}" \
  python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["ENV_FILE"])
existing = {}
if path.exists():
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        existing[key] = value

ordered_keys = [
    "WIFI_PDF_API_KEY",
    "ZOHO_WORKDRIVE_CLIENT_ID",
    "ZOHO_WORKDRIVE_CLIENT_SECRET",
    "ZOHO_WORKDRIVE_REFRESH_TOKEN",
]

for key in ordered_keys:
    value = os.environ.get(key, "")
    if value:
        existing[key] = value
    elif key not in existing and key == "WIFI_PDF_API_KEY":
        existing[key] = value

lines = []
for key in ordered_keys:
    lines.append(f"{key}={existing.get(key, '')}")

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"
}

write_install_metadata() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'SERVICE_NAME=%q\n' "$SERVICE_NAME"
    printf 'SERVICE_USER=%q\n' "$SERVICE_USER"
    printf 'INSTALL_OWNER=%q\n' "$INSTALL_OWNER"
    printf 'SERVICE_ROOT=%q\n' "$SERVICE_ROOT"
    printf 'APP_DIR=%q\n' "$APP_DIR"
    printf 'VENV_DIR=%q\n' "$VENV_DIR"
    printf 'DATA_DIR=%q\n' "$DATA_DIR"
    printf 'LOG_DIR=%q\n' "$LOG_DIR"
    printf 'CONFIG_DIR=%q\n' "$CONFIG_DIR"
    printf 'CONFIG_PATH=%q\n' "$CONFIG_PATH"
    printf 'ENV_FILE=%q\n' "$ENV_FILE"
    printf 'META_FILE=%q\n' "$META_FILE"
    printf 'PATHS_FILE=%q\n' "$PATHS_FILE"
    printf 'CADDY_FILE=%q\n' "$CADDY_FILE"
    printf 'CADDY_ROUTES_DIR=%q\n' "$CADDY_ROUTES_DIR"
    printf 'CADDY_ROUTE_FILE=%q\n' "$CADDY_ROUTE_FILE"
    printf 'HOST=%q\n' "$HOST"
    printf 'PORT=%q\n' "$PORT"
    printf 'REPO_REF=%q\n' "$REPO_REF"
  } >"$META_FILE"
  chmod 644 "$META_FILE"
}

write_paths_file() {
  mkdir -p "$(dirname "$PATHS_FILE")"
  {
    printf '%s  # service root\n' "$SERVICE_ROOT"
    printf '%s  # application code\n' "$APP_DIR"
    printf '%s  # Python virtualenv\n' "$VENV_DIR"
    printf '%s  # runtime config directory\n' "$CONFIG_DIR"
    printf '%s  # active JSON config\n' "$CONFIG_PATH"
    printf '%s  # secrets environment file\n' "$ENV_FILE"
    printf '%s  # systemd service file\n' "/etc/systemd/system/${SERVICE_NAME}.service"
    printf '%s  # service data root\n' "$DATA_DIR"
    printf '%s  # generated PDFs, manifests, QR images, and jobs\n' "${DATA_DIR}/output/pdf/wifi"
    printf '%s  # application logs\n' "$LOG_DIR"
    printf '%s  # rotating application log file\n' "${LOG_DIR}/wifi_pdf.log"
    printf '%s  # local update script\n' "${APP_DIR}/update.sh"
    if [[ -n "$HOST" ]]; then
      printf '%s  # shared Caddy site config\n' "$CADDY_FILE"
      printf '%s  # per-app Caddy route snippets\n' "$CADDY_ROUTES_DIR"
      printf '%s  # this service Caddy route snippet\n' "$CADDY_ROUTE_FILE"
    fi
  } >"$PATHS_FILE"

  if id -u "$INSTALL_OWNER" >/dev/null 2>&1; then
    chown "$INSTALL_OWNER:$INSTALL_OWNER" "$PATHS_FILE" || true
  fi
}

report_secret_follow_up() {
  local missing=()

  if [[ "$ENABLE_WORKDRIVE" == "true" ]]; then
    [[ -z "${ZOHO_WORKDRIVE_CLIENT_ID:-}" ]] && missing+=("ZOHO_WORKDRIVE_CLIENT_ID")
    [[ -z "${ZOHO_WORKDRIVE_CLIENT_SECRET:-}" ]] && missing+=("ZOHO_WORKDRIVE_CLIENT_SECRET")
    [[ -z "${ZOHO_WORKDRIVE_REFRESH_TOKEN:-}" ]] && missing+=("ZOHO_WORKDRIVE_REFRESH_TOKEN")
  fi

  if [[ "${#missing[@]}" -gt 0 ]]; then
    log "Open ${ENV_FILE} and fill in these values:"
    for key in "${missing[@]}"; do
      log "  - ${key}"
    done
    log "Then restart the service:"
    log "  sudo systemctl restart ${SERVICE_NAME}"
  else
    log "Secrets file is populated: ${ENV_FILE}"
  fi

  case "$API_KEY_SOURCE" in
    generated)
      log "Generated webhook API key. Copy this value now:"
      printf '%s\n' "$GENERATED_API_KEY"
      ;;
    existing)
      log "Existing webhook API key preserved in ${ENV_FILE}"
      ;;
    provided)
      log "Webhook API key stored from installer input in ${ENV_FILE}"
      ;;
  esac
}

write_service_file() {
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  cat >"$service_file" <<EOF
[Unit]
Description=Password PDF Generator API
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
Environment=WIFI_PDF_CONFIG_PATH=${CONFIG_PATH}
Environment=WIFI_PDF_LOG_DIR=${LOG_DIR}
Environment=PATH=${VENV_DIR}/bin
ExecStart=${VENV_DIR}/bin/uvicorn wifi_pdf.api:app --host 127.0.0.1 --port ${PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

configure_caddy() {
  if [[ -z "$HOST" ]]; then
    log "No hostname provided. Skipping Caddy configuration."
    return
  fi

  mkdir -p /etc/caddy/conf.d "$CADDY_ROUTES_DIR"
  if [[ ! -f /etc/caddy/Caddyfile ]] || grep -Fq '/usr/share/caddy' /etc/caddy/Caddyfile; then
    cat >/etc/caddy/Caddyfile <<'EOF'
import /etc/caddy/conf.d/*.caddy
EOF
  elif ! grep -Fq 'import /etc/caddy/conf.d/*.caddy' /etc/caddy/Caddyfile; then
    printf '\nimport /etc/caddy/conf.d/*.caddy\n' >> /etc/caddy/Caddyfile
  fi

  if [[ -f "$CADDY_FILE" ]]; then
    local existing_host
    existing_host="$(sed -n '1s/[[:space:]]*{[[:space:]]*$//p' "$CADDY_FILE" | head -n1)"
    if [[ -n "$existing_host" && "$existing_host" != "$HOST" ]]; then
      fail "Caddy host file ${CADDY_FILE} already targets '${existing_host}'. Reuse that hostname or update the file manually."
    fi
  fi

  cat >"$CADDY_FILE" <<EOF
${HOST} {
    import ${CADDY_ROUTES_DIR}/*.caddy
}
EOF

  cat >"$CADDY_ROUTE_FILE" <<EOF
handle_path /pdf/* {
    reverse_proxy 127.0.0.1:${PORT}
}

handle /webhooks/zoho/wifi-pdfs* {
    reverse_proxy 127.0.0.1:${PORT}
}
EOF

  caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null
  caddy fmt --overwrite "$CADDY_FILE" >/dev/null
  caddy fmt --overwrite "$CADDY_ROUTE_FILE" >/dev/null
  caddy validate --config /etc/caddy/Caddyfile
  systemctl enable --now caddy
  systemctl reload caddy
}

configure_ufw() {
  if [[ "$UFW_MODE" == "false" ]]; then
    log "Skipping UFW configuration."
    return
  fi

  ufw allow OpenSSH >/dev/null 2>&1 || true
  if [[ -n "$HOST" ]]; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi
  ufw --force enable >/dev/null 2>&1 || true
}

main() {
  require_root
  initialize_context

  prompt HOST "Public hostname for shared Caddy/HTTPS" false "$HOST"
  if [[ -z "${ENABLE_WORKDRIVE}" ]]; then
    ENABLE_WORKDRIVE="true"
  fi
  prompt_yes_no ENABLE_WORKDRIVE "Enable Zoho WorkDrive upload" true
  prompt ZOHO_REGION "Zoho region (com, eu, in, com.au)" false "$ZOHO_REGION"

  if [[ -z "${HOST// }" ]]; then
    fail "A public hostname is required. Set PASSWORD_PDF_HOST or enter one at the prompt."
  fi

  if [[ "$ENABLE_WORKDRIVE" == "true" ]]; then
    prompt ZOHO_WORKDRIVE_CLIENT_ID "Zoho WorkDrive client id"
    prompt ZOHO_WORKDRIVE_CLIENT_SECRET "Zoho WorkDrive client secret" true
    prompt ZOHO_WORKDRIVE_REFRESH_TOKEN "Zoho WorkDrive refresh token" true
  fi

  ensure_packages
  ensure_user_and_dirs
  migrate_legacy_layout
  prepare_api_key
  select_service_port "$PORT"
  sync_repo
  install_python_deps
  configure_runtime_json
  write_env_file
  write_install_metadata
  write_service_file
  configure_caddy
  configure_ufw
  write_paths_file

  log "Install complete."
  log "Service root: ${SERVICE_ROOT}"
  log "Code directory: ${APP_DIR}"
  log "Virtualenv: ${VENV_DIR}"
  log "Runtime config: ${CONFIG_PATH}"
  log "Secrets file: ${ENV_FILE}"
  log "Logs: ${LOG_DIR}"
  log "Service: ${SERVICE_NAME}"
  log "Path inventory: ${PATHS_FILE}"
  report_secret_follow_up
  log "Public PDF health check: https://${HOST}/pdf/health"
  log "Public PDF webhook: https://${HOST}/pdf/webhooks/zoho/wifi-pdfs"
  log "Legacy PDF webhook path still routed: https://${HOST}/webhooks/zoho/wifi-pdfs"
}

main "$@"
