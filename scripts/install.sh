#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  Xray Manager — интерактивная установка v2.7.1
#  Запуск: sudo bash scripts/install.sh
# ══════════════════════════════════════════════════════════════
set -euo pipefail

R="\e[0m"; BOLD="\e[1m"; DIM="\e[2m"
GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RED="\e[31m"

ok()   { printf " ${GREEN}✓${R} %s\n" "$*"; }
err()  { printf " ${RED}✗${R} ${RED}%s${R}\n" "$*" >&2; }
info() { printf " ${CYAN}→${R} %s\n" "$*"; }
warn() { printf " ${YELLOW}⚠${R}  %s\n" "$*"; }
step() { printf "\n${CYAN}${BOLD}[%s/%s]${R} %s\n" "$1" "7" "$2"; }
ask_val() {
    local label="$1" var="$2" def="${3:-}"
    [[ -n "$def" ]] && printf " ${CYAN}?${R} %s ${DIM}[%s]${R}: " "$label" "$def" \
                    || printf " ${CYAN}?${R} %s: " "$label"
    local v; read -r v
    [[ -z "$v" && -n "$def" ]] && v="$def"
    printf -v "$var" '%s' "$v"
}

spin_start() {
    printf " ${CYAN}⠋${R} %s..." "$1"
    ( local f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") i=0
      while true; do
          printf "\r ${CYAN}%s${R} %s..." "${f[$((i%10))]}" "$1"
          sleep 0.1; i=$((i+1))
      done ) &
    _SPIN=$!
}
spin_stop() {
    [[ -n "${_SPIN:-}" ]] && { kill "$_SPIN" 2>/dev/null; wait "$_SPIN" 2>/dev/null || true; _SPIN=""; }
    printf "\r"
}
_SPIN=""

[[ "$(id -u)" -eq 0 ]] || { err "Запускать от root: sudo bash $0"; exit 1; }

# Надёжное определение REPO_DIR — работает при curl|bash, bash scripts/install.sh,
# и bash /absolute/path/scripts/install.sh.
# BASH_SOURCE[0] пуст или "/dev/stdin" при curl|bash → dirname даёт "/dev" или "."
# В этом случае fallback: ищем репо рядом с CWD или в /root/xray-manager.
_detect_repo_dir() {
    # Попытка 1: из BASH_SOURCE (работает при bash scripts/install.sh из репо)
    local _src="${BASH_SOURCE[0]:-}"
    if [[ -n "$_src" && "$_src" != "/dev/stdin" && "$_src" != "bash" ]]; then
        local _sdir; _sdir="$(cd "$(dirname "$_src")" 2>/dev/null && pwd)"
        local _rdir; _rdir="$(dirname "$_sdir")"
        if [[ -f "${_rdir}/nginx/sites/vpn.conf" ]]; then
            echo "$_rdir"; return
        fi
    fi
    # Попытка 2: CWD содержит nginx/sites/vpn.conf (запуск из корня репо)
    if [[ -f "$(pwd)/nginx/sites/vpn.conf" ]]; then
        echo "$(pwd)"; return
    fi
    # Попытка 3: CWD — это scripts/, репо — родитель
    if [[ -f "$(dirname "$(pwd)")/nginx/sites/vpn.conf" ]]; then
        echo "$(dirname "$(pwd)")"; return
    fi
    # Попытка 4: стандартный путь клона
    for _try in /root/xray-manager /root/xray-manager-main /opt/xray-manager; do
        [[ -f "${_try}/nginx/sites/vpn.conf" ]] && { echo "$_try"; return; }
    done
    echo ""
}
REPO_DIR="$(_detect_repo_dir)"
if [[ -z "$REPO_DIR" ]]; then
    err "Не удалось найти файлы репозитория (nginx/sites/vpn.conf)."
    err "Запускай так: cd /path/to/xray-manager && sudo bash scripts/install.sh"
    exit 1
fi
SCRIPT_DIR="${REPO_DIR}/scripts"
info "Репозиторий: ${REPO_DIR}"

clear
printf "\n${CYAN}${BOLD}"
cat << 'BANNER'
 ██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗
 ╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗
  ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝
  ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗
 ██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║
 ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
BANNER
printf "${R}\n  ${DIM}Установка стека v2.8.1${R}\n\n"

# ══════════════════════════════════════════════════════════════
# ОБНАРУЖЕНИЕ СУЩЕСТВУЮЩЕЙ УСТАНОВКИ
# ══════════════════════════════════════════════════════════════

_svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
_svc_exists() { systemctl list-unit-files "$1" 2>/dev/null | grep -q "$1"; }

_detect_installed() {
    # Возвращает 0 если что-то установлено, 1 если чисто
    [[ -f /usr/local/bin/xray ]]             && return 0
    [[ -f /usr/local/bin/xray-manager ]]     && return 0
    [[ -f /usr/local/etc/xray/config.json ]] && return 0
    command -v hysteria &>/dev/null          && return 0
    [[ -f /etc/hysteria/config.yaml ]]       && return 0
    [[ -f /usr/local/bin/telemt ]]           && return 0
    _svc_exists telemt                       && return 0
    { docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^telemt$"; } && return 0
    [[ -f /root/.xray-mgr-install ]]         && return 0
    return 1
}

_show_installed_summary() {
    local xray_ver="" hy_ver="" tm_ver="" tm_mode=""

    printf "\n  ${YELLOW}${BOLD}Обнаружены установленные компоненты:${R}\n\n"

    # Xray
    if [[ -f /usr/local/bin/xray ]]; then
        xray_ver=$(/usr/local/bin/xray version 2>/dev/null | grep -i 'xray\|version' | head -1 | awk '{print $NF}' || echo "?")
        printf "  ${GREEN}✓${R}  Xray-core          ${DIM}%s${R}\n" "$xray_ver"
    else
        printf "  ${DIM}○  Xray-core          не установлен${R}\n"
    fi

    # xray-manager
    if [[ -f /usr/local/bin/xray-manager ]]; then
        printf "  ${GREEN}✓${R}  xray-manager       ${DIM}бинарник${R}\n"
    else
        printf "  ${DIM}○  xray-manager       не установлен${R}\n"
    fi

    # Hysteria2
    if command -v hysteria &>/dev/null; then
        hy_ver=$(hysteria version 2>/dev/null | grep -i version | awk '{print $NF}' || echo "?")
        printf "  ${GREEN}✓${R}  Hysteria2          ${DIM}%s${R}\n" "$hy_ver"
    else
        printf "  ${DIM}○  Hysteria2          не установлен${R}\n"
    fi

    # telemt
    if [[ -f /usr/local/bin/telemt ]]; then
        tm_ver=$(/usr/local/bin/telemt --version 2>/dev/null | awk '{print $NF}' || echo "?")
        _svc_active telemt && tm_mode="systemd, активен" || tm_mode="systemd, не активен"
        printf "  ${GREEN}✓${R}  telemt (MTProto)   ${DIM}%s  %s${R}\n" "$tm_ver" "$tm_mode"
    elif docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^telemt$"; then
        printf "  ${GREEN}✓${R}  telemt (MTProto)   ${DIM}Docker, запущен${R}\n"
    else
        printf "  ${DIM}○  telemt (MTProto)   не установлен${R}\n"
    fi

    # nginx / stream
    if [[ -f /etc/nginx/sites-enabled/vpn.conf ]]; then
        printf "  ${GREEN}✓${R}  nginx vhost        ${DIM}/etc/nginx/sites-enabled/vpn.conf${R}\n"
    fi
    if [[ -f /etc/nginx/stream.d/stream-443.conf ]]; then
        printf "  ${GREEN}✓${R}  nginx stream       ${DIM}stream-443.conf (SNI на 443)${R}\n"
    fi

    # Параметры установки
    if [[ -f /root/.xray-mgr-install ]]; then
        local inst_domain; inst_domain=$(grep -oP '^DOMAIN="\K[^"]+' /root/.xray-mgr-install 2>/dev/null || echo "?")
        printf "  ${GREEN}✓${R}  Параметры          ${DIM}/root/.xray-mgr-install  (домен: %s)${R}\n" "$inst_domain"
    fi

    printf "\n"
}

_purge_all() {
    printf "\n  ${RED}${BOLD}Удаление всех компонентов...${R}\n\n"

    # Xray
    if [[ -f /usr/local/bin/xray ]]; then
        info "Удаление Xray-core..."
        bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
            @ remove --purge 2>/dev/null || true
        rm -f /usr/local/etc/xray/config.json
        rm -f /usr/local/etc/xray/.keys.* 2>/dev/null || true
        rm -f /usr/local/etc/xray/.limits.json 2>/dev/null || true
        rm -rf /var/log/xray 2>/dev/null || true
        ok "Xray удалён"
    fi

    # Hysteria2
    if command -v hysteria &>/dev/null || [[ -f /etc/hysteria/config.yaml ]]; then
        info "Удаление Hysteria2..."
        systemctl stop hysteria-server 2>/dev/null || true
        systemctl disable hysteria-server 2>/dev/null || true
        rm -f /etc/systemd/system/hysteria-server.service \
              /usr/local/bin/hysteria /usr/bin/hysteria 2>/dev/null || true
        rm -rf /etc/hysteria 2>/dev/null || true
        rm -f /root/hysteria-*.txt 2>/dev/null || true
        ok "Hysteria2 удалена"
    fi

    # telemt (systemd)
    if [[ -f /usr/local/bin/telemt ]] || _svc_exists telemt; then
        info "Удаление telemt (systemd)..."
        systemctl stop telemt 2>/dev/null || true
        systemctl disable telemt 2>/dev/null || true
        rm -f /etc/systemd/system/telemt.service /usr/local/bin/telemt 2>/dev/null || true
        rm -rf /etc/telemt /opt/telemt 2>/dev/null || true
        ok "telemt (systemd) удалён"
    fi

    # telemt (Docker)
    if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^telemt$"; then
        info "Удаление telemt (Docker)..."
        docker compose -f "${HOME}/mtproxy/docker-compose.yml" down 2>/dev/null || true
        rm -rf "${HOME}/mtproxy" 2>/dev/null || true
        ok "telemt (Docker) удалён"
    fi

    # nginx конфиги
    info "Очистка nginx..."
    rm -f /etc/nginx/sites-enabled/vpn.conf \
          /etc/nginx/sites-available/vpn.conf \
          /etc/nginx/sites-available/acme-temp.conf \
          /etc/nginx/stream.d/stream-443.conf 2>/dev/null || true
    ok "nginx очищен"

    # xray-manager
    rm -f /usr/local/bin/xray-manager 2>/dev/null || true

    # systemd таймеры лимитов
    systemctl stop xray-limits.timer 2>/dev/null || true
    systemctl disable xray-limits.timer 2>/dev/null || true
    rm -f /etc/systemd/system/xray-limits.* 2>/dev/null || true

    # Файлы состояния
    rm -f /root/.xray-mgr-install /root/.xray-reality-local-port 2>/dev/null || true

    systemctl daemon-reload 2>/dev/null || true
    printf "\n  ${GREEN}${BOLD}Всё удалено. Продолжаем чистую установку...${R}\n\n"
    sleep 1
}

_reinstall_menu() {
    _show_installed_summary
    printf "  ${BOLD}Что делаем?${R}\n\n"
    printf "  ${CYAN}1)${R} ${BOLD}Чистая переустановка${R}  — удалить всё и установить заново\n"
    printf "  ${CYAN}2)${R} Продолжить             — обновить nginx и скрипт, не трогая сервисы\n"
    printf "  ${CYAN}0)${R} Выйти\n\n"
    local ch
    while true; do
        read -rp " $(printf "${CYAN}?${R}") Выбор [1/2/0]: " ch
        case "${ch:-}" in
            1)
                printf "\n  ${RED}${BOLD}ВНИМАНИЕ:${R} Это удалит Xray, Hysteria2, telemt и все конфиги.\n"
                local yn; read -rp "  Вы уверены? [y/N]: " yn
                [[ "${yn:-N}" =~ ^[Yy]$ ]] || { warn "Отменено"; exit 0; }
                _purge_all
                break
                ;;
            2) printf "\n  Продолжаем обновление...\n\n"; break ;;
            0) printf "\n  Выход.\n"; exit 0 ;;
            *) warn "Введите 1, 2 или 0" ;;
        esac
    done
}

# Запускаем детекцию до ввода параметров
if _detect_installed; then
    _reinstall_menu
fi
ask_val "Ваш домен (напр. vpn.example.com)" DOMAIN ""
while [[ -z "$DOMAIN" ]]; do warn "Домен обязателен"; ask_val "Домен" DOMAIN ""; done

ask_val "Email для Let's Encrypt" LE_EMAIL ""
while [[ -z "$LE_EMAIL" ]]; do warn "Email обязателен"; ask_val "Email" LE_EMAIL ""; done

ask_val "Порт VLESS+WebSocket (внутренний, Nginx → Xray)" WS_PORT "10001"
ask_val "Порт VLESS+REALITY (напрямую, без Nginx)" REALITY_PORT "8443"

# ── Конфликт 443 ─────────────────────────────────────────────
USE_STREAM=false
NGINX_PORT=443

if [[ "$REALITY_PORT" == "443" ]]; then
    echo ""
    warn "Порт 443 выбран для REALITY, но его же использует Nginx (HTTPS)."
    echo ""
    printf "  ${CYAN}1)${R} Nginx stream — SNI-маршрутизация на 443 ${DIM}(рекомендуется)${R}\n"
    printf "     REALITY-трафик → Xray, HTTPS → Nginx(4443)\n"
    printf "  ${CYAN}2)${R} Перевести REALITY на другой порт (напр. 8443)\n"
    echo ""
    printf " ${CYAN}?${R} Выбери вариант [1/2]: "
    read -r stream_choice
    if [[ "${stream_choice:-1}" == "2" ]]; then
        ask_val "Порт для REALITY" REALITY_PORT "8443"
        USE_STREAM=false; NGINX_PORT=443
    else
        USE_STREAM=true; NGINX_PORT=4443
        info "Nginx → 4443, nginx stream → 443 (SNI-маршрутизация)"
    fi
fi

SUB_TOKEN=$(openssl rand -hex 16)

echo ""
echo "  ─────────────────────────────────────"
printf "   Домен:        ${CYAN}%s${R}\n"   "$DOMAIN"
printf "   Email:        ${CYAN}%s${R}\n"   "$LE_EMAIL"
printf "   WS порт:      ${YELLOW}%s${R}\n"  "$WS_PORT"
printf "   REALITY порт: ${YELLOW}%s${R}\n"  "$REALITY_PORT"
$USE_STREAM && printf "   Nginx порт:   ${YELLOW}4443${R} ${DIM}(за stream 443)${R}\n"
printf "   SUB_TOKEN:    ${DIM}%s${R}\n"    "$SUB_TOKEN"
echo "  ─────────────────────────────────────"
echo ""
printf " ${YELLOW}?${R} Всё верно? [Y/n]: "
read -r confirm
[[ "${confirm,,}" == "n" ]] && { info "Отменено"; exit 0; }

# ══════════════════════════════════════════════════════════════
step 1 "Установка зависимостей"

# Версия nginx для http2 синтаксиса (>=1.25 → http2 on;)
NGINX_MINOR=0
command -v nginx &>/dev/null && \
    NGINX_MINOR=$(nginx -v 2>&1 | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2 || echo 0)

spin_start "apt-get update"
apt-get update -qq 2>/dev/null
spin_stop; ok "Индексы обновлены"

PKGS=(nginx certbot python3-certbot-nginx curl jq openssl
      qrencode python3 uuid-runtime unzip dnsutils ufw)
NEED=()
for p in "${PKGS[@]}"; do dpkg -s "$p" &>/dev/null || NEED+=("$p"); done

if [[ ${#NEED[@]} -gt 0 ]]; then
    info "Устанавливаем: ${NEED[*]}"
    spin_start "apt-get install"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${NEED[@]}" 2>/dev/null
    spin_stop
fi

# nginx stream модуль нужен если USE_STREAM=true
if $USE_STREAM && ! nginx -V 2>&1 | grep -q "stream_module\|ngx_stream"; then
    spin_start "nginx-full (stream module)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx-full 2>/dev/null
    spin_stop
fi

# Перепроверяем версию после возможного обновления nginx
NGINX_MINOR=$(nginx -v 2>&1 | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2 || echo 0)
ok "Зависимости готовы (nginx 1.${NGINX_MINOR})"

# ══════════════════════════════════════════════════════════════
step 2 "Настройка UFW"

ufw --force enable 2>/dev/null || true
for rule in "22/tcp" "80/tcp" "443/tcp" "443/udp"; do
    ufw allow "$rule" 2>/dev/null || true
done
[[ "$REALITY_PORT" != "443" ]] && ufw allow "${REALITY_PORT}/tcp" 2>/dev/null || true
ok "UFW настроен"

# ══════════════════════════════════════════════════════════════
step 3 "Настройка Nginx"

# Убрать артефакты предыдущих установок (stream-443 в conf.d ломает nginx -t)
rm -f /etc/nginx/conf.d/stream-443.conf 2>/dev/null || true

mkdir -p /var/www/html /var/www/certbot
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>OK</title>
<style>body{margin:0;display:flex;align-items:center;justify-content:center;
height:100vh;background:#0d1117;color:#c9d1d9;font-family:sans-serif}</style>
</head><body><h2>Server is running</h2></body></html>
HTML

# Временный HTTP-конфиг для ACME
cat > /etc/nginx/sites-available/acme-temp.conf << ACME_CONF
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 200 'OK'; add_header Content-Type text/plain; }
}
ACME_CONF
ln -sf /etc/nginx/sites-available/acme-temp.conf \
       /etc/nginx/sites-enabled/acme-temp.conf 2>/dev/null || true
# При переустановке старый vpn.conf остаётся в sites-enabled и конфликтует
# с acme-temp по server_name на 80 → убираем до nginx -t
rm -f /etc/nginx/sites-enabled/default \
      /etc/nginx/sites-enabled/vpn.conf 2>/dev/null || true
if nginx -t -q 2>/dev/null && systemctl restart nginx; then
    ok "Nginx запущен (временный ACME-конфиг)"
else
    # nginx -t вывел ошибки выше (-q не подавляет emerg/warn)
    warn "nginx -t вернул ошибку — пробуем продолжить"
    systemctl restart nginx 2>/dev/null || true
fi

# ══════════════════════════════════════════════════════════════
step 4 "TLS-сертификат"

# Проверка DNS
spin_start "Проверка DNS"
SERVER_IP=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null || echo "")
DOMAIN_IP=$(dig +short A "${DOMAIN}" 2>/dev/null | tail -1 || echo "")
spin_stop

if [[ -n "$SERVER_IP" && -n "$DOMAIN_IP" && "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    warn "DNS: A-запись ${DOMAIN} → ${DOMAIN_IP}, IP сервера → ${SERVER_IP}"
    warn "Они не совпадают — ACME может провалиться."
    printf " ${YELLOW}?${R} Продолжить? [y/N]: "; read -r dns_ok
    [[ "${dns_ok,,}" != "y" ]] && { err "Дождись обновления DNS и запусти снова"; exit 1; }
fi

if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    info "Сертификат существует"
else
    spin_start "certbot certonly"
    certbot certonly --webroot \
        -w /var/www/certbot \
        -d "${DOMAIN}" \
        --email "${LE_EMAIL}" \
        --agree-tos --non-interactive --quiet
    spin_stop
fi
ok "Сертификат: /etc/letsencrypt/live/${DOMAIN}/"

# Deploy hook
HOOK_SRC="${REPO_DIR}/scripts/certbot-deploy-hook.sh"
HOOK_DST="/etc/letsencrypt/renewal-hooks/deploy/reload-services.sh"
[[ -f "$HOOK_SRC" ]] && { cp "$HOOK_SRC" "$HOOK_DST"; chmod +x "$HOOK_DST"; }

# ── Основной nginx vhost ──────────────────────────────────────
# Устанавливаем базовый nginx.conf с поддержкой stream.d (если ещё не наш)
NGINX_CONF_SRC="${REPO_DIR}/nginx/nginx.conf"
if [[ -f "$NGINX_CONF_SRC" ]]; then
    if ! grep -q "stream.d" /etc/nginx/nginx.conf 2>/dev/null; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d_%H%M%S)
        cp "$NGINX_CONF_SRC" /etc/nginx/nginx.conf
        mkdir -p /etc/nginx/stream.d
        info "nginx.conf обновлён (добавлена поддержка stream.d)"
    fi
fi

VHOST_SRC="${REPO_DIR}/nginx/sites/vpn.conf"
VHOST_DST="/etc/nginx/sites-available/vpn.conf"

# http2: nginx <1.25 → в listen, nginx >=1.25 → отдельная директива
if [[ "$NGINX_MINOR" -ge 25 ]]; then
    H2_LISTEN=""; H2_EXTRA="    http2 on;"
else
    H2_LISTEN="http2"; H2_EXTRA=""
fi

sed \
    -e "s|DOMAIN|${DOMAIN}|g" \
    -e "s|SUB_TOKEN|${SUB_TOKEN}|g" \
    -e "s|WS_PORT|${WS_PORT}|g" \
    -e "s|NGINX_PORT|${NGINX_PORT}|g" \
    -e "s|HTTP2_DIRECTIVE|${H2_LISTEN}|g" \
    "$VHOST_SRC" > "$VHOST_DST"

# Вставляем http2 on; для nginx >= 1.25
[[ -n "$H2_EXTRA" ]] && \
    sed -i "/ssl_certificate_key/a\\${H2_EXTRA}" "$VHOST_DST"

# ── Nginx stream для REALITY на 443 ──────────────────────────
# ВАЖНО: stream {} должен быть на корневом уровне nginx.conf, НЕ внутри http {}.
# Файл пишется в /etc/nginx/stream.d/ и подключается через include вне http {}.
# nginx.conf из репозитория уже содержит: include /etc/nginx/stream.d/*.conf;
if $USE_STREAM; then
    # Nginx слушает на 127.0.0.1:4443 с proxy_protocol
    sed -i \
        -e "s|listen ${NGINX_PORT} ssl|listen 127.0.0.1:${NGINX_PORT} ssl proxy_protocol|g" \
        -e "s|listen \[::\]:${NGINX_PORT} ssl|#listen [::]:${NGINX_PORT} ssl|g" \
        "$VHOST_DST"

    # Stream-конфиг: SNI-маршрутизация на 443
    # Трафик на домен → nginx (HTTPS), всё остальное (REALITY) → Xray
    # Xray REALITY слушает на 127.0.0.1:${REALITY_PORT} (или напрямую если нужно)
    # Xray REALITY слушает на localhost-порту, а не на 0.0.0.0:443
    # Чтобы не конфликтовать с nginx stream на 443.
    # Если REALITY_PORT=443 — Xray уходит на внутренний порт 18443.
    XRAY_LOCAL_PORT="${REALITY_PORT}"
    [[ "$REALITY_PORT" == "443" ]] && XRAY_LOCAL_PORT="18443"

    mkdir -p /etc/nginx/stream.d
    cat > /etc/nginx/stream.d/stream-443.conf << STREAM_CONF
stream {
    # SNI-маршрутизация:
    #   домен сервера  → nginx HTTPS (${NGINX_PORT})
    #   всё остальное  → Xray REALITY (127.0.0.1:${XRAY_LOCAL_PORT})
    map \$ssl_preread_server_name \$backend {
        ~^(.+\.)?$(echo "$DOMAIN" | sed 's/\./\./g')\$  nginx_https;
        default                                            xray_reality;
    }
    upstream nginx_https  { server 127.0.0.1:${NGINX_PORT}; }
    upstream xray_reality { server 127.0.0.1:${XRAY_LOCAL_PORT}; }
    server {
        listen 443;
        listen [::]:443;
        proxy_pass  \$backend;
        ssl_preread on;
        # proxy_protocol НЕ включаем для xray_reality — Xray его не ожидает
        # Nginx передаёт поток как есть, Xray видит настоящий TLS ClientHello
    }
}
STREAM_CONF

    # Сохраняем порт для proto_vless_tcp_reality
    echo "${XRAY_LOCAL_PORT}" > /root/.xray-reality-local-port

    ok "Nginx stream: 443 → SNI → nginx(${NGINX_PORT}) | Xray(${XRAY_LOCAL_PORT})"
    info "При добавлении VLESS+REALITY используй порт: ${XRAY_LOCAL_PORT} (не 443)"
    warn "Xray должен слушать на 127.0.0.1:${XRAY_LOCAL_PORT}, а не 0.0.0.0:443"
fi

ln -sf "$VHOST_DST" /etc/nginx/sites-enabled/vpn.conf
rm -f /etc/nginx/sites-enabled/acme-temp.conf

# ssl_stapling работает только если сертификат содержит OCSP URL.
# Let's Encrypt через certbot — содержит. Через acme.sh без флага — может не содержать.
# Проверяем и отключаем stapling если URL нет, чтобы не получать [warn] при старте.
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [[ -f "$CERT_FILE" ]] && ! openssl x509 -in "$CERT_FILE" -noout -text 2>/dev/null | grep -q "OCSP"; then
    sed -i 's/ssl_stapling\s*on/ssl_stapling off/' "$VHOST_DST" 2>/dev/null || true
    sed -i 's/ssl_stapling_verify\s*on/ssl_stapling_verify off/' "$VHOST_DST" 2>/dev/null || true
    info "ssl_stapling отключён — сертификат не содержит OCSP URL"
fi

nginx -t -q && systemctl restart nginx
ok "Nginx настроен (порт ${NGINX_PORT})"

# ══════════════════════════════════════════════════════════════
step 5 "Xray-core"

spin_start "Загрузка и установка"
bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install 2>/dev/null
spin_stop
ok "Xray $(/usr/local/bin/xray -version 2>/dev/null | awk 'NR==1{print $2}')"

# ══════════════════════════════════════════════════════════════
step 6 "xray-manager"

MANAGER_DST="/usr/local/bin/xray-manager"
MANAGER_SRC="${REPO_DIR}/xray-manager.sh"

# Собираем из модулей если xray-manager.sh пустой или отсутствует
if [[ ! -s "$MANAGER_SRC" ]] && [[ -d "${REPO_DIR}/modules" ]] && \
   [[ -n "$(ls "${REPO_DIR}/modules/"*.sh 2>/dev/null)" ]]; then
    info "Собираем из модулей..."
    cat "${REPO_DIR}/modules/"*.sh > "$MANAGER_SRC"
fi

if [[ -s "$MANAGER_SRC" ]]; then
    cp "$MANAGER_SRC" "$MANAGER_DST"
    chmod +x "$MANAGER_DST"
    ok "xray-manager установлен ($(wc -l < "$MANAGER_DST") строк)"
else
    warn "xray-manager.sh не найден — скопируй вручную в /usr/local/bin/xray-manager"
fi

# ══════════════════════════════════════════════════════════════
step 7 "Сохранение параметров"

cat > /root/.xray-mgr-install << PARAMS
DOMAIN="${DOMAIN}"
LE_EMAIL="${LE_EMAIL}"
WS_PORT="${WS_PORT}"
REALITY_PORT="${REALITY_PORT}"
NGINX_PORT="${NGINX_PORT}"
USE_STREAM="${USE_STREAM}"
SUB_TOKEN="${SUB_TOKEN}"
INSTALLED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
PARAMS
chmod 600 /root/.xray-mgr-install
ok "Сохранено в /root/.xray-mgr-install"

# ══════════════════════════════════════════════════════════════
echo ""
echo "  ════════════════════════════════════════"
printf "  ${GREEN}${BOLD}Готово!${R}\n\n"
printf "  Домен:     ${CYAN}%s${R}\n" "$DOMAIN"
printf "  SUB_TOKEN: ${DIM}%s${R}\n" "$SUB_TOKEN"
echo ""
printf "  Подписка:\n"
printf "    ${YELLOW}https://%s/%s/sub${R}\n"   "$DOMAIN" "$SUB_TOKEN"
printf "    ${YELLOW}https://%s/%s/clash${R}\n" "$DOMAIN" "$SUB_TOKEN"
echo ""
printf "  ${CYAN}sudo xray-manager${R}\n"
echo "  ════════════════════════════════════════"
echo ""
