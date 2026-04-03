#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  Xray Manager — интерактивная установка v2.8.3
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

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
printf "${R}\n  ${DIM}Установка стека v2.8.3${R}\n\n"

# ══════════════════════════════════════════════════════════════
# ОБНАРУЖЕНИЕ СУЩЕСТВУЮЩЕЙ УСТАНОВКИ
# ══════════════════════════════════════════════════════════════

_svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
_svc_exists() { systemctl list-unit-files "$1" 2>/dev/null | grep -q "$1"; }

_detect_installed() {
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
    printf "\n  ${YELLOW}${BOLD}Обнаружены установленные компоненты:${R}\n\n"

    if [[ -f /usr/local/bin/xray ]]; then
        local xv; xv=$(/usr/local/bin/xray version 2>/dev/null | awk 'NR==1{print $2}' || echo "?")
        printf "  ${GREEN}✓${R}  Xray-core          ${DIM}%s${R}\n" "$xv"
    else
        printf "  ${DIM}○  Xray-core          не установлен${R}\n"
    fi

    if [[ -f /usr/local/bin/xray-manager ]]; then
        printf "  ${GREEN}✓${R}  xray-manager       ${DIM}бинарник${R}\n"
    else
        printf "  ${DIM}○  xray-manager       не установлен${R}\n"
    fi

    if command -v hysteria &>/dev/null; then
        local hv; hv=$(hysteria version 2>/dev/null | awk 'NR==1{print $NF}' || echo "?")
        printf "  ${GREEN}✓${R}  Hysteria2          ${DIM}%s${R}\n" "$hv"
    else
        printf "  ${DIM}○  Hysteria2          не установлен${R}\n"
    fi

    if [[ -f /usr/local/bin/telemt ]]; then
        local tv tm
        tv=$(/usr/local/bin/telemt --version 2>/dev/null | awk '{print $NF}' || echo "?")
        _svc_active telemt && tm="systemd, активен" || tm="systemd, не активен"
        printf "  ${GREEN}✓${R}  telemt (MTProto)   ${DIM}%s  %s${R}\n" "$tv" "$tm"
    elif docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^telemt$"; then
        printf "  ${GREEN}✓${R}  telemt (MTProto)   ${DIM}Docker, запущен${R}\n"
    else
        printf "  ${DIM}○  telemt (MTProto)   не установлен${R}\n"
    fi

    [[ -f /etc/nginx/sites-enabled/vpn.conf ]] && \
        printf "  ${GREEN}✓${R}  nginx vhost        ${DIM}/etc/nginx/sites-enabled/vpn.conf${R}\n"
    [[ -f /etc/nginx/stream.d/stream-443.conf ]] && \
        printf "  ${GREEN}✓${R}  nginx stream       ${DIM}stream-443.conf (SNI на 443)${R}\n"

    if [[ -f /root/.xray-mgr-install ]]; then
        local d; d=$(grep -oP '^DOMAIN="\K[^"]+' /root/.xray-mgr-install 2>/dev/null || echo "?")
        printf "  ${GREEN}✓${R}  Параметры          ${DIM}/root/.xray-mgr-install  (домен: %s)${R}\n" "$d"
    fi
    printf "\n"
}

_purge_all() {
    printf "\n  ${RED}${BOLD}Удаление всех компонентов...${R}\n\n"

    # Xray — через официальный установщик
    if [[ -f /usr/local/bin/xray ]]; then
        info "Удаление Xray-core..."
        bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
            @ remove --purge 2>/dev/null || true
    fi
    # Остатки которые установщик не чистит
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    rm -f  /etc/systemd/system/xray.service \
           /etc/systemd/system/xray@.service \
           /etc/systemd/system/multi-user.target.wants/xray.service 2>/dev/null || true
    rm -rf /etc/systemd/system/xray.service.d \
           /etc/systemd/system/xray@.service.d 2>/dev/null || true
    rm -f  /usr/local/bin/xray /usr/local/bin/xray-manager 2>/dev/null || true
    rm -rf /usr/local/etc/xray /usr/local/share/xray \
           /var/log/xray /run/xray 2>/dev/null || true
    ok "Xray удалён"

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

    # Системные файлы состояния
    systemctl stop xray-limits.timer 2>/dev/null || true
    systemctl disable xray-limits.timer 2>/dev/null || true
    rm -f /etc/systemd/system/xray-limits.* 2>/dev/null || true
    rm -f /root/.xray-mgr-install /root/.xray-reality-local-port 2>/dev/null || true

    systemctl daemon-reexec 2>/dev/null || true
    systemctl daemon-reload
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
        printf " ${CYAN}?${R} Выбор [1/2/0]: "; read -r ch
        case "${ch:-}" in
            1)
                printf "\n  ${RED}${BOLD}ВНИМАНИЕ:${R} Это удалит Xray, Hysteria2, telemt и все конфиги.\n"
                printf " ${YELLOW}?${R} Вы уверены? [y/N]: "; read -r yn
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

if _detect_installed; then
    _reinstall_menu
fi

# ── Параметры ─────────────────────────────────────────────────
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
if $USE_STREAM; then
    _summary_xray_port="$REALITY_PORT"; [[ "$REALITY_PORT" == "443" ]] && _summary_xray_port="18443"
    printf "   REALITY порт: ${YELLOW}%s${R} ${DIM}(stream → Xray inbound: %s)${R}\n" "$REALITY_PORT" "$_summary_xray_port"
    printf "   Nginx порт:   ${YELLOW}4443${R} ${DIM}(за stream 443)${R}\n"
else
    printf "   REALITY порт: ${YELLOW}%s${R}\n" "$REALITY_PORT"
fi
printf "   SUB_TOKEN:    ${DIM}%s${R}\n"    "$SUB_TOKEN"
echo "  ─────────────────────────────────────"
echo ""
printf " ${YELLOW}?${R} Всё верно? [Y/n]: "
read -r confirm
[[ "${confirm,,}" == "n" ]] && { info "Отменено"; exit 0; }

# ══════════════════════════════════════════════════════════════
step 1 "Установка зависимостей"

systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
_apt_wait=0
while ! flock -n /var/lib/dpkg/lock-frontend -c true 2>/dev/null; do
    [[ $_apt_wait -eq 0 ]] && info "Ждём освобождения apt lock..."
    sleep 2; _apt_wait=$((_apt_wait+2))
    [[ $_apt_wait -ge 60 ]] && { warn "apt lock не освободился за 60с — продолжаем"; break; }
done

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

if $USE_STREAM && ! nginx -V 2>&1 | grep -q "stream_module\|ngx_stream"; then
    spin_start "nginx-full (stream module)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx-full 2>/dev/null
    spin_stop
fi

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

rm -f /etc/nginx/conf.d/stream-443.conf   2>/dev/null || true
rm -f /etc/nginx/stream.d/stream-443.conf 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/vpn.conf   2>/dev/null || true

_port80_owner=$(ss -tlnp 'sport = :80' 2>/dev/null \
    | awk 'NR>1 && /LISTEN/{match($0,/users:\(\("([^"]+)/,a); print a[1]}' | head -1)
if [[ -n "$_port80_owner" && "$_port80_owner" != "nginx" ]]; then
    warn "Порт 80 занят: ${_port80_owner} — nginx не запустится"
    exit 1
fi

mkdir -p /var/www/html /var/www/certbot
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>OK</title>
<style>body{margin:0;display:flex;align-items:center;justify-content:center;
height:100vh;background:#0d1117;color:#c9d1d9;font-family:sans-serif}</style>
</head><body><h2>Server is running</h2></body></html>
HTML

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
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

if ! nginx -t 2>/tmp/nginx_test.log; then
    err "nginx -t провалился:"; cat /tmp/nginx_test.log >&2; exit 1
fi
systemctl restart nginx || {
    err "nginx не запустился:"; journalctl -u nginx -n 20 --no-pager >&2; exit 1
}
ok "Nginx запущен (временный ACME-конфиг)"

# ══════════════════════════════════════════════════════════════
step 4 "TLS-сертификат"

spin_start "Проверка DNS"
SERVER_IP=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null || echo "")
DOMAIN_IP=$(dig +short A "${DOMAIN}" 2>/dev/null | tail -1 || echo "")
spin_stop

if [[ -n "$SERVER_IP" && -n "$DOMAIN_IP" && "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    warn "DNS: A-запись ${DOMAIN} → ${DOMAIN_IP}, IP сервера → ${SERVER_IP}"
    printf " ${YELLOW}?${R} Продолжить? [y/N]: "; read -r dns_ok
    [[ "${dns_ok,,}" != "y" ]] && { err "Дождись обновления DNS"; exit 1; }
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

HOOK_SRC="${REPO_DIR}/scripts/certbot-deploy-hook.sh"
HOOK_DST="/etc/letsencrypt/renewal-hooks/deploy/reload-services.sh"
[[ -f "$HOOK_SRC" ]] && { cp "$HOOK_SRC" "$HOOK_DST"; chmod +x "$HOOK_DST"; }

# ── Основной nginx vhost ──────────────────────────────────────
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

[[ -n "$H2_EXTRA" ]] && sed -i "/ssl_certificate_key/a\\${H2_EXTRA}" "$VHOST_DST"

# ── Nginx stream для REALITY на 443 ──────────────────────────
# ВАЖНО: stream {} на корневом уровне nginx.conf, НЕ внутри http {}.
# nginx.conf из репозитория уже содержит: include /etc/nginx/stream.d/*.conf;
if $USE_STREAM; then
    # Nginx слушает на 127.0.0.1:4443 — proxy_protocol НЕ нужен,
    # Xray получает чистый TLS поток и сам читает ClientHello через ssl_preread
    sed -i \
        -e "s|listen ${NGINX_PORT} ssl|listen 127.0.0.1:${NGINX_PORT} ssl|g" \
        -e "s|listen \[::\]:${NGINX_PORT} ssl|#listen [::]:${NGINX_PORT} ssl|g" \
        "$VHOST_DST"

    # Если REALITY_PORT=443 — Xray уходит на внутренний порт 18443
    XRAY_LOCAL_PORT="${REALITY_PORT}"
    [[ "$REALITY_PORT" == "443" ]] && XRAY_LOCAL_PORT="18443"

    mkdir -p /etc/nginx/stream.d
    cat > /etc/nginx/stream.d/stream-443.conf << STREAM_CONF
stream {
    # SNI-маршрутизация:
    #   домен сервера  → nginx HTTPS (${NGINX_PORT})
    #   всё остальное  → Xray REALITY (127.0.0.1:${XRAY_LOCAL_PORT})
    map \$ssl_preread_server_name \$backend {
        ~^(.+\.)?$(echo "$DOMAIN" | sed 's/\./\\./g')\$  nginx_https;
        default                                            xray_local;
    }
    upstream nginx_https  { server 127.0.0.1:${NGINX_PORT}; }
    upstream xray_local { server 127.0.0.1:${XRAY_LOCAL_PORT}; }
    server {
        listen 443;
        listen [::]:443;
        proxy_pass  \$backend;
        ssl_preread on;
        # proxy_protocol НЕ включаем — Xray читает чистый TLS ClientHello
    }
}
STREAM_CONF

    # Сохраняем порт — proto_vless_tcp_reality читает его как default
    echo "${XRAY_LOCAL_PORT}" > /root/.xray-reality-local-port

    ok "Nginx stream: 443 → SNI → nginx(${NGINX_PORT}) | Xray(${XRAY_LOCAL_PORT})"
    warn "При добавлении VLESS+REALITY используй порт ${XRAY_LOCAL_PORT} (не 443)"
fi

ln -sf "$VHOST_DST" /etc/nginx/sites-enabled/vpn.conf
rm -f /etc/nginx/sites-enabled/acme-temp.conf
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
