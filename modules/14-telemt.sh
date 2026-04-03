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

_telemt_patch_stream() {
    local masq_domain="$1" internal_port="$2"
    local stream_conf="/etc/nginx/stream.d/stream-443.conf"

    [[ -f "$stream_conf" ]] || { warn "stream-443.conf не найден — патч пропущен"; return 1; }

    if grep -q "telemt_local" "$stream_conf" 2>/dev/null; then
        warn "nginx stream: telemt уже прописан — пропускаем"
        return 0
    fi

    local bak="${stream_conf}.bak.$(date +%s)"
    cp "$stream_conf" "$bak"

    # Экранируем точки в домене для map-паттерна
    local escaped; escaped=$(echo "$masq_domain" | sed 's/\./\\./g')

    # Вставить map-запись перед строкой "default"
    sed -i "s|        default |        ${escaped}  telemt_local;\n        default |" "$stream_conf"

    # Вставить upstream перед "upstream nginx_https"
    sed -i "s|    upstream nginx_https|    upstream telemt_local { server 127.0.0.1:${internal_port}; }\n    upstream nginx_https|" "$stream_conf"

    if nginx -t -q 2>/dev/null; then
        systemctl reload nginx \
            && ok "nginx stream: SNI '${masq_domain}' → telemt 127.0.0.1:${internal_port}" \
            || { warn "nginx reload не удался"; mv "$bak" "$stream_conf"; return 1; }
    else
        warn "nginx -t провалился — откат stream conf"
        mv "$bak" "$stream_conf"
        return 1
    fi
}

telemt_menu_install() {
    header "Установка MTProxy (${TELEMT_MODE})"
    local port; read -rp "Порт прокси [8443]: " port; port="${port:-8443}" < /dev/tty
    while ss -tlnp 2>/dev/null | grep -q ":${port} "; do
        warn "Порт $port занят!"
        read -rp "  Другой порт: " port < /dev/tty
    done
    local domain; read -rp "Домен-маскировка [petrovich.ru]: " domain; domain="${domain:-petrovich.ru}" < /dev/tty

    # Если выбран порт 443 и активен nginx stream — предложить маршрутизацию по SNI
    # Только для systemd-режима: в Docker 127.0.0.1 — loopback контейнера, не хоста
    local _use_nginx_stream=false _internal_port="$port"
    local _stream_conf="/etc/nginx/stream.d/stream-443.conf"
    if [[ "$port" == "443" && -f "$_stream_conf" && "$TELEMT_MODE" == "systemd" ]]; then
        echo ""
        echo -e "  ${YELLOW}Обнаружен nginx stream на 443.${R}"
        echo -e "  ${DIM}telemt может слушать внутри, а nginx будет направлять трафик"
        echo -e "  по SNI '${domain}' → telemt. Порт 443 остаётся за nginx.${R}"
        echo ""
        local _yn; read -rp "  Маршрутизировать через nginx stream? [Y/n]: " _yn < /dev/tty
        if [[ "${_yn:-Y}" =~ ^[Yy]$ ]]; then
            _use_nginx_stream=true
            read -rp "  Внутренний порт telemt (localhost) [2053]: " _internal_port < /dev/tty
            _internal_port="${_internal_port:-2053}"
            while ss -tlnp 2>/dev/null | grep -q ":${_internal_port} "; do
                warn "Порт ${_internal_port} занят!"
                read -rp "  Другой внутренний порт: " _internal_port < /dev/tty
            done
            ok "telemt → 127.0.0.1:${_internal_port}, nginx stream → 443 (SNI: ${domain})"
        fi
    fi
    echo ""; telemt_ask_users
    if [ "$TELEMT_MODE" = "systemd" ]; then
        telemt_pick_version
        telemt_download_binary "$TELEMT_CHOSEN_VERSION"
        id telemt &>/dev/null || useradd -d "$TELEMT_WORK_DIR" -m -r -U telemt
        telemt_write_config "$_internal_port" "$domain" "${TELEMT_USER_PAIRS[@]}"
        mkdir -p "$TELEMT_TLSFRONT_DIR"
        chown -R telemt:telemt "$TELEMT_CONFIG_DIR" "$TELEMT_WORK_DIR"
        telemt_write_service
        # stream-режим: слушаем только на localhost
        $_use_nginx_stream && sed -i 's/^ip = "0\.0\.0\.0"/ip = "127.0.0.1"/' "$TELEMT_CONFIG_FILE"
        systemctl daemon-reload; systemctl enable telemt; systemctl start telemt
        ok "Сервис запущен"
    else
        telemt_write_config "$_internal_port" "$domain" "${TELEMT_USER_PAIRS[@]}"
        telemt_write_compose "$_internal_port"
        # stream-режим: слушаем только на localhost
        $_use_nginx_stream && sed -i 's/^ip = "0\.0\.0\.0"/ip = "127.0.0.1"/' "$TELEMT_CONFIG_FILE"
        cd "$TELEMT_WORK_DIR_DOCKER"
        docker compose pull -q; docker compose up -d
        ok "Контейнер запущен"
    fi
    if $_use_nginx_stream; then
        _telemt_patch_stream "$domain" "$_internal_port"
        ok "MTProto доступен на TCP:443 (nginx stream, SNI: ${domain})"
    else
        command -v ufw &>/dev/null && ufw allow "${port}/tcp" &>/dev/null && ok "ufw: порт $port открыт"
    fi
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
