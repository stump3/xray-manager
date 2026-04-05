_cleanup() { [[ ${#_TMPFILES[@]} -gt 0 ]] && rm -f "${_TMPFILES[@]}" 2>/dev/null || true; }
trap _cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────────
#  ВЕРСИЯ
# ──────────────────────────────────────────────────────────────────────────────
MANAGER_VERSION="3.0.5"

# ──────────────────────────────────────────────────────────────────────────────
#  ПУТИ
# ──────────────────────────────────────────────────────────────────────────────
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_KEYS_DIR="/usr/local/etc/xray"
XRAY_DAT="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
LIMITS_FILE="/usr/local/etc/xray/.limits.json"
MANAGER_BIN="/usr/local/bin/xray-manager"
BACKUP_DIR="/root/xray-backups"
STATS_PORT=10085

# ──────────────────────────────────────────────────────────────────────────────
#  ЦВЕТА
# ──────────────────────────────────────────────────────────────────────────────
R="\e[0m"
BOLD="\e[1m"; DIM="\e[2m"
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"
BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"
WHITE="\e[37m"; GRAY="\e[38;5;240m"; LIGHT="\e[38;5;252m"
ORANGE="\e[38;5;208m"; PINK="\e[38;5;213m"

