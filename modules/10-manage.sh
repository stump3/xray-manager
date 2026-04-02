#  УПРАВЛЕНИЕ СЕРВИСОМ
# ──────────────────────────────────────────────────────────────────────────────

menu_manage() {
    while true; do
        cls; box_top " ⚙️  Xray" "$BLUE"; box_blank
        local st_icon st_text
        if xray_active; then st_icon="${GREEN}●${R}"; st_text="${GREEN}Работает${R}"
        else st_icon="${RED}○${R}"; st_text="${RED}Остановлен${R}"; fi
        box_row "  Ядро:   ${CYAN}$(xray_ver)${R}   Статус: ${st_icon} ${st_text}"
        box_row "  IP:     ${YELLOW}$(server_ip)${R}"
        local _rp; _rp=$(routing_active_profile 2>/dev/null || echo "custom")
        local _rn; _rn=$(routing_rules_count 2>/dev/null || echo 0)
        box_row "  Маршрутизация: ${DIM}профиль: ${_rp} · ${_rn} правил${R}"
        box_blank; box_mid
        mi "1" "📊" "Статус + логи"
        mi "2" "🔄" "Перезапустить"
        mi "3" "⏹" "$(xray_active && echo "Остановить" || echo "Запустить")"
        mi "4" "📈" "Статистика traffic"
        mi "5" "🌍" "Обновить геоданные"
        mi "6" "🔧" "Установка / Обновление ядра"
        mi "7" "📈" "Metrics endpoint"
        mi "R" "🗺" "${CYAN}Маршрутизация${R}" "${DIM}профиль: ${_rp} · ${_rn} правил${R}"
        box_row "  ${MAGENTA}${BOLD}Расширенные${R}"
        mi "8" "🧩" "${CYAN}Fragment — фрагментация TLS${R}"
        mi "9" "🔊" "${CYAN}Noises — UDP шум${R}"
        mi "10" "🛡️ " "${YELLOW}Fallbacks — защита от зондирования${R}"
        mi "11" "⚖️ " "${MAGENTA}Балансировщик + Observatory${R}"
        mi "12" "🚀" "${GREEN}Hysteria2 Outbound — relay/цепочка${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) cls; systemctl status xray --no-pager -l; echo ""; journalctl -u xray -n 30 --no-pager; pause ;;
            2) systemctl restart xray; ok "Перезапущен"; sleep 1 ;;
            3) if xray_active; then systemctl stop xray; ok "Остановлен"
               else systemctl start xray; ok "Запущен"; fi; sleep 1 ;;
            4) show_global_stats ;;
            5) update_geodata ;;
            6) install_xray_core ;;
            7) menu_metrics ;;
            R|r) menu_routing ;;
            8) menu_freedom_fragment ;;
            9) menu_freedom_noises ;;
            10) menu_fallbacks ;;
            11) menu_balancer ;;
            12) menu_hysteria_outbound ;;
            0) return ;;
        esac
    done
}

show_global_stats() {
    cls; box_top " 📈  Глобальная статистика" "$BLUE"; box_blank
    xray_active || { box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return; }
    box_row "  ${DIM}Данные из Stats API (127.0.0.1:${STATS_PORT})${R}"; box_blank
    local stats_out; stats_out=$("$XRAY_BIN" api statsquery \
        --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || echo "[]")
    if [[ "$stats_out" == "[]" || -z "$stats_out" ]]; then
        box_row "  ${DIM}Нет данных (Stats API недоступен или нет трафика)${R}"
    else
        while IFS= read -r line; do
            local name val
            name=$(echo "$line" | jq -r '.name // ""')
            val=$(echo "$line" | jq -r '.value // "0"')
            [[ -z "$name" ]] && continue
            local fmt_val; fmt_val=$(fmt_bytes "$val")
            box_row "  ${DIM}${name}${R}  ${YELLOW}${fmt_val}${R}"
        done < <(echo "$stats_out" | jq -c '.[]' 2>/dev/null)
    fi
    box_blank; box_end; pause
}

update_geodata() {
    cls; box_top " 🌍  Обновление геоданных" "$BLUE"; box_blank
    spin_start "Загрузка geoip.dat + geosite.dat"
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install-geodata &>/tmp/xray_geo.log
    local ec=$?
    spin_stop "$([[ $ec -eq 0 ]] && echo ok || echo err)"
    [[ $ec -eq 0 ]] && { ok "Геоданные обновлены"; xray_restart; } || err "Ошибка"
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  СИСТЕМА
# ──────────────────────────────────────────────────────────────────────────────

