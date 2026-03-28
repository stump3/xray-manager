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

