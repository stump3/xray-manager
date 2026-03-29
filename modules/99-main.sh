main_menu() {
    while true; do
        cls
        local w; w=$(tw); local i=$((w-2))
        printf "${DIM}╭%s╮${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        printf "${DIM}│${R}  ${CYAN}${BOLD}%-*s${R}${DIM}│${R}\n" $((i-3)) "██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) " ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) " ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║"
        printf "${DIM}│${R}  ${CYAN}%-*s${R}${DIM}│${R}\n" $((i-3)) "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
        printf "${DIM}│${R}  ${DIM}%-*s${R}${DIM}│${R}\n" $((i-3)) "Manager v${MANAGER_VERSION}  •  VLESS • VMess • Trojan • SS2022 • MTProto • Hysteria2"
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"

        # Статус Xray
        local xver; xver=$(xray_ver)
        local sip; sip=$(server_ip)
        local st_ic st_tx
        if ! xray_ok; then st_ic="${RED}✗${R}"; st_tx="${RED}не установлен${R}"
        elif xray_active; then st_ic="${GREEN}●${R}"; st_tx="${GREEN}работает${R}"
        else st_ic="${YELLOW}○${R}"; st_tx="${YELLOW}остановлен${R}"; fi
        printf "${DIM}│${R}  Xray: %b ${CYAN}%s${R}  %b  IP: ${YELLOW}%s${R}%-*s${DIM}│${R}\n" \
            "$st_ic" "$xver" "$st_tx" "$sip" $((i-52)) ""

        # Статус подписки
        if _sub_is_running 2>/dev/null; then
            local _sp; _sp=$(_sub_get_port 2>/dev/null || echo "?")
            printf "${DIM}│${R}  📡 Подписка: ${GREEN}●${R} ${DIM}:${_sp}${R}%-*s${DIM}│${R}\n" $((i-26)) ""
        fi

        # Протоколы Xray
        local pc=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            printf "${DIM}│${R}  • ${CYAN}%-20s${R} ${DIM}порт %-6s${R} ${YELLOW}%s польз.${R}%-*s${DIM}│${R}\n" \
                "$tag" "$port" "$uc" $((i-44)) ""
            ((pc++))
        done < <(ib_list)
        [[ $pc -eq 0 ]] && printf "${DIM}│${R}  ${DIM}%-*s${R}${DIM}│${R}\n" $((i-3)) "Xray-протоколы не настроены"

        # Статус MTProto
        local mt_st=""; local hy_st=""
        if systemctl is-active --quiet telemt 2>/dev/null || \
           { docker ps --format "{{.Names}}" 2>/dev/null || true; } | grep -q "^telemt$"; then
            local mt_ver; mt_ver=$(get_telemt_version 2>/dev/null || true)
            mt_st=" ${GREEN}●${R} ${GRAY}${mt_ver}${R}"
        fi
        # Статус Hysteria2
        hy_is_running 2>/dev/null && {
            local hy_ver; hy_ver=$(get_hysteria_version 2>/dev/null || true)
            hy_st=" ${GREEN}●${R} ${GRAY}${hy_ver}${R}"
        }

        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        mi "1" "🔧" "Установка / Обновление Xray"
        mi "2" "🌐" "Протоколы Xray"              "(добавить / удалить)"
        mi "3" "👥" "Пользователи Xray"            "(добавить / лимиты / QR)"
        mi "4" "⚙️ " "Управление Xray"             "(статус / логи / гео)"
        mi "5" "🛠" "Система"                      "(BBR / бэкап / удалить)"
        # Строка роутинга с активным профилем
        local _rp; _rp=$(routing_active_profile 2>/dev/null || echo "custom")
        local _rn; _rn=$(routing_rules_count 2>/dev/null || echo 0)
        local _r_text="${CYAN}Маршрутизация${R}  ${DIM}профиль: ${_rp} · ${_rn} правил${R}"
        local _r_pad=$(( i - 4 - $(vwidth "R") - 2 - $(vwidth "🗺") - 1 - $(vwidth "$_r_text") ))
        [[ $_r_pad -lt 0 ]] && _r_pad=0
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${CYAN}Маршрутизация${R}  ${DIM}профиль: %s · %s правил${R}%-*s${DIM}│${R}\n" \
            "R" "🗺" "$_rp" "$_rn" "$_r_pad" ""
        printf "${DIM}├%s┤${R}\n" "$(printf '%*s' "$i" | tr ' ' '─')"
        local _mt_pad=$(( i - 4 - $(vwidth "6") - 2 - $(vwidth "📡") - 1 - $(vwidth "MTProto (Telegram)") - $(vwidth "$mt_st") ))
        local _hy_pad=$(( i - 4 - $(vwidth "7") - 2 - $(vwidth "🚀") - 1 - $(vwidth "Hysteria2 (QUIC/UDP)") - $(vwidth "$hy_st") ))
        [[ $_mt_pad -lt 0 ]] && _mt_pad=0
        [[ $_hy_pad -lt 0 ]] && _hy_pad=0
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${MAGENTA}MTProto (Telegram)${R}%-*s${DIM}%b │${R}\n" \
            "6" "📡" "$_mt_pad" "" "$mt_st"
        printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${ORANGE}Hysteria2 (QUIC/UDP)${R}%-*s${DIM}%b │${R}\n" \
            "7" "🚀" "$_hy_pad" "" "$hy_st"
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
