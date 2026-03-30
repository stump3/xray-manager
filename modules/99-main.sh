main_menu() {
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
        local sip; sip=$(server_ip)
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
            ((pc++))
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
        mi "1" "🔧" "Установка / Обновление Xray"
        mi "2" "🌐" "Протоколы Xray"   "(добавить / удалить)"
        mi "3" "👥" "Пользователи Xray" "(добавить / лимиты / QR)"
        mi "4" "⚙️ " "Управление Xray"  "(статус / логи / гео)"
        mi "5" "🛠" "Система"           "(BBR / бэкап / удалить)"

        # Строка роутинга — используем mi() для корректного выравнивания
        local _rp; _rp=$(routing_active_profile 2>/dev/null || echo "custom")
        local _rn; _rn=$(routing_rules_count 2>/dev/null || echo 0)
        mi "R" "🗺" "${CYAN}Маршрутизация${R}" "${DIM}профиль: ${_rp} · ${_rn} правил${R}"

        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "6" "📡" "${MAGENTA}MTProto (Telegram)${R}"   "$mt_st"
        mi "7" "🚀" "${ORANGE}Hysteria2 (QUIC/UDP)${R}"  "$hy_st"
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
