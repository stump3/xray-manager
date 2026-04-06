main_menu() {
    local _cached_ip; _cached_ip=$(server_ip)

    while true; do
        cls
        local w; w=$(tw)

        # ── Шапка ─────────────────────────────────────────────────────────────
        printf "\n"
        printf "  ${CYAN}${BOLD}xray-manager${R}  ${DIM}v${MANAGER_VERSION}${R}\n"
        printf "  ${DIM}VLESS · VMess · Trojan · SS2022 · MTProto · Hysteria2${R}\n"
        _sep

        # ── Статус ────────────────────────────────────────────────────────────
        local xver; xver=$(xray_ver)
        local sip="$_cached_ip"
        local st_ic st_tx
        if ! xray_ok; then
            st_ic="${RED}✗${R}"; st_tx="${RED}не установлен${R}"
        elif xray_active; then
            st_ic="${GREEN}●${R}"; st_tx="${GREEN}работает${R}"
        else
            st_ic="${YELLOW}○${R}"; st_tx="${YELLOW}остановлен${R}"
        fi

        local ngx_ic
        systemctl is-active --quiet nginx 2>/dev/null \
            && ngx_ic="${GREEN}●${R}" || ngx_ic="${YELLOW}○${R}"

        local sub_ic
        _sub_is_running 2>/dev/null \
            && sub_ic="${GREEN}●${R}" || sub_ic="${DIM}○${R}"

        render_status_bar \
            "${st_ic} ${CYAN}${xver}${R} ${st_tx}" \
            "$ngx_ic" "$sub_ic" "$sip"

        # ── Протоколы (inline) ────────────────────────────────────────────────
        local pc=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            printf "  ${DIM}·${R} ${CYAN}%s${R}  ${DIM}:%s${R}  %s\n" \
                "$tag" "$port" "${uc} польз."
            (( pc++ )) || true
        done < <(ib_list)
        [[ $pc -eq 0 ]] && printf "  ${DIM}нет протоколов${R}\n"

        # ── MTProto / Hysteria2 статус ────────────────────────────────────────
        local mt_st="" hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            local mt_ver; mt_ver=$(get_telemt_version 2>/dev/null || true)
            mt_st="${GREEN}●${R} ${DIM}${mt_ver}${R}"
        fi
        hy_is_running 2>/dev/null && {
            local hy_ver; hy_ver=$(get_hysteria_version 2>/dev/null || true)
            hy_st="${GREEN}●${R} ${DIM}${hy_ver}${R}"
        }

        # ── Меню ──────────────────────────────────────────────────────────────
        printf "\n"
        _sep
        mi "1" "🔌" "Протоколы и пользователи" \
            "${DIM}добавить · удалить · QR · лимиты${R}"
        mi "2" "⚙️ " "Xray" \
            "${DIM}управление · маршрутизация · обновление${R}"

        local tr_badge
        if [[ -n "$mt_st" || -n "$hy_st" ]]; then
            tr_badge="${DIM}$(
                [[ -n "$mt_st" ]] && printf "MTProto %b" "$mt_st"
                [[ -n "$mt_st" && -n "$hy_st" ]] && printf "  "
                [[ -n "$hy_st" ]] && printf "Hysteria2 %b" "$hy_st"
            )${R}"
        else
            tr_badge="${DIM}MTProto · Hysteria2${R}"
        fi
        mi "3" "🌐" "Транспорты" "$tr_badge"
        mi "4" "🛠" "Сервер" "${DIM}BBR · бэкап · удалить${R}"
        _sep
        mi "0" "" "Выход"
        printf "\n"

        read -rp "$(printf "  ${CYAN}›${R} ")" ch
        case "$ch" in
            1) menu_protocols ;;
            2) menu_manage ;;
            3) menu_transports ;;
            4) menu_system ;;
            0) cls; exit 0 ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
#  ТРАНСПОРТЫ
# ──────────────────────────────────────────────────────────────────────────────

menu_transports() {
    while true; do
        cls
        local mt_st="" hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            mt_st=" ${GREEN}●${R} ${DIM}$(get_telemt_version 2>/dev/null)${R}"
        else
            mt_st=" ${DIM}○${R}"
        fi
        hy_is_running 2>/dev/null \
            && hy_st=" ${GREEN}●${R} ${DIM}$(get_hysteria_version 2>/dev/null)${R}" \
            || hy_st=" ${DIM}○${R}"

        printf "\n"
        _sep
        printf "  ${CYAN}${BOLD}Транспорты${R}\n"
        _sep
        printf "  MTProto  %b\n" "$mt_st"
        printf "  Hysteria2%b\n" "$hy_st"
        printf "\n"
        _sep
        mi "1" "📡" "${MAGENTA}MTProto (Telegram)${R}"
        mi "2" "🚀" "${ORANGE}Hysteria2 (QUIC/UDP)${R}"
        _sep
        mi "0" "" "Назад"
        printf "\n"

        read -rp "$(printf "  ${CYAN}›${R} ")" ch
        case "$ch" in
            1) telemt_section ;;
            2) hysteria_section ;;
            0) return ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
#  STUBS — защита от crash когда модули 05-12, 16 не загружены
#  В собранном монолите эти функции перекрываются реальными из модулей
# ──────────────────────────────────────────────────────────────────────────────

if ! declare -f ib_list &>/dev/null; then
    ib_list() { return 0; }
fi

if ! declare -f ib_users_count &>/dev/null; then
    ib_users_count() { echo "0"; }
fi

if ! declare -f _sub_is_running &>/dev/null; then
    _sub_is_running() { return 1; }
fi

if ! declare -f _init_limits_file &>/dev/null; then
    _init_limits_file() { return 0; }
fi

if ! declare -f check_limits &>/dev/null; then
    check_limits() { return 0; }
fi

_stub_menu() {
    local name="$1"
    cls
    printf "\n  ${RED}✗${R}  Модуль ${CYAN}%s${R} не загружен.\n\n" "$name"
    printf "  ${DIM}Переустановите xray-manager чтобы получить все функции:${R}\n"
    printf "  ${CYAN}  sudo bash scripts/install.sh${R}\n\n"
    pause
}

if ! declare -f menu_protocols &>/dev/null; then
    menu_protocols() { _stub_menu "протоколы и пользователи"; }
fi

if ! declare -f menu_manage &>/dev/null; then
    menu_manage() { _stub_menu "управление Xray"; }
fi

if ! declare -f menu_system &>/dev/null; then
    menu_system() { _stub_menu "система"; }
fi

# ──────────────────────────────────────────────────────────────────────────────
#  PREFLIGHT — проверка перед первым запуском
# ──────────────────────────────────────────────────────────────────────────────

_find_installer() {
    # 1. Рядом с исходным скриптом (dev-режим: ./scripts/install.sh)
    local self_dir
    self_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[-1]}")")" && pwd 2>/dev/null || pwd)"
    [[ -f "${self_dir}/scripts/install.sh" ]] && { echo "${self_dir}/scripts/install.sh"; return; }
    # 2. Текущая директория
    [[ -f "scripts/install.sh" ]] && { echo "scripts/install.sh"; return; }
    # 3. Стандартные пути клона
    for _d in /opt/xray-manager /root/xray-manager /root/xray-manager-v2 /opt/xray-manager-v2; do
        [[ -f "${_d}/scripts/install.sh" ]] && { echo "${_d}/scripts/install.sh"; return; }
    done
    echo ""
}

_preflight_check() {
    xray_ok && return 0   # xray установлен — продолжаем в main_menu

    cls
    printf "\n"
    printf "  ${CYAN}${BOLD}xray-manager${R}  ${DIM}v${MANAGER_VERSION}${R}\n"
    _sep
    printf "\n"
    printf "  ${RED}${BOLD}✗  Xray-core не установлен${R}\n\n"
    printf "  ${DIM}Перед использованием менеджера необходимо выполнить установку.${R}\n\n"

    local installer; installer="$(_find_installer)"

    if [[ -n "$installer" ]]; then
        printf "  ${GREEN}✓${R}  Установщик найден: ${DIM}%s${R}\n\n" "$installer"
        _sep
        mi "1" "🚀" "Запустить установку" "${DIM}займёт 1–2 минуты${R}"
        mi "0" ""   "Выход"
        printf "\n"
        read -rp "$(printf "  ${CYAN}›${R} ")" _ch
        case "${_ch:-}" in
            1) exec bash "$installer" ;;
            *) cls; exit 0 ;;
        esac
    else
        printf "  ${YELLOW}⚠${R}  Установщик не найден.\n\n"
        printf "  ${DIM}Клонируйте репозиторий и запустите установку вручную:${R}\n\n"
        printf "  ${CYAN}  git clone <repo>\n"
        printf "  ${CYAN}  cd xray-manager-v2\n"
        printf "  ${CYAN}  sudo bash scripts/install.sh${R}\n\n"
        _sep
        mi "0" "" "Выход"
        printf "\n"
        read -rp "$(printf "  ${CYAN}›${R} ")" _
        cls; exit 0
    fi
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
_preflight_check
main_menu
