#  УСТАНОВКА ЯДРА
# ──────────────────────────────────────────────────────────────────────────────

install_xray_core() {
    cls; box_top " 🔧  Установка / Обновление ядра Xray" "$GREEN"
    box_blank
    box_row "  Текущая версия: ${CYAN}$(xray_ver)${R}"
    box_blank; install_deps
    spin_start "Получение актуальной версии"
    local latest; latest=$(curl -sf "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        | jq -r '.tag_name' 2>/dev/null || echo "")
    spin_stop "ok"
    [[ -z "$latest" ]] && { err "Не удалось получить версию с GitHub"; pause; return 1; }
    box_row "  Последняя версия: ${GREEN}${latest}${R}"
    local cur; cur=$(xray_ver)
    if [[ "$cur" == "${latest#v}" ]] && xray_ok; then
        box_blank
        box_row "  ${GREEN}Уже установлена актуальная версия!${R}"
        box_blank; box_mid
        mi "1" "🔄" "Переустановить принудительно"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        [[ "$ch" != "1" ]] && return 0
    fi
    box_blank; box_end
    spin_start "Установка Xray ${latest}"
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install --version "$latest" -f &>/tmp/xray_install.log
    local ec=$?
    spin_stop "$( [[ $ec -eq 0 ]] && echo ok || echo err )"
    if [[ $ec -ne 0 ]]; then err "Установка завершилась с ошибкой"; tail -10 /tmp/xray_install.log; pause; return 1; fi
    mkdir -p "$XRAY_CONF_DIR"
    _init_config
    enable_bbr
    _init_limits_file
    _enable_stats_api
    install_self
    cls; box_top " ✅  Установка завершена" "$GREEN"
    box_blank
    box_row "  ✓ Xray-core ${GREEN}${latest}${R} установлен"
    box_row "  ✓ BBR активирован"
    box_row "  ✓ Stats API включён"
    box_row "  ✓ Команда ${CYAN}xray-manager${R} доступна глобально"
    box_blank
    box_row "  ${YELLOW}Следующий шаг: добавьте протокол в разделе «Протоколы»${R}"
    box_blank; box_end; pause
}

install_self() {
    local me; me=$(realpath "$0" 2>/dev/null || echo "$0")
    [[ "$me" != "$MANAGER_BIN" ]] && { cp "$me" "$MANAGER_BIN"; chmod +x "$MANAGER_BIN"; }
}

_init_config() {
    [[ -f "$XRAY_CONF" ]] && return
    cat > "$XRAY_CONF" << 'JSON'
{
  "log": {"loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"},
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService", "HandlerService"]
  },
  "policy": {
    "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}},
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true}
  },
  "inbounds": [],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
      {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"}
    ]
  }
}
JSON
    mkdir -p "$XRAY_LOG_DIR"
    touch "$XRAY_LOG_DIR/access.log" "$XRAY_LOG_DIR/error.log"
}

_enable_stats_api() {
    # Добавить API inbound если нет
    local has_api; has_api=$(jq -r '.inbounds[] | select(.tag == "api") | .tag' "$XRAY_CONF" 2>/dev/null || echo "")
    if [[ -z "$has_api" ]]; then
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --argjson port "$STATS_PORT" \
            '.inbounds += [{"tag":"api","listen":"127.0.0.1","port":$port,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi
    # Убедиться что HandlerService включён (нужен для xray api adu/rmu)
    local has_handler; has_handler=$(jq -r '(.api.services // []) | map(select(. == "HandlerService")) | length' "$XRAY_CONF" 2>/dev/null || echo "0")
    if [[ "$has_handler" == "0" ]]; then
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq '.api.services |= (. // [] | if map(select(. == "HandlerService")) | length == 0 then . + ["HandlerService"] else . end)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi
}

