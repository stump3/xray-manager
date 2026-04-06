# shellcheck disable=SC2059
# ──────────────────────────────────────────────────────────────────────────────
#  13-compat.sh — слой совместимости
#  • msg_* алиасы (для кода из xray-install)
#  • die, header, NC — для telemt/hysteria2
#  • Логирование в файл
#  • detect_os / detect_arch / ensure_pkg
#  • ask_input / ask_yes_no / ask_menu — обёртки над 02-ui.sh
#  • Прочие утилиты
# ──────────────────────────────────────────────────────────────────────────────

# ── Алиасы для ANSI-переменных ────────────────────────────────────────────────
NC="$R"
RESET="$R"

# ── msg_* → native UI ─────────────────────────────────────────────────────────
msg_ok()      { ok   "$@"; }
msg_info()    { info "$@"; }
msg_warn()    { warn "$@"; }
msg_err()     { err  "$@"; }
msg_step()    { printf "\n  ${CYAN}${BOLD}%s${R}\n  ${DIM}%s${R}\n" \
                    "$*" "$(printf '%.0s─' {1..48})"; }
msg_header()  { cls; printf "\n  ${CYAN}${BOLD}%s${R}\n  ${DIM}%s${R}\n\n" \
                    "$*" "$(printf '%.0s═' {1..48})"; }
msg_divider() { printf "  ${DIM}%s${R}\n" "$(printf '%.0s─' {1..48})"; }
msg_raw()     { printf "%b\n" "$@"; }
msg_prompt()  { printf "  ${YELLOW}?${R}  %b  " "$*"; }

# header — алиас для telemt / hysteria2
header() { msg_header "$@"; }

# die — завершить с ошибкой (используется по всему коду)
die() { err "$*"; exit 1; }

# ── Логирование в файл ────────────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-/var/log/xray-manager-install.log}"

log_init() {
    if [[ $EUID -eq 0 ]]; then
        touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/xray-manager-install.log"
        chmod 640 "$LOG_FILE" 2>/dev/null || true
    else
        LOG_FILE="/tmp/xray-manager-install.log"
    fi
    printf "=== xray-manager install: %s ===\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
}

_log() {
    local level="$1"; shift
    printf "[%s] [%s] %s\n" "$(date '+%H:%M:%S')" "$level" "$*" \
        >> "$LOG_FILE" 2>/dev/null || true
}
log_info() { _log INFO  "$@"; }
log_ok()   { _log OK    "$@"; }
log_warn() { _log WARN  "$@"; }
log_err()  { _log ERROR "$@"; }

log_run() {
    local desc="$1"; shift
    log_info "Выполняем: $* ($desc)"
    if "$@" >> "$LOG_FILE" 2>&1; then
        log_ok "OK: $desc"; return 0
    else
        local rc=$?
        log_err "FAIL(rc=${rc}): $desc"
        err "Ошибка (rc=${rc}): $desc  →  лог: $LOG_FILE"
        return $rc
    fi
}

# ── Определение ОС и пакетного менеджера ──────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_ID="${ID}"
        OS_PRETTY="${PRETTY_NAME:-${ID}}"
    else
        die "Не удалось определить ОС (/etc/os-release отсутствует)"
    fi

    case "$OS_ID" in
        ubuntu|debian|raspbian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE=(apt-get update -qq)
            PKG_INSTALL=(apt-get install -y -qq)
            ;;
        centos|rhel|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_UPDATE=(yum makecache -q)
            PKG_INSTALL=(yum install -y -q)
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_UPDATE=(dnf makecache -q)
            PKG_INSTALL=(dnf install -y -q)
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            PKG_UPDATE=(pacman -Sy --noconfirm)
            PKG_INSTALL=(pacman -S --noconfirm --needed)
            ;;
        *)
            die "Неподдерживаемый дистрибутив: ${OS_ID}. Поддерживаются: Debian/Ubuntu, RHEL/CentOS, Fedora, Arch."
            ;;
    esac
    log_info "ОС: ${OS_PRETTY} | менеджер пакетов: ${PKG_MANAGER}"
    ok "ОС: ${OS_PRETTY}"
}

# ── Определение архитектуры ───────────────────────────────────────────────────
detect_arch() {
    local arch; arch="$(uname -m)"
    case "$arch" in
        x86_64)        XRAY_ARCH="64" ;;
        aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
        armv7l|armv7)  XRAY_ARCH="arm32-v7a" ;;
        *)             die "Неподдерживаемая архитектура: ${arch}" ;;
    esac
    log_info "Архитектура: ${arch} → пакет: Xray-linux-${XRAY_ARCH}"
}

# ── Установка пакета если не найден ──────────────────────────────────────────
ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    command -v "$cmd" &>/dev/null && return 0
    info "Устанавливаем ${pkg}..."
    log_run "Установка ${pkg}" "${PKG_INSTALL[@]}" "$pkg" \
        || die "Не удалось установить ${pkg}"
    ok "${pkg} установлен"
}

# ── Резервная копия файла ─────────────────────────────────────────────────────
backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local bak="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$file" "$bak"
    info "Резервная копия: ${bak}"
    log_info "backup_file: ${bak}"
}

# ── Обёртки ввода ─────────────────────────────────────────────────────────────

# ask_input "Подсказка" ["default"] — пишет результат в $REPLY
ask_input() {
    local prompt="$1" default="${2:-}"
    ask "$prompt" REPLY "$default"
}

# ask_yes_no "Вопрос?" ["y"|"n"] — возвращает 0 (да) или 1 (нет)
ask_yes_no() {
    local prompt="$1" default="${2:-y}"
    confirm "$prompt" "$default"
}

# ask_menu "Заголовок" "Опция 1" "Опция 2" ... — пишет выбор в $MENU_CHOICE
ask_menu() {
    local title="$1"; shift
    local options=("$@")
    printf "\n  ${BOLD}%s${R}\n" "$title"
    msg_divider
    local i=1
    for opt in "${options[@]}"; do
        printf "  ${CYAN}%s${R}  %s\n" "${i})" "$opt"
        (( i++ ))
    done
    msg_divider
    ask "Выберите (1–${#options[@]})" MENU_CHOICE "1"
}

# ── UUID и ключи ──────────────────────────────────────────────────────────────
generate_uuid() {
    if command -v xray &>/dev/null; then
        xray uuid 2>/dev/null && return
    fi
    [[ -f /proc/sys/kernel/random/uuid ]] \
        && cat /proc/sys/kernel/random/uuid && return
    python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null \
        || die "Не удалось сгенерировать UUID"
}

gen_secret() { openssl rand -hex 16 2>/dev/null; }

# ── Прочие алиасы ─────────────────────────────────────────────────────────────
get_public_ip() { server_ip; }

get_telemt_version() {
    if command -v telemt &>/dev/null; then
        telemt --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "?"
    elif docker inspect telemt &>/dev/null 2>&1; then
        docker exec telemt telemt --version 2>/dev/null \
            | grep -oP '[\d.]+' | head -1 || echo "?"
    else
        echo ""
    fi
}

get_hysteria_version() {
    command -v hysteria &>/dev/null \
        && hysteria version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo ""
}

check_port_free() {
    local port="$1"
    ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}" && {
        warn "Порт ${port} уже занят"
        return 1
    }
    return 0
}

# SSH-миграция (заглушки — полная реализация в отдельном модуле)
ensure_sshpass()       { ensure_pkg sshpass; }
ask_ssh_target()       { ask "SSH хост (user@ip)" _SSH_TARGET ""; }
init_ssh_helpers()     { :; }
check_ssh_connection() { :; }
