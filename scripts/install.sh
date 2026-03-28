#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  Xray Manager — интерактивная установка
#  Запуск: sudo bash scripts/install.sh
#
#  Что делает:
#    1. Устанавливает зависимости (nginx, certbot, jq, qrencode, python3)
#    2. Открывает порты в UFW
#    3. Выпускает TLS-сертификат через Let's Encrypt
#    4. Генерирует SUB_TOKEN и настраивает Nginx
#    5. Устанавливает Xray-core
#    6. Регистрирует xray-manager как системную команду
#    7. Устанавливает certbot deploy hook
# ══════════════════════════════════════════════════════════════
set -euo pipefail

# ── Цвета ─────────────────────────────────────────────────────
R="\e[0m"; BOLD="\e[1m"; DIM="\e[2m"
GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RED="\e[31m"

ok()   { printf " ${GREEN}✓${R} %s\n" "$*"; }
err()  { printf " ${RED}✗${R} ${RED}%s${R}\n" "$*" >&2; }
info() { printf " ${CYAN}ℹ${R} %s\n" "$*"; }
warn() { printf " ${YELLOW}⚠${R} %s\n" "$*"; }
ask_val() {
    local label="$1" var="$2" def="${3:-}"
    if [[ -n "$def" ]]; then
        printf " ${CYAN}?${R} %s ${DIM}[%s]${R}: " "$label" "$def"
    else
        printf " ${CYAN}?${R} %s: " "$label"
    fi
    local v; read -r v
    [[ -z "$v" && -n "$def" ]] && v="$def"
    printf -v "$var" '%s' "$v"
}

# ── Проверка root ──────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || { err "Запускать от root: sudo bash $0"; exit 1; }

# ── Баннер ────────────────────────────────────────────────────
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
printf "${R}\n"
printf " ${DIM}Интерактивная установка v2.6.0${R}\n\n"

# ── Определение директории скрипта ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── Сбор параметров ───────────────────────────────────────────
echo "  Введите параметры установки:"
echo ""

ask_val "Ваш домен (например: vpn.example.com)" DOMAIN ""
while [[ -z "$DOMAIN" ]]; do
    warn "Домен обязателен"
    ask_val "Ваш домен" DOMAIN ""
done

ask_val "Email для Let's Encrypt (уведомления об истечении)" LE_EMAIL ""
while [[ -z "$LE_EMAIL" ]]; do
    warn "Email обязателен для Let's Encrypt"
    ask_val "Email" LE_EMAIL ""
done

ask_val "Порт VLESS+WebSocket (внутренний, Nginx → Xray)" WS_PORT "10001"
ask_val "Порт VLESS+REALITY (внешний, напрямую)" REALITY_PORT "8443"

# Генерируем токен подписки
SUB_TOKEN=$(openssl rand -hex 16)

# Подтверждение
echo ""
echo "  ────────────────────────────────"
printf "   Домен:        ${CYAN}%s${R}\n"  "$DOMAIN"
printf "   Email (LE):   ${CYAN}%s${R}\n"  "$LE_EMAIL"
printf "   WS порт:      ${YELLOW}%s${R}\n" "$WS_PORT"
printf "   REALITY порт: ${YELLOW}%s${R}\n" "$REALITY_PORT"
printf "   SUB_TOKEN:    ${DIM}%s${R}\n"   "$SUB_TOKEN"
echo "  ────────────────────────────────"
echo ""
printf " ${YELLOW}?${R} Всё верно? [Y/n]: "
read -r confirm
[[ "${confirm,,}" == "n" ]] && { info "Установка отменена"; exit 0; }

echo ""

# ── Шаг 1: Зависимости ───────────────────────────────────────
info "Шаг 1/7: Установка зависимостей..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nginx certbot python3-certbot-nginx \
    curl jq openssl qrencode python3 uuid-runtime \
    unzip dnsutils ufw 2>/dev/null
ok "Зависимости установлены"

# ── Шаг 2: UFW ───────────────────────────────────────────────
info "Шаг 2/7: Настройка UFW..."
ufw --force enable 2>/dev/null || true
ufw allow 22/tcp    comment "SSH"      2>/dev/null || true
ufw allow 80/tcp    comment "HTTP/ACME" 2>/dev/null || true
ufw allow 443/tcp   comment "HTTPS"    2>/dev/null || true
ufw allow 443/udp   comment "QUIC/H3"  2>/dev/null || true
ufw allow "${REALITY_PORT}/tcp" comment "VLESS+REALITY" 2>/dev/null || true
ok "UFW настроен (порты: 22, 80, 443, ${REALITY_PORT})"

# ── Шаг 3: Nginx + заглушка ──────────────────────────────────
info "Шаг 3/7: Настройка Nginx..."

# Базовый конфиг из репо
if [[ -f "${REPO_DIR}/nginx/nginx.conf" ]]; then
    cp "${REPO_DIR}/nginx/nginx.conf" /etc/nginx/nginx.conf
fi

# Создаём заглушку-сайт
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Welcome</title>
<style>body{font-family:sans-serif;display:flex;justify-content:center;
align-items:center;height:100vh;margin:0;background:#f5f5f5}
.box{text-align:center;color:#555}</style></head>
<body><div class="box"><h1>Welcome</h1><p>Server is running.</p></div></body>
</html>
HTML

# Временный конфиг для ACME challenge (только HTTP)
cat > /etc/nginx/sites-available/acme-temp.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 200 'OK'; }
}
EOF
mkdir -p /var/www/certbot
ln -sf /etc/nginx/sites-available/acme-temp.conf \
       /etc/nginx/sites-enabled/acme-temp.conf 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t -q && systemctl reload nginx
ok "Nginx временно настроен для ACME"

# ── Шаг 4: TLS-сертификат ────────────────────────────────────
info "Шаг 4/7: Выпуск TLS-сертификата (Let's Encrypt)..."
certbot certonly --webroot \
    -w /var/www/certbot \
    -d "${DOMAIN}" \
    --email "${LE_EMAIL}" \
    --agree-tos \
    --non-interactive \
    --quiet

ok "Сертификат выпущен: /etc/letsencrypt/live/${DOMAIN}/"

# Устанавливаем deploy hook
HOOK_SRC="${REPO_DIR}/scripts/certbot-deploy-hook.sh"
HOOK_DST="/etc/letsencrypt/renewal-hooks/deploy/reload-services.sh"
if [[ -f "$HOOK_SRC" ]]; then
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    ok "Certbot deploy hook установлен"
fi

# Основной nginx vhost
VHOST_SRC="${REPO_DIR}/nginx/sites/vpn.conf"
VHOST_DST="/etc/nginx/sites-available/vpn.conf"
if [[ -f "$VHOST_SRC" ]]; then
    sed \
        -e "s/DOMAIN/${DOMAIN}/g" \
        -e "s/SUB_TOKEN/${SUB_TOKEN}/g" \
        -e "s/WS_PORT/${WS_PORT}/g" \
        "$VHOST_SRC" > "$VHOST_DST"
    ln -sf "$VHOST_DST" /etc/nginx/sites-enabled/vpn.conf
    rm -f /etc/nginx/sites-enabled/acme-temp.conf
    nginx -t -q && systemctl reload nginx
    ok "Nginx настроен для ${DOMAIN}"
fi

# ── Шаг 5: Xray-core ─────────────────────────────────────────
info "Шаг 5/7: Установка Xray-core..."
bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install --without-geodata 2>/dev/null
# Геоданные отдельно
bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install-geodata 2>/dev/null
ok "Xray-core установлен: $(/usr/local/bin/xray -version 2>/dev/null | awk 'NR==1{print $2}')"

# ── Шаг 6: xray-manager как системная команда ────────────────
info "Шаг 6/7: Установка xray-manager..."
MANAGER_SRC="${REPO_DIR}/xray-manager.sh"
if [[ ! -f "$MANAGER_SRC" ]]; then
    # Если не собран — собрать
    if command -v make &>/dev/null && [[ -f "${REPO_DIR}/Makefile" ]]; then
        make -C "${REPO_DIR}" build 2>/dev/null
    fi
fi
if [[ -f "$MANAGER_SRC" ]]; then
    cp "$MANAGER_SRC" /usr/local/bin/xray-manager
    chmod +x /usr/local/bin/xray-manager
    ok "xray-manager → /usr/local/bin/xray-manager"
else
    warn "xray-manager.sh не найден — запусти 'make build' в корне репо"
fi

# ── Шаг 7: Сохранение параметров ─────────────────────────────
info "Шаг 7/7: Сохранение параметров..."
cat > /root/.xray-mgr-install << EOF
DOMAIN="${DOMAIN}"
LE_EMAIL="${LE_EMAIL}"
WS_PORT="${WS_PORT}"
REALITY_PORT="${REALITY_PORT}"
SUB_TOKEN="${SUB_TOKEN}"
INSTALLED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
EOF
chmod 600 /root/.xray-mgr-install
ok "Параметры сохранены: /root/.xray-mgr-install"

# ── Готово ────────────────────────────────────────────────────
echo ""
echo "  ════════════════════════════════════"
printf "  ${GREEN}${BOLD}Установка завершена!${R}\n\n"
printf "  Домен:       ${CYAN}%s${R}\n"      "$DOMAIN"
printf "  SUB_TOKEN:   ${DIM}%s${R}\n"       "$SUB_TOKEN"
echo ""
printf "  URL подписки:\n"
printf "    Base64  ${YELLOW}https://%s/%s/sub${R}\n"   "$DOMAIN" "$SUB_TOKEN"
printf "    Clash   ${YELLOW}https://%s/%s/clash${R}\n" "$DOMAIN" "$SUB_TOKEN"
echo ""
printf "  ${DIM}Следующий шаг: добавить протокол через меню${R}\n"
printf "  ${CYAN}sudo xray-manager${R}\n"
echo "  ════════════════════════════════════"
echo ""
