#!/usr/bin/env bash
# ==============================================================================
#  Xray Manager v2.0.0
#  Интерактивный менеджер Xray-core — установка, протоколы, пользователи
#  Автор: generated | Лицензия: MIT
# ==============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
#  ОЧИСТКА ВРЕМЕННЫХ ФАЙЛОВ ПРИ ВЫХОДЕ
# ──────────────────────────────────────────────────────────────────────────────
_TMPFILES=()
_cleanup() { [[ ${#_TMPFILES[@]} -gt 0 ]] && rm -f "${_TMPFILES[@]}" 2>/dev/null || true; }
trap _cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────────
#  ВЕРСИЯ
# ──────────────────────────────────────────────────────────────────────────────
MANAGER_VERSION="2.6.0"

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

# ──────────────────────────────────────────────────────────────────────────────
#  ВСПОМОГАТЕЛЬНЫЕ UI-ФУНКЦИИ
# ──────────────────────────────────────────────────────────────────────────────

tw() { tput cols 2>/dev/null || echo 80; }

cls() { printf "\e[2J\e[H"; }

box_top() {
    local title="$1" col="${2:-$CYAN}"
    local w; w=$(tw); local i=$((w-2))
    local tl=${#title}; local p=$(( (i - tl - 2) ))
    local pl=$(( p/2 )); local pr=$(( p - pl ))
    printf "${DIM}╭%s╮${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
    printf "${DIM}│${R} ${col}${BOLD}%*s%s%*s${R} ${DIM}│${R}\n" "$pl" "" "$title" "$pr" ""
    printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_end() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}╰%s╯${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_mid() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
}

box_row() {
    local text="$1"
    local w; w=$(tw); local i=$((w-2))
    local raw; raw=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local rl=${#raw}; local pad=$((i - rl - 2))
    [[ $pad -lt 0 ]] && pad=0
    printf "${DIM}│${R} %b%*s${DIM}│${R}\n" "$text" "$pad" ""
}

box_blank() {
    local w; w=$(tw); local i=$((w-2))
    printf "${DIM}│%*s│${R}\n" "$i" ""
}

mi() {
    # menu_item num icon label [badge]
    local n="$1" ic="$2" lb="$3" badge="${4:-}"
    local w; w=$(tw); local i=$((w-2))
    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    local used=$(( ${#n} + ${#raw_lb} + 8 ))
    local pad=$(( i - used - ${#badge} - 1 ))
    [[ $pad -lt 0 ]] && pad=0
    if [[ -n "$badge" ]]; then
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s %b%*s${DIM}%s │${R}\n" \
            "$n" "$ic" "$lb" "$pad" "" "$badge"
    else
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s %b%*s${DIM}│${R}\n" \
            "$n" "$ic" "$lb" "$pad" ""
    fi
}

ask() {
    local label="$1" var="$2" def="${3:-}"
    if [[ -n "$def" ]]; then
        printf "${DIM}│${R} ${CYAN}?${R} ${LIGHT}%s${R} ${DIM}[%s]${R}: " "$label" "$def"
    else
        printf "${DIM}│${R} ${CYAN}?${R} ${LIGHT}%s${R}: " "$label"
    fi
    local inp; read -r inp
    [[ -z "$inp" && -n "$def" ]] && inp="$def"
    printf -v "$var" '%s' "$inp"
}

confirm() {
    local msg="$1" def="${2:-n}"
    local pr="[y/N]"; [[ "$def" == "y" ]] && pr="[Y/n]"
    printf "${YELLOW}?${R} %s %s: " "$msg" "$pr"
    local a; read -r a; a="${a:-$def}"
    [[ "$a" =~ ^[Yy]$ ]]
}

pause() {
    printf "\n${DIM}%s${R}" "${1:-Нажмите Enter...}"
    read -r
}

ok()   { printf " ${GREEN}✓${R} %b\n" "$*"; }
err()  { printf " ${RED}✗${R} ${RED}%b${R}\n" "$*"; }
warn() { printf " ${YELLOW}⚠${R} %b\n" "$*"; }
info() { printf " ${BLUE}ℹ${R} %b\n" "$*"; }

spin_start() {
    printf "\r${CYAN}⠋${R} %s..." "$1"
    ( local f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") i=0
      while true; do
          printf "\r${CYAN}%s${R} %s..." "${f[$((i%10))]}" "$1"
          sleep 0.08; ((i++))
      done ) &
    _SPIN=$!
}
spin_stop() {
    [[ -n "${_SPIN:-}" ]] && { kill "$_SPIN" 2>/dev/null; wait "$_SPIN" 2>/dev/null || true; _SPIN=""; }
    if [[ "${1:-ok}" == "ok" ]]; then printf "\r${GREEN}✓${R} Готово!%-25s\n" ""
    else printf "\r${RED}✗${R} Ошибка!%-25s\n" ""; fi
}

hr() {
    local w; w=$(tw)
    printf "${DIM}%s${R}\n" "$(printf '%*s' "$w" | tr ' ' '─')"
}

# ──────────────────────────────────────────────────────────────────────────────
#  СИСТЕМНЫЕ ПРОВЕРКИ
# ──────────────────────────────────────────────────────────────────────────────

need_root() {
    [[ "$(id -u)" -eq 0 ]] || { err "Требуются права root: sudo bash $0"; exit 1; }
}

xray_ok()      { [[ -f "$XRAY_BIN" ]]; }
xray_active()  { systemctl is-active --quiet xray 2>/dev/null; }
xray_ver()     { xray_ok && "$XRAY_BIN" -version 2>/dev/null | awk 'NR==1{print $2}' || echo "—"; }
server_ip()    { timeout 3 curl -4 -s https://icanhazip.com 2>/dev/null || timeout 3 curl -4 -s https://api.ipify.org 2>/dev/null || echo "0.0.0.0"; }

# ──────────────────────────────────────────────────────────────────────────────
#  ЗАВИСИМОСТИ
# ──────────────────────────────────────────────────────────────────────────────

install_deps() {
    local need=()
    for p in curl unzip jq qrencode openssl uuid-runtime python3; do
        command -v "$p" &>/dev/null || need+=("$p")
    done
    [[ ${#need[@]} -eq 0 ]] && return
    info "Установка: ${need[*]}"
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq "${need[@]}" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
#  BBR
# ──────────────────────────────────────────────────────────────────────────────

enable_bbr() {
    local cur; cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [[ "$cur" == "bbr" ]]; then ok "BBR уже активен"; return; fi
    grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || {
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    }
    sysctl -p -q 2>/dev/null
    ok "BBR включён"
}

menu_bbr_tune() {
    cls; box_top " 🔧  Оптимизация сети (BBR + sysctl)" "$ORANGE"
    box_blank
    enable_bbr
    # Дополнительные оптимизации TCP
    local tune_file="/etc/sysctl.d/99-xray-tune.conf"
    if [[ ! -f "$tune_file" ]]; then
        cat > "$tune_file" << 'EOF'
# Xray Manager — оптимизация сети
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.tcp_rmem = 4096 87380 26214400
net.ipv4.tcp_wmem = 4096 65536 26214400
EOF
        sysctl -p "$tune_file" -q 2>/dev/null
        ok "TCP Fast Open + буферы оптимизированы"
    else
        ok "Оптимизации уже применены"
    fi
    box_blank
    box_row "  ${GREEN}Активный алгоритм:${R} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  УСТАНОВКА ЯДРА
# ──────────────────────────────────────────────────────────────────────────────

install_xray_core() {
    cls; box_top " 🔧  Установка / Обновление ядра Xray" "$GREEN"
    box_blank
    box_row "  Текущая версия: ${CYAN}$(xray_ver)${R}"
    box_blank; install_deps
    spin_start "Получение актуальной версии"
    local latest; latest=$(curl -sf "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | jq -r '.tag_name' 2>/dev/null || echo "")
    spin_stop "ok"
    [[ -z "$latest" ]] && { err "Не удалось получить версию с GitHub"; pause; return 1; }
    box_row "  Последняя версия: ${GREEN}${latest}${R}"
    local cur; cur=$(xray_ver)
    if [[ "$cur" == "${latest#v}" ]] && xray_ok; then
        box_blank
        box_row "  ${GREEN}Уже установлена актуальная версия!${R}"
        box_blank; box_mid
        mi "1" "🔄" "Переустановить принудительно"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        [[ "$ch" != "1" ]] && return 0
    fi
    box_blank; box_end
    spin_start "Установка Xray ${latest}"
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install --version "$latest" -f &>/tmp/xray_install.log
    local ec=$?
    spin_stop "$( [[ $ec -eq 0 ]] && echo ok || echo err )"
    if [[ $ec -ne 0 ]]; then err "Установка завершилась с ошибкой"; tail -10 /tmp/xray_install.log; pause; return 1; fi
    mkdir -p "$XRAY_CONF_DIR"
    _init_config
    enable_bbr
    _init_limits_file
    _enable_stats_api
    install_self
    cls; box_top " ✅  Установка завершена" "$GREEN"
    box_blank
    box_row "  ✓ Xray-core ${GREEN}${latest}${R} установлен"
    box_row "  ✓ BBR активирован"
    box_row "  ✓ Stats API включён"
    box_row "  ✓ Команда ${CYAN}xray-manager${R} доступна глобально"
    box_blank
    box_row "  ${YELLOW}Следующий шаг: добавьте протокол в разделе «Протоколы»${R}"
    box_blank; box_end; pause
}

install_self() {
    local me; me=$(realpath "$0" 2>/dev/null || echo "$0")
    [[ "$me" != "$MANAGER_BIN" ]] && { cp "$me" "$MANAGER_BIN"; chmod +x "$MANAGER_BIN"; }
}

_init_config() {
    [[ -f "$XRAY_CONF" ]] && return
    cat > "$XRAY_CONF" << 'JSON'
{
  "log": {"loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"},
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService", "HandlerService"]
  },
  "policy": {
    "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}},
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true}
  },
  "inbounds": [],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
      {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"}
    ]
  }
}
JSON
    mkdir -p "$XRAY_LOG_DIR"
    touch "$XRAY_LOG_DIR/access.log" "$XRAY_LOG_DIR/error.log"
}

_enable_stats_api() {
    # Добавить API inbound если нет
    local has_api; has_api=$(jq -r '.inbounds[] | select(.tag == "api") | .tag' "$XRAY_CONF" 2>/dev/null || echo "")
    if [[ -z "$has_api" ]]; then
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --argjson port "$STATS_PORT" \
            '.inbounds += [{"tag":"api","listen":"127.0.0.1","port":$port,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi
    # Убедиться что HandlerService включён (нужен для xray api adu/rmu)
    local has_handler; has_handler=$(jq -r '(.api.services // []) | map(select(. == "HandlerService")) | length' "$XRAY_CONF" 2>/dev/null || echo "0")
    if [[ "$has_handler" == "0" ]]; then
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq '.api.services |= (. // [] | if map(select(. == "HandlerService")) | length == 0 then . + ["HandlerService"] else . end)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  КЛЮЧИ ПРОТОКОЛОВ
# ──────────────────────────────────────────────────────────────────────────────

kfile()   { echo "${XRAY_KEYS_DIR}/.keys.${1}"; }
kset()    { local f; f=$(kfile "$1"); local _kt; _kt=$(mktemp); _TMPFILES+=("$_kt"); grep -v "^${2}:" "$f" 2>/dev/null > "$_kt" || true; echo "${2}: ${3}" >> "$_kt"; mv "$_kt" "$f"; }
kget()    { grep "^${2}:" "$(kfile "$1")" 2>/dev/null | cut -d' ' -f2-; }

# ──────────────────────────────────────────────────────────────────────────────
#  КОНФИГ HELPERS
# ──────────────────────────────────────────────────────────────────────────────

cfg()     { jq -r "$1" "$XRAY_CONF" 2>/dev/null; }
cfgw()    { local t; t=$(mktemp); _TMPFILES+=("$t"); jq "$1" "$XRAY_CONF" > "$t" && mv "$t" "$XRAY_CONF"; }
ib_exists() { [[ -n "$(jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.tag' "$XRAY_CONF" 2>/dev/null)" ]]; }
ib_list()   { jq -r '.inbounds[]|select(.tag!="api")|"\(.tag)|\(.port)|\(.protocol)|\(.streamSettings.network//"tcp")|\(.streamSettings.security//"none")"' "$XRAY_CONF" 2>/dev/null; }
ib_del()    { cfgw "del(.inbounds[]|select(.tag==\"$1\"))"; }
ib_proto()  { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.protocol' "$XRAY_CONF"; }
ib_net()    { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.streamSettings.network//"tcp"' "$XRAY_CONF"; }
ib_port()   { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.port' "$XRAY_CONF"; }
ib_emails() {
    # Returns emails from .settings.clients (most protocols) or .settings.users (hysteria)
    local tag="$1"
    jq -r --arg t "$tag" '
        .inbounds[]|select(.tag==$t)|
        ((.settings.clients//[]) + (.settings.users//[]))[].email
    ' "$XRAY_CONF" 2>/dev/null
}
ib_users_count() { jq --arg t "$1" '[.inbounds[]|select(.tag==$t)|(.settings.clients//empty,.settings.users//empty)[]?]|length' "$XRAY_CONF" 2>/dev/null || echo 0; }

ib_add() {
    local json="$1"; local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson ib "$json" '.inbounds += [$ib]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
}

xray_restart() { systemctl restart xray 2>/dev/null; sleep 1; xray_active; }
# Добавить пользователя в работающий Xray без перезапуска (gRPC API)
xray_api_add_user() {
    local tag="$1" client_json="$2" proto="$3" net="$4"
    # Hysteria использует settings.users, остальные — settings.clients
    local field="clients"
    [[ "${proto}:${net}" == "hysteria:hysteria" ]] && field="users"
    # Формируем минимальный inbound JSON для xray api adu
    local tmp; tmp=$(mktemp /tmp/xray-adu-XXXXXX.json); _TMPFILES+=("$tmp")
    local protocol; protocol=$(ib_proto "$tag")
    jq -n \
        --arg tag "$tag" --arg proto "$protocol" \
        --arg field "$field" --argjson user "$client_json" \
        '{"inbounds":[{"tag":$tag,"protocol":$proto,"settings":{($field):[$user]}}]}' \
        > "$tmp"
    "$XRAY_BIN" api adu \
        --server="127.0.0.1:${STATS_PORT}" \
        "$tmp" 2>/dev/null
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# Удалить пользователя из работающего Xray без перезапуска (gRPC API)
xray_api_del_user() {
    local tag="$1" email="$2"
    "$XRAY_BIN" api rmu \
        --server="127.0.0.1:${STATS_PORT}" \
        -tag="$tag" "$email" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
#  ЛИМИТЫ ПОЛЬЗОВАТЕЛЕЙ
# ──────────────────────────────────────────────────────────────────────────────

_init_limits_file() {
    [[ -f "$LIMITS_FILE" ]] || echo '{}' > "$LIMITS_FILE"
}

limit_set() {
    local tag="$1" email="$2" field="$3" value="$4"
    _init_limits_file
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" --arg f "$field" --arg v "$value" \
        '.[$t][$e][$f] = $v' "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
}

limit_get() {
    local tag="$1" email="$2" field="$3"
    jq -r --arg t "$tag" --arg e "$email" --arg f "$field" \
        '.[$t][$e][$f] // ""' "$LIMITS_FILE" 2>/dev/null
}

limit_del_user() {
    local tag="$1" email="$2"
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" 'del(.[$t][$e])' "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
}

# Получить трафик пользователя через Xray Stats API
get_user_traffic() {
    local email="$1" dir="${2:-uplink}"  # uplink | downlink
    local stat_name="user>>>${email}>>>traffic>>>${dir}"
    "$XRAY_BIN" api statsquery \
        --server="127.0.0.1:${STATS_PORT}" \
        -pattern "$stat_name" 2>/dev/null \
        | jq -r '.[0].value // "0"' 2>/dev/null || echo "0"
}

fmt_bytes() {
    local b="$1"
    if [[ "$b" -ge 1073741824 ]]; then printf "%.2f GB" "$(echo "scale=2; $b/1073741824" | bc)"
    elif [[ "$b" -ge 1048576 ]]; then printf "%.2f MB" "$(echo "scale=2; $b/1048576" | bc)"
    elif [[ "$b" -ge 1024 ]]; then printf "%.2f KB" "$(echo "scale=2; $b/1024" | bc)"
    else echo "${b} B"; fi
}

# Проверить и деактивировать истёкших пользователей
check_limits() {
    _init_limits_file
    local now; now=$(date +%s)
    local changed=0

    # Один батч-запрос вместо N×2 отдельных вызовов xray api statsquery
    local all_stats=""
    if xray_active; then
        all_stats=$("$XRAY_BIN" api statsquery \
            --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || true)
    fi

    # Получить трафик пользователя из заранее загруженного батча
    _traffic_from_batch() {
        local email="$1" dir="$2"
        echo "$all_stats" \
            | jq -r --arg n "user>>>${email}>>>traffic>>>${dir}" \
                '[.[] | select(.name == $n)] | .[0].value // "0"' \
              2>/dev/null || echo "0"
    }

    while IFS='|' read -r tag _ proto _ _; do
        local emails=()
        while IFS= read -r em; do emails+=("$em"); done < <(ib_emails "$tag")

        for email in "${emails[@]}"; do
            # Проверка даты
            local exp; exp=$(limit_get "$tag" "$email" "expire_ts")
            if [[ -n "$exp" && "$exp" != "null" && "$now" -gt "$exp" ]]; then
                _remove_user_from_tag "$tag" "$email"
                xray_api_del_user "$tag" "$email" 2>/dev/null || true
                warn "Пользователь $email@$tag: срок истёк — деактивирован"
                changed=1; continue
            fi
            # Проверка трафика
            local limit_bytes; limit_bytes=$(limit_get "$tag" "$email" "traffic_limit_bytes")
            if [[ -n "$limit_bytes" && "$limit_bytes" != "null" && "$limit_bytes" -gt 0 ]]; then
                local up; up=$(_traffic_from_batch "$email" "uplink")
                local dn; dn=$(_traffic_from_batch "$email" "downlink")
                local total=$(( up + dn ))
                if [[ "$total" -ge "$limit_bytes" ]]; then
                    _remove_user_from_tag "$tag" "$email"
                    xray_api_del_user "$tag" "$email" 2>/dev/null || true
                    warn "Пользователь $email@$tag: трафик исчерпан — деактивирован"
                    changed=1
                fi
            fi
        done
    done < <(ib_list)

    # changed-флаг уже не нужен для restart — API применил изменения горячо
    # Но если API не сработал (xray не активен), делаем restart
    [[ $changed -eq 1 ]] && ! xray_active && xray_restart || true
}

_remove_user_from_tag() {
    local tag="$1" email="$2"
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" \
        '(.inbounds[]|select(.tag==$t)|.settings.clients) |= (. // [] | map(select(.email!=$e))) | (.inbounds[]|select(.tag==$t)|.settings.users) |= (. // [] | map(select(.email!=$e)))' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
}

# Установить systemd timer для проверки лимитов
install_limits_timer() {
    cat > /etc/systemd/system/xray-limits.service << EOF
[Unit]
Description=Xray Manager: проверка лимитов пользователей

[Service]
Type=oneshot
ExecStart=$MANAGER_BIN --check-limits
EOF
    cat > /etc/systemd/system/xray-limits.timer << 'EOF'
[Unit]
Description=Xray Manager: проверка лимитов (каждые 5 минут)

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now xray-limits.timer 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
#  ГЕНЕРАЦИЯ ССЫЛОК
# ──────────────────────────────────────────────────────────────────────────────

urlencode() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"; }

gen_link() {
    local tag="$1" email="$2"
    local proto; proto=$(ib_proto "$tag")
    local net;   net=$(ib_net "$tag")
    local port;  port=$(ib_port "$tag")
    # IP принимаем тремя способами (приоритет по убыванию):
    #   1) явный $3 — вызывающий закешировал сам (локальный вызов)
    #   2) _CACHED_SERVER_IP — экспортированный родителем (_sub_all_links)
    #   3) server_ip() — одиночный вызов без кеша
    local sip="${3:-${_CACHED_SERVER_IP:-$(server_ip)}}"

    case "${proto}:${net}" in

      vless:tcp|vless:raw)  # VLESS + TCP + REALITY
        local uuid sni pbk sid
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey"); sid=$(kget "$tag" "shortId")
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=tcp&flow=xtls-rprx-vision&encryption=none#${email}"
        ;;

      vless:xhttp)  # VLESS + XHTTP + REALITY
        local uuid sni pbk sid path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
        sid=$(kget "$tag" "shortId"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&path=${ep}&mode=auto&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=xhttp&encryption=none#${email}"
        ;;

      vless:ws)  # VLESS + WS + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=ws&path=${ep}&host=${dom}&sni=${dom}&encryption=none#${email}"
        ;;

      vless:grpc)  # VLESS + gRPC + TLS
        local uuid dom svc
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); svc=$(kget "$tag" "serviceName")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=grpc&serviceName=${svc}&sni=${dom}&encryption=none#${email}"
        ;;

      vless:httpupgrade)  # VLESS + HTTPUpgrade + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=httpupgrade&path=${ep}&host=${dom}&sni=${dom}&encryption=none#${email}"
        ;;

      vmess:ws)  # VMess + WS + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        # VMess link format (base64 JSON)
        local vmess_json; vmess_json=$(jq -nc \
            --arg id "$uuid" --arg add "$dom" --argjson port "$port" \
            --arg path "$path_v" --arg host "$dom" --arg tls "tls" \
            '{"v":"2","ps":"'"$email"'","add":$add,"port":$port,"id":$id,"aid":0,"scy":"auto","net":"ws","type":"none","host":$host,"path":$path,"tls":$tls,"sni":$host,"alpn":""}')
        echo "vmess://$(echo -n "$vmess_json" | base64 -w0)"
        ;;

      vmess:tcp|vmess:raw)  # VMess + TCP + TLS
        local uuid dom
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        local vmess_json; vmess_json=$(jq -nc \
            --arg id "$uuid" --arg add "$dom" --argjson port "$port" \
            --arg tls "tls" \
            '{"v":"2","ps":"'"$email"'","add":$add,"port":$port,"id":$id,"aid":0,"scy":"auto","net":"tcp","type":"none","host":$add,"path":"/","tls":$tls,"sni":$add,"alpn":""}')
        echo "vmess://$(echo -n "$vmess_json" | base64 -w0)"
        ;;

      trojan:tcp|trojan:raw)  # Trojan + TCP + TLS
        local pass dom
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        echo "trojan://${pass}@${dom}:${port}?security=tls&sni=${dom}&type=tcp#${email}"
        ;;

      hysteria:hysteria)  # Hysteria2 нативный Xray
        local pass dom
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.users[]|select(.email==$e)|.password' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        echo "hy2://${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0#${email}"
        ;;

      shadowsocks:tcp|shadowsocks:raw)  # Shadowsocks 2022
        local pass method
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
        method=$(jq -r --arg t "$tag" \
            '.inbounds[]|select(.tag==$t)|.settings.method' "$XRAY_CONF")
        local sp; sp=$(kget "$tag" "serverPassword")
        # SS URI
        local userinfo; userinfo=$(echo -n "${method}:${sp}:${pass}" | base64 -w0)
        echo "ss://${userinfo}@${sip}:${port}#${email}"
        ;;

      vless:grpc_reality|vless:grpc-reality)  # VLESS + gRPC + REALITY
        local uuid sni pbk sid svc
        uuid=$(jq -r --arg t "$tag" --arg e "$email"             '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
        sid=$(kget "$tag" "shortId"); svc=$(kget "$tag" "serviceName")
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=grpc&serviceName=${svc}&encryption=none#${email}"
        ;;

      vless:splithttp)  # VLESS + SplitHTTP + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email"             '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=splithttp&path=${ep}&host=${dom}&sni=${dom}&encryption=none#${email}"
        ;;

      *)
        echo ""
        ;;
    esac
}

show_link_qr() {
    local tag="$1" email="$2"
    local link; link=$(gen_link "$tag" "$email")
    if [[ -z "$link" ]]; then warn "Не удалось сгенерировать ссылку для ${proto}+${net}"; return; fi
    cls; box_top " 🔗  Подключение: ${email}" "$CYAN"
    box_blank
    box_row "  ${CYAN}${BOLD}Ссылка:${R}"
    # Wrap long link across lines
    local w; w=$(tw); local chunk=$((w-6)); local i=0
    while [[ $i -lt ${#link} ]]; do
        box_row "  ${DIM}${link:$i:$chunk}${R}"
        i=$((i+chunk))
    done
    box_blank
    box_row "  ${YELLOW}QR-код:${R}"
    box_end
    echo ""
    echo "$link" | qrencode -t ansiutf8 2>/dev/null || warn "qrencode не найден"
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  ВЫБОР ИНБАУНДА
# ──────────────────────────────────────────────────────────────────────────────

pick_inbound() {
    local __var="$1"
    local tags=()
    while IFS='|' read -r t p pr n s; do tags+=("$t|$p|$pr|$n|$s"); done < <(ib_list)
    if [[ ${#tags[@]} -eq 0 ]]; then err "Нет настроенных протоколов"; return 1; fi
    if [[ ${#tags[@]} -eq 1 ]]; then
        IFS='|' read -r t _ _ _ _ <<< "${tags[0]}"
        printf -v "$__var" '%s' "$t"; return 0
    fi
    local i=1
    for e in "${tags[@]}"; do
        IFS='|' read -r t p pr n s <<< "$e"
        local uc; uc=$(ib_users_count "$t")
        mi "$i" "🔌" "${CYAN}${t}${R}" "  порт ${p} · ${uc} польз."
        ((i++))
    done
    read -rp "$(printf "${YELLOW}›${R} Протокол: ")" idx
    [[ "$idx" -ge 1 && "$idx" -le ${#tags[@]} ]] || return 1
    IFS='|' read -r t _ _ _ _ <<< "${tags[$((idx-1))]}"
    printf -v "$__var" '%s' "$t"; return 0
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + TCP + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_tcp_reality() {
    cls; box_top " 🌐  VLESS + TCP + REALITY" "$CYAN"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni tag
    ask "Порт" port "443"
    ask "SNI (камуфляжный домен)" sni "www.microsoft.com"
    ask "Тег (уникальный ID)" tag "vless-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    spin_start "Генерация ключей x25519"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | awk '/PrivateKey/{print $2}')
    local pub;  pub=$(echo "$kout" | awk '/PublicKey/{print $2}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid"; kset "$tag" sni "$sni"
    kset "$tag" port "$port"; kset "$tag" type "vless-reality"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":"xtls-rprx-vision"}],"decryption":"none"},
        "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
            "show":false,"target":($sni+":443"),"xver":0,
            "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + TCP + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_row "  ShortId:   ${DIM}${sid}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + XHTTP + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_xhttp_reality() {
    cls; box_top " ⚡  VLESS + XHTTP + REALITY" "$MAGENTA"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni path_v tag mode_v
    ask "Порт" port "443"
    ask "SNI" sni "www.microsoft.com"
    ask "Path" path_v "/"
    ask "Режим (auto/packet-up/stream-up/stream-one)" mode_v "auto"
    ask "Тег" tag "vless-xhttp"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    spin_start "Генерация ключей"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | awk '/PrivateKey/{print $2}')
    local pub;  pub=$(echo "$kout" | awk '/PublicKey/{print $2}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid"; kset "$tag" sni "$sni"
    kset "$tag" port "$port"; kset "$tag" path "$path_v"
    kset "$tag" type "vless-xhttp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" \
        --arg path "$path_v" --arg mode "$mode_v" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":""}],"decryption":"none"},
        "streamSettings":{"network":"xhttp","security":"reality",
            "xhttpSettings":{"path":$path,"mode":$mode},
            "realitySettings":{"show":false,"target":($sni+":443"),"xver":0,
                "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + XHTTP + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  Path: ${WHITE}${path_v}${R}  Режим: ${CYAN}${mode_v}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + WebSocket + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_ws_tls() {
    cls; box_top " ☁️  VLESS + WebSocket + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_row "  ${DIM}⚡ Рекомендуется перейти на XHTTP — WebSocket имеет заметный ALPN-отпечаток (http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт (Xray слушает)" port "8443"
    ask "Домен" dom ""
    ask "Path" path_v "/vless"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-ws"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-ws"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"ws","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "wsSettings":{"path":$path}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_row "  Path: ${WHITE}${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_tls() {
    cls; box_top " 🔄  VLESS + gRPC + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom svc tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "ServiceName" svc "xray"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-grpc"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" serviceName "$svc"; kset "$tag" type "vless-grpc"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg svc "$svc" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"grpc","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "grpcSettings":{"serviceName":$svc,"multiMode":false}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + gRPC + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен: ${WHITE}${dom}${R}  ServiceName: ${CYAN}${svc}${R}"
    box_blank
    box_row "  ${YELLOW}Nginx (grpc_pass):${R}"
    box_row "  ${DIM}grpc_pass grpc://127.0.0.1:${port};${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + HTTPUpgrade + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_httpupgrade_tls() {
    cls; box_top " 🔀  VLESS + HTTPUpgrade + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_row "  ${DIM}⚡ Рекомендуется перейти на XHTTP — HTTPUpgrade имеет заметный ALPN-отпечаток (http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/upgrade"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-httpupgrade"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-httpupgrade"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"httpupgrade","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "httpupgradeSettings":{"path":$path,"host":$sni}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + HTTPUpgrade + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Path: ${WHITE}${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + WS + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_ws_tls() {
    cls; box_top " 📦  VMess + WebSocket + TLS" "$ORANGE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/vmess"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vmess-ws"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vmess-ws"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vmess",
        "settings":{"clients":[{"email":"main","id":$uuid,"alterId":0}]},
        "streamSettings":{"network":"ws","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "wsSettings":{"path":$path,"headers":{"Host":$sni}}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VMess + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + TCP + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_tcp_tls() {
    cls; box_top " 📦  VMess + TCP + TLS" "$ORANGE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vmess-tcp"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" type "vmess-tcp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg cert "$cert_p" --arg key "$key_p" --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vmess",
        "settings":{"clients":[{"email":"main","id":$uuid,"alterId":0}]},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VMess + TCP + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: Trojan + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_trojan_tls() {
    cls; box_top " 🔐  Trojan + TCP + TLS" "$GREEN"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "trojan"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local pass; pass=$(openssl rand -hex 16)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" type "trojan"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg pass "$pass" \
        --arg cert "$cert_p" --arg key "$key_p" --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"trojan",
        "settings":{"clients":[{"email":"main","password":$pass}]},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  Trojan + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_row "  Пароль: ${DIM}${pass}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: Shadowsocks 2022
# ──────────────────────────────────────────────────────────────────────────────

proto_shadowsocks() {
    cls; box_top " 🌑  Shadowsocks 2022" "$GRAY"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port method tag
    box_row "  Методы: 2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305"
    ask "Порт" port "8388"
    ask "Метод" method "2022-blake3-aes-256-gcm"
    ask "Тег" tag "shadowsocks"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    # Генерация сервер-пароля (base64, 32 bytes для 256-gcm)
    local sp; sp=$(openssl rand -base64 32)
    local up; up=$(openssl rand -base64 32)
    kset "$tag" serverPassword "$sp"; kset "$tag" port "$port"
    kset "$tag" method "$method"; kset "$tag" type "shadowsocks"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" \
        --arg method "$method" --arg sp "$sp" --arg up "$up" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"shadowsocks",
        "settings":{"method":$method,"password":$sp,
            "clients":[{"email":"main","password":$up}]},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  Shadowsocks добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Метод: ${WHITE}${method}${R}"
    box_row "  Серверный пароль: ${DIM}${sp}${R}"
    box_row "  Пользов. пароль:  ${DIM}${up}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  FREEDOM + FRAGMENT (обход фрагментацией TLS)
# ──────────────────────────────────────────────────────────────────────────────

# ── Fragment helpers ─────────────────────────────────────────────────────────

_fragment_get_freedom_tag() {
    jq -r '.outbounds[]|select(.protocol=="freedom" and (.tag=="direct" or .tag==null or .tag=="freedom"))|.tag' \
        "$XRAY_CONF" 2>/dev/null | head -1
}

_fragment_is_enabled() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && return 1
    local pkt; pkt=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.packets // ""' "$XRAY_CONF" 2>/dev/null)
    [[ -n "$pkt" ]]
}

_fragment_show_status() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { box_row "  ${RED}Freedom outbound не найден${R}"; return; }
    local pkt len inv
    pkt=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.packets // ""' "$XRAY_CONF" 2>/dev/null)
    len=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.length // ""' "$XRAY_CONF" 2>/dev/null)
    inv=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.interval // ""' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$pkt" ]]; then
        box_row "  Статус:    ${GREEN}${BOLD}● ВКЛЮЧЕНО${R}"
        box_row "  Outbound:  ${CYAN}${tag}${R}"
        box_row "  Режим:     ${CYAN}${pkt}${R}"
        box_row "  Размер:    ${YELLOW}${len:-—}${R} байт"
        box_row "  Интервал:  ${YELLOW}${inv:-—}${R} мс"
    else
        box_row "  Статус:    ${DIM}○ ВЫКЛЮЧЕНО${R}"
        box_row "  Outbound:  ${CYAN}${tag}${R}"
    fi
}

_fragment_enable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }

    cls; box_top " 🧩  Настройка фрагментации" "$CYAN"; box_blank
    box_row "  ${CYAN}${BOLD}Фрагментация TLS Client Hello${R}"
    box_row "  ${DIM}Разбивает первый пакет на куски — DPI не собирает SNI${R}"
    box_blank
    box_row "  ${YELLOW}Режим пакетов:${R}"
    mi "1" "🔐" "${CYAN}tlshello${R}  — только TLS ClientHello  ${DIM}(рекомендуется)${R}"
    mi "2" "📦" "${CYAN}1-3${R}       — первые 1-3 TCP write'а"
    box_end

    read -rp "$(printf "${YELLOW}›${R} Режим [1]: ")" pkt_ch
    local packets
    case "${pkt_ch:-1}" in
        2) packets="1-3" ;;
        *) packets="tlshello" ;;
    esac

    local length interval
    ask "Размер фрагмента (байты, диапазон)" length "100-200"
    ask "Интервал между фрагментами (мс)"    interval "10-20"

    local frag_json; frag_json=$(jq -n \
        --arg pkt "$packets" --arg len "$length" --arg inv "$interval" \
        '{"packets":$pkt,"length":$len,"interval":$inv}')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --argjson fr "$frag_json" \
        '(.outbounds[]|select(.tag==$t)|.settings) |= (. // {} | .fragment = $fr)' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "Фрагментация включена  (режим: ${packets}, размер: ${length}, интервал: ${interval} мс)"
}

_fragment_disable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" 'del(.outbounds[]|select(.tag==$t)|.settings.fragment)' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "Фрагментация выключена"
}

menu_freedom_fragment() {
    while true; do
        cls; box_top " 🧩  Фрагментация TLS (Fragment)" "$CYAN"
        box_blank
        _fragment_show_status
        box_blank
        box_mid

        if _fragment_is_enabled; then
            mi "1" "⏹" "${RED}Выключить фрагментацию${R}"
            mi "2" "🔄" "Перенастроить (изменить параметры)"
        else
            mi "1" "▶" "${GREEN}Включить фрагментацию${R}"
        fi

        box_blank
        box_row "  ${DIM}Работает только для direct-трафика (freedom outbound).${R}"
        box_row "  ${DIM}VLESS/VMess/Trojan используют собственный транспорт.${R}"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        if _fragment_is_enabled; then
            case "$ch" in
                1) _fragment_disable; pause ;;
                2) _fragment_enable;  pause ;;
                0) return ;;
            esac
        else
            case "$ch" in
                1) _fragment_enable; pause ;;
                0) return ;;
            esac
        fi
    done
}

menu_freedom_noises() {
    cls; box_top " 🔊  Freedom outbound + Noises (UDP шум)" "$MAGENTA"
    box_blank
    box_row "  ${CYAN}${BOLD}UDP Noise — отправка случайных пакетов перед соединением${R}"
    box_row "  ${DIM}Маскирует начало UDP-потока под случайный трафик${R}"
    box_blank
    box_row "  ${YELLOW}⚠  Порт 53 (DNS) автоматически исключается${R}"
    box_blank

    local noise_type noise_size noise_delay
    box_row "  Тип пакета:"
    mi "1" "🎲" "rand   — случайные байты"
    mi "2" "📝" "str    — строка"
    mi "3" "📦" "base64 — бинарные данные (base64)"
    box_end
    read -rp "$(printf "${YELLOW}›${R} Тип [1]: ")" type_ch
    type_ch="${type_ch:-1}"
    case "$type_ch" in
        2) noise_type="str"; ask "Строка" noise_size "hello" ;;
        3) noise_type="base64"; ask "Base64 данные" noise_size "7nQBAAABAAAAAAAABnQtcmluZwZtc2VkZ2UDbmV0AAABAAE=" ;;
        *) noise_type="rand"; ask "Размер (байты или диапазон)" noise_size "50-100" ;;
    esac
    ask "Задержка после пакета (мс, диапазон)" noise_delay "10-20"

    local noise_json; noise_json=$(jq -n \
        --arg t "$noise_type" --arg p "$noise_size" --arg d "$noise_delay" \
        '[{"type":$t,"packet":$p,"delay":$d}]')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    local has_freedom; has_freedom=$(jq -r '.outbounds[]|select(.protocol=="freedom" and (.tag=="direct" or .tag==null))|.tag' "$XRAY_CONF" 2>/dev/null | head -1)

    if [[ -n "$has_freedom" ]]; then
        jq --arg t "${has_freedom:-direct}" --argjson nz "$noise_json" \
            '(.outbounds[]|select(.protocol=="freedom" and .tag==$t)|.settings) |= (. // {} | .noises = $nz)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Noises добавлен к outbound '${has_freedom:-direct}'"
    else
        warn "Freedom outbound не найден"
    fi

    xray_restart
    cls; box_top " ✅  Noises настроен" "$GREEN"; box_blank
    box_row "  Тип:      ${CYAN}${noise_type}${R}"
    box_row "  Данные:   ${DIM}${noise_size}${R}"
    box_row "  Задержка: ${YELLOW}${noise_delay}${R} мс"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  FALLBACKS (защита от зондирования)
# ──────────────────────────────────────────────────────────────────────────────

menu_fallbacks() {
    while true; do
        cls; box_top " 🛡️  Fallbacks — защита от зондирования" "$YELLOW"
        box_blank
        box_row "  ${CYAN}${BOLD}Что это:${R}"
        box_row "  ${DIM}Если кто-то подключается без правильного протокола — вместо разрыва${R}"
        box_row "  ${DIM}соединение перенаправляется на реальный сайт. Прокси не детектируется.${R}"
        box_blank
        box_row "  ${YELLOW}⚠  Работает только с: VLESS+TCP+TLS и Trojan+TCP+TLS${R}"
        box_row "  ${DIM}   Не работает с REALITY, WebSocket, gRPC, XHTTP${R}"
        box_blank

        # Показать текущие fallbacks
        local has_fb=0
        while IFS='|' read -r tag _ proto net sec; do
            if [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]]; then
                local fb_count; fb_count=$(jq --arg t "$tag" \
                    '.inbounds[]|select(.tag==$t)|.settings.fallbacks|length' "$XRAY_CONF" 2>/dev/null || echo 0)
                if [[ "$fb_count" -gt 0 ]]; then
                    box_row "  ${GREEN}✓${R} ${CYAN}${tag}${R}: ${fb_count} fallback(s) настроено"
                    has_fb=1
                else
                    box_row "  ${DIM}○ ${tag}: нет fallbacks${R}"
                fi
            fi
        done < <(ib_list)
        box_blank; box_mid
        mi "1" "➕" "Добавить fallback к протоколу"
        mi "2" "📋" "Показать текущие fallbacks"
        mi "3" "🗑" "Удалить все fallbacks у протокола"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) fallback_add ;;
            2) fallback_show ;;
            3) fallback_clear ;;
            0) return ;;
        esac
    done
}

fallback_add() {
    cls; box_top " ➕  Добавить fallback" "$YELLOW"; box_blank

    # Выбрать подходящий inbound
    local eligible=()
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] && eligible+=("$tag")
    done < <(ib_list)

    if [[ ${#eligible[@]} -eq 0 ]]; then
        box_row "  ${RED}Нет подходящих протоколов (нужен VLESS или Trojan + TCP + TLS)${R}"
        box_end; pause; return
    fi

    local tag
    if [[ ${#eligible[@]} -eq 1 ]]; then
        tag="${eligible[0]}"
        box_row "  Протокол: ${CYAN}${tag}${R}"
    else
        local i=1
        for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)); done
        box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
        tag="${eligible[$((idx-1))]}"
    fi
    box_blank

    box_row "  ${YELLOW}Куда перенаправлять (dest):${R}"
    box_row "  ${DIM}Формат: порт (напр. 80) или адрес:порт (напр. 127.0.0.1:8080)${R}"

    local dest sni_match alpn_match path_match
    ask "Dest (порт или addr:port)" dest "80"
    ask "SNI для совпадения (пусто = любой)" sni_match ""
    ask "ALPN для совпадения (h2 / http/1.1, пусто = любой)" alpn_match ""
    ask "Path для совпадения (пусто = любой)" path_match ""

    local fb_obj; fb_obj=$(jq -n \
        --arg dest "$dest" \
        --arg name "$sni_match" \
        --arg alpn "$alpn_match" \
        --arg path "$path_match" \
        '{dest: (if ($dest|test("^[0-9]+$")) then ($dest|tonumber) else $dest end)}
        + (if $name != "" then {name: $name} else {} end)
        + (if $alpn != "" then {alpn: $alpn} else {} end)
        + (if $path != "" then {path: $path} else {} end)')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --argjson fb "$fb_obj" \
        '(.inbounds[]|select(.tag==$t)|.settings.fallbacks) |= (. // [] | . + [$fb])
         | (.inbounds[]|select(.tag==$t)|.streamSettings.tlsSettings.alpn) |=
             if (. == null or (map(select(. == "http/1.1")) | length) == 0)
             then (. // []) + ["http/1.1"]
             else . end' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Fallback добавлен: → ${dest}"
    pause
}

fallback_show() {
    cls; box_top " 📋  Текущие fallbacks" "$YELLOW"; box_blank
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] || continue
        local fallbacks; fallbacks=$(jq -r --arg t "$tag" \
            '.inbounds[]|select(.tag==$t)|.settings.fallbacks[]?|
             "  dest=\(.dest) name=\(.name//"*") alpn=\(.alpn//"*") path=\(.path//"*")"' \
            "$XRAY_CONF" 2>/dev/null)
        if [[ -n "$fallbacks" ]]; then
            box_row "  ${CYAN}${tag}${R}"
            while IFS= read -r line; do box_row "$line"; done <<< "$fallbacks"
            box_blank
        fi
    done < <(ib_list)
    box_end; pause
}

fallback_clear() {
    cls; box_top " 🗑  Удалить fallbacks" "$RED"; box_blank
    local eligible=()
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] && eligible+=("$tag")
    done < <(ib_list)
    [[ ${#eligible[@]} -eq 0 ]] && { box_row "  ${DIM}Нет подходящих протоколов${R}"; box_end; pause; return; }
    local i=1
    for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)); done
    box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
    local tag="${eligible[$((idx-1))]}"
    confirm "Удалить все fallbacks у '${tag}'?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --arg t "$tag" 'del(.inbounds[]|select(.tag==$t)|.settings.fallbacks)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        xray_restart; ok "Fallbacks удалены"
    }
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  METRICS ENDPOINT
# ──────────────────────────────────────────────────────────────────────────────

menu_metrics() {
    cls; box_top " 📈  Metrics Endpoint" "$BLUE"
    box_blank
    box_row "  ${CYAN}${BOLD}HTTP JSON статистика — альтернатива Stats API${R}"
    box_row "  ${DIM}Слушает 127.0.0.1:PORT → /debug/vars (JSON) + /debug/pprof${R}"
    box_blank

    local cur_metrics; cur_metrics=$(jq -r '.metrics.listen // ""' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$cur_metrics" ]]; then
        box_row "  ${GREEN}● Metrics уже включён:${R} ${CYAN}http://${cur_metrics}/debug/vars${R}"
        box_blank
        mi "1" "🔄" "Изменить порт"
        mi "2" "🗑" "Отключить"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) ;;
            2)
                local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
                jq 'del(.metrics)' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
                xray_restart; ok "Metrics отключён"; pause; return ;;
            0) return ;;
        esac
    fi

    local port; ask "Порт Metrics" port "11111"
    local listen="127.0.0.1:${port}"

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg l "$listen" '.metrics = {"tag":"metrics_out","listen":$l}' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    # Добавить outbound для metrics если нет
    local has_m; has_m=$(jq -r '.outbounds[]|select(.tag=="metrics_out")|.tag' "$XRAY_CONF" 2>/dev/null)
    if [[ -z "$has_m" ]]; then
        local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
        jq '.outbounds += [{"tag":"metrics_out","protocol":"blackhole"}]' \
            "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
    fi

    xray_restart
    cls; box_top " ✅  Metrics включён" "$GREEN"; box_blank
    box_row "  URL: ${CYAN}http://${listen}/debug/vars${R}"
    box_blank
    box_row "  ${YELLOW}Эндпоинты:${R}"
    box_row "  ${DIM}/debug/vars     — JSON статистика (inbound/outbound/user трафик)${R}"
    box_row "  ${DIM}/debug/pprof/   — профилировщик Go (память, CPU, горутины)${R}"
    box_blank
    box_row "  ${YELLOW}Пример запроса:${R}"
    box_row "  ${DIM}curl -s http://${listen}/debug/vars | python3 -m json.tool${R}"
    box_blank
    box_row "  ${YELLOW}Разница с Stats API:${R}"
    box_row "  ${DIM}Stats API → gRPC на :${STATS_PORT} → xray api statsquery${R}"
    box_row "  ${DIM}Metrics   → HTTP JSON на :${port} → curl / Grafana / Netdata${R}"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  HYSTERIA2 OUTBOUND (клиентский режим — relay/цепочка)
# ──────────────────────────────────────────────────────────────────────────────

menu_hysteria_outbound() {
    cls; box_top " 🚀  Hysteria2 Outbound (relay / цепочка)" "$GREEN"
    box_blank
    box_row "  ${CYAN}${BOLD}Этот VPS подключается к другому Hysteria2-серверу${R}"
    box_blank
    box_row "  ${YELLOW}Схема:${R}"
    box_row "  ${DIM}Клиент → [VLESS/REALITY → этот VPS] → [Hysteria2 → VPS2] → интернет${R}"
    box_blank
    box_row "  ${YELLOW}Требует:${R} Hysteria2-сервер на другом VPS (меню 7 или меню 10)${R}"
    box_blank

    # Показать существующие Hysteria outbounds
    local existing; existing=$(jq -r '.outbounds[]|select(.protocol=="hysteria")|.tag' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$existing" ]]; then
        box_row "  ${YELLOW}Существующие Hysteria outbounds:${R}"
        while IFS= read -r t; do box_row "    ${CYAN}${t}${R}"; done <<< "$existing"
        box_blank
    fi
    box_end

    local addr port pass tag up_mbps dn_mbps sni insecure
    ask "Адрес сервера (домен или IP)" addr ""
    ask "Порт"                         port "443"
    ask "Пароль (от удалённого сервера)" pass ""
    ask "SNI (домен сертификата)"      sni  "$addr"
    ask "Тег outbound"                 tag  "hy2-relay"

    [[ -z "$addr" || -z "$pass" ]] && { err "Адрес и пароль обязательны"; pause; return; }

    box_blank
    box_row "  ${YELLOW}Алгоритм скорости:${R}"
    mi "1" "🔵" "BBR (0) — стандартный"
    mi "2" "🔴" "Brutal — задать Mbps"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " spd_ch
    if [[ "$spd_ch" == "2" ]]; then
        ask "Download Mbps" dn_mbps "100"
        ask "Upload Mbps"   up_mbps "50"
    else
        up_mbps="0"; dn_mbps="0"
    fi

    local allow_insecure="false"
    confirm "Разрешить небезопасный TLS (если нет валидного сертификата)?" "n" && allow_insecure="true"

    local out_json; out_json=$(jq -n \
        --arg tag "$tag" \
        --arg addr "$addr" \
        --argjson port "$port" \
        --arg pass "$pass" \
        --arg sni "$sni" \
        --arg up "$up_mbps" \
        --arg dn "$dn_mbps" \
        --argjson ins "$allow_insecure" \
        '{
            "tag": $tag,
            "protocol": "hysteria",
            "settings": {
                "address": $addr,
                "port": $port
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": $sni,
                    "allowInsecure": $ins,
                    "alpn": ["h3"]
                },
                "hysteriaSettings": {
                    "version": 2,
                    "auth": $pass,
                    "up": $up,
                    "down": $dn
                }
            }
        }')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson ob "$out_json" '.outbounds += [$ob]' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    cls; box_top " ✅  Hysteria2 Outbound добавлен" "$GREEN"; box_blank
    box_row "  Тег:    ${CYAN}${tag}${R}"
    box_row "  Сервер: ${WHITE}${addr}:${port}${R}"
    box_row "  SNI:    ${DIM}${sni}${R}"
    box_blank
    box_row "  ${YELLOW}Следующий шаг — добавить routing-правило:${R}"
    box_row "  ${DIM}Настройки → Маршрутизация → направить нужный трафик на '${tag}'${R}"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  БАЛАНСИРОВЩИК НАГРУЗКИ + OBSERVATORY
# ──────────────────────────────────────────────────────────────────────────────

menu_balancer() {
    while true; do
        cls; box_top " ⚖️  Балансировщик нагрузки" "$MAGENTA"
        box_blank
        box_row "  ${CYAN}${BOLD}Автоматический выбор лучшего outbound${R}"
        box_row "  ${DIM}Observatory пингует серверы → Balancer выбирает быстрейший${R}"
        box_blank

        # Текущее состояние
        local obs_url; obs_url=$(jq -r '.observatory.probeUrl // ""' "$XRAY_CONF" 2>/dev/null)
        local bal_count; bal_count=$(jq '.balancers|length // 0' "$XRAY_CONF" 2>/dev/null || echo 0)
        if [[ -n "$obs_url" ]]; then
            box_row "  ${GREEN}● Observatory:${R} ping → ${DIM}${obs_url}${R}"
            box_row "  ${GREEN}● Balancers:${R} ${CYAN}${bal_count}${R} настроено"
        else
            box_row "  ${DIM}○ Observatory не настроен${R}"
        fi

        box_blank; box_mid
        mi "1" "🔭" "Настроить Observatory (мониторинг)"
        mi "2" "⚖️ " "Добавить балансировщик"
        mi "3" "🗑" "Удалить балансировщик"
        mi "4" "📋" "Показать текущие балансировщики"
        mi "5" "📊" "Результаты Observatory"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) balancer_setup_observatory ;;
            2) balancer_add ;;
            3) balancer_del ;;
            4) balancer_show ;;
            5) balancer_results ;;
            0) return ;;
        esac
    done
}

balancer_setup_observatory() {
    cls; box_top " 🔭  Observatory — мониторинг outbounds" "$BLUE"; box_blank

    local probe_url probe_interval
    ask "URL для пинга" probe_url "https://www.google.com/generate_204"
    ask "Интервал проверки (напр. 30s, 5m)" probe_interval "30s"

    local selector_prefix
    ask "Префикс тегов для мониторинга (пусто = все)" selector_prefix "out-"

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg url "$probe_url" \
       --arg inv "$probe_interval" \
       --arg sel "$selector_prefix" \
       '.observatory = {
           "subjectSelector": (if $sel != "" then [$sel] else [""] end),
           "probeUrl": $url,
           "probeInterval": $inv,
           "enableConcurrency": false
       }' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Observatory настроен — пингует каждые ${probe_interval}"
    pause
}

balancer_add() {
    cls; box_top " ➕  Добавить балансировщик" "$MAGENTA"; box_blank

    # Показать outbounds
    local outbounds; outbounds=$(jq -r '.outbounds[].tag' "$XRAY_CONF" 2>/dev/null)
    box_row "  ${YELLOW}Доступные outbounds:${R}"
    while IFS= read -r t; do [[ "$t" != "direct" && "$t" != "block" && "$t" != "api" ]] && box_row "    ${CYAN}${t}${R}"; done <<< "$outbounds"
    box_blank

    local tag selector strategy
    ask "Тег балансировщика"       tag      "lb-main"
    ask "Префикс тегов outbounds"  selector "out-"
    box_blank
    box_row "  Стратегия:"
    mi "1" "🎲" "random    — случайный"
    mi "2" "🔄" "roundRobin — по очереди"
    mi "3" "⚡" "leastPing  — наименьшая задержка ${DIM}(нужен Observatory)${R}"
    mi "4" "📊" "leastLoad  — наименьшая нагрузка ${DIM}(нужен Observatory)${R}"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " strat_ch
    case "$strat_ch" in
        2) strategy="roundRobin" ;;
        3) strategy="leastPing" ;;
        4) strategy="leastLoad" ;;
        *) strategy="random" ;;
    esac

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg tag "$tag" --arg sel "$selector" --arg strat "$strategy" '
        if .routing.balancers == null then .routing.balancers = [] else . end |
        .routing.balancers += [{
            "tag": $tag,
            "selector": [$sel],
            "strategy": {"type": $strat}
        }]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Балансировщик '${tag}' добавлен (стратегия: ${strategy})"
    box_blank
    box_row "  ${YELLOW}Использование в routing:${R}"
    box_row "  ${DIM}{\"inboundTag\":[\"your-inbound\"],\"balancerTag\":\"${tag}\"}${R}"
    pause
}

balancer_del() {
    cls; box_top " 🗑  Удалить балансировщик" "$RED"; box_blank
    local bals; bals=$(jq -r '.routing.balancers[]?.tag' "$XRAY_CONF" 2>/dev/null)
    [[ -z "$bals" ]] && { box_row "  ${DIM}Нет балансировщиков${R}"; box_end; pause; return; }
    local i=1; local -a btags=()
    while IFS= read -r t; do mi "$i" "⚖️ " "$t"; btags+=("$t"); ((i++)); done <<< "$bals"
    box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
    local sel_tag="${btags[$((idx-1))]}"
    confirm "Удалить балансировщик '${sel_tag}'?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --arg t "$sel_tag" 'del(.routing.balancers[]|select(.tag==$t))' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        xray_restart; ok "Удалён"
    }
    pause
}

balancer_show() {
    cls; box_top " 📋  Балансировщики" "$MAGENTA"; box_blank
    local info; info=$(jq -r '.routing.balancers[]? |
        "  \(.tag)  стратегия: \(.strategy.type//"random")  selector: \(.selector|join(","))"' \
        "$XRAY_CONF" 2>/dev/null)
    [[ -z "$info" ]] && info="  (нет балансировщиков)"
    while IFS= read -r line; do box_row "$line"; done <<< "$info"
    box_blank; box_end; pause
}

balancer_results() {
    cls; box_top " 📊  Результаты Observatory" "$BLUE"; box_blank
    xray_active || { box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return; }
    local obs; obs=$("$XRAY_BIN" api statsonline --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || echo "")
    if [[ -z "$obs" ]]; then
        box_row "  ${DIM}Данные Observatory недоступны через Stats API${R}"
        box_row "  ${DIM}Включите Metrics endpoint для просмотра результатов Observatory${R}"
        box_row "  ${DIM}curl -s http://127.0.0.1:11111/debug/vars | python3 -m json.tool${R}"
    fi
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_reality() {
    cls; box_top " 🔄  VLESS + gRPC + REALITY" "$MAGENTA"
    box_blank
    box_row "  ${DIM}Не требует домена и сертификата — REALITY камуфлирует трафик${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni svc tag
    ask "Порт" port "443"
    ask "SNI (камуфляжный домен)" sni "www.yahoo.com"
    ask "gRPC ServiceName" svc "grpc"
    ask "Тег" tag "vless-grpc-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    spin_start "Генерация ключей x25519"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | awk '/PrivateKey/{print $2}')
    local pub;  pub=$(echo "$kout"  | awk '/PublicKey/{print $2}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid";     kset "$tag" sni "$sni"
    kset "$tag" port "$port";       kset "$tag" serviceName "$svc"
    kset "$tag" type "vless-grpc-reality"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" --arg svc "$svc" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":""}],"decryption":"none"},
        "streamSettings":{"network":"grpc","security":"reality",
            "grpcSettings":{"serviceName":$svc,"multiMode":false},
            "realitySettings":{"show":false,"target":($sni+":443"),"xver":0,
                "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + gRPC + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  ServiceName: ${CYAN}${svc}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_row "  ShortId:   ${DIM}${sid}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + SplitHTTP + TLS (HTTP/3 / QUIC)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_splithttp_tls() {
    cls; box_top " 🌊  VLESS + SplitHTTP + TLS/H3" "$CYAN"
    box_blank
    box_row "  ${DIM}HTTP/3 (QUIC) напрямую или через CDN (alpn: h2,http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p alpn_mode
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/split"
    ask "Режим ALPN: [1] h3 (прямое) [2] h2,http/1.1 (CDN)" alpn_mode "1"
    ask "Тег" tag "vless-splithttp"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    local cert_p key_p
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    # Формируем alpn-массив
    local alpn_json
    if [[ "$alpn_mode" == "2" ]]; then
        alpn_json='["h2","http/1.1"]'
    else
        alpn_json='["h3"]'
    fi
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-splithttp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg dom "$dom" \
        --arg cert "$cert_p" --arg key "$key_p" \
        --argjson alpn "$alpn_json" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{
            "network":"splithttp","security":"tls",
            "splithttpSettings":{"path":$path,"host":$dom},
            "tlsSettings":{
                "rejectUnknownSni":true,
                "minVersion":"1.3",
                "alpn":$alpn,
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + SplitHTTP + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен: ${WHITE}${dom}${R}  Path: ${CYAN}${path_v}${R}"
    local alpn_label; [[ "$alpn_mode" == "2" ]] && alpn_label="h2,http/1.1 (CDN)" || alpn_label="h3 (прямое)"
    box_row "  ALPN: ${DIM}${alpn_label}${R}"
    box_blank
    if [[ "$alpn_mode" == "2" ]]; then
        box_row "  ${YELLOW}CDN-режим: убедитесь что CDN поддерживает gRPC/WebSocket${R}"
    else
        box_row "  ${YELLOW}UDP/443 должен быть открыт для QUIC${R}"
    fi
    box_blank; box_end
    show_link_qr "$tag" "main"
}

#  МЕНЮ ПРОТОКОЛОВ
# ──────────────────────────────────────────────────────────────────────────────

# ── Hysteria2 (нативный Xray) ─────────────────────────────────────────────

proto_hysteria_xray() {
    cls; box_top " 🚀  Hysteria2 (нативный Xray)" "$GREEN"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }

    box_row "  ${CYAN}${BOLD}Реализация Hysteria2 внутри Xray — без отдельного бинарника${R}"
    box_row "  ${DIM}Требует домен + TLS-сертификат. Поддерживает Stats API и лимиты Xray.${R}"
    box_blank
    box_row "  ${YELLOW}Отличия от отдельного Hysteria2 (меню 7):${R}"
    box_row "  ${DIM}+ Единый процесс и конфиг / + Статистика через xray api statsquery${R}"
    box_row "  ${DIM}+ Лимиты по трафику/дате через .limits.json${R}"
    box_row "  ${DIM}− Нет встроенного ACME / − Port Hopping требует iptables вручную${R}"
    box_blank

    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен (для SNI и сертификата)" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"

    local up_mbps dn_mbps
    box_blank
    box_row "  ${YELLOW}Алгоритм скорости:${R}"
    mi "1" "🔵" "BBR (0) — стандартный, рекомендуется"
    mi "2" "🔴" "Brutal — задать скорость вручную"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " spd_ch
    if [[ "$spd_ch" == "2" ]]; then
        ask "Download Mbps (сервер→клиент)" dn_mbps "100"
        ask "Upload Mbps   (клиент→сервер)" up_mbps "50"
        ok "Brutal: ↓${dn_mbps} / ↑${up_mbps} Mbps"
    else
        up_mbps="0"; dn_mbps="0"
        ok "BBR (авто)"
    fi

    box_blank
    box_row "  ${YELLOW}Port Hopping (UDP) — необязательно:${R}"
    box_row "  ${DIM}Диапазон портов напр. 20000-29999 (пусто = отключено)${R}"
    local udphop_range
    ask "Port Hopping диапазон" udphop_range ""

    ask "Тег" tag "hysteria-xray"
    [[ -z "$dom" ]]   && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag"  && { err "Тег '$tag' уже занят"; pause; return; }

    local pass; pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
    info "Сгенерирован пароль: $pass"

    kset "$tag" domain   "$dom"
    kset "$tag" port     "$port"
    kset "$tag" type     "hysteria-xray"
    kset "$tag" password "$pass"
    [[ -n "$udphop_range" ]] && kset "$tag" udphop "$udphop_range"

    local ib; ib=$(jq -n \
        --arg  tag   "$tag" \
        --argjson port "$port" \
        --arg  pass  "$pass" \
        --arg  cert  "$cert_p" \
        --arg  key   "$key_p" \
        --arg  sni   "$dom" \
        --arg  up    "$up_mbps" \
        --arg  down  "$dn_mbps" \
        --arg  hop   "$udphop_range" \
        '{
            "tag": $tag,
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "hysteria",
            "settings": {
                "users": [
                    {"email": "main", "password": $pass}
                ]
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": $sni,
                    "alpn": ["h3"],
                    "certificates": [
                        {"certificateFile": $cert, "keyFile": $key}
                    ]
                },
                "hysteriaSettings": ({
                    "version": 2,
                    "up": $up,
                    "down": $down
                } + (if $hop != "" then {"udphop": {"port": $hop, "interval": 30}} else {} end))
            },
            "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
        }')

    ib_add "$ib"; xray_restart

    # UFW для Port Hopping
    if [[ -n "$udphop_range" ]] && command -v ufw &>/dev/null; then
        local hop_start hop_end
        hop_start="${udphop_range%-*}"; hop_end="${udphop_range#*-}"
        if [[ "$hop_start" != "$hop_end" ]]; then
            ufw allow "${hop_start}:${hop_end}/udp" >/dev/null 2>&1
            ok "UFW: открыт диапазон ${udphop_range}/udp"
        fi
    fi
    command -v ufw &>/dev/null && ufw allow "${port}/udp" >/dev/null 2>&1

    # Ссылка: стандартный hy2:// URI — совместим с любым Hysteria2-клиентом
    local server_ip; server_ip=$(server_ip)
    local link="hy2://${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0#${tag}"
    local link_ip="hy2://${pass}@${server_ip}:${port}?sni=${dom}&alpn=h3&insecure=0#${tag}"

    cls; box_top " ✅  Hysteria2 (нативный Xray) добавлен!" "$GREEN"; box_blank
    box_row "  Тег:    ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен:  ${WHITE}${dom}${R}"
    box_row "  Пароль: ${DIM}${pass}${R}"
    box_row "  Скорость: $(  [[ "$up_mbps" == "0" ]] && echo "BBR" || echo "Brutal ↓${dn_mbps}/↑${up_mbps} Mbps" )"
    [[ -n "$udphop_range" ]] && box_row "  Port Hop: ${CYAN}${udphop_range}${R}"
    box_blank
    box_row "  ${CYAN}URI (по домену — рекомендуется):${R}"
    box_row "  ${DIM}${link}${R}"
    box_blank
    box_row "  ${CYAN}URI (по IP — если домен не настроен):${R}"
    box_row "  ${DIM}${link_ip}&allowInsecure=1${R}"
    box_blank
    box_row "  ${YELLOW}QR-код (домен):${R}"
    box_end
    echo ""
    echo "$link" | qrencode -t ansiutf8 2>/dev/null || warn "qrencode не установлен"
    pause
}

menu_protocols() {
    while true; do
        cls; box_top " 🌐  Протоколы" "$MAGENTA"
        box_blank
        # Текущие протоколы
        box_row "  ${YELLOW}Активные протоколы:${R}"
        local cnt=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            local label_col="$CYAN"
            box_row "    • ${label_col}${tag}${R}  ${DIM}порт ${port} · ${proto}+${net}+${sec} · ${uc} польз.${R}"
            ((cnt++))
        done < <(ib_list)
        [[ $cnt -eq 0 ]] && box_row "    ${DIM}(нет протоколов)${R}"
        box_blank; box_mid
        box_row "  ${CYAN}${BOLD}VLESS + REALITY${R}"
        mi "1"  "🌐" "${CYAN}VLESS + TCP + REALITY${R}"          "(рекомендуется)"
        mi "2"  "⚡" "${MAGENTA}VLESS + XHTTP + REALITY${R}"     "(CDN/прямое)"
        mi "12" "🔄" "${MAGENTA}VLESS + gRPC + REALITY${R}"      "(без домена)"
        box_row "  ${BLUE}${BOLD}VLESS + TLS${R}"
        mi "3"  "☁️ " "${BLUE}VLESS + WebSocket + TLS${R}"      "(CDN)"
        mi "4"  "🔄" "${BLUE}VLESS + gRPC + TLS${R}"             "(CDN/Nginx)"
        mi "5"  "🔀" "${BLUE}VLESS + HTTPUpgrade + TLS${R}"      ""
        mi "13" "🌊" "${BLUE}VLESS + SplitHTTP + TLS/H3${R}"     "(QUIC/CDN)"
        box_row "  ${ORANGE}${BOLD}VMess${R}"
        mi "6"  "📦" "${ORANGE}VMess + WebSocket + TLS${R}"      ""
        mi "7"  "📦" "${ORANGE}VMess + TCP + TLS${R}"             ""
        box_row "  ${GREEN}${BOLD}Другие${R}"
        mi "8"  "🔐" "${GREEN}Trojan + TCP + TLS${R}"              ""
        mi "9"  "🌑" "${GRAY}Shadowsocks 2022${R}"                 ""
        box_row "  ${CYAN}${BOLD}Hysteria2${R}"
        mi "10" "🚀" "${CYAN}Hysteria2 (нативный Xray)${R}"       "(TLS-сертификат + Stats API)"
        mi "11" "🚀" "${GREEN}Hysteria2 (отдельный бинарник)${R}" "(ACME + Masquerade + Port Hop)"
        box_mid
        mi "d" "🗑" "${RED}Удалить протокол${R}"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1)  proto_vless_tcp_reality ;;
            2)  proto_vless_xhttp_reality ;;
            3)  proto_vless_ws_tls ;;
            4)  proto_vless_grpc_tls ;;
            5)  proto_vless_httpupgrade_tls ;;
            6)  proto_vmess_ws_tls ;;
            7)  proto_vmess_tcp_tls ;;
            8)  proto_trojan_tls ;;
            9)  proto_shadowsocks ;;
            10) proto_hysteria_xray ;;
            11) hysteria_section ;;
            12) proto_vless_grpc_reality ;;
            13) proto_vless_splithttp_tls ;;
            d|D) menu_del_protocol ;;
            0) return ;;
        esac
    done
}

menu_del_protocol() {
    cls; box_top " 🗑  Удалить протокол" "$RED"; box_blank
    local tags=()
    while IFS='|' read -r t p pr n s; do tags+=("$t|$p|$pr|$n|$s"); done < <(ib_list)
    if [[ ${#tags[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет протоколов${R}"; box_end; pause; return
    fi
    local i=1
    for e in "${tags[@]}"; do
        IFS='|' read -r t p pr n s <<< "$e"
        mi "$i" "🔌" "${CYAN}${t}${R}" "  порт ${p} · ${pr}+${n}"
        ((i++))
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#tags[@]} ]]; then
        IFS='|' read -r t _ _ _ _ <<< "${tags[$((ch-1))]}"
        confirm "Удалить протокол '${t}'?" && {
            ib_del "$t"; rm -f "$(kfile "$t")"; xray_restart
            ok "Протокол '${t}' удалён"
        }
    fi
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ
# ──────────────────────────────────────────────────────────────────────────────

menu_users() {
    while true; do
        cls; box_top " 👥  Пользователи" "$YELLOW"; box_blank
        # Статистика по протоколам
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            box_row "  • ${CYAN}${tag}${R}  ${DIM}${proto}+${net}+${sec} · порт ${port}${R}  ${YELLOW}${uc} польз.${R}"
        done < <(ib_list)
        box_blank; box_mid
        mi "1" "➕" "Добавить пользователя"
        mi "2" "➖" "Удалить пользователя"
        mi "3" "📋" "Список всех пользователей"
        mi "4" "🔗" "Показать ссылку / QR-код"
        mi "5" "📊" "Статистика трафика"
        mi "6" "⏱" "Установить лимит (трафик / дата)"
        mi "7" "🔍" "Проверить лимиты сейчас"
        mi "8" "📡" "${CYAN}Подписка (Subscription)${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) user_add ;;
            2) user_del ;;
            3) user_list ;;
            4) user_link ;;
            5) user_stats ;;
            6) user_set_limit ;;
            7) cls; check_limits; pause ;;
            8) menu_subscription ;;
            0) return ;;
        esac
    done
}

user_add() {
    cls; box_top " ➕  Добавить пользователя" "$GREEN"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local email
    ask "Логин пользователя" email ""
    [[ -z "$email" ]] && { err "Логин не может быть пустым"; pause; return; }
    # Допускаем только безопасные символы: буквы, цифры, точка, дефис, подчёркивание, @
    # @ используется как разделитель в конвенции alice@vpn (это не email, просто идентификатор)
    # Запрещаем пробелы, ../ $() и прочие символы, которые попадают в URI и имена файлов
    [[ ! "$email" =~ ^[a-zA-Z0-9._@-]+$ ]] && { err "Логин содержит недопустимые символы. Разрешены: a-z A-Z 0-9 . _ @ -"; pause; return; }
    # Проверка дублей
    local ex; ex=$(jq -r --arg t "$tag" --arg e "$email" \
        '[.inbounds[]|select(.tag==$t)|((.settings.clients//[]) + (.settings.users//[]))[]]|map(select(.email==$e))|.[0].email' "$XRAY_CONF" 2>/dev/null)
    [[ -n "$ex" ]] && { err "Пользователь '$email' уже существует в '$tag'"; pause; return; }

    local proto; proto=$(ib_proto "$tag")
    local net;   net=$(ib_net "$tag")
    local uuid;  uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local client_json

    case "${proto}:${net}" in
        vless:tcp|vless:raw)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"flow":"xtls-rprx-vision"}') ;;
        vless:xhttp)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"flow":""}') ;;
        vless:ws|vless:grpc|vless:httpupgrade)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id}') ;;
        vmess:*)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"alterId":0}') ;;
        trojan:*)
            local pass; pass=$(openssl rand -hex 16)
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        hysteria:hysteria)
            local pass; pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        shadowsocks:*)
            local pass; pass=$(openssl rand -base64 32)
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        *)
            err "Неизвестный протокол ${proto}+${net}"; pause; return ;;
    esac

    # Спросить про лимиты сразу
    local set_lim; set_lim="n"
    box_blank
    box_row "  ${YELLOW}Установить лимиты для пользователя?${R}"
    mi "1" "⏱" "Да — задать прямо сейчас"
    mi "2" "⏭" "Нет — без лимитов"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " lim_ch
    [[ "$lim_ch" == "1" ]] && set_lim="y"

    local expire_ts="" traffic_gb=""
    if [[ "$set_lim" == "y" ]]; then
        box_blank
        ask "Дата истечения (YYYY-MM-DD, пусто = без ограничения)" expire_date ""
        ask "Лимит трафика ГБ (пусто = без ограничения)" traffic_gb ""
        if [[ -n "$expire_date" ]]; then
            expire_ts=$(date -d "$expire_date 23:59:59" +%s 2>/dev/null || echo "")
        fi
    fi

    # Добавить клиента (hysteria использует .settings.users, остальные — .settings.clients)
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "${proto}:${net}" == "hysteria:hysteria" ]]; then
        jq --arg t "$tag" --argjson c "$client_json" \
            '(.inbounds[]|select(.tag==$t)|.settings.users) += [$c]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    else
        jq --arg t "$tag" --argjson c "$client_json" \
            '(.inbounds[]|select(.tag==$t)|.settings.clients) += [$c]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi

    # Сохранить лимиты
    if [[ -n "$expire_ts" ]]; then
        limit_set "$tag" "$email" "expire_ts" "$expire_ts"
        limit_set "$tag" "$email" "expire_date" "$expire_date"
    fi
    if [[ -n "$traffic_gb" && "$traffic_gb" -gt 0 ]]; then
        local bytes=$(( traffic_gb * 1073741824 ))
        limit_set "$tag" "$email" "traffic_limit_bytes" "$bytes"
        limit_set "$tag" "$email" "traffic_limit_gb" "$traffic_gb"
    fi

    # Применяем без перезапуска через gRPC API
    if xray_active && xray_api_add_user "$tag" "$client_json" "$proto" "$net"; then
        ok "Пользователь добавлен в работающий Xray (без разрыва соединений)"
    else
        warn "API недоступен — перезапускаем Xray..."
        xray_restart
    fi

    # Автообновление файлов подписки
    if _sub_autoupdate_enabled && _sub_is_running; then
        info "Обновляем файлы подписки..."
        _sub_update_files
    fi

    cls; box_top " ✅  Пользователь добавлен" "$GREEN"; box_blank
    box_row "  Протокол: ${CYAN}${tag}${R}  Имя: ${YELLOW}${email}${R}"
    [[ -n "$expire_date" ]] && box_row "  Срок до: ${ORANGE}${expire_date}${R}"
    [[ -n "$traffic_gb" ]] && box_row "  Лимит трафика: ${ORANGE}${traffic_gb} GB${R}"
    if _sub_autoupdate_enabled && _sub_is_running; then
        box_row "  ${GREEN}✓ Подписка обновлена автоматически${R}"
    fi
    box_blank; box_end
    show_link_qr "$tag" "$email"
}

user_del() {
    cls; box_top " ➖  Удалить пользователя" "$RED"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        local exp; exp=$(limit_get "$tag" "$em" "expire_date")
        local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
        local badge=""
        [[ -n "$exp" ]] && badge="до ${exp}"
        [[ -n "$tlim" ]] && badge="${badge} ${tlim}GB"
        mi "$i" "👤" "$em" "  ${DIM}${badge}${R}"
        ((i++))
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        local sel="${emails[$((ch-1))]}"
        confirm "Удалить '${sel}' из '${tag}'?" && {
            _remove_user_from_tag "$tag" "$sel"
            limit_del_user "$tag" "$sel"
            xray_reload
            ok "'${sel}' удалён"
        }
    fi
    pause
}

user_list() {
    cls; box_top " 📋  Все пользователи" "$YELLOW"; box_blank
    local total=0
    while IFS='|' read -r tag port proto net sec; do
        box_row "  ${CYAN}${BOLD}${tag}${R}  ${DIM}${proto}+${net}+${sec} · порт ${port}${R}"
        local cnt=0
        while IFS= read -r em; do
            local exp; exp=$(limit_get "$tag" "$em" "expire_date")
            local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
            local info_str=""
            [[ -n "$exp" ]]  && info_str="${info_str} ${ORANGE}до ${exp}${R}"
            [[ -n "$tlim" ]] && info_str="${info_str} ${ORANGE}${tlim}GB${R}"
            # Проверим статус
            local now; now=$(date +%s)
            local ets; ets=$(limit_get "$tag" "$em" "expire_ts")
            local status_icon="✓"
            [[ -n "$ets" && "$ets" != "null" && "$now" -gt "$ets" ]] && status_icon="${RED}✗${R}"
            box_row "    ${status_icon} ${LIGHT}${em}${R}${info_str}"
            ((cnt++)); ((total++))
        done < <(ib_emails "$tag")
        [[ $cnt -eq 0 ]] && box_row "    ${DIM}(нет пользователей)${R}"
        box_blank
    done < <(ib_list)
    box_row "  Итого: ${YELLOW}${total}${R} пользователей"
    box_blank; box_end; pause
}

user_link() {
    cls; box_top " 🔗  Ссылка и QR-код" "$CYAN"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(
        ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        mi "$i" "👤" "$em"; ((i++))
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        show_link_qr "$tag" "${emails[$((ch-1))]}"
    fi
}

user_stats() {
    cls; box_top " 📊  Статистика трафика" "$BLUE"; box_blank
    if ! xray_active; then
        box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return
    fi
    while IFS='|' read -r tag port proto net sec; do
        box_row "  ${CYAN}${BOLD}${tag}${R}  ${DIM}${proto}+${net}${R}"
        while IFS= read -r em; do
            local up dn total_b
            up=$(get_user_traffic "$em" "uplink")
            dn=$(get_user_traffic "$em" "downlink")
            total_b=$(( up + dn ))
            local up_fmt; up_fmt=$(fmt_bytes "$up")
            local dn_fmt; dn_fmt=$(fmt_bytes "$dn")
            local tot_fmt; tot_fmt=$(fmt_bytes "$total_b")
            local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_bytes")
            local lim_str=""
            if [[ -n "$tlim" && "$tlim" != "null" && "$tlim" -gt 0 ]]; then
                local pct=$(( total_b * 100 / tlim ))
                lim_str=" ${ORANGE}${pct}%${R}"
            fi
            box_row "    ${LIGHT}${em}${R}  ↑${up_fmt}  ↓${dn_fmt}  =${tot_fmt}${lim_str}"
        done < <(ib_emails "$tag")
        box_blank
    done < <(ib_list)
    box_end; pause
}

user_set_limit() {
    cls; box_top " ⏱  Установить лимит" "$ORANGE"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(
        ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        local exp; exp=$(limit_get "$tag" "$em" "expire_date")
        local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
        mi "$i" "👤" "$em" "  ${DIM}до:${exp:-∞} трафик:${tlim:-∞}GB${R}"
        ((i++))
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        local sel="${emails[$((ch-1))]}"
        box_blank
        box_row "  Пользователь: ${YELLOW}${sel}${R}"
        box_blank
        local expire_date traffic_gb
        ask "Дата истечения (YYYY-MM-DD, пусто = сбросить)" expire_date ""
        ask "Лимит трафика ГБ (0 = сбросить)" traffic_gb ""
        if [[ -n "$expire_date" ]]; then
            local expire_ts; expire_ts=$(date -d "$expire_date 23:59:59" +%s 2>/dev/null || echo "")
            if [[ -n "$expire_ts" ]]; then
                limit_set "$tag" "$sel" "expire_ts" "$expire_ts"
                limit_set "$tag" "$sel" "expire_date" "$expire_date"
                ok "Дата истечения: $expire_date"
            fi
        else
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg t "$tag" --arg e "$sel" 'del(.[$t][$e].expire_ts) | del(.[$t][$e].expire_date)' \
                "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
            ok "Ограничение по дате снято"
        fi
        if [[ -n "$traffic_gb" && "$traffic_gb" -gt 0 ]]; then
            local bytes=$(( traffic_gb * 1073741824 ))
            limit_set "$tag" "$sel" "traffic_limit_bytes" "$bytes"
            limit_set "$tag" "$sel" "traffic_limit_gb" "$traffic_gb"
            ok "Лимит трафика: ${traffic_gb} GB"
        elif [[ "$traffic_gb" == "0" ]]; then
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg t "$tag" --arg e "$sel" 'del(.[$t][$e].traffic_limit_bytes) | del(.[$t][$e].traffic_limit_gb)' \
                "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
            ok "Ограничение по трафику снято"
        fi
    fi
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  УПРАВЛЕНИЕ СЕРВИСОМ
# ──────────────────────────────────────────────────────────────────────────────

menu_manage() {
    while true; do
        cls; box_top " ⚙️  Управление сервисом" "$BLUE"; box_blank
        local st_icon st_text
        if xray_active; then st_icon="${GREEN}●${R}"; st_text="${GREEN}Работает${R}"
        else st_icon="${RED}○${R}"; st_text="${RED}Остановлен${R}"; fi
        box_row "  Ядро:   ${CYAN}$(xray_ver)${R}   Статус: ${st_icon} ${st_text}"
        box_row "  IP:     ${YELLOW}$(server_ip)${R}"
        box_blank; box_mid
        mi "1" "📊" "Статус + логи"
        mi "2" "🔄" "Перезапустить"
        mi "3" "⏹" "$(xray_active && echo "Остановить" || echo "Запустить")"
        mi "4" "📈" "Статистика inbound/outbound"
        mi "5" "🌍" "Обновить геоданные"
        mi "6" "⬆️ " "Обновить ядро Xray"
        mi "7" "📈" "Metrics endpoint      (HTTP JSON статистика)"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) cls; systemctl status xray --no-pager -l; echo ""; journalctl -u xray -n 30 --no-pager; pause ;;
            2) systemctl restart xray; ok "Перезапущен"; sleep 1 ;;
            3) if xray_active; then systemctl stop xray; ok "Остановлен"
               else systemctl start xray; ok "Запущен"; fi; sleep 1 ;;
            4) show_global_stats ;;
            5) update_geodata ;;
            6) install_xray_core ;;
            7) menu_metrics ;;
            0) return ;;
        esac
    done
}

show_global_stats() {
    cls; box_top " 📈  Глобальная статистика" "$BLUE"; box_blank
    xray_active || { box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return; }
    box_row "  ${DIM}Данные из Stats API (127.0.0.1:${STATS_PORT})${R}"; box_blank
    local stats_out; stats_out=$("$XRAY_BIN" api statsquery \
        --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || echo "[]")
    if [[ "$stats_out" == "[]" || -z "$stats_out" ]]; then
        box_row "  ${DIM}Нет данных (Stats API недоступен или нет трафика)${R}"
    else
        while IFS= read -r line; do
            local name val
            name=$(echo "$line" | jq -r '.name // ""')
            val=$(echo "$line" | jq -r '.value // "0"')
            [[ -z "$name" ]] && continue
            local fmt_val; fmt_val=$(fmt_bytes "$val")
            box_row "  ${DIM}${name}${R}  ${YELLOW}${fmt_val}${R}"
        done < <(echo "$stats_out" | jq -c '.[]' 2>/dev/null)
    fi
    box_blank; box_end; pause
}

update_geodata() {
    cls; box_top " 🌍  Обновление геоданных" "$BLUE"; box_blank
    spin_start "Загрузка geoip.dat + geosite.dat"
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install-geodata &>/tmp/xray_geo.log
    local ec=$?
    spin_stop "$([[ $ec -eq 0 ]] && echo ok || echo err)"
    [[ $ec -eq 0 ]] && { ok "Геоданные обновлены"; xray_restart; } || err "Ошибка"
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  СИСТЕМА
# ──────────────────────────────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════════════════════════════
#  ПОДПИСКА (Subscription)
# ══════════════════════════════════════════════════════════════════════════════

SUB_DIR="/usr/local/etc/xray/subscriptions"
SUB_SVC_FILE="/etc/systemd/system/xray-sub.service"
SUB_PORT_FILE="${SUB_DIR}/.port"
SUB_INTERVAL_FILE="${SUB_DIR}/.interval"
SUB_AUTOUPDATE_FILE="${SUB_DIR}/.autoupdate"

# ── Собрать все ссылки для email по всем inbound ──────────────────────────────
_sub_links_for_email() {
    local email="$1"
    local links=""
    # Кешируем IP один раз до цикла — gen_link может вызываться N×M раз
    local sip; sip="${_CACHED_SERVER_IP:-$(server_ip)}"
    while IFS='|' read -r tag port proto net sec; do
        # Проверить есть ли этот email в данном inbound
        local exists; exists=$(jq -r \
            --arg t "$tag" --arg e "$email" \
            '[.inbounds[]|select(.tag==$t)|
              ((.settings.clients//[]) + (.settings.users//[]))[]]
             | map(select(.email==$e)) | length' \
            "$XRAY_CONF" 2>/dev/null)
        [[ "$exists" -gt 0 ]] || continue

        local link; link=$(gen_link "$tag" "$email" "$sip")
        [[ -n "$link" ]] && links="${links}${link}"$'\n'
    done < <(ib_list)

    # Hysteria2 отдельного бинарника
    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        local dom; dom=$(hy_get_domain 2>/dev/null || true)
        local hport; hport=$(hy_get_port 2>/dev/null || true)
        if [[ -n "$dom" && -n "$hport" ]]; then
            # Найти пароль пользователя
            local hpass; hpass=$(python3 -c "
import sys, re
try:
    cfg = open('$HYSTERIA_CONFIG').read()
    m = re.search(r'^ {4}' + re.escape('${email}'.split('@')[0]) + r':\s*[\"\'']?([^\"\''\n]+)', cfg, re.M)
    if m: print(m.group(1).strip())
except: pass
" 2>/dev/null)
            [[ -n "$hpass" ]] && links="${links}hy2://${hpass}@${dom}:${hport}?sni=${dom}&alpn=h3&insecure=0#${email}-hy2"$'\n'
        fi
    fi

    echo -n "$links"
}

# ── Собрать все ссылки всех пользователей ─────────────────────────────────────
_sub_all_links() {
    local -A seen_emails=()
    local all_links=""
    # Кешируем IP один раз — gen_link вызывается N×M раз в цикле
    local _CACHED_SERVER_IP; _CACHED_SERVER_IP=$(server_ip)
    export _CACHED_SERVER_IP

    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen_emails[$em]}" ]] && continue
            seen_emails["$em"]=1
            local lnk; lnk=$(_sub_links_for_email "$em")
            [[ -n "$lnk" ]] && all_links="${all_links}${lnk}"
        done < <(ib_emails "$tag")
    done < <(ib_list)

    echo -n "$all_links"
}

# ── Clash/Mihomo YAML для одного пользователя ─────────────────────────────────
_sub_clash_for_email() {
    local email="$1"
    local proxies=""
    local proxy_names=""

    while IFS='|' read -r tag port proto net sec; do
        local exists; exists=$(jq -r \
            --arg t "$tag" --arg e "$email" \
            '[.inbounds[]|select(.tag==$t)|
              ((.settings.clients//[]) + (.settings.users//[]))[]]
             | map(select(.email==$e)) | length' \
            "$XRAY_CONF" 2>/dev/null)
        [[ "$exists" -gt 0 ]] || continue

        local name="${email}-${tag}"
        local sip; sip=$(server_ip)
        local p=""

        case "${proto}:${net}" in
            vless:tcp|vless:raw)
                local uuid pbk sid sni
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey"); sid=$(kget "$tag" "shortId")
                p="  - name: ${name}
    type: vless
    server: ${sip}
    port: ${port}
    uuid: ${uuid}
    tls: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${pbk}
      short-id: ${sid}
    servername: ${sni}
    client-fingerprint: firefox
    udp: true"
                ;;
            vless:xhttp)
                local uuid pbk sid sni path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
                sid=$(kget "$tag" "shortId"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vless
    server: ${sip}
    port: ${port}
    uuid: ${uuid}
    tls: true
    network: xhttp
    xhttp-opts:
      path: ${path_v}
      mode: auto
    reality-opts:
      public-key: ${pbk}
      short-id: ${sid}
    servername: ${sni}
    client-fingerprint: firefox
    udp: true"
                ;;
            vless:ws)
                local uuid dom path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vless
    server: ${dom}
    port: 443
    uuid: ${uuid}
    tls: true
    network: ws
    ws-opts:
      path: ${path_v}
    servername: ${dom}
    udp: true"
                ;;
            vmess:ws)
                local uuid dom path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vmess
    server: ${dom}
    port: 443
    uuid: ${uuid}
    alterId: 0
    cipher: auto
    tls: true
    network: ws
    ws-opts:
      path: ${path_v}
      headers:
        Host: ${dom}"
                ;;
            trojan:tcp|trojan:raw)
                local pass dom
                pass=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
                dom=$(kget "$tag" "domain")
                p="  - name: ${name}
    type: trojan
    server: ${dom}
    port: ${port}
    password: ${pass}
    sni: ${dom}
    udp: true"
                ;;
            hysteria:hysteria)
                local pass dom
                pass=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.users[]|select(.email==$e)|.password' "$XRAY_CONF")
                dom=$(kget "$tag" "domain")
                p="  - name: ${name}
    type: hysteria2
    server: ${dom}
    port: ${port}
    password: ${pass}
    sni: ${dom}
    alpn: [h3]"
                ;;
        esac

        if [[ -n "$p" ]]; then
            proxies="${proxies}${p}"$'\n'
            proxy_names="${proxy_names}    - ${name}"$'\n'
        fi
    done < <(ib_list)

    [[ -z "$proxies" ]] && return

    cat << YAML
proxies:
${proxies}
proxy-groups:
  - name: PROXY
    type: select
    proxies:
$(echo "$proxy_names" | sed 's/^//')    - DIRECT

  - name: AUTO
    type: url-test
    url: https://www.google.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
${proxy_names}
rules:
  - GEOIP,LAN,DIRECT
  - MATCH,PROXY
YAML
}

# ── HTTP сервер подписки ───────────────────────────────────────────────────────

_sub_is_running() {
    systemctl is-active --quiet xray-sub 2>/dev/null
}

_sub_get_port() {
    [[ -f "$SUB_PORT_FILE" ]] && cat "$SUB_PORT_FILE" || echo "8888"
}

_sub_get_interval() {
    [[ -f "$SUB_INTERVAL_FILE" ]] && cat "$SUB_INTERVAL_FILE" || echo "12"
}

_sub_autoupdate_enabled() {
    [[ -f "$SUB_AUTOUPDATE_FILE" ]] && [[ "$(cat "$SUB_AUTOUPDATE_FILE")" == "1" ]]
}

_sub_start() {
    local port="$1"
    mkdir -p "$SUB_DIR"
    echo "$port" > "$SUB_PORT_FILE"

    # Обновить файлы подписок
    _sub_update_files

    # Создать Python HTTP-сервер
    cat > "${SUB_DIR}/server.py" << 'PYSERVER'
#!/usr/bin/env python3
import http.server, os, base64, sys

SUB_DIR = os.path.dirname(os.path.abspath(__file__))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8888

def get_interval():
    f = os.path.join(SUB_DIR, ".interval")
    try:
        return open(f).read().strip() if os.path.exists(f) else "12"
    except Exception:
        return "12"

class SubHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # тихий режим

    def do_GET(self):
        path = self.path.strip("/")
        # Токен безопасности: первая часть пути
        parts = path.split("/", 1)
        if len(parts) < 2:
            self.send_response(404); self.end_headers(); return

        token, rest = parts[0], parts[1] if len(parts) > 1 else ""

        # Проверить токен
        token_file = os.path.join(SUB_DIR, ".token")
        if os.path.exists(token_file):
            with open(token_file) as f:
                expected = f.read().strip()
            if token != expected:
                self.send_response(403); self.end_headers(); return

        # Маршруты
        if rest == "" or rest == "sub":
            # Базовая base64 подписка — все пользователи
            fn = os.path.join(SUB_DIR, "all.b64")
        elif rest == "clash":
            fn = os.path.join(SUB_DIR, "all.clash.yaml")
        elif rest.startswith("u/"):
            email = rest[2:]
            safe = email.replace("@", "_at_").replace(".", "_")
            fn = os.path.join(SUB_DIR, f"user_{safe}.b64")
        elif rest.startswith("clash/u/"):
            email = rest[8:]
            safe = email.replace("@", "_at_").replace(".", "_")
            fn = os.path.join(SUB_DIR, f"user_{safe}.clash.yaml")
        else:
            self.send_response(404); self.end_headers(); return

        if not os.path.exists(fn):
            self.send_response(404); self.end_headers(); return

        with open(fn, "rb") as f:
            data = f.read()

        ct = "text/plain; charset=utf-8"
        if fn.endswith(".yaml"):
            ct = "text/yaml; charset=utf-8"

        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Profile-Update-Interval", get_interval())
        self.send_header("Content-Disposition", "inline")
        self.end_headers()
        self.wfile.write(data)

if __name__ == "__main__":
    print(f"Subscription server on port {PORT}", flush=True)
    server = http.server.HTTPServer(("127.0.0.1", PORT), SubHandler)
    server.serve_forever()
PYSERVER

    # Systemd unit
    cat > "$SUB_SVC_FILE" << EOF
[Unit]
Description=Xray Subscription Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SUB_DIR}/server.py ${port}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray-sub
    sleep 1
    _sub_is_running && ok "Сервер подписки запущен на 127.0.0.1:${port}" || warn "Не удалось запустить"
}

_sub_update_files() {
    mkdir -p "$SUB_DIR"
    local -A seen=()

    # ── Все пользователи — base64 ──
    local all_links; all_links=$(_sub_all_links)
    echo -n "$all_links" | base64 -w0 > "${SUB_DIR}/all.b64"

    # ── Clash — все пользователи (первый найденный) ──
    local first_email=""
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1
            [[ -z "$first_email" ]] && first_email="$em"

            # Индивидуальная base64
            local ulinks; ulinks=$(_sub_links_for_email "$em")
            local safe="${em//@/_at_}"; safe="${safe//./_}"
            echo -n "$ulinks" | base64 -w0 > "${SUB_DIR}/user_${safe}.b64"

            # Индивидуальный Clash
            _sub_clash_for_email "$em" > "${SUB_DIR}/user_${safe}.clash.yaml"
        done < <(ib_emails "$tag")
    done < <(ib_list)

    # Clash для всех: берём первого пользователя как шаблон (или объединяем)
    [[ -n "$first_email" ]] && \
        _sub_clash_for_email "$first_email" > "${SUB_DIR}/all.clash.yaml"

    ok "Файлы подписок обновлены"
}

# ── Главное меню подписки ──────────────────────────────────────────────────────

menu_subscription() {
    while true; do
        cls; box_top " 📡  Подписка (Subscription)" "$CYAN"
        box_blank

        local sub_status sub_port sub_token="" sub_interval
        sub_port=$(_sub_get_port)
        sub_interval=$(_sub_get_interval)
        [[ -f "${SUB_DIR}/.token" ]] && sub_token=$(cat "${SUB_DIR}/.token")

        if _sub_is_running; then
            box_row "  Статус:  ${GREEN}● работает${R}  порт ${YELLOW}${sub_port}${R}  интервал ${CYAN}${sub_interval}ч${R}"
        else
            box_row "  Статус:  ${DIM}○ не запущен${R}"
        fi

        if [[ -n "$sub_token" ]]; then
            local sip; sip=$(server_ip)
            box_row "  Токен:   ${DIM}${sub_token}${R}"
            box_blank
            box_row "  ${YELLOW}Ссылки (через обратный прокси/туннель):${R}"
            box_row "  ${DIM}Все       http://127.0.0.1:${sub_port}/${sub_token}/sub${R}"
            box_row "  ${DIM}Clash     http://127.0.0.1:${sub_port}/${sub_token}/clash${R}"
            box_row "  ${DIM}Польз.    http://127.0.0.1:${sub_port}/${sub_token}/u/EMAIL${R}"
        fi

        box_blank; box_mid
        if _sub_is_running; then
            mi "1" "🔄" "Обновить файлы подписок"
            mi "2" "🔗" "Показать ссылки и QR"
            mi "3" "👤" "Подписка для конкретного пользователя"
            mi "4" "⏹" "${RED}Остановить сервер${R}"
        else
            mi "1" "▶" "${GREEN}Запустить сервер подписки${R}"
        fi
        mi "5" "📋" "Показать содержимое подписки"
        mi "6" "⏱" "Интервал обновления  ${DIM}(сейчас: ${sub_interval}ч)${R}"
        if _sub_autoupdate_enabled; then
            mi "7" "🔁" "Автообновление при добавлении  ${GREEN}[вкл]${R}"
        else
            mi "7" "🔁" "Автообновление при добавлении  ${DIM}[выкл]${R}"
        fi
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch

        if _sub_is_running; then
            case "$ch" in
                1) _sub_update_files; pause ;;
                2) sub_show_links ;;
                3) sub_user_links ;;
                4)
                    systemctl stop xray-sub
                    systemctl disable xray-sub
                    ok "Сервер остановлен"
                    pause
                    ;;
                5) sub_show_content ;;
                6) sub_set_interval ;;
                7) sub_toggle_autoupdate ;;
                0) return ;;
            esac
        else
            case "$ch" in
                1) sub_setup ;;
                5) sub_show_content ;;
                6) sub_set_interval ;;
                7) sub_toggle_autoupdate ;;
                0) return ;;
            esac
        fi
    done
}

sub_setup() {
    cls; box_top " ▶  Запуск сервера подписки" "$GREEN"; box_blank
    box_row "  ${CYAN}${BOLD}Что это:${R}"
    box_row "  ${DIM}Сервер отдаёт base64-список ссылок и Clash YAML по HTTP.${R}"
    box_row "  ${DIM}Клиент (v2rayN, Mihomo) периодически скачивает и обновляет.${R}"
    box_blank
    box_row "  ${YELLOW}⚠  Сервер слушает только 127.0.0.1 — доступен через SSH-туннель или Nginx.${R}"
    box_blank

    local port token
    ask "Порт сервера" port "8888"
    ask "Токен безопасности (Enter = сгенерировать)" token ""
    if [[ -z "$token" ]]; then
        token=$(openssl rand -hex 12)
        info "Сгенерирован токен: ${token}"
    fi

    mkdir -p "$SUB_DIR"
    echo "$token" > "${SUB_DIR}/.token"

    _sub_start "$port"

    cls; box_top " ✅  Сервер подписки запущен" "$GREEN"; box_blank
    box_row "  Порт:  ${YELLOW}${port}${R}"
    box_row "  Токен: ${CYAN}${token}${R}"
    box_blank
    box_row "  ${YELLOW}Прямой доступ (только с этого сервера):${R}"
    box_row "  ${DIM}Base64  http://127.0.0.1:${port}/${token}/sub${R}"
    box_row "  ${DIM}Clash   http://127.0.0.1:${port}/${token}/clash${R}"
    box_blank
    box_row "  ${YELLOW}Для клиентов снаружи — SSH-туннель:${R}"
    box_row "  ${DIM}ssh -L ${port}:127.0.0.1:${port} user@$(server_ip)${R}"
    box_row "  ${DIM}Затем в клиенте: http://127.0.0.1:${port}/${token}/sub${R}"
    box_blank
    box_row "  ${YELLOW}Или Nginx location (если есть домен):${R}"
    box_row "  ${DIM}location /${token}/ { proxy_pass http://127.0.0.1:${port}; }${R}"
    box_blank; box_end; pause
}


sub_set_interval() {
    cls; box_top " ⏱  Интервал обновления подписки" "$CYAN"; box_blank
    local cur; cur=$(_sub_get_interval)
    box_row "  Текущий интервал: ${CYAN}${cur} ч${R}"
    box_row "  ${DIM}Клиент обновляет подписку раз в N часов.${R}"
    box_row "  ${DIM}Рекомендуется: 12 (умеренно), 1 (быстро), 24 (редко).${R}"
    box_blank; box_end
    local val
    ask "Новый интервал в часах" val "$cur"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -lt 1 ]] || [[ "$val" -gt 168 ]]; then
        err "Введите число от 1 до 168"; pause; return
    fi
    mkdir -p "$SUB_DIR"
    echo "$val" > "$SUB_INTERVAL_FILE"
    ok "Интервал установлен: ${val} ч"
    box_row "  ${DIM}Вступит в силу при следующем запросе клиента.${R}"
    box_row "  ${DIM}Перезапуск сервера не требуется.${R}"
    box_end; pause
}

sub_toggle_autoupdate() {
    cls; box_top " 🔁  Автообновление подписки" "$CYAN"; box_blank
    if _sub_autoupdate_enabled; then
        box_row "  Текущий режим: ${GREEN}включено${R}"
        box_row "  ${DIM}Файлы подписки обновляются автоматически${R}"
        box_row "  ${DIM}при каждом добавлении пользователя.${R}"
        box_blank; box_end
        ask "Выключить автообновление? [y/N]" confirm "n"
        if [[ "${confirm,,}" == "y" ]]; then
            echo "0" > "$SUB_AUTOUPDATE_FILE"
            ok "Автообновление выключено"
        else
            info "Без изменений"
        fi
    else
        box_row "  Текущий режим: ${DIM}выключено${R}"
        box_row "  ${DIM}Файлы подписки обновляются только вручную${R}"
        box_row "  ${DIM}через пункт \"Обновить файлы подписок\".${R}"
        box_blank; box_end
        ask "Включить автообновление? [Y/n]" confirm "y"
        if [[ "${confirm,,}" != "n" ]]; then
            mkdir -p "$SUB_DIR"
            echo "1" > "$SUB_AUTOUPDATE_FILE"
            ok "Автообновление включено"
        else
            info "Без изменений"
        fi
    fi
    pause
}
sub_show_links() {
    cls; box_top " 🔗  Ссылки подписки" "$CYAN"; box_blank
    local port; port=$(_sub_get_port)
    local token=""
    [[ -f "${SUB_DIR}/.token" ]] && token=$(cat "${SUB_DIR}/.token")
    [[ -z "$token" ]] && { warn "Токен не найден"; pause; return; }

    local sip; sip=$(server_ip)

    box_row "  ${YELLOW}Для вставки в клиент (через SSH-туннель или Nginx):${R}"
    box_blank
    box_row "  ${CYAN}Все пользователи — Base64 (v2rayN, v2rayNG):${R}"
    box_row "  ${DIM}http://127.0.0.1:${port}/${token}/sub${R}"
    box_blank
    box_row "  ${CYAN}Все пользователи — Clash YAML (Mihomo):${R}"
    box_row "  ${DIM}http://127.0.0.1:${port}/${token}/clash${R}"
    box_blank
    box_row "  ${YELLOW}Индивидуальные подписки (по пользователю):${R}"
    local -A seen=()
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1
            box_row "  ${DIM}${em}${R}"
            box_row "    ${DIM}Base64  http://127.0.0.1:${port}/${token}/u/${em}${R}"
            box_row "    ${DIM}Clash   http://127.0.0.1:${port}/${token}/clash/u/${em}${R}"
        done < <(ib_emails "$tag")
    done < <(ib_list)
    box_blank
    box_row "  ${YELLOW}Через публичный Nginx (замени domain.com):${R}"
    box_row "  ${DIM}https://domain.com/${token}/sub${R}"
    box_blank; box_end; pause
}

sub_user_links() {
    cls; box_top " 👤  Подписка пользователя" "$YELLOW"; box_blank

    # Собрать список пользователей
    local -A seen=()
    local -a emails=()
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1; emails+=("$em")
        done < <(ib_emails "$tag")
    done < <(ib_list)

    [[ ${#emails[@]} -eq 0 ]] && { box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return; }

    local i=1
    for em in "${emails[@]}"; do mi "$i" "👤" "$em"; ((i++)); done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return

    local sel_email="${emails[$((ch-1))]}"
    [[ -z "$sel_email" ]] && return

    cls; box_top " 🔗  Подписка: ${sel_email}" "$CYAN"; box_blank

    # Показать все ссылки этого пользователя
    local links; links=$(_sub_links_for_email "$sel_email")
    if [[ -z "$links" ]]; then
        box_row "  ${DIM}Нет ссылок для этого пользователя${R}"
    else
        local cnt=0
        while IFS= read -r lnk; do
            [[ -z "$lnk" ]] && continue
            ((cnt++))
            # Укоротить ссылку для отображения
            local disp="${lnk:0:80}"
            [[ ${#lnk} -gt 80 ]] && disp="${disp}..."
            box_row "  ${DIM}${cnt})${R} ${CYAN}${disp}${R}"
        done <<< "$links"
        box_blank
        box_row "  Итого ссылок: ${YELLOW}${cnt}${R}"
        box_blank
        # Base64 для копирования
        local b64; b64=$(echo -n "$links" | base64 -w0)
        box_row "  ${YELLOW}Base64 (вставить в клиент как URL подписки):${R}"
        box_row "  ${DIM}${b64:0:100}...${R}"
        box_blank
        # QR-код base64 URL (если короткий)
        if [[ ${#b64} -lt 500 ]] && command -v qrencode &>/dev/null; then
            box_row "  ${YELLOW}QR (Base64):${R}"
            box_end
            echo "$b64" | qrencode -t ansiutf8 2>/dev/null || true
        fi
    fi

    box_blank; box_end; pause
}

sub_show_content() {
    cls; box_top " 📋  Содержимое подписки" "$DIM"; box_blank
    local all_links; all_links=$(_sub_all_links)
    if [[ -z "$all_links" ]]; then
        box_row "  ${DIM}Нет ссылок — добавьте протоколы и пользователей${R}"
        box_blank; box_end; pause; return
    fi

    local cnt=0
    while IFS= read -r lnk; do
        [[ -z "$lnk" ]] && continue
        ((cnt++))
        local proto_mark
        case "$lnk" in
            vless://*) proto_mark="${CYAN}VLESS${R}" ;;
            vmess://*) proto_mark="${ORANGE}VMess${R}" ;;
            trojan://*) proto_mark="${GREEN}Trojan${R}" ;;
            ss://*) proto_mark="${MAGENTA}SS${R}" ;;
            hy2://*) proto_mark="${GREEN}HY2${R}" ;;
            *) proto_mark="${DIM}?${R}" ;;
        esac
        # Извлечь имя (#fragment)
        local name; name=$(echo "$lnk" | grep -oP '#\K.*' || echo "")
        printf "${DIM}│${R}  %b %-30s ${DIM}%s${R}\n" \
            "$proto_mark" "$name" "${lnk:0:50}..."
    done <<< "$all_links"

    box_blank
    box_row "  Итого: ${YELLOW}${cnt}${R} ссылок"
    box_blank; box_end; pause
}

menu_system() {
    while true; do
        cls; box_top " 🛠  Система" "$ORANGE"; box_blank; box_mid
        mi "1" "🔧" "BBR + оптимизация сети"
        mi "2" "💾" "Бэкап конфигурации"
        mi "3" "♻️ " "Восстановить конфиг"
        mi "4" "⏰" "Установить таймер проверки лимитов"
        mi "5" "🔍" "Проверить лимиты вручную"
        mi "6" "📋" "Посмотреть текущий config.json"
        mi "7" "🗑" "${RED}Удалить Xray полностью${R}"
        box_row "  ${MAGENTA}${BOLD}Расширенные функции${R}"
        # Показать статус фрагментации в меню
        local _frag_status=""
        if _fragment_is_enabled 2>/dev/null; then
            local _fp; _fp=$(jq -r '.outbounds[]|select(.protocol=="freedom")|.settings.fragment.packets // ""' "$XRAY_CONF" 2>/dev/null | head -1)
            _frag_status="${GREEN}● ${_fp}${R}"
        else
            _frag_status="${DIM}○ выкл${R}"
        fi
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${CYAN}Fragment — фрагментация TLS${R}  %b%-*s${DIM}│${R}
" \
            "8" "🧩" "$_frag_status" $(($(tw)-52)) ""
        mi "9" "🔊" "${CYAN}Noises — UDP шум перед соединением${R}"
        mi "10" "🛡️ " "${YELLOW}Fallbacks — защита от зондирования${R}"
        mi "11" "⚖️ " "${MAGENTA}Балансировщик нагрузки + Observatory${R}"
        mi "12" "🚀" "${GREEN}Hysteria2 Outbound — relay/цепочка${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) menu_bbr_tune ;;
            2) do_backup ;;
            3) do_restore ;;
            4) install_limits_timer; ok "Таймер установлен (каждые 5 минут)"; pause ;;
            5) cls; check_limits; pause ;;
            6) cls; cat "$XRAY_CONF" | python3 -m json.tool 2>/dev/null || cat "$XRAY_CONF"; pause ;;
            7) do_remove_all ;;
            8) menu_freedom_fragment ;;
            9) menu_freedom_noises ;;
            10) menu_fallbacks ;;
            11) menu_balancer ;;
            12) menu_hysteria_outbound ;;
            0) return ;;
        esac
    done
}

do_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local bf="${BACKUP_DIR}/xray-backup-${ts}.tar.gz"
    local files=()
    [[ -f "$XRAY_CONF" ]] && files+=("$XRAY_CONF")
    [[ -f "$LIMITS_FILE" ]] && files+=("$LIMITS_FILE")
    for f in "${XRAY_KEYS_DIR}"/.keys.*; do [[ -f "$f" ]] && files+=("$f"); done
    [[ ${#files[@]} -eq 0 ]] && { warn "Нечего сохранять"; pause; return; }
    tar -czf "$bf" "${files[@]}" 2>/dev/null
    ok "Бэкап: ${CYAN}${bf}${R}"
    # Ротация: хранить последние 7 бэкапов, удалять старые
    local old_count; old_count=$(ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | tail -n +8 | wc -l)
    if [[ "$old_count" -gt 0 ]]; then
        ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
        info "Удалено старых бэкапов: ${old_count}"
    fi
    local total; total=$(ls "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | wc -l)
    info "Всего бэкапов: ${total} (хранится последних 7)"
    pause
}

do_restore() {
    cls; box_top " ♻️  Восстановление" "$ORANGE"; box_blank
    local baks=(); while IFS= read -r f; do baks+=("$f"); done < <(ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null)
    if [[ ${#baks[@]} -eq 0 ]]; then box_row "  ${DIM}Нет бэкапов${R}"; box_end; pause; return; fi
    local i=1
    for b in "${baks[@]}"; do
        local sz; sz=$(du -sh "$b" 2>/dev/null | cut -f1)
        mi "$i" "💾" "$(basename "$b")" "  ${sz}"
        ((i++))
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#baks[@]} ]]; then
        local bak="${baks[$((ch-1))]}"
        # Защита от path traversal: проверяем что архив содержит только
        # ожидаемые пути. Покрываем оба варианта: tar без ./ и с ./ префиксом
        # (стандартный вывод tar -czf ... -C / ./usr/... содержит ./-префикс).
        local bad_paths; bad_paths=$(tar -tzf "$bak" 2>/dev/null \
            | grep -v -e '^usr/local/etc/xray/' \
                      -e '^\./usr/local/etc/xray/' \
                      -e '^var/log/xray/' \
                      -e '^\./var/log/xray/' \
                      -e '^\.$' \
                      -e '^\./$' \
            || true)
        if [[ -n "$bad_paths" ]]; then
            err "Архив содержит подозрительные пути — восстановление прервано"
            box_row "  ${RED}Неожиданные пути в архиве:${R}"
            echo "$bad_paths" | head -5 | while IFS= read -r p; do box_row "  ${DIM}${p}${R}"; done
            box_end; pause; return
        fi
        confirm "Восстановить? Текущий конфиг будет перезаписан." && {
            tar -xzf "$bak" -C / 2>/dev/null
            xray_restart; ok "Конфиг восстановлен"
        }
    fi
    pause
}

do_remove_all() {
    cls; box_top " 🗑  Удаление Xray" "$RED"; box_blank
    box_row "  ${RED}${BOLD}ЭТО УДАЛИТ ВСЁ: ядро, конфиги, ключи, логи!${R}"
    box_blank; box_end
    confirm "Вы уверены?" "n" || return
    confirm "Последнее предупреждение. Продолжить?" "n" || return
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ remove --purge 2>/dev/null || true
    rm -f "$XRAY_CONF" "$LIMITS_FILE" "${XRAY_KEYS_DIR}"/.keys.* "$MANAGER_BIN"
    systemctl disable --now xray-limits.timer 2>/dev/null || true
    ok "Xray полностью удалён"; exit 0
}

# ──────────────────────────────────────────────────────────────────────────────
#  ГЛАВНОЕ МЕНЮ
# ──────────────────────────────────────────────────────────────────────────────


# ══════════════════════════════════════════════════════════════════════════════
#  СОВМЕСТИМОСТЬ (псевдонимы для MTProto и Hysteria секций)
# ══════════════════════════════════════════════════════════════════════════════

NC="$R"
# Псевдонимы для совместимости с MTProto/Hysteria секциями — не переобъявляем цвета,
# используем уже объявленные в начале файла (двойные кавычки, \e раскрывается).
WHITE="${WHITE:-\e[1;37m}"

die()       { printf "${RED}  ✗  %s${R}\n" "$*" >&2; exit 1; }
gen_secret(){ openssl rand -hex 16; }

get_public_ip() { server_ip; }

get_telemt_version() {
    "$TELEMT_BIN" --version 2>/dev/null | awk '{print $2}' | head -1 || echo ""
}
get_hysteria_version() {
    /usr/local/bin/hysteria version 2>/dev/null | awk '/^Version:/{v=$2; sub(/^v/,"",v); print v; exit}' || true
}

header() {
    clear
    printf "\n${BOLD}${WHITE}  %s${R}\n" "$*"
    printf "${GRAY}  ────────────────────────────────────────${R}\n\n"
}

# ── SSH-миграция ──────────────────────────────────────────────────

_SSH_IP=""; _SSH_PORT="22"; _SSH_USER="root"; _SSH_PASS=""

ensure_sshpass() {
    command -v sshpass &>/dev/null && return
    info "Устанавливаю sshpass..."
    apt-get install -y -q sshpass 2>/dev/null && ok "sshpass установлен"
}

ask_ssh_target() {
    read -rp "  IP нового сервера: " _SSH_IP < /dev/tty
    read -rp "  SSH порт [22]: " _SSH_PORT < /dev/tty; _SSH_PORT="${_SSH_PORT:-22}"
    read -rp "  Пользователь [root]: " _SSH_USER < /dev/tty; _SSH_USER="${_SSH_USER:-root}"
    read -rsp "  Пароль: " _SSH_PASS < /dev/tty; echo ""
}

init_ssh_helpers() {
    local mode="${1:-full}"
    local base_opts="-o StrictHostKeyChecking=no -o BatchMode=no -o ConnectTimeout=10 -p ${_SSH_PORT}"
    [[ "$mode" == "telemt" ]] && base_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p ${_SSH_PORT}"
    RUN() { sshpass -p "$_SSH_PASS" ssh $base_opts "${_SSH_USER}@${_SSH_IP}" "$@"; }
    PUT() { sshpass -p "$_SSH_PASS" scp -rp $base_opts "$@"; }
    export -f RUN PUT 2>/dev/null || true
}

check_ssh_connection() {
    RUN echo ok >/dev/null 2>&1 || { err "Не удалось подключиться к ${_SSH_IP}:${_SSH_PORT}"; return 1; }
    ok "Подключение к ${_SSH_IP}:${_SSH_PORT} успешно"
}

# ══════════════════════════════════════════════════════════════════════════════
#  MTProto (telemt) — СЕКЦИЯ
# ══════════════════════════════════════════════════════════════════════════════

TELEMT_BIN="/usr/local/bin/telemt"
TELEMT_CONFIG_DIR="/etc/telemt"
TELEMT_CONFIG_SYSTEMD="/etc/telemt/telemt.toml"
TELEMT_WORK_DIR_SYSTEMD="/opt/telemt"
TELEMT_TLSFRONT_DIR="/opt/telemt/tlsfront"
TELEMT_SERVICE_FILE="/etc/systemd/system/telemt.service"
TELEMT_WORK_DIR_DOCKER="${HOME}/mtproxy"
TELEMT_CONFIG_DOCKER="${HOME}/mtproxy/telemt.toml"
TELEMT_COMPOSE_FILE="${HOME}/mtproxy/docker-compose.yml"
TELEMT_GITHUB_REPO="telemt/telemt"
TELEMT_MODE=""
TELEMT_CONFIG_FILE=""
TELEMT_WORK_DIR=""
TELEMT_CHOSEN_VERSION="latest"

telemt_choose_mode() {
    header "telemt MTProxy — метод установки"
    echo -e "  ${BOLD}1)${R} ${BOLD}systemd${R} — бинарник с GitHub"
    echo -e "     ${CYAN}Рекомендуется:${R} hot reload, меньше RAM, миграция"
    echo ""
    echo -e "  ${BOLD}2)${R} ${BOLD}Docker${R} — образ с GitHub Container Registry"
    echo ""
    echo -e "  ${BOLD}0)${R} Назад"
    echo ""
    local ch; read -rp "Выбор [1/2]: " ch < /dev/tty
    case "$ch" in
        1) TELEMT_MODE="systemd"; TELEMT_CONFIG_FILE="$TELEMT_CONFIG_SYSTEMD"; TELEMT_WORK_DIR="$TELEMT_WORK_DIR_SYSTEMD" ;;
        2) TELEMT_MODE="docker";  TELEMT_CONFIG_FILE="$TELEMT_CONFIG_DOCKER";  TELEMT_WORK_DIR="$TELEMT_WORK_DIR_DOCKER" ;;
        0) return 1 ;;
        *) warn "Неверный выбор"; telemt_choose_mode ;;
    esac
    ok "Режим: $TELEMT_MODE"
}

telemt_check_deps() {
    for cmd in curl openssl python3; do
        command -v "$cmd" &>/dev/null || die "Не найдена команда: $cmd"
    done
    if [ "$TELEMT_MODE" = "docker" ]; then
        command -v docker &>/dev/null || die "Docker не установлен."
        docker compose version &>/dev/null || die "Нужен Docker Compose v2."
    else
        command -v systemctl &>/dev/null || die "systemctl не найден. Используй Docker-режим."
    fi
}

telemt_is_running() {
    if [ "$TELEMT_MODE" = "systemd" ]; then
        systemctl is-active --quiet telemt 2>/dev/null
    else
        docker compose -f "$TELEMT_COMPOSE_FILE" ps --status running 2>/dev/null | grep -q "telemt"
    fi
}

telemt_wait_api() {
    local attempts="${1:-15}" i=0
    while [ $i -lt "$attempts" ]; do
        local resp; resp=$(curl -s --max-time 3 "http://127.0.0.1:9091/v1/health" 2>/dev/null || true)
        echo "$resp" | grep -q '"ok":true' && return 0
        i=$((i+1)); sleep 2; echo -n "."
    done
    echo ""; return 1
}

telemt_pick_version() {
    info "Получаю список версий..."
    local versions
    versions=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/${TELEMT_GITHUB_REPO}/releases?per_page=10" 2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -10 || true)
    [ -z "$versions" ] && { warn "Не удалось получить список. Используется latest."; TELEMT_CHOSEN_VERSION="latest"; return; }
    echo ""
    echo -e "${BOLD}Доступные версии:${R}"
    local i=1; local -a va=()
    while IFS= read -r v; do
        [ $i -eq 1 ] && echo -e "  ${GREEN}${BOLD}$i)${R} $v  ${CYAN}← последняя${R}" \
                      || echo -e "  ${BOLD}$i)${R} $v"
        va+=("$v"); i=$((i+1))
    done <<< "$versions"
    echo ""
    local ch; read -rp "Версия [1]: " ch < /dev/tty; ch="${ch:-1}"
    if echo "$ch" | grep -qE '^[0-9]+$' && [ "$ch" -ge 1 ] && [ "$ch" -le "${#va[@]}" ]; then
        TELEMT_CHOSEN_VERSION="${va[$((ch-1))]}"
    else
        warn "Неверный выбор, используется latest."; TELEMT_CHOSEN_VERSION="latest"
    fi
}

telemt_download_binary() {
    local ver="${1:-latest}" arch libc url
    arch=$(uname -m)
    case "$arch" in x86_64) ;; aarch64|arm64) arch="aarch64" ;; *) die "Архитектура не поддерживается: $arch" ;; esac
    ldd --version 2>&1 | grep -iq musl && libc="musl" || libc="gnu"
    [ "$ver" = "latest" ] \
        && url="https://github.com/${TELEMT_GITHUB_REPO}/releases/latest/download/telemt-${arch}-linux-${libc}.tar.gz" \
        || url="https://github.com/${TELEMT_GITHUB_REPO}/releases/download/${ver}/telemt-${arch}-linux-${libc}.tar.gz"
    info "Скачиваю telemt $ver..."
    local tmp; tmp=$(mktemp -d); _TMPFILES+=("$tmp")
    curl -fsSL "$url" | tar -xz -C "$tmp" \
        && install -m 0755 "$tmp/telemt" "$TELEMT_BIN" \
        && rm -rf "$tmp" \
        && ok "Установлен: $TELEMT_BIN" \
        || { rm -rf "$tmp"; die "Не удалось скачать бинарник."; }
}

telemt_write_config() {
    local port="$1" domain="$2"; shift 2
    local tls_front_dir api_listen api_wl
    if [ "$TELEMT_MODE" = "systemd" ]; then
        mkdir -p "$TELEMT_CONFIG_DIR" "$TELEMT_TLSFRONT_DIR"
        tls_front_dir="$TELEMT_TLSFRONT_DIR"; api_listen="127.0.0.1:9091"; api_wl='["127.0.0.1/32"]'
    else
        mkdir -p "$TELEMT_WORK_DIR_DOCKER"; tls_front_dir="tlsfront"; api_listen="0.0.0.0:9091"; api_wl='["127.0.0.0/8"]'
    fi
    { cat <<EOF
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show = "*"

[server]
port = $port

[server.api]
enabled   = true
listen    = "$api_listen"
whitelist = $api_wl

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain    = "$domain"
mask          = true
tls_emulation = true
tls_front_dir = "$tls_front_dir"

[access.users]
EOF
      for pair in "$@"; do echo "${pair%% *} = \"${pair#* }\""; done
    } > "$TELEMT_CONFIG_FILE"
    [ "$TELEMT_MODE" = "systemd" ] && chmod 640 "$TELEMT_CONFIG_FILE"
}

telemt_write_service() {
    cat > "$TELEMT_SERVICE_FILE" <<'EOF'
[Unit]
Description=Telemt MTProto Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/usr/local/bin/telemt /etc/telemt/telemt.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
}

telemt_write_compose() {
    local port="$1"
    cat > "$TELEMT_COMPOSE_FILE" <<EOF
services:
  telemt:
    image: ghcr.io/telemt/telemt:latest
    container_name: telemt
    restart: unless-stopped
    working_dir: /run/telemt
    volumes:
      - ./telemt.toml:/run/telemt/config.toml:ro
    tmpfs:
      - /run/telemt:rw,mode=1777,size=1m
    ports:
      - "${port}:${port}/tcp"
      - "127.0.0.1:9091:9091/tcp"
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    read_only: true
    ulimits: {nofile: {soft: 65536, hard: 65536}}
    logging: {driver: json-file, options: {max-size: "10m", max-file: "3"}}
EOF
}

telemt_api() {
    local method="$1" path="$2" body="${3:-}"
    local url="http://127.0.0.1:9091${path}"
    if [ -n "$body" ]; then
        curl -s --max-time 10 -X "$method" -H "Content-Type: application/json" -d "$body" "$url" 2>/dev/null
    else
        curl -s --max-time 10 -X "$method" "$url" 2>/dev/null
    fi
}

telemt_api_ok()    { echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; }
telemt_api_error() { echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('message','неизвестная ошибка'))" 2>/dev/null; }

telemt_fetch_links() {
    local attempt=0
    info "Запрашиваю данные через API..."
    while [ $attempt -lt 15 ]; do
        local resp; resp=$(telemt_api GET "/v1/users" || true)
        if echo "$resp" | grep -q "tg://proxy"; then
            echo ""
            echo "$resp" | python3 -c "
import sys, json
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; GRAY='\033[0;37m'; RESET='\033[0m'
def fmt_bytes(b):
    if not b: return '0 B'
    for u in ('B','KB','MB','GB','TB'):
        if b < 1024: return f'{b:.1f} {u}' if u != 'B' else f'{int(b)} B'
        b /= 1024
    return f'{b:.2f} PB'
data = json.load(sys.stdin)
users = data if isinstance(data, list) else data.get('users', data.get('data', []))
if isinstance(users, dict): users = list(users.values())
for u in users:
    name = u.get('username') or u.get('name') or 'user'
    tls  = u.get('links', {}).get('tls', [])
    conns = u.get('current_connections', 0)
    aips  = u.get('active_unique_ips', 0)
    oct   = u.get('total_octets', 0)
    mc    = u.get('max_tcp_conns')
    mi    = u.get('max_unique_ips')
    q     = u.get('data_quota_bytes')
    exp   = u.get('expiration_rfc3339')
    print(f'{BOLD}{CYAN}┌─ {name}{RESET}')
    if tls: print(f'{BOLD}│  Ссылка:{RESET}      {tls[0]}')
    print(f'{BOLD}│  Подключений:{RESET} {conns}' + (f' / {mc}' if mc else ''))
    print(f'{BOLD}│  Активных IP:{RESET} {aips}' + (f' / {mi}' if mi else ''))
    print(f'{BOLD}│  Трафик:{RESET}      {fmt_bytes(oct)}' + (f' / {fmt_bytes(q)}' if q else ''))
    if exp: print(f'{BOLD}│  Истекает:{RESET}    {exp}')
    print(f'{BOLD}└{chr(9472)*44}{RESET}'); print()
" 2>/dev/null || echo "$resp"
            return 0
        fi
        attempt=$((attempt+1)); sleep 2; echo -n "."
    done
    echo ""; warn "API не ответил. Попробуй: curl -s http://127.0.0.1:9091/v1/users"
    return 1
}

telemt_user_count() {
    local resp; resp=$(telemt_api GET "/v1/users" 2>/dev/null || true)
    echo "$resp" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    users=d if isinstance(d,list) else d.get('data',d.get('users',[]))
    if isinstance(users,dict): users=list(users.values())
    print(len(users))
except: print('')
" 2>/dev/null || true
}

telemt_ask_users() {
    TELEMT_USER_PAIRS=()
    info "Добавление пользователей"
    while true; do
        local uname; read -rp "  Имя [Enter чтобы завершить]: " uname < /dev/tty
        [ -z "$uname" ] && [ ${#TELEMT_USER_PAIRS[@]} -gt 0 ] && break
        [ -z "$uname" ] && { warn "Нужен хотя бы один пользователь!"; continue; }
        local secret; read -rp "  Секрет (32 hex) [Enter = сгенерировать]: " secret < /dev/tty
        if [ -z "$secret" ]; then
            secret=$(gen_secret); ok "Секрет: $secret"
        elif ! echo "$secret" | grep -qE '^[0-9a-fA-F]{32}$'; then
            warn "Секрет должен быть 32 hex-символа"; continue
        fi
        TELEMT_USER_PAIRS+=("$uname $secret"); ok "Пользователь '$uname' добавлен"
        echo ""
    done
}

telemt_menu_install() {
    header "Установка MTProxy (${TELEMT_MODE})"
    local port; read -rp "Порт прокси [8443]: " port; port="${port:-8443}" < /dev/tty
    ss -tlnp 2>/dev/null | grep -q ":${port} " && { warn "Порт $port занят!"; read -rp "Другой порт: " port; } < /dev/tty
    local domain; read -rp "Домен-маскировка [petrovich.ru]: " domain; domain="${domain:-petrovich.ru}" < /dev/tty
    echo ""; telemt_ask_users
    if [ "$TELEMT_MODE" = "systemd" ]; then
        telemt_pick_version
        telemt_download_binary "$TELEMT_CHOSEN_VERSION"
        id telemt &>/dev/null || useradd -d "$TELEMT_WORK_DIR" -m -r -U telemt
        telemt_write_config "$port" "$domain" "${TELEMT_USER_PAIRS[@]}"
        mkdir -p "$TELEMT_TLSFRONT_DIR"
        chown -R telemt:telemt "$TELEMT_CONFIG_DIR" "$TELEMT_WORK_DIR"
        telemt_write_service
        systemctl daemon-reload; systemctl enable telemt; systemctl start telemt
        ok "Сервис запущен"
    else
        telemt_write_config "$port" "$domain" "${TELEMT_USER_PAIRS[@]}"
        telemt_write_compose "$port"
        cd "$TELEMT_WORK_DIR_DOCKER"
        docker compose pull -q; docker compose up -d
        ok "Контейнер запущен"
    fi
    command -v ufw &>/dev/null && ufw allow "${port}/tcp" &>/dev/null && ok "ufw: порт $port открыт"
    sleep 3; header "Ссылки"
    echo -e "${BOLD}IP:${R} $(get_public_ip)"
    telemt_fetch_links
}

telemt_menu_add_user() {
    header "Добавить пользователя MTProxy"
    [ ! -f "$TELEMT_CONFIG_FILE" ] && die "Конфиг не найден. Сначала выполни установку."
    telemt_is_running || die "Сервис не запущен."
    local uname; read -rp "  Имя: " uname < /dev/tty
    [ -z "$uname" ] && die "Имя не может быть пустым"
    local secret; read -rp "  Секрет [Enter = сгенерировать]: " secret < /dev/tty
    [ -z "$secret" ] && { secret=$(gen_secret); ok "Секрет: $secret"; } \
        || echo "$secret" | grep -qE '^[0-9a-fA-F]{32}$' || die "Секрет должен быть 32 hex"
    echo ""; echo -e "${BOLD}Ограничения (Enter = пропустить):${R}"
    local mc mi qg ed
    read -rp "  Макс. подключений:    " mc < /dev/tty
    read -rp "  Макс. уникальных IP:  " mi < /dev/tty
    read -rp "  Квота трафика (ГБ):   " qg < /dev/tty
    read -rp "  Срок действия (дней): " ed < /dev/tty
    local body; body=$(python3 -c "
import json, sys
d = {'username': '$uname', 'secret': '$secret'}
mc='$mc'; mi='$mi'; qg='$qg'; ed='$ed'
if mc: d['max_tcp_conns'] = int(mc)
if mi: d['max_unique_ips'] = int(mi)
if qg: d['data_quota_bytes'] = int(float(qg) * 1024**3)
if ed:
    from datetime import datetime, timezone, timedelta
    dt = datetime.now(timezone.utc) + timedelta(days=int(ed))
    d['expiration_rfc3339'] = dt.strftime('%Y-%m-%dT%H:%M:%SZ')
print(json.dumps(d))
" 2>/dev/null)
    info "Создаю пользователя через API..."
    local resp; resp=$(telemt_api POST "/v1/users" "$body")
    if telemt_api_ok "$resp"; then
        ok "Пользователь '$uname' добавлен"; echo ""; header "Ссылки"; telemt_fetch_links
    else
        local errmsg; errmsg=$(telemt_api_error "$resp"); die "Ошибка API: $errmsg"
    fi
}

telemt_menu_delete_user() {
    header "Удалить пользователя MTProxy"
    [ ! -f "$TELEMT_CONFIG_FILE" ] && die "Конфиг не найден."
    telemt_is_running || die "Сервис не запущен."
    local resp; resp=$(telemt_api GET "/v1/users" || true)
    local -a users=()
    while IFS= read -r u; do [ -n "$u" ] && users+=("$u"); done < <(echo "$resp" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    us=d if isinstance(d,list) else d.get('data',d.get('users',[]))
    if isinstance(us,dict): us=list(us.values())
    for u in us: print(u.get('username',''))
except: pass
" 2>/dev/null || true)
    [ ${#users[@]} -eq 0 ] && { warn "Пользователи не найдены"; return 1; }
    echo -e "  ${WHITE}Выберите пользователя для удаления:${R}"; echo ""
    local i=1
    for u in "${users[@]}"; do echo -e "  ${BOLD}${i})${R} ${u}"; i=$((i+1)); done
    echo ""; echo -e "  ${BOLD}0)${R} Назад"; echo ""
    local ch; read -rp "  Выбор: " ch < /dev/tty
    [[ "$ch" == "0" ]] && return
    if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -lt 1 ] || [ "$ch" -gt ${#users[@]} ]; then
        warn "Неверный выбор"; return 1
    fi
    local selected="${users[$((ch-1))]}"
    local _yn; read -rp "  Удалить '${selected}'? (y/N): " _yn < /dev/tty
    [[ "${_yn:-N}" =~ ^[yY]$ ]] || { warn "Отменено"; return; }
    info "Удаляю через API..."
    local dresp; dresp=$(telemt_api DELETE "/v1/users/${selected}")
    if telemt_api_ok "$dresp"; then ok "Пользователь '${selected}' удалён"
    else local errmsg; errmsg=$(telemt_api_error "$dresp"); die "Ошибка API: $errmsg"; fi
}

telemt_menu_status() {
    header "Статус MTProxy"
    if [ "$TELEMT_MODE" = "systemd" ]; then
        systemctl status telemt --no-pager || true; echo ""
        if telemt_is_running; then
            local summary; summary=$(telemt_api GET "/v1/stats/summary" 2>/dev/null || true)
            local sysinfo; sysinfo=$(telemt_api GET "/v1/system/info" 2>/dev/null || true)
            echo "$summary $sysinfo" | python3 -c "
import sys, json
BOLD='\033[1m'; GRAY='\033[0;90m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
raw = sys.stdin.read().strip()
parts = []; depth = 0; buf = ''
for ch in raw:
    if ch == '{': depth += 1
    if depth > 0: buf += ch
    if ch == '}':
        depth -= 1
        if depth == 0:
            try: parts.append(json.loads(buf))
            except: pass
            buf = ''
sm = parts[0].get('data', {}) if len(parts) > 0 else {}
si = parts[1].get('data', {}) if len(parts) > 1 else {}
def fmt_uptime(s):
    if not s: return '—'
    s = int(s); d, s = divmod(s, 86400); h, s = divmod(s, 3600); m, _ = divmod(s, 60)
    parts2 = []
    if d: parts2.append(f'{d}д')
    if h: parts2.append(f'{h}ч')
    if m: parts2.append(f'{m}м')
    return ' '.join(parts2) or '< 1м'
version   = si.get('version', '')
uptime    = fmt_uptime(sm.get('uptime_seconds'))
conns     = sm.get('connections_total', '—')
bad       = sm.get('connections_bad_total', 0)
users     = sm.get('configured_users', '—')
print(f'  {GRAY}────────────────────────────────────────{RESET}')
if version: print(f'  {GRAY}Версия         {RESET}{version}')
print(       f'  {GRAY}Uptime         {RESET}{uptime}')
print(       f'  {GRAY}Подключений    {RESET}{conns}' + (f'  {GRAY}(плохих: {bad}){RESET}' if bad else ''))
print(       f'  {GRAY}Пользователей  {RESET}{users}')
print(f'  {GRAY}────────────────────────────────────────{RESET}')
" 2>/dev/null || true
            echo ""
        fi
        info "Последние логи:"; journalctl -u telemt --no-pager -n 25
    else
        cd "$TELEMT_WORK_DIR_DOCKER" 2>/dev/null || die "Директория не найдена"
        docker compose ps; echo ""; info "Последние логи:"; docker compose logs --tail=20
    fi
}

telemt_menu_update() {
    header "Обновление MTProxy"
    if [ "$TELEMT_MODE" = "systemd" ]; then
        info "Текущая версия: $("$TELEMT_BIN" --version 2>/dev/null || echo неизвестна)"
        telemt_pick_version; systemctl stop telemt
        telemt_download_binary "$TELEMT_CHOSEN_VERSION"; systemctl start telemt
    else
        cd "$TELEMT_WORK_DIR_DOCKER" || die "Директория не найдена"
        docker compose pull; docker compose up -d
    fi
    ok "Обновлено"
}

telemt_menu_stop() {
    header "Остановка MTProxy"
    if [ "$TELEMT_MODE" = "systemd" ]; then systemctl stop telemt
    else cd "$TELEMT_WORK_DIR_DOCKER" || die ""; docker compose down; fi
    ok "Остановлено"
}

telemt_menu_migrate() {
    header "Миграция MTProxy на новый сервер"
    [ "$TELEMT_MODE" != "systemd" ] && die "Миграция доступна только в systemd-режиме."
    [ ! -f "$TELEMT_CONFIG_FILE" ] && die "Конфиг не найден."
    ensure_sshpass
    echo -e "${BOLD}Данные нового сервера:${R}"; echo ""
    ask_ssh_target
    init_ssh_helpers telemt
    check_ssh_connection || return 1
    local nh="$_SSH_IP"
    local cur_port; cur_port=$(grep -E "^port\s*=" "$TELEMT_CONFIG_FILE" | head -1 | grep -oE "[0-9]+" || echo "8443")
    local cur_domain; cur_domain=$(grep -E "^tls_domain\s*=" "$TELEMT_CONFIG_FILE" | head -1 | grep -oP '"K[^"]+' || echo "petrovich.ru")
    echo ""; echo -e "${BOLD}Текущие настройки:${R} порт=$cur_port домен=$cur_domain"
    local new_pp new_dom
    read -rp "  Порт на новом сервере [Enter=$cur_port]: " new_pp; new_pp="${new_pp:-$cur_port}" < /dev/tty
    read -rp "  Домен-маскировка [Enter=$cur_domain]: " new_dom; new_dom="${new_dom:-$cur_domain}" < /dev/tty
    local users_block; users_block=$(awk '/^\[access\.users\]/{found=1;next} found&&/^\[/{exit} found&&/=/{print}' "$TELEMT_CONFIG_FILE")
    [ -z "$users_block" ] && die "Не найдено пользователей в конфиге"
    ok "Пользователей: $(echo "$users_block" | grep -c "=")"
    info "Копирую конфиг на новый сервер..."
    printf '[general]\nuse_middle_proxy = true\nlog_level = "normal"\n\n[general.modes]\nclassic = false\nsecure  = false\ntls     = true\n\n[general.links]\nshow = "*"\n\n[server]\nport = %s\n\n[server.api]\nenabled   = true\nlisten    = "127.0.0.1:9091"\nwhitelist = ["127.0.0.1/32"]\n\n[[server.listeners]]\nip = "0.0.0.0"\n\n[censorship]\ntls_domain    = "%s"\nmask          = true\ntls_emulation = true\ntls_front_dir = "%s"\n\n[access.users]\n%s\n' \
        "$new_pp" "$new_dom" "$TELEMT_TLSFRONT_DIR" "$users_block" \
        | RUN "mkdir -p /etc/telemt && cat > /etc/telemt/telemt.toml"
    header "Установка на $nh"
    RUN bash << REMOTE_INSTALL
set -e
ARCH=\$(uname -m); case "\$ARCH" in x86_64) ;; aarch64) ARCH="aarch64" ;; *) echo "Архитектура не поддерживается"; exit 1 ;; esac
LIBC=\$(ldd --version 2>&1|grep -iq musl&&echo musl||echo gnu)
URL="https://github.com/telemt/telemt/releases/latest/download/telemt-\${ARCH}-linux-\${LIBC}.tar.gz"
TMP=\$(mktemp -d); curl -fsSL "\$URL"|tar -xz -C "\$TMP"; install -m 0755 "\$TMP/telemt" /usr/local/bin/telemt; rm -rf "\$TMP"
echo "[OK] Telemt установлен"
id telemt &>/dev/null||useradd -d /opt/telemt -m -r -U telemt
mkdir -p /opt/telemt/tlsfront; chown -R telemt:telemt /etc/telemt /opt/telemt
cat > /etc/systemd/system/telemt.service << 'SERVICE'
[Unit]
Description=Telemt MTProto Proxy
After=network-online.target
[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/usr/local/bin/telemt /etc/telemt/telemt.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecReload=/bin/kill -HUP \$MAINPID
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload; systemctl enable telemt; systemctl restart telemt
echo "[OK] Сервис запущен"
command -v ufw &>/dev/null && ufw allow ${new_pp}/tcp &>/dev/null && echo "[OK] Порт $new_pp открыт"
REMOTE_INSTALL
    ok "Установка завершена!"; header "Новые ссылки"; echo -e "${BOLD}Новый IP:${R} $nh"
    info "Жду запуска..."; sleep 5
    local nl; nl=$(RUN "curl -s --max-time 10 http://127.0.0.1:9091/v1/users 2>/dev/null" || true)
    echo "$nl" | grep -q "tg://proxy" && ok "Миграция завершена!" \
        || warn "Проверь: ssh ${_SSH_USER}@${nh} curl -s http://127.0.0.1:9091/v1/users"
}

telemt_submenu_manage() {
    while true; do
        clear; header "MTProxy — Управление"
        echo -e "  ${BOLD}1)${R} 📊  Статус и логи"
        echo -e "  ${BOLD}2)${R} 🔄  Обновить"
        echo -e "  ${BOLD}3)${R} ⏹️  Остановить"
        echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) telemt_menu_status || true; read -rp "  Enter..." < /dev/tty ;;
            2) telemt_menu_update || true ;;
            3) telemt_menu_stop   || true; read -rp "  Enter..." < /dev/tty ;;
            0) return ;;
            *) warn "Неверный выбор" ;;
        esac
    done
}

telemt_submenu_users() {
    while true; do
        local user_count=""
        telemt_is_running 2>/dev/null && user_count=$(telemt_user_count 2>/dev/null || true)
        clear; echo ""
        printf "${BOLD}${WHITE}  MTProxy — Пользователи${R}"
        [ -n "$user_count" ] && printf "  ${GRAY}%s${R}" "$user_count"
        printf "\n${GRAY}  ────────────────────────────────────────${R}\n\n"
        echo -e "  ${BOLD}1)${R} ➕  Добавить пользователя"
        echo -e "  ${BOLD}2)${R} ➖  Удалить пользователя"
        echo -e "  ${BOLD}3)${R} 👥  Пользователи и ссылки"
        echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) telemt_menu_add_user    || true ;;
            2) telemt_menu_delete_user || true; read -rp "  Enter..." < /dev/tty ;;
            3) header "Пользователи и ссылки"; telemt_is_running || die "Сервис не запущен."; telemt_fetch_links; read -rp "  Enter..." < /dev/tty ;;
            0) return ;;
            *) warn "Неверный выбор" ;;
        esac
    done
}

telemt_section() {
    if [ -z "$TELEMT_MODE" ]; then
        if systemctl is-active --quiet telemt 2>/dev/null || systemctl is-enabled --quiet telemt 2>/dev/null; then
            TELEMT_MODE="systemd"; TELEMT_CONFIG_FILE="$TELEMT_CONFIG_SYSTEMD"; TELEMT_WORK_DIR="$TELEMT_WORK_DIR_SYSTEMD"
        elif { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            TELEMT_MODE="docker"; TELEMT_CONFIG_FILE="$TELEMT_CONFIG_DOCKER"; TELEMT_WORK_DIR="$TELEMT_WORK_DIR_DOCKER"
        else
            telemt_choose_mode || return
        fi
    fi
    telemt_check_deps
    # Главное меню MTProxy
    local mode_label ver telemt_port
    [ "$TELEMT_MODE" = "systemd" ] && mode_label="systemd" || mode_label="Docker"
    while true; do
        ver=$(get_telemt_version 2>/dev/null || true)
        telemt_port=""
        [ -f "$TELEMT_CONFIG_FILE" ] && telemt_port=$(grep -E "^port\s*=" "$TELEMT_CONFIG_FILE" 2>/dev/null | grep -oE "[0-9]+" | head -1 || true)
        clear; echo ""
        echo -e "${BOLD}${WHITE}  📡  MTProxy (telemt)${R}"
        echo -e "${GRAY}  ────────────────────────────────────────────${R}"
        [ -n "$ver" ]         && echo -e "  ${GRAY}Версия  ${R}${ver}  ${GRAY}(${mode_label})${R}"
        [ -n "$telemt_port" ] && echo -e "  ${GRAY}Порт    ${R}${telemt_port}"
        echo ""
        echo -e "  ${BOLD}1)${R} 🔧  Установка"
        echo -e "  ${BOLD}2)${R} ⚙️  Управление"
        local user_count=""
        telemt_is_running 2>/dev/null && user_count=$(telemt_user_count 2>/dev/null || true)
        if [ -n "$user_count" ]; then
            echo -e "  ${BOLD}3)${R} 👥  Пользователи  ${GRAY}${user_count}${R}"
        else
            echo -e "  ${BOLD}3)${R} 👥  Пользователи"
        fi
        echo -e "  ${BOLD}4)${R} 📦  Миграция на другой сервер"
        echo -e "  ${BOLD}5)${R} 🔀  Сменить режим (systemd ↔ Docker)"
        echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) telemt_menu_install || true ;;
            2) telemt_submenu_manage || true ;;
            3) telemt_submenu_users  || true ;;
            4) telemt_menu_migrate   || true; read -rp "  Enter..." < /dev/tty ;;
            5) telemt_choose_mode; telemt_check_deps || true ;;
            0) return ;;
            *) warn "Неверный выбор" ;;
        esac
    done
}


# ══════════════════════════════════════════════════════════════════════════════
#  Hysteria2 — СЕКЦИЯ
# ══════════════════════════════════════════════════════════════════════════════

HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_SVC="hysteria-server"

hy_is_installed() { command -v hysteria &>/dev/null; }
hy_is_running()   { systemctl is-active --quiet hysteria-server 2>/dev/null; }

hy_port_is_free() {
    ss -tulpn 2>/dev/null | awk '{print $5}' | grep -qE ":${1}$" && return 1 || return 0
}

hy_port_label() {
    if hy_port_is_free "$1"; then echo "свободен ✓"
    else
        local proc; proc=$(ss -tulpn 2>/dev/null | awk '{print $5,$7}' | grep ":${1} " \
            | grep -oP 'users:\(\("K[^"]+' | head -1 || true)
        [ -n "$proc" ] && echo "занят ($proc) ✗" || echo "занят ✗"
    fi
}

hy_is_valid_fqdn() {
    local d="$1"
    [[ "$d" == *.* ]] || return 1
    [[ "${#d}" -le 253 ]] || return 1
    [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

hy_resolve_a() {
    local domain="$1"
    if command -v dig &>/dev/null; then
        dig +short A "$domain" 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+\.' || true
    else
        getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' || true
    fi
}

hy_get_domain() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ""; return 1; }
    awk '/domains:/{f=1;next} f&&/^  - /{gsub(/[[:space:]]*-[[:space:]]*/,""); print; exit}' "$HYSTERIA_CONFIG"
}

hy_get_port() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ""; return 1; }
    awk '/^listen:/{match($0,/[0-9]+$/); print substr($0,RSTART,RLENGTH); exit}' "$HYSTERIA_CONFIG"
}

hy_get_domain_port() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ":"; return 1; }
    awk '
        /^listen:/{match($0,/[0-9]+$/); port=substr($0,RSTART,RLENGTH)}
        /domains:/{f=1; next}
        f&&/^  - /{gsub(/[[:space:]]*-[[:space:]]*/,""); dom=$0; f=0}
        END{print dom ":" port}
    ' "$HYSTERIA_CONFIG"
}

hysteria_install() {
    header "Установка / Переустановка Hysteria2"

    if hy_is_installed; then
        echo ""; echo -e "  ${YELLOW}Hysteria2 уже установлена.${R}"
        echo -e "  ${BOLD}1)${R} Переустановить (сохранить пользователей и настройки)"
        echo -e "  ${BOLD}2)${R} Переустановить полностью (сброс конфига)"
        echo -e "  ${BOLD}0)${R} Отмена"; echo ""
        local reinstall_ch; read -rp "  Выбор: " reinstall_ch < /dev/tty
        case "$reinstall_ch" in
            1)
                info "Переустановка с сохранением конфига..."
                local backup_cfg="/tmp/hysteria_backup_$(date +%Y%m%d_%H%M%S).yaml"
                cp "$HYSTERIA_CONFIG" "$backup_cfg" 2>/dev/null && info "Конфиг сохранён: $backup_cfg"
                systemctl stop "$HYSTERIA_SVC" 2>/dev/null || true
                bash <(curl -fsSL https://get.hy2.sh/) || { err "Ошибка установки"; return 1; }
                cp "$backup_cfg" "$HYSTERIA_CONFIG"
                systemctl restart "$HYSTERIA_SVC"; ok "Hysteria2 переустановлена, конфиг восстановлен"; return 0 ;;
            2)
                warn "Конфиг будет удалён!"
                local _yn; read -rp "  Продолжить? (y/N): " _yn < /dev/tty
                [[ "${_yn:-N}" =~ ^[yY]$ ]] || return 1
                systemctl stop "$HYSTERIA_SVC" 2>/dev/null || true; rm -f "$HYSTERIA_CONFIG" ;;
            0) return 0 ;; *) warn "Неверный выбор"; return 1 ;;
        esac
    fi

    # ── Домен ────────────────────────────────────────────────────
    local domain=""
    while true; do
        read -rp "  Домен (например cdn.example.com): " domain < /dev/tty
        hy_is_valid_fqdn "$domain" && break
        warn "Некорректный домен. Нужен FQDN вида sub.example.com"
    done
    local email=""; read -rp "  Email для ACME (необязателен): " email < /dev/tty; email="${email// /}"

    # ── CA ───────────────────────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Центр сертификации (CA):${R}"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  1) Let's Encrypt  — стандарт, рекомендуется            │"
    echo "  │  2) ZeroSSL        — резерв если LE заблокирован         │"
    echo "  │  3) Buypass        — сертификат на 180 дней              │"
    echo "  └──────────────────────────────────────────────────────────┘"
    local ca_choice="" ca_name
    while [[ ! "$ca_choice" =~ ^[123]$ ]]; do read -rp "  Выбор [1]: " ca_choice < /dev/tty; ca_choice="${ca_choice:-1}"; done
    case "$ca_choice" in 1) ca_name="letsencrypt" ;; 2) ca_name="zerossl" ;; 3) ca_name="buypass" ;; esac

    # ── Порт / Port Hopping ─────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Режим порта:${R}"
    echo "  ┌────────────────────────────────────────────────────────┐"
    echo "  │  1) Один порт      — стандарт                          │"
    echo "  │  2) Port Hopping   — диапазон UDP (обход блокировок)   │"
    echo "  └────────────────────────────────────────────────────────┘"
    local port_mode=""; while [[ ! "$port_mode" =~ ^[12]$ ]]; do read -rp "  Выбор [1]: " port_mode < /dev/tty; port_mode="${port_mode:-1}"; done
    local port port_hop_start port_hop_end listen_addr uri_port
    if [ "$port_mode" = "2" ]; then
        read -rp "  Начало диапазона [20000]: " port_hop_start < /dev/tty; port_hop_start="${port_hop_start:-20000}"
        read -rp "  Конец диапазона [29999]: "  port_hop_end   < /dev/tty; port_hop_end="${port_hop_end:-29999}"
        port="$port_hop_start"; listen_addr="0.0.0.0:${port_hop_start}-${port_hop_end}"
        uri_port="${port_hop_start}-${port_hop_end}"; ok "Port Hopping: UDP ${port_hop_start}-${port_hop_end}"
    else
        echo ""; echo -e "  ${WHITE}Выберите UDP порт:${R}"
        local l8443 l2053 l2083 l2087
        l8443=$(hy_port_label 8443); l2053=$(hy_port_label 2053); l2083=$(hy_port_label 2083); l2087=$(hy_port_label 2087)
        echo "  ┌──────────────────────────────────────────────────────────┐"
        printf "  │  1) 8443  — рекомендуется  [%-26s]  │\n" "$l8443"
        printf "  │  2) 2053  — альтернатива   [%-26s]  │\n" "$l2053"
        printf "  │  3) 2083  — альтернатива   [%-26s]  │\n" "$l2083"
        printf "  │  4) 2087  — альтернатива   [%-26s]  │\n" "$l2087"
        echo "  │  5) Ввести свой порт                                     │"
        echo "  └──────────────────────────────────────────────────────────┘"
        local port_choice=""; while [[ ! "$port_choice" =~ ^[12345]$ ]]; do read -rp "  Выбор [1]: " port_choice < /dev/tty; port_choice="${port_choice:-1}"; done
        case "$port_choice" in 1) port=8443 ;; 2) port=2053 ;; 3) port=2083 ;; 4) port=2087 ;;
            5) while true; do read -rp "  Порт (1-65535): " port < /dev/tty
               [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) && break; warn "Некорректный порт"; done ;;
        esac
        listen_addr="0.0.0.0:${port}"; uri_port="$port"
        hy_port_is_free "$port" || { warn "Порт $port занят!"; local fp; read -rp "  Продолжить? (y/N): " fp < /dev/tty; [[ "${fp:-N}" =~ ^[yY]$ ]] || { warn "Отмена"; return 1; }; }
        ok "Порт: $port"
    fi

    # ── IPv6 ────────────────────────────────────────────────────
    local use_ipv6=false
    if ip -6 addr show 2>/dev/null | grep -q "inet6.*global"; then
        local ipv6_ch; read -rp "  Включить IPv6 поддержку? (y/N): " ipv6_ch < /dev/tty
        [[ "${ipv6_ch:-N}" =~ ^[yY]$ ]] && {
            use_ipv6=true
            [ "$port_mode" = "2" ] && listen_addr="[::]:${port_hop_start}-${port_hop_end}" \
                                   || listen_addr="[::]:${port}"
            ok "IPv6 включён"
        }
    fi

    # ── Пользователь ────────────────────────────────────────────
    local username pass
    read -rp "  Логин [admin]: " username < /dev/tty; username="${username:-admin}"
    read -rp "  Пароль (пусто = авто): " pass < /dev/tty
    if [ -z "$pass" ]; then
        pass=$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
        info "Сгенерирован пароль: $pass"
    fi
    local conn_name; read -rp "  Название подключения [Hysteria2]: " conn_name < /dev/tty; conn_name="${conn_name:-Hysteria2}"

    # ── Masquerade ──────────────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Режим маскировки:${R}"
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │  1) bing.com          — рекомендуется, поддерживает HTTP/3  │"
    echo "  │  2) yahoo.com         — стабильный, поддерживает HTTP/3     │"
    echo "  │  3) cdn.apple.com     — нейтральный                         │"
    echo "  │  4) speed.hetzner.de  — нейтральный                         │"
    echo "  │  5) /var/www/html     — локальная заглушка                  │"
    echo "  │  6) Ввести свой URL                                          │"
    echo "  └─────────────────────────────────────────────────────────────┘"
    local masq_choice="" masq_type masq_url; masq_type="proxy"; masq_url=""
    while [[ ! "$masq_choice" =~ ^[123456]$ ]]; do read -rp "  Выбор [1]: " masq_choice < /dev/tty; masq_choice="${masq_choice:-1}"; done
    case "$masq_choice" in
        1) masq_url="https://www.bing.com" ;;
        2) masq_url="https://www.yahoo.com" ;;
        3) masq_url="https://cdn.apple.com" ;;
        4) masq_url="https://speed.hetzner.de" ;;
        5) masq_type="file"
           [ ! -d /var/www/html ] && { mkdir -p /var/www/html
               printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Please wait</title></head><body style="background:#080808;color:#ccc;text-align:center;padding:100px">Loading...</body></html>' \
                   > /var/www/html/index.html; ok "Заглушка создана: /var/www/html"; } ;;
        6) while true; do read -rp "  URL (https://...): " masq_url < /dev/tty
           [[ "$masq_url" =~ ^https?:// ]] && break; warn "URL должен начинаться с https://"; done ;;
    esac

    # ── Алгоритм скорости ───────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Алгоритм контроля скорости:${R}"
    echo "  [1] BBR    — стандартный, рекомендуется"
    echo "  [2] Brutal — агрессивный, для нестабильных каналов"
    local speed_mode use_brutal=false bw_up bw_down
    read -rp "  Выбор [1]: " speed_mode < /dev/tty; speed_mode="${speed_mode:-1}"
    if [ "$speed_mode" = "2" ]; then
        use_brutal=true
        read -rp "  Download (Mbps) [100]: " bw_down < /dev/tty; bw_down="${bw_down:-100}"
        read -rp "  Upload (Mbps) [50]: "   bw_up   < /dev/tty; bw_up="${bw_up:-50}"
        ok "Brutal: ↓${bw_down}/↑${bw_up} Mbps"
    fi

    # ── Зависимости ────────────────────────────────────────────
    info "Установка зависимостей..."
    apt-get update -y -q && apt-get install -y -q curl ca-certificates openssl qrencode dnsutils

    # ── Проверка DNS ────────────────────────────────────────────
    info "Проверка DNS..."
    local server_ip; server_ip=$(server_ip)
    [ -z "$server_ip" ] && { err "Не удалось определить IP сервера"; return 1; }
    ok "IP сервера: $server_ip"
    local domain_ips; domain_ips=$(hy_resolve_a "$domain" || true)
    [ -z "$domain_ips" ] && { err "Домен $domain не резолвится. Создайте A-запись → $server_ip"; return 1; }
    echo "  A-записи: $(echo "$domain_ips" | tr '\n' ' ')"
    if ! echo "$domain_ips" | grep -qx "$server_ip"; then
        warn "Домен не указывает на этот сервер ($server_ip)!"
        local fc; read -rp "  Продолжить принудительно? (y/N): " fc < /dev/tty
        [[ "${fc:-N}" =~ ^[yY]$ ]] || { warn "Исправьте DNS и запустите снова"; return 1; }
    else
        ok "DNS корректен: $domain → $server_ip"
    fi

    # ── Установка бинарника ────────────────────────────────────
    info "Установка Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) || { err "Ошибка установки"; return 1; }
    command -v hysteria &>/dev/null || { err "Бинарник hysteria не найден"; return 1; }
    ok "Hysteria2 установлен: $(hysteria version 2>/dev/null | grep Version | awk '{print $2}')"

    # ── Конфиг ─────────────────────────────────────────────────
    info "Запись конфигурации..."
    install -d -m 0755 "$HYSTERIA_DIR"
    local acme_email_line=""; [ -n "$email" ] && acme_email_line="  email: ${email}"
    local bw_block=""
    $use_brutal && bw_block="
bandwidth:
  up: ${bw_up} mbps
  down: ${bw_down} mbps"
    local masq_block
    if [ "$masq_type" = "file" ]; then
        masq_block="masquerade:
  type: file
  file:
    dir: /var/www/html"
    else
        masq_block="masquerade:
  type: proxy
  proxy:
    url: ${masq_url}
    rewriteHost: true"
    fi
    cat > "$HYSTERIA_CONFIG" << EOF
listen: ${listen_addr}

acme:
  type: http
  domains:
    - ${domain}
  ca: ${ca_name}
${acme_email_line}

auth:
  type: userpass
  userpass:
    ${username}: "${pass}"
${bw_block}
${masq_block}

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
EOF
    ok "Конфигурация записана: $HYSTERIA_CONFIG"

    # ── Сервис ─────────────────────────────────────────────────
    systemctl daemon-reload
    command -v ufw &>/dev/null && ufw allow 80/tcp >/dev/null 2>&1 && ufw --force enable >/dev/null 2>&1
    systemctl enable --now "$HYSTERIA_SVC"
    info "Ждём получения сертификата..."
    local i=0
    while [ $i -lt 30 ]; do
        journalctl -u "$HYSTERIA_SVC" -n 20 --no-pager 2>/dev/null | grep -q "server up and running" && break
        sleep 1; i=$((i+1))
    done
    command -v ufw &>/dev/null && ufw delete allow 80/tcp >/dev/null 2>&1
    ok "Сервис $HYSTERIA_SVC запущен"

    # ── UFW ────────────────────────────────────────────────────
    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp >/dev/null 2>&1
        if [ "$port_mode" = "2" ]; then
            ufw allow "${port_hop_start}:${port_hop_end}/udp" >/dev/null 2>&1
            ok "UFW: открыт диапазон ${port_hop_start}-${port_hop_end}/udp"
        else
            ufw allow "${port}/udp" >/dev/null 2>&1; ufw allow "${port}/tcp" >/dev/null 2>&1
            ok "UFW: открыт ${port}/udp и ${port}/tcp"
        fi
        ufw --force enable >/dev/null 2>&1
    fi

    # ── URI и итог ─────────────────────────────────────────────
    local uri="hy2://${username}:${pass}@${domain}:${uri_port}?sni=${domain}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    local txt_file="/root/hysteria-${domain}.txt"; echo "$uri" > "$txt_file"

    echo ""; echo -e "${BOLD}${GREEN}  ✓ Hysteria2 установлен${R}"
    echo ""; echo -e "${BOLD}${WHITE}  Конфигурация${R}"
    echo -e "${GRAY}  ──────────────────────────────${R}"
    echo -e "  ${GRAY}Сервер    ${R}${domain}:${uri_port}"
    echo -e "  ${GRAY}Логин     ${R}${username}"
    echo -e "  ${GRAY}Пароль    ${R}${pass}"
    echo -e "  ${GRAY}Алгоритм  ${R}$( $use_brutal && echo "Brutal ↓${bw_down}/↑${bw_up} Mbps" || echo "BBR" )"
    echo ""; echo -e "${BOLD}${WHITE}  URI подключения${R}"
    echo -e "${GRAY}  ──────────────────────────────${R}"
    echo -e "  ${CYAN}${uri}${R}"
    echo ""
    command -v qrencode &>/dev/null && { echo -e "${BOLD}${WHITE}  QR-код${R}"; qrencode -t ANSIUTF8 "$uri" 2>/dev/null || true; echo ""; }
    ok "URI сохранён: $txt_file"
}

hysteria_status() {
    header "Hysteria2 — Статус"
    hy_is_installed && echo -e "  Версия:  $(hysteria version 2>/dev/null | head -1)"
    systemctl --no-pager status "$HYSTERIA_SVC" 2>/dev/null || warn "Сервис не найден"
    if [ -f "$HYSTERIA_CONFIG" ]; then
        echo ""; echo -e "  ${WHITE}Конфигурация:${R}"
        local dp dom port
        dp=$(hy_get_domain_port 2>/dev/null || true)
        dom="${dp%%:*}"; [ -z "$dom" ] && dom="—"
        port="${dp##*:}"; [ -z "$port" ] && port="—"
        echo "    Домен: $dom    Порт: $port"
    fi
}

hysteria_logs()    { header "Hysteria2 — Логи"; journalctl -u "$HYSTERIA_SVC" -n 80 --no-pager 2>/dev/null || warn "Логи недоступны"; }
hysteria_restart() { systemctl restart "$HYSTERIA_SVC" && ok "Hysteria2 перезапущен" || warn "Ошибка перезапуска"; }

hysteria_add_user() {
    header "Hysteria2 — Добавить пользователя"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден. Сначала установите Hysteria2"; return 1; }
    local new_user new_pass
    local existing; existing=$(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:" | sed 's/:.*//' | tr -d ' ' | tr '\n' ' ')
    [ -n "$existing" ] && info "Существующие пользователи: ${existing}"
    while true; do
        read -rp "  Имя пользователя: " new_user < /dev/tty
        [ -z "$new_user" ] && { warn "Имя не может быть пустым"; continue; }
        if grep -qE "^    ${new_user}:" "$HYSTERIA_CONFIG" 2>/dev/null; then
            warn "Пользователь '${new_user}' уже существует."
            echo -e "  ${BOLD}1)${R} Ввести другое имя"; echo -e "  ${BOLD}2)${R} Заменить пароль"; echo -e "  ${BOLD}0)${R} Отмена"
            local ch; read -rp "  Выбор: " ch < /dev/tty
            case "$ch" in
                1) continue ;;
                2) read -rp "  Новый пароль (пусто = авто): " new_pass < /dev/tty
                   [ -z "$new_pass" ] && { new_pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '='); info "Пароль: $new_pass"; }
                   sed -i "s/^    ${new_user}:.*$/    ${new_user}: \"${new_pass}\"/" "$HYSTERIA_CONFIG"
                   systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
                   ok "Пароль для '${new_user}' обновлён"; return 0 ;;
                *) return 0 ;;
            esac
        else
            break
        fi
    done
    read -rp "  Пароль (пусто = авто): " new_pass < /dev/tty
    [ -z "$new_pass" ] && { new_pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '='); info "Сгенерирован пароль: $new_pass"; }
    sed -i "/^  userpass:/a\\    ${new_user}: \"${new_pass}\"" "$HYSTERIA_CONFIG"
    systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
    ok "Пользователь '${new_user}' добавлен"
    local dom; dom=$(hy_get_domain)
    local port; port=$(hy_get_port)
    local conn_name; read -rp "  Название подключения [${new_user}]: " conn_name < /dev/tty; conn_name="${conn_name:-$new_user}"
    local uri="hy2://${new_user}:${new_pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    echo ""; echo -e "  ${CYAN}URI:${R}"; echo "  $uri"; echo ""
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$uri" 2>/dev/null || true
    echo "$uri" >> "/root/hysteria-${dom}-users.txt"
    ok "URI сохранён: /root/hysteria-${dom}-users.txt"
}

hysteria_delete_user() {
    header "Hysteria2 — Удалить пользователя"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден"; return 1; }
    local -a users=()
    while IFS= read -r line; do
        local u; u=$(echo "$line" | sed 's/:.*//' | tr -d ' ')
        [ -n "$u" ] && users+=("$u")
    done < <(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:")
    [ ${#users[@]} -eq 0 ] && { warn "Пользователи не найдены"; return 1; }
    echo -e "  ${WHITE}Выберите пользователя для удаления:${R}"; echo ""
    local i=1
    for u in "${users[@]}"; do echo -e "  ${BOLD}${i})${R} ${u}"; i=$((i+1)); done
    echo ""; echo -e "  ${BOLD}0)${R} Назад"; echo ""
    local ch; read -rp "  Выбор: " ch < /dev/tty
    [[ "$ch" == "0" ]] && return
    if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -lt 1 ] || [ "$ch" -gt ${#users[@]} ]; then
        warn "Неверный выбор"; return 1
    fi
    local selected="${users[$((ch-1))]}"
    local _yn; read -rp "  Удалить '${selected}'? (y/N): " _yn < /dev/tty
    [[ "${_yn:-N}" =~ ^[yY]$ ]] || { warn "Отменено"; return; }
    sed -i "/^    ${selected}:/d" "$HYSTERIA_CONFIG"
    systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
    ok "Пользователь '${selected}' удалён"
}

hysteria_show_links() {
    header "Hysteria2 — Пользователи и ссылки"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден"; return 1; }
    local dom port; dom=$(hy_get_domain); port=$(hy_get_port)
    local -a users=()
    while IFS= read -r line; do
        local u; u=$(echo "$line" | sed 's/:.*//' | tr -d ' ')
        [ -n "$u" ] && users+=("$u")
    done < <(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:")
    [ ${#users[@]} -eq 0 ] && { warn "Пользователи не найдены"; return 1; }
    echo -e "  ${WHITE}Выберите пользователя:${R}"; echo ""
    local i=1
    for u in "${users[@]}"; do echo -e "  ${BOLD}${i})${R} ${u}"; i=$((i+1)); done
    echo ""; echo -e "  ${BOLD}0)${R} Назад"; echo ""
    local ch; read -rp "  Выбор: " ch < /dev/tty
    [[ "$ch" == "0" ]] && return
    if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -lt 1 ] || [ "$ch" -gt ${#users[@]} ]; then
        warn "Неверный выбор"; return 1
    fi
    local selected="${users[$((ch-1))]}"
    local pass; pass=$(python3 -c "
import sys, re
cfg = open('$HYSTERIA_CONFIG').read()
m = re.search(r'^ {4}' + re.escape('${selected}') + r':\s*[\"\'']?([^\"\''\n]+)[\"\'']?', cfg, re.M)
print(m.group(1).strip() if m else '')
" 2>/dev/null)
    local conn_name; conn_name=$(grep -a "hy2://${selected}:" "/root/hysteria-${dom}.txt" 2>/dev/null | sed 's/.*#//' | tail -1 || echo "$selected")
    local uri="hy2://${selected}:${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    echo ""; echo -e "  ${CYAN}Пользователь:${R} ${selected}"
    echo -e "  ${CYAN}Сервер:${R}       ${dom}:${port}"
    echo ""; echo -e "  ${CYAN}URI:${R}"; echo "  $uri"; echo ""
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$uri" 2>/dev/null || warn "qrencode не установлен"
    echo ""; read -rp "  Enter для возврата..." < /dev/tty
}

hysteria_migrate() {
    header "Hysteria2 — Перенос на новый сервер"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Hysteria2 не установлена"; return 1; }
    ensure_sshpass
    ask_ssh_target
    init_ssh_helpers hysteria
    local rip="$_SSH_IP" ruser="$_SSH_USER"
    info "Проверка подключения..."; RUN echo ok >/dev/null 2>&1 || { err "Не удалось подключиться"; return 1; }
    ok "Подключение успешно"
    local domain; domain=$(hy_get_domain)
    local hy_port; hy_port=$(hy_get_port)
    info "Установка Hysteria2 на новом сервере..."
    RUN "bash <(curl -fsSL https://get.hy2.sh/)" || { err "Ошибка установки"; return 1; }
    info "Копирование конфигурации..."; RUN "mkdir -p /etc/hysteria"
    PUT "$HYSTERIA_CONFIG" "${ruser}@${rip}:/etc/hysteria/config.yaml"; ok "Конфиг скопирован"
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        info "Копирование SSL-сертификата..."
        PUT /etc/letsencrypt/live    "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        PUT /etc/letsencrypt/archive "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        PUT /etc/letsencrypt/renewal "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        ok "Сертификат скопирован"
    else
        warn "Сертификат не найден — Hysteria переиздаст его через ACME после смены DNS"
    fi
    info "Запуск сервиса..."
    RUN bash << REMOTE
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow ${hy_port}/udp >/dev/null 2>&1 || true
ufw allow ${hy_port}/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
systemctl daemon-reload; systemctl enable --now hysteria-server
REMOTE
    ok "Перенос завершён!"
    echo ""; echo -e "  ${YELLOW}Следующие шаги:${R}"
    echo -e "  1. Обновите DNS A-запись: ${CYAN}${domain}${R} → ${WHITE}${rip}${R}"
    echo -e "  2. После DNS: systemctl restart hysteria-server (на новом сервере)"
    echo -e "  3. Проверьте работу, затем остановите старый: ${CYAN}systemctl stop hysteria-server${R}"
}

hysteria_submenu_manage() {
    while true; do
        clear; header "Hysteria2 — Управление"
        echo -e "  ${BOLD}1)${R} 📊  Статус"; echo -e "  ${BOLD}2)${R} 📋  Логи"
        echo -e "  ${BOLD}3)${R} 🔄  Перезапустить"; echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_status  || true; read -rp "  Enter..." < /dev/tty ;;
            2) hysteria_logs    || true; read -rp "  Enter..." < /dev/tty ;;
            3) hysteria_restart || true; read -rp "  Enter..." < /dev/tty ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}

hysteria_submenu_users() {
    while true; do
        clear; header "Hysteria2 — Пользователи"
        echo -e "  ${BOLD}1)${R} ➕  Добавить пользователя"
        echo -e "  ${BOLD}2)${R} ➖  Удалить пользователя"
        echo -e "  ${BOLD}3)${R} 👥  Пользователи и ссылки"
        echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_add_user    || true; read -rp "  Enter..." < /dev/tty ;;
            2) hysteria_delete_user || true; read -rp "  Enter..." < /dev/tty ;;
            3) hysteria_show_links  || true ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}

hysteria_section() {
    local ver dp dom port
    ver=$(get_hysteria_version 2>/dev/null || true)
    dp=$(hy_get_domain_port 2>/dev/null || true)
    dom="${dp%%:*}"; port="${dp##*:}"
    while true; do
        clear; echo ""; echo -e "${BOLD}${WHITE}  🚀  Hysteria2${R}"
        echo -e "${GRAY}  ────────────────────────────────────────────${R}"
        [ -n "$ver" ] && echo -e "  ${GRAY}Версия  ${R}${ver}"
        [ -n "$dom" ] && echo -e "  ${GRAY}Сервер  ${R}${dom}${port:+:$port}"
        echo ""
        echo -e "  ${BOLD}1)${R}  🔧  Установка"
        echo -e "  ${BOLD}2)${R}  ⚙️  Управление"
        echo -e "  ${BOLD}3)${R}  👥  Пользователи"
        echo -e "  ${BOLD}4)${R}  📦  Миграция на другой сервер"
        echo ""; echo -e "  ${BOLD}0)${R}  ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_install         || true; ver=$(get_hysteria_version 2>/dev/null||true); dp=$(hy_get_domain_port 2>/dev/null||true); dom="${dp%%:*}"; port="${dp##*:}" ;;
            2) hysteria_submenu_manage  || true ;;
            3) hysteria_submenu_users   || true ;;
            4) hysteria_migrate         || true; read -rp "  Enter..." < /dev/tty ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}


# ──────────────────────────────────────────────────────────────────────────────
#  ГЛАВНОЕ МЕНЮ
# ──────────────────────────────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════════════════════════════
#  РОУТИНГ — управление правилами маршрутизации
# ══════════════════════════════════════════════════════════════════════════════

PROFILES_DIR="/usr/local/etc/xray/profiles"

# ── Helpers ───────────────────────────────────────────────────────────────────

routing_rules_count() {
    jq '[.routing.rules[]? | select(.inboundTag[0]? != "api")] | length' \
        "$XRAY_CONF" 2>/dev/null || echo 0
}

routing_active_profile() {
    jq -r '.routing._profile // "custom"' "$XRAY_CONF" 2>/dev/null
}

routing_rule_summary() {
    # Выводит читаемое описание правила по индексу
    local idx="$1"
    jq -r --argjson i "$idx" '
        .routing.rules[$i] |
        [
            (if .domain   then "domain:"   + (.domain   | join(",") | .[0:40]) else empty end),
            (if .ip       then "ip:"       + (.ip       | join(",") | .[0:30]) else empty end),
            (if .port     then "port:"     + .port                              else empty end),
            (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
            (if .user     then "user:"     + (.user     | join(","))            else empty end),
            (if .network  then "net:"      + .network                           else empty end),
            (if .inboundTag then "from:"   + (.inboundTag | join(","))          else empty end)
        ] | join(" | ") + " → " + (.outboundTag // .balancerTag // "?")
    ' "$XRAY_CONF" 2>/dev/null
}

# ── Главное меню роутинга ─────────────────────────────────────────────────────

menu_routing() {
    while true; do
        cls; box_top " 🗺  Маршрутизация (Routing)" "$CYAN"
        box_blank

        # Текущее состояние
        local profile; profile=$(routing_active_profile)
        local rules_n; rules_n=$(routing_rules_count)
        local strategy; strategy=$(jq -r '.routing.domainStrategy // "AsIs"' "$XRAY_CONF" 2>/dev/null)

        box_row "  Профиль:         ${YELLOW}${profile}${R}"
        box_row "  Правил:          ${CYAN}${rules_n}${R}  ${DIM}(не считая служебные)${R}"
        box_row "  domainStrategy:  ${DIM}${strategy}${R}"
        box_blank; box_mid

        mi "1" "📋" "Список правил"
        mi "2" "➕" "Добавить правило"
        mi "3" "🗑" "Удалить правило"
        mi "4" "↕️ " "Порядок правил (поднять/опустить)"
        mi "5" "🌐" "domainStrategy"
        box_mid
        mi "6" "💾" "${YELLOW}Профили${R}  ${DIM}(сохранить / загрузить / шаблоны)${R}"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) routing_list ;;
            2) routing_add ;;
            3) routing_del ;;
            4) routing_reorder ;;
            5) routing_strategy ;;
            6) menu_profiles ;;
            0) return ;;
        esac
    done
}

# ── Список правил ─────────────────────────────────────────────────────────────

routing_list() {
    cls; box_top " 📋  Правила маршрутизации" "$CYAN"; box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    if [[ "$total" -eq 0 ]]; then
        box_row "  ${DIM}Нет правил${R}"; box_blank; box_end; pause; return
    fi

    local i=0
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        # Пропустить служебное правило api
        if [[ "$tag" == "api" ]]; then ((i++)); continue; fi

        local outb; outb=$(jq -r --argjson n "$i" '.routing.rules[$n] | .outboundTag // .balancerTag // "?"' "$XRAY_CONF" 2>/dev/null)
        local col="$LIGHT"
        case "$outb" in
            direct) col="$GREEN" ;;
            block)  col="$RED" ;;
            *)      col="$CYAN" ;;
        esac

        local summary; summary=$(routing_rule_summary "$i")
        local idx_disp=$(( i + 1 ))
        box_row "  ${DIM}#${idx_disp}${R}  ${col}→ ${outb}${R}  ${DIM}${summary}${R}"
        ((i++))
    done

    box_blank; box_end; pause
}

# ── Добавить правило ──────────────────────────────────────────────────────────

# ── Мульти-выбор профилей для синхронизации ──────────────────────────────────
# Возвращает список выбранных файлов профилей через newline в переменную $1
# Использование: _profile_multiselect selected_files_var
_profile_multiselect() {
    local __result_var="$1"
    _profiles_init

    # Собрать список профилей
    local -a pnames=() pfiles=()
    while IFS='|' read -r name desc file; do
        pnames+=("$name"); pfiles+=("$file")
    done < <(_profile_list)

    if [[ ${#pnames[@]} -eq 0 ]]; then
        printf -v "$__result_var" '%s' ""
        return
    fi

    # Состояние выбора (0=нет, 1=да)
    local -a selected=()
    for _ in "${pnames[@]}"; do selected+=(0); done

    while true; do
        echo ""
        box_row "  ${CYAN}${BOLD}Выберите профили для синхронизации:${R}"
        box_row "  ${DIM}Пробел — переключить, A — все/сброс, Enter — подтвердить, 0 — пропустить${R}"
        box_blank

        local i=0
        for name in "${pnames[@]}"; do
            local rc; rc=$(_profile_rules_count "${pfiles[$i]}")
            local mark
            if [[ "${selected[$i]}" == "1" ]]; then
                mark="${GREEN}[✓]${R}"
            else
                mark="${DIM}[ ]${R}"
            fi
            printf "${DIM}│${R}  %b ${YELLOW}${BOLD}%s)${R} ${CYAN}%-20s${R} ${DIM}%s правил${R}\n" \
                "$mark" "$((i+1))" "$name" "$rc"
            ((i++))
        done

        local total_sel=0
        for s in "${selected[@]}"; do [[ "$s" == "1" ]] && ((total_sel++)); done

        box_blank
        box_row "  ${DIM}Выбрано: ${YELLOW}${total_sel}${R}${DIM} профилей${R}"
        box_end

        local key
        read -rp "$(printf "${YELLOW}›${R} [1-${#pnames[@]}/A/Enter/0]: ")" key < /dev/tty

        case "$key" in
            0|"")
                if [[ -z "$key" ]]; then
                    # Enter — подтверждение
                    break
                else
                    # 0 — пропустить
                    printf -v "$__result_var" '%s' ""
                    return
                fi
                ;;
            a|A)
                # Все/сброс
                local any=0
                for s in "${selected[@]}"; do [[ "$s" == "1" ]] && { any=1; break; }; done
                if [[ $any -eq 1 ]]; then
                    for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=0; done
                else
                    for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=1; done
                fi
                ;;
            *)
                if [[ "$key" =~ ^[0-9]+$ ]] && [[ "$key" -ge 1 && "$key" -le ${#pnames[@]} ]]; then
                    local idx=$(( key - 1 ))
                    if [[ "${selected[$idx]}" == "1" ]]; then
                        selected[$idx]=0
                    else
                        selected[$idx]=1
                    fi
                fi
                ;;
        esac
    done

    # Вернуть файлы выбранных профилей
    local result=""
    local i=0
    for name in "${pnames[@]}"; do
        if [[ "${selected[$i]}" == "1" ]]; then
            result="${result}${pfiles[$i]}"$'\n'
        fi
        ((i++))
    done
    printf -v "$__result_var" '%s' "${result%$'\n'}"
}

# Применить правило к файлу профиля (добавить в конец, не дублировать)
_profile_add_rule() {
    local file="$1"
    local rule_json="$2"
    [[ ! -f "$file" ]] && return 1
    # Проверить нет ли уже точно такого же правила
    local exists; exists=$(jq --argjson r "$rule_json" \
        '[.rules[]? | . == $r] | any' "$file" 2>/dev/null)
    if [[ "$exists" == "true" ]]; then
        warn "Правило уже есть в $(basename "$file" .json)"
        return 0
    fi
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson r "$rule_json" '.rules += [$r]' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Удалить правило из файла профиля по совпадению полей
_profile_del_rule() {
    local file="$1"
    local rule_json="$2"
    [[ ! -f "$file" ]] && return 1
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson r "$rule_json" \
        '.rules = [.rules[]? | select(. != $r)]' \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

routing_add() {
    cls; box_top " ➕  Добавить правило" "$GREEN"; box_blank

    # Выбор критерия
    box_row "  ${YELLOW}Критерий совпадения:${R}"
    mi "1" "🌐" "По домену          ${DIM}(example.com, geosite:google)${R}"
    mi "2" "🔢" "По IP / CIDR       ${DIM}(1.2.3.4, geoip:ru, 10.0.0.0/8)${R}"
    mi "3" "🔌" "По порту           ${DIM}(443, 80, 1000-2000)${R}"
    mi "4" "📡" "По протоколу       ${DIM}(http, tls, quic, bittorrent)${R}"
    mi "5" "👤" "По пользователю    ${DIM}(alice@xray.com)${R}"
    mi "6" "🏷" "По inbound тегу    ${DIM}(vless-reality, vmess-ws)${R}"
    mi "7" "🌍" "По сети (tcp/udp)"
    mi "8" "✨" "Комбинированное    ${DIM}(несколько критериев сразу)${R}"
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " crit_ch
    [[ "$crit_ch" == "0" ]] && return

    # Формируем JSON правила
    local rule_json="{}"

    case "$crit_ch" in
        1)  # Домен
            box_blank
            box_row "  ${DIM}Примеры: google.com  geosite:google  regexp:\\.fb\\.  full:example.com${R}"
            box_row "  ${DIM}Несколько через пробел: youtube.com geosite:netflix${R}"
            local domains; ask "Домены" domains ""
            [[ -z "$domains" ]] && return
            local darr; darr=$(echo "$domains" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson d "$darr" '{domain: $d}')
            ;;
        2)  # IP
            box_blank
            box_row "  ${DIM}Примеры: 8.8.8.8  geoip:ru  10.0.0.0/8  geoip:private${R}"
            local ips; ask "IP / CIDR" ips ""
            [[ -z "$ips" ]] && return
            local iarr; iarr=$(echo "$ips" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson ip "$iarr" '{ip: $ip}')
            ;;
        3)  # Порт
            local port_val; ask "Порты" port_val "443"
            rule_json=$(jq -n --arg p "$port_val" '{port: $p}')
            ;;
        4)  # Протокол
            box_blank
            box_row "  Варианты: http tls quic bittorrent"
            box_row "  ${YELLOW}⚠ Нужен sniffing в inbound!${R}"
            local protos; ask "Протоколы (через пробел)" protos "bittorrent"
            local parr; parr=$(echo "$protos" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson p "$parr" '{protocol: $p}')
            ;;
        5)  # Пользователь
            local users; ask "Email пользователей (через пробел)" users ""
            [[ -z "$users" ]] && return
            local uarr; uarr=$(echo "$users" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson u "$uarr" '{user: $u}')
            ;;
        6)  # Inbound tag
            box_blank
            box_row "  ${YELLOW}Доступные inbound:${R}"
            ib_list | while IFS='|' read -r tag port proto net sec; do
                box_row "    ${CYAN}${tag}${R}"
            done
            local tags; ask "Теги (через пробел)" tags ""
            [[ -z "$tags" ]] && return
            local tarr; tarr=$(echo "$tags" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson t "$tarr" '{inboundTag: $t}')
            ;;
        7)  # Сеть
            box_blank
            mi "1" "📶" "tcp"; mi "2" "📡" "udp"; mi "3" "🔀" "tcp,udp"
            box_end
            read -rp "$(printf "${YELLOW}›${R} ") " net_ch
            local net_val
            case "$net_ch" in 1) net_val="tcp";; 2) net_val="udp";; *) net_val="tcp,udp";; esac
            rule_json=$(jq -n --arg n "$net_val" '{network: $n}')
            ;;
        8)  # Комбинированное
            box_blank
            box_row "  ${DIM}Оставь пустым то что не нужно${R}"
            local dom_v ip_v port_v net_v
            ask "Домены (пусто = пропустить)" dom_v ""
            ask "IP/CIDR  (пусто = пропустить)" ip_v ""
            ask "Порты    (пусто = пропустить)" port_v ""
            ask "Сеть tcp/udp/tcp,udp (пусто = пропустить)" net_v ""
            rule_json="{}"
            [[ -n "$dom_v" ]]  && { local darr; darr=$(echo "$dom_v" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))"); rule_json=$(echo "$rule_json" | jq --argjson d "$darr" '.domain=$d'); }
            [[ -n "$ip_v" ]]   && { local iarr; iarr=$(echo "$ip_v" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))"); rule_json=$(echo "$rule_json" | jq --argjson ip "$iarr" '.ip=$ip'); }
            [[ -n "$port_v" ]] && rule_json=$(echo "$rule_json" | jq --arg p "$port_v" '.port=$p')
            [[ -n "$net_v" ]]  && rule_json=$(echo "$rule_json" | jq --arg n "$net_v" '.network=$n')
            ;;
    esac

    # Выбор outbound
    box_blank
    box_row "  ${YELLOW}Действие (outbound):${R}"
    mi "1" "✈️ " "${GREEN}direct${R}   — напрямую"
    mi "2" "🚫" "${RED}block${R}    — заблокировать"
    # Показать доступные outbounds
    local i=3
    local -a ob_list=()
    while IFS= read -r t; do
        [[ "$t" == "direct" || "$t" == "block" || "$t" == "api" || "$t" == "metrics_out" ]] && continue
        mi "$i" "🔌" "${CYAN}${t}${R}"
        ob_list+=("$t"); ((i++))
    done < <(jq -r '.outbounds[].tag' "$XRAY_CONF" 2>/dev/null)
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ob_ch

    local outbound_tag
    case "$ob_ch" in
        1) outbound_tag="direct" ;;
        2) outbound_tag="block" ;;
        *)
            local idx=$(( ob_ch - 3 ))
            if [[ $idx -ge 0 && $idx -lt ${#ob_list[@]} ]]; then
                outbound_tag="${ob_list[$idx]}"
            else
                warn "Неверный выбор"; pause; return
            fi
            ;;
    esac

    rule_json=$(echo "$rule_json" | jq --arg o "$outbound_tag" '. + {outboundTag: $o, type: "field"}')

    # Позиция вставки
    box_blank
    local total; total=$(routing_rules_count)
    box_row "  ${YELLOW}Позиция (правила проверяются сверху вниз):${R}"
    mi "1" "⬆️ " "В начало  ${DIM}(высокий приоритет)${R}"
    mi "2" "⬇️ " "В конец   ${DIM}(низкий приоритет, дефолт)${R}"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " pos_ch

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "$pos_ch" == "1" ]]; then
        # Вставить после служебного api-правила (индекс 0)
        jq --argjson r "$rule_json" \
            '.routing.rules = [.routing.rules[0]] + [$r] + .routing.rules[1:]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    else
        jq --argjson r "$rule_json" '.routing.rules += [$r]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi

    # Сбросить имя профиля — конфиг изменён вручную
    local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
    jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"

    xray_restart
    ok "Правило добавлено: ${outbound_tag}"

    # Предложить синхронизацию с профилями
    if [[ -d "$PROFILES_DIR" ]] && compgen -G "${PROFILES_DIR}/*.json" >/dev/null 2>&1; then
        box_blank
        box_row "  ${YELLOW}Добавить это правило в профили?${R}"
        box_end
        local sync_files
        _profile_multiselect sync_files
        if [[ -n "$sync_files" ]]; then
            while IFS= read -r pfile; do
                [[ -z "$pfile" ]] && continue
                _profile_add_rule "$pfile" "$rule_json"
                ok "→ $(basename "$pfile" .json)"
            done <<< "$sync_files"
        fi
    fi

    pause
}

# ── Удалить правило ───────────────────────────────────────────────────────────

routing_del() {
    cls; box_top " 🗑  Удалить правило" "$RED"; box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    local -a display_indices=()
    local i=0
    local disp=1
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        if [[ "$tag" != "api" ]]; then
            local summary; summary=$(routing_rule_summary "$i")
            mi "$disp" "📍" "${DIM}${summary}${R}"
            display_indices+=("$i")
            ((disp++))
        fi
        ((i++))
    done

    [[ ${#display_indices[@]} -eq 0 ]] && { box_row "  ${DIM}Нет правил для удаления${R}"; box_end; pause; return; }
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return

    local real_idx="${display_indices[$((ch-1))]}"
    [[ -z "$real_idx" ]] && { warn "Неверный выбор"; pause; return; }

    local del_rule_json; del_rule_json=$(jq -c --argjson n "$real_idx" '.routing.rules[$n]' "$XRAY_CONF" 2>/dev/null)

    confirm "Удалить правило #${ch}?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --argjson n "$real_idx" 'del(.routing.rules[$n])' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
        jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
        xray_restart
        ok "Правило удалено"

        # Предложить синхронизацию с профилями
        if [[ -n "$del_rule_json" ]] && [[ -d "$PROFILES_DIR" ]] && compgen -G "${PROFILES_DIR}/*.json" >/dev/null 2>&1; then
            box_blank
            box_row "  ${YELLOW}Удалить это правило из профилей?${R}"
            box_end
            local sync_files
            _profile_multiselect sync_files
            if [[ -n "$sync_files" ]]; then
                while IFS= read -r pfile; do
                    [[ -z "$pfile" ]] && continue
                    _profile_del_rule "$pfile" "$del_rule_json"
                    ok "→ $(basename "$pfile" .json)"
                done <<< "$sync_files"
            fi
        fi
    }
    pause
}

# ── Порядок правил ────────────────────────────────────────────────────────────

routing_reorder() {
    cls; box_top " ↕️  Порядок правил" "$YELLOW"; box_blank
    box_row "  ${DIM}Правила проверяются сверху вниз. Первое совпадение — победитель.${R}"
    box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    local -a display_indices=()
    local i=0; local disp=1
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        if [[ "$tag" != "api" ]]; then
            local summary; summary=$(routing_rule_summary "$i")
            mi "$disp" "📍" "${DIM}${summary}${R}"
            display_indices+=("$i"); ((disp++))
        fi
        ((i++))
    done
    [[ ${#display_indices[@]} -le 1 ]] && { box_row "  ${DIM}Нечего перемещать${R}"; box_end; pause; return; }
    box_blank
    box_row "  ${DIM}Введите номер правила для перемещения,${R}"
    box_row "  ${DIM}затем: U — вверх, D — вниз${R}"
    box_end

    local rule_num dir
    read -rp "$(printf "${YELLOW}›${R} Правило: ")" rule_num
    [[ -z "$rule_num" || "$rule_num" == "0" ]] && return
    read -rp "$(printf "${YELLOW}›${R} [U]верх / [D]вниз: ")" dir

    local real_idx="${display_indices[$((rule_num-1))]}"
    [[ -z "$real_idx" ]] && { warn "Неверный номер"; pause; return; }

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "${dir,,}" == "u" && "$real_idx" -gt 1 ]]; then
        # Swap с предыдущим (не api)
        local prev_real="${display_indices[$((rule_num-2))]}"
        jq --argjson a "$real_idx" --argjson b "$prev_real" \
            '.routing.rules[$a], .routing.rules[$b] = .routing.rules[$b], .routing.rules[$a]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Правило перемещено вверх"
    elif [[ "${dir,,}" == "d" && "$rule_num" -lt ${#display_indices[@]} ]]; then
        local next_real="${display_indices[$((rule_num))]}"
        jq --argjson a "$real_idx" --argjson b "$next_real" \
            '.routing.rules[$a], .routing.rules[$b] = .routing.rules[$b], .routing.rules[$a]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Правило перемещено вниз"
    else
        warn "Невозможно переместить"
    fi

    local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
    jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
    xray_restart
    pause
}

# ── domainStrategy ────────────────────────────────────────────────────────────

routing_strategy() {
    cls; box_top " 🌐  domainStrategy" "$BLUE"; box_blank
    local cur; cur=$(jq -r '.routing.domainStrategy // "AsIs"' "$XRAY_CONF" 2>/dev/null)
    box_row "  Текущая: ${CYAN}${cur}${R}"; box_blank

    box_row "  ${YELLOW}Варианты:${R}"
    mi "1" "⚡" "${CYAN}AsIs${R}           — только домен, без резолва  ${DIM}(быстро, по умолчанию)${R}"
    mi "2" "🔍" "${CYAN}IPIfNonMatch${R}   — резолвит если нет совпадения по домену"
    mi "3" "🔎" "${CYAN}IPOnDemand${R}     — резолвит при любом IP-правиле сразу"
    box_blank
    box_row "  ${DIM}IPIfNonMatch: клиент идёт к 1.2.3.4 → нет совпадения по домену${R}"
    box_row "  ${DIM}→ резолвит 1.2.3.4 → google.com → совпадает geosite:google → proxy${R}"
    box_mid; mi "0" "◀" "Назад"; box_end

    read -rp "$(printf "${YELLOW}›${R} ") " ch
    local new_strat
    case "$ch" in
        1) new_strat="AsIs" ;;
        2) new_strat="IPIfNonMatch" ;;
        3) new_strat="IPOnDemand" ;;
        0) return ;;
        *) warn "Неверный выбор"; pause; return ;;
    esac

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg s "$new_strat" '.routing.domainStrategy = $s' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "domainStrategy → ${new_strat}"
    pause
}

# ══════════════════════════════════════════════════════════════════════════════
#  ПРОФИЛИ — сохранение/загрузка наборов правил
# ══════════════════════════════════════════════════════════════════════════════

_profiles_init() { mkdir -p "$PROFILES_DIR"; }

_profile_list() {
    find "$PROFILES_DIR" -name "*.json" 2>/dev/null | sort | while read -r f; do
        local name; name=$(basename "$f" .json)
        local desc; desc=$(jq -r '.description // ""' "$f" 2>/dev/null)
        echo "${name}|${desc}|${f}"
    done
}

_profile_rules_count() {
    jq '[.rules[]? | select(.inboundTag[0]? != "api")] | length' "$1" 2>/dev/null || echo 0
}

menu_profiles() {
    _profiles_init
    while true; do
        cls; box_top " 💾  Профили роутинга" "$YELLOW"
        box_blank
        box_row "  ${DIM}Профиль = сохранённый набор правил. Загрузка заменяет текущие правила.${R}"
        box_blank

        local active; active=$(routing_active_profile)
        box_row "  Активный: ${YELLOW}${active}${R}"
        box_blank

        # Список профилей
        local i=1; local -a pnames=() pfiles=()
        while IFS='|' read -r name desc file; do
            local rc; rc=$(_profile_rules_count "$file")
            local marker=""
            [[ "$name" == "$active" ]] && marker="${GREEN}◄ активен${R}"
            mi "$i" "📄" "${CYAN}${name}${R}  ${DIM}${desc:+— $desc }(${rc} правил)${R}  ${marker}"
            pnames+=("$name"); pfiles+=("$file"); ((i++))
        done < <(_profile_list)

        [[ ${#pnames[@]} -eq 0 ]] && box_row "  ${DIM}(нет сохранённых профилей)${R}"
        box_blank; box_mid

        mi "s" "💾" "Сохранить текущие правила как профиль"
        mi "t" "📋" "Шаблоны  ${DIM}(готовые наборы правил)${R}"
        mi "d" "🗑" "Удалить профиль"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch

        case "$ch" in
            s|S) profile_save ;;
            t|T) menu_profile_templates ;;
            d|D) profile_delete "${pnames[@]}" "${pfiles[@]}" ;;
            0)   return ;;
            *)
                if [[ "$ch" =~ ^[0-9]+$ ]] && [[ "$ch" -ge 1 && "$ch" -le ${#pnames[@]} ]]; then
                    profile_load "${pfiles[$((ch-1))]}" "${pnames[$((ch-1))]}"
                fi
                ;;
        esac
    done
}

profile_save() {
    cls; box_top " 💾  Сохранить профиль" "$YELLOW"; box_blank
    local name desc
    ask "Имя профиля (без пробелов)" name ""
    [[ -z "$name" ]] && return
    name="${name// /_}"
    ask "Описание (необязательно)" desc ""

    # Сохраняем только routing.rules (без служебного api-правила)
    local file="${PROFILES_DIR}/${name}.json"
    jq --arg d "$desc" '{
        description: $d,
        domainStrategy: .routing.domainStrategy,
        rules: [.routing.rules[]? | select(.inboundTag[0]? != "api")]
    }' "$XRAY_CONF" > "$file"

    local rc; rc=$(_profile_rules_count "$file")
    ok "Профиль '${name}' сохранён (${rc} правил)"
    pause
}

profile_load() {
    local file="$1" name="$2"
    [[ ! -f "$file" ]] && { err "Файл профиля не найден"; return; }

    local rc; rc=$(_profile_rules_count "$file")
    cls; box_top " 📂  Загрузить профиль: ${name}" "$CYAN"; box_blank
    box_row "  Правил в профиле: ${CYAN}${rc}${R}"
    box_blank

    # Показать правила профиля
    jq -r '.rules[]? |
        [
            (if .domain   then "domain:"   + (.domain   | join(",") | .[0:35]) else empty end),
            (if .ip       then "ip:"       + (.ip       | join(",") | .[0:25]) else empty end),
            (if .port     then "port:"     + .port                              else empty end),
            (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
            (if .network  then "net:"      + .network                           else empty end)
        ] | join(" | ") + " → " + (.outboundTag // "?")
    ' "$file" | while read -r line; do box_row "  ${DIM}${line}${R}"; done

    box_blank
    box_row "  ${YELLOW}⚠  Текущие правила будут заменены!${R}"
    box_blank; box_end

    confirm "Загрузить профиль '${name}'?" || return

    # Сохраняем api-правило, берём из профиля остальные
    local api_rule; api_rule=$(jq -c '.routing.rules[]? | select(.inboundTag[0]? == "api")' "$XRAY_CONF" 2>/dev/null | head -1)
    local new_strategy; new_strategy=$(jq -r '.domainStrategy // "IPIfNonMatch"' "$file")
    local new_rules; new_rules=$(jq -c '.rules' "$file")

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg strat "$new_strategy" \
       --arg name "$name" \
       --argjson ar "${api_rule:-null}" \
       --argjson rules "$new_rules" \
       '.routing.domainStrategy = $strat |
        .routing._profile = $name |
        .routing.rules = (
            if $ar != null then [$ar] + $rules
            else $rules end
        )' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Профиль '${name}' загружен"
    pause
}

profile_delete() {
    cls; box_top " 🗑  Удалить профиль" "$RED"; box_blank
    local -a pnames=("$@")
    # pnames и pfiles передаются как отдельные массивы — нужно восстановить
    local count=${#pnames[@]}
    local half=$(( count / 2 ))
    local names=("${pnames[@]:0:$half}")
    local files=("${pnames[@]:$half}")

    [[ ${#names[@]} -eq 0 ]] && { box_row "  ${DIM}Нет профилей${R}"; box_end; pause; return; }
    local i=1
    for n in "${names[@]}"; do mi "$i" "📄" "$n"; ((i++)); done
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    local sel_name="${names[$((ch-1))]}"
    local sel_file="${files[$((ch-1))]}"
    [[ -z "$sel_name" ]] && return
    confirm "Удалить профиль '${sel_name}'?" && { rm -f "$sel_file"; ok "Удалён"; }
    pause
}

# ── Шаблоны профилей ──────────────────────────────────────────────────────────

menu_profile_templates() {
    cls; box_top " 📋  Шаблоны правил" "$MAGENTA"; box_blank
    box_row "  ${DIM}Готовые наборы. Можно загрузить сразу или сохранить как профиль.${R}"
    box_blank

    mi "1" "🇷🇺" "${CYAN}Россия напрямую${R}          ${DIM}RU/CIS сайты → direct, остальное → proxy${R}"
    mi "2" "🌍" "${CYAN}Всё через прокси${R}         ${DIM}Любой трафик → proxy${R}"
    mi "3" "🚫" "${CYAN}Блокировка рекламы++${R}     ${DIM}Реклама + трекеры + торренты → block${R}"
    mi "4" "👤" "${CYAN}Разные пользователи${R}      ${DIM}alice → proxy, bob → direct (шаблон)${R}"
    mi "5" "🔒" "${CYAN}Только HTTPS напрямую${R}    ${DIM}443 → direct, остальное → block${R}"
    mi "6" "⚡" "${CYAN}Оптимальный (рекомендуется)${R}  ${DIM}Реклама block, RU direct, остальное proxy${R}"
    box_mid; mi "0" "◀" "Назад"; box_end

    read -rp "$(printf "${YELLOW}›${R} ") " ch
    local tpl_rules tpl_name tpl_desc tpl_strategy

    case "$ch" in
        1)
            tpl_name="russia-direct"; tpl_strategy="IPIfNonMatch"
            tpl_desc="RU/CIS сайты и IP напрямую, остальное через proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","domain":["geosite:ru","geosite:yandex","geosite:category-gov-ru"],"outboundTag":"direct"},
                {"type":"field","ip":["geoip:ru","geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        2)
            tpl_name="all-proxy"; tpl_strategy="AsIs"
            tpl_desc="Весь трафик через proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        3)
            tpl_name="block-ads-torrents"; tpl_strategy="AsIs"
            tpl_desc="Блокировка рекламы, трекеров и торрентов"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","protocol":["bittorrent"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"direct"}
            ]'
            ;;
        4)
            tpl_name="per-user"; tpl_strategy="AsIs"
            tpl_desc="Разные outbound по пользователям (шаблон — замени emails)"
            tpl_rules='[
                {"type":"field","user":["alice@xray.com"],"outboundTag":"proxy"},
                {"type":"field","user":["bob@xray.com"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"direct"}
            ]'
            ;;
        5)
            tpl_name="https-only"; tpl_strategy="AsIs"
            tpl_desc="Только HTTPS (443) напрямую, остальное заблокировано"
            tpl_rules='[
                {"type":"field","port":"443","network":"tcp","outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"block"}
            ]'
            ;;
        6)
            tpl_name="optimal"; tpl_strategy="IPIfNonMatch"
            tpl_desc="Оптимальный: реклама block, RU direct, остальное proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","domain":["geosite:ru","geosite:yandex","geosite:category-gov-ru"],"outboundTag":"direct"},
                {"type":"field","ip":["geoip:ru"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        0) return ;;
        *) warn "Неверный выбор"; pause; return ;;
    esac

    cls; box_top " 📋  Шаблон: ${tpl_name}" "$MAGENTA"; box_blank
    box_row "  ${DIM}${tpl_desc}${R}"; box_blank
    echo "$tpl_rules" | jq -r '.[] | [
        (if .domain   then "domain:"   + (.domain   | join(",") | .[0:40]) else empty end),
        (if .ip       then "ip:"       + (.ip       | join(",") | .[0:30]) else empty end),
        (if .port     then "port:"     + .port                              else empty end),
        (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
        (if .network  then "net:"      + .network                           else empty end)
    ] | join(" | ") + " → " + (.outboundTag // "?")
    ' | while read -r line; do box_row "  ${DIM}${line}${R}"; done
    box_blank; box_mid
    mi "1" "▶" "Применить сейчас"
    mi "2" "💾" "Сохранить как профиль (не применять)"
    mi "0" "◀" "Назад"
    box_end

    read -rp "$(printf "${YELLOW}›${R} ") " action_ch
    case "$action_ch" in
        1)
            # Применить
            local api_rule; api_rule=$(jq -c '.routing.rules[]? | select(.inboundTag[0]? == "api")' "$XRAY_CONF" 2>/dev/null | head -1)
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg strat "$tpl_strategy" \
               --arg name "$tpl_name" \
               --argjson ar "${api_rule:-null}" \
               --argjson rules "$tpl_rules" \
               '.routing.domainStrategy = $strat |
                .routing._profile = $name |
                .routing.rules = (if $ar != null then [$ar] + $rules else $rules end)' \
                "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
            xray_restart
            ok "Шаблон '${tpl_name}' применён"
            ;;
        2)
            # Сохранить
            _profiles_init
            local file="${PROFILES_DIR}/${tpl_name}.json"
            echo "{\"description\":\"${tpl_desc}\",\"domainStrategy\":\"${tpl_strategy}\",\"rules\":${tpl_rules}}" \
                | jq . > "$file"
            ok "Сохранён как профиль '${tpl_name}'"
            ;;
    esac
    pause
}


main_menu() {
    while true; do
        cls
        local w; w=$(tw); local i=$((w-2))
        printf "${DIM}╭%s╮${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        printf "${DIM}│${R}  ${CYAN}${BOLD}%-*s${R}${DIM}│${R}\n" $((i-3)) "██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) " ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) " ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
        printf "${DIM}│${R}  ${DIM}%-*s${R}${DIM}│${R}\n" $((i-3)) "Manager v${MANAGER_VERSION}  •  VLESS • VMess • Trojan • SS2022 • MTProto • Hysteria2"
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"

        # Статус Xray
        local xver; xver=$(xray_ver)
        local sip; sip=$(server_ip)
        local st_ic st_tx
        if ! xray_ok; then st_ic="${RED}✗${R}"; st_tx="${RED}не установлен${R}"
        elif xray_active; then st_ic="${GREEN}●${R}"; st_tx="${GREEN}работает${R}"
        else st_ic="${YELLOW}○${R}"; st_tx="${YELLOW}остановлен${R}"; fi
        printf "${DIM}│${R}  Xray: %b ${CYAN}%s${R}  %b  IP: ${YELLOW}%s${R}%-*s${DIM}│${R}\n" \
            "$st_ic" "$xver" "$st_tx" "$sip" $((i-52)) ""

        # Статус подписки
        if _sub_is_running 2>/dev/null; then
            local _sp; _sp=$(_sub_get_port 2>/dev/null || echo "?")
            printf "${DIM}│${R}  📡 Подписка: ${GREEN}●${R} ${DIM}:${_sp}${R}%-*s${DIM}│${R}\n" $((i-26)) ""
        fi

        # Протоколы Xray
        local pc=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            printf "${DIM}│${R}  • ${CYAN}%-20s${R} ${DIM}порт %-6s${R} ${YELLOW}%s польз.${R}%-*s${DIM}│${R}\n" \
                "$tag" "$port" "$uc" $((i-44)) ""
            ((pc++))
        done < <(ib_list)
        [[ $pc -eq 0 ]] && printf "${DIM}│${R}  ${DIM}%-*s${R}${DIM}│${R}\n" $((i-3)) "Xray-протоколы не настроены"

        # Статус MTProto
        local mt_st=""; local hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            local mt_ver; mt_ver=$(get_telemt_version 2>/dev/null || true)
            mt_st=" ${GREEN}●${R} ${GRAY}${mt_ver}${R}"
        fi
        # Статус Hysteria2
        hy_is_running 2>/dev/null && {
            local hy_ver; hy_ver=$(get_hysteria_version 2>/dev/null || true)
            hy_st=" ${GREEN}●${R} ${GRAY}${hy_ver}${R}"
        }

        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "1" "🔧" "Установка / Обновление Xray"
        mi "2" "🌐" "Протоколы Xray"              "(добавить / удалить)"
        mi "3" "👥" "Пользователи Xray"            "(добавить / лимиты / QR)"
        mi "4" "⚙️ " "Управление Xray"             "(статус / логи / гео)"
        mi "5" "🛠" "Система"                      "(BBR / бэкап / удалить)"
        # Строка роутинга с активным профилем
        local _rp; _rp=$(routing_active_profile 2>/dev/null || echo "custom")
        local _rn; _rn=$(routing_rules_count 2>/dev/null || echo 0)
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${CYAN}Маршрутизация${R}  ${DIM}профиль: %s · %s правил${R}%-*s${DIM}│${R}\n" \
            "R" "🗺" "$_rp" "$_rn" $((i-56)) ""
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${MAGENTA}MTProto (Telegram)${R}%-*s${DIM}%s │${R}\n" \
            "6" "📡" $((i-40)) "" "$mt_st"
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${ORANGE}Hysteria2 (QUIC/UDP)${R}%-*s${DIM}%s │${R}\n" \
            "7" "🚀" $((i-42)) "" "$hy_st"
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "0" "🚪" "Выход"
        printf "${DIM}╰%s╯${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) install_xray_core ;;
            2) menu_protocols ;;
            3) menu_users ;;
            4) menu_manage ;;
            5) menu_system ;;
            R|r) menu_routing ;;
            6) telemt_section ;;
            7) hysteria_section ;;
            0) cls; echo -e "${CYAN}До свидания!${R}"; exit 0 ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
#  ТОЧКА ВХОДА
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--check-limits" ]]; then
    _init_limits_file
    check_limits
    exit 0
fi

need_root
main_menu
