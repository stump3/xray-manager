#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  Xray Manager — установщик
#  Запуск: sudo bash scripts/install.sh
#
#  Варианты:
#    1) Nginx stream + Xray Reality   (в разработке)
#    2) Xray + TLS + Nginx decoy      (в разработке)
#    3) Только Xray                   ← РАБОТАЕТ
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Загружаем все модули ──────────────────────────────────────────────────────
for _mod in $(ls -1 "${REPO_DIR}/modules/"*.sh | sort); do
    # shellcheck disable=SC1090
    source "$_mod"
done

# ── Проверка root ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || {
    printf "\e[31m✗\e[0m  Запустите от root: sudo bash %s\n" "$0"
    exit 1
}

# ── Баннер ────────────────────────────────────────────────────────────────────
cls
printf "\n"
cat << 'BANNER'
  ██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗
  ╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗
   ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝
   ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗
  ██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
BANNER
printf "  ${DIM}v${MANAGER_VERSION} — установка${R}\n\n"

# ── Выбор варианта ────────────────────────────────────────────────────────────
printf "  Выберите вариант установки:\n\n"
printf "  ${CYAN}1)${R} ${BOLD}Nginx stream + Xray Reality${R}  ${DIM}(в разработке)${R}\n"
printf "     443 → SNI → Reality + WS/gRPC на одном порту\n\n"
printf "  ${CYAN}2)${R} ${BOLD}Xray + TLS + Nginx decoy${R}     ${DIM}(в разработке)${R}\n"
printf "     Xray на 443, собственный TLS-сертификат, decoy-сайт\n\n"
printf "  ${CYAN}3)${R} ${BOLD}Только Xray${R}                  ${DIM}(рекомендуется для начала)${R}\n"
printf "     Xray напрямую на 443, VLESS+Reality — без домена и сертификата\n\n"

read -rp "$(printf "  ${YELLOW}?${R}  Вариант [3]: ")" _variant
_variant="${_variant:-3}"

case "$_variant" in
    1|2)
        warn "Вариант ${_variant} пока в разработке."
        info "Используйте вариант 3 или следите за обновлениями."
        exit 0
        ;;
    3) ;;
    *)
        err "Неверный выбор: ${_variant}"
        exit 1
        ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
#  ВАРИАНТ 3 — Только Xray (VLESS + Reality)
# ══════════════════════════════════════════════════════════════════════════════

printf "\n"
info "Вариант 3: Только Xray"
printf "\n"

# Шаг 1: лог + определение ОС
log_init
detect_os

# Шаг 2: зависимости
box_top " 📦  Зависимости" "$CYAN"
box_blank
install_deps

# Шаг 3: установка xray-core
install_xray_core

# Шаг 4: базовый конфиг (stats API + routing)
info "Инициализируем базовый конфиг..."
_init_config

# Шаг 5: параметры Reality
SERVER_PORT=443
CLIENT_UUID="$(generate_uuid)"
CLIENT_EMAIL="user-1"

ask_reality_domain

info "Генерируем ключевую пару X25519..."
generate_reality_keypair

box_blank
printf "  ${DIM}UUID:           ${CYAN}%s${R}\n" "$CLIENT_UUID"
printf "  ${DIM}Публичный ключ: ${CYAN}%s${R}\n" "$REALITY_PUB_KEY"
printf "  ${DIM}Short ID:       ${CYAN}%s${R}\n" "$REALITY_SHORT_ID"
box_blank

# Шаг 6: добавляем Reality inbound в конфиг
add_reality_inbound "vless-reality"

# Шаг 7: проверка конфига
validate_xray_config

# Шаг 8: capability (порт < 1024)
set_cap_net_bind "$SERVER_PORT"

# Шаг 9: systemd сервис
create_service
enable_and_start_service

# Шаг 10: фаервол
ask_firewall

# Шаг 11: установка xray-manager
box_top " 🛠  xray-manager" "$CYAN"
box_blank
install_self "$REPO_DIR"
box_blank

# ── Итоговая сводка ───────────────────────────────────────────────────────────
_print_install_summary() {
    local _ip; _ip="$(server_ip)"

    cls
    box_top " ✅  Установка завершена!" "$GREEN"
    box_blank
    printf "  ${BOLD}%-18s${R} ${CYAN}%s${R}\n" "Сервер:"        "${_ip}:${SERVER_PORT}"
    printf "  ${BOLD}%-18s${R} %s\n"             "Протокол:"      "VLESS + Reality (XTLS Vision)"
    printf "  ${BOLD}%-18s${R} %s\n"             "Домен-маска:"   "$REALITY_DOMAIN"
    printf "  ${BOLD}%-18s${R} ${DIM}%s${R}\n"  "UUID клиента:"  "$CLIENT_UUID"
    box_blank

    # Генерируем vless:// URI
    local _spx; _spx="/$(printf '%s' "$CLIENT_EMAIL" | sha256sum | head -c8)"
    local _spx_enc; _spx_enc="$(python3 -c \
        "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" \
        "$_spx" 2>/dev/null || printf '%s' "$_spx")"

    local _uri
    _uri="vless://${CLIENT_UUID}@${_ip}:${SERVER_PORT}"
    _uri+="?encryption=none&flow=xtls-rprx-vision&security=reality"
    _uri+="&sni=${REALITY_DOMAIN}&fp=chrome"
    _uri+="&pbk=${REALITY_PUB_KEY}&sid=${REALITY_SHORT_ID}"
    _uri+="&type=raw&spx=${_spx_enc}"
    _uri+="#${CLIENT_EMAIL}"

    printf "  ${BOLD}Ссылка для клиента:${R}\n\n"
    printf "  ${CYAN}%s${R}\n\n" "$_uri"

    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$_uri" 2>/dev/null && printf "\n" || true
    fi

    printf "  ${DIM}%-18s %s${R}\n"              "Лог установки:"  "$LOG_FILE"
    printf "  ${DIM}%-18s %s${R}\n"              "Конфиг xray:"    "$XRAY_CONF"
    printf "  ${DIM}%-18s sudo xray-manager${R}\n" "Управление:"
    box_blank
}

_print_install_summary

# ── Автозапуск xray-manager ───────────────────────────────────────────────────
info "Запускаем xray-manager..."
sleep 1
exec "$MANAGER_BIN"
