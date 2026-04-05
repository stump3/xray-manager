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
#  ТОЧКА ВХОДА
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--check-limits" ]]; then
    _init_limits_file
    check_limits
    exit 0
fi

need_root
main_menu
