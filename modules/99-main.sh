main_menu() {
    # IP кешируем один раз — curl на каждый рендер даёт задержку
    local _cached_ip; _cached_ip=$(server_ip)

    while true; do
        cls
        local w; w=$(tw); local i=$((w-2))

        # ── Шапка: ASCII-арт ──────────────────────────────────────────────────
        # Правый │ рассчитывается так: │(1) + "  "(2) + content(i-2) + │(1) = w
        # Т.е. %-*s должен получать (i-2), чтобы "  " + content = i символов внутри рамки
        printf "${DIM}╭%s╮${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        printf "${DIM}│${R}  ${CYAN}${BOLD}%-*s${R}${DIM}│${R}\n" $((i-2)) "██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-2)) "╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-2)) " ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-2)) " ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-2)) "██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-2)) "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
        printf "${DIM}│${R}  ${DIM}%-*s${R}${DIM}│${R}\n" $((i-2)) "Manager v${MANAGER_VERSION}  •  VLESS • VMess • Trojan • SS2022 • MTProto • Hysteria2"
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"

        # ── Статус Xray ───────────────────────────────────────────────────────
        # Используем box_row — он корректно считает ширину через ${#raw} (символы, не байты)
        local xver; xver=$(xray_ver)
        local sip="$_cached_ip"
        local st_ic st_tx
        if ! xray_ok; then st_ic="${RED}✗${R}"; st_tx="${RED}не установлен${R}"
        elif xray_active; then st_ic="${GREEN}●${R}"; st_tx="${GREEN}работает${R}"
        else st_ic="${YELLOW}○${R}"; st_tx="${YELLOW}остановлен${R}"; fi
        box_row "  Xray: ${st_ic} ${CYAN}${xver}${R}  ${st_tx}  IP: ${YELLOW}${sip}${R}"

        # ── Статус подписки ───────────────────────────────────────────────────
        if _sub_is_running 2>/dev/null; then
            local _sp; _sp=$(_sub_get_port 2>/dev/null || echo "?")
            box_row "  📡 Подписка: ${GREEN}●${R} ${DIM}:${_sp}${R}"
        fi

        # ── Протоколы Xray ────────────────────────────────────────────────────
        local pc=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            box_row "  • ${CYAN}${tag}${R}  ${DIM}порт ${port}${R}  ${YELLOW}${uc} польз.${R}"
            ((pc++)) || true
        done < <(ib_list)
        [[ $pc -eq 0 ]] && box_row "  ${DIM}Xray-протоколы не настроены${R}"

        # ── Статус MTProto / Hysteria2 ────────────────────────────────────────
        local mt_st=""; local hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            local mt_ver; mt_ver=$(get_telemt_version 2>/dev/null || true)
            mt_st=" ${GREEN}●${R} ${GRAY}${mt_ver}${R}"
        fi
        hy_is_running 2>/dev/null && {
            local hy_ver; hy_ver=$(get_hysteria_version 2>/dev/null || true)
            hy_st=" ${GREEN}●${R} ${GRAY}${hy_ver}${R}"
        }

        # ── Меню ──────────────────────────────────────────────────────────────
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "1" "🔌" "Протоколы и пользователи" "(добавить / удалить / QR / лимиты)"
        mi "2" "⚙️ " "Xray"                     "(управление / маршрутизация / обновление)"
        mi "3" "🌐" "Транспорты"                "$( [[ -n "$mt_st$hy_st" ]] && echo "(MTProto · Hysteria2)" || echo "(MTProto / Hysteria2)" )"
        mi "4" "🛠" "Сервер"                    "(BBR / бэкап / удалить)"
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "0" "🚪" "Выход"
        printf "${DIM}╰%s╯${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) menu_protocols ;;
            2) menu_manage ;;
            3) menu_transports ;;
            4) menu_system ;;
            0) cls; echo -e "${CYAN}До свидания!${R}"; exit 0 ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
#  ТРАНСПОРТЫ (MTProto + Hysteria2)
# ──────────────────────────────────────────────────────────────────────────────

menu_transports() {
    while true; do
        cls; box_top " 🌐  Транспорты" "$CYAN"; box_blank

        # Статус каждого транспорта в шапке
        local mt_st=""; local hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            mt_st=" ${GREEN}●${R} ${DIM}$(get_telemt_version 2>/dev/null)${R}"
        else
            mt_st=" ${DIM}○ не запущен${R}"
        fi
        hy_is_running 2>/dev/null \
            && hy_st=" ${GREEN}●${R} ${DIM}$(get_hysteria_version 2>/dev/null)${R}" \
            || hy_st=" ${DIM}○ не запущен${R}"

        box_row "  📡 MTProto:   ${mt_st}"
        box_row "  🚀 Hysteria2: ${hy_st}"
        box_blank; box_mid
        mi "1" "📡" "${MAGENTA}MTProto (Telegram)${R}"
        mi "2" "🚀" "${ORANGE}Hysteria2 (QUIC/UDP)${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) telemt_section ;;
            2) hysteria_section ;;
            0) return ;;
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
