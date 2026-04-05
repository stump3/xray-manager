menu_system() {
    while true; do
        cls; box_top " 🛠  Сервер" "$ORANGE"; box_blank; box_mid
        mi "1" "🔧" "BBR + оптимизация сети"
        mi "2" "💾" "Бэкап конфигурации"
        mi "3" "♻️ " "Восстановить конфиг"
        mi "4" "⏰" "Установить таймер проверки лимитов"
        mi "5" "🔍" "Проверить лимиты вручную"
        mi "6" "📋" "Посмотреть текущий config.json"
        mi "7" "🗑" "${RED}Удалить Xray полностью${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) menu_bbr_tune ;;
            2) do_backup ;;
            3) do_restore ;;
            4) install_limits_timer; ok "Таймер установлен (каждые 5 минут)"; pause ;;
            5) cls; check_limits; pause ;;
            6) cls; cat "$XRAY_CONF" | python3 -m json.tool 2>/dev/null || cat "$XRAY_CONF"; pause ;;
            7) do_remove_all ;;
            0) return ;;
        esac
    done
}

do_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local bf="${BACKUP_DIR}/xray-backup-${ts}.tar.gz"
    local files=()
    [[ -f "$XRAY_CONF" ]] && files+=("$XRAY_CONF")
    [[ -f "$LIMITS_FILE" ]] && files+=("$LIMITS_FILE")
    for f in "${XRAY_KEYS_DIR}"/.keys.*; do [[ -f "$f" ]] && files+=("$f"); done
    [[ ${#files[@]} -eq 0 ]] && { warn "Нечего сохранять"; pause; return; }
    tar -czf "$bf" "${files[@]}" 2>/dev/null
    ok "Бэкап: ${CYAN}${bf}${R}"
    # Ротация: хранить последние 7 бэкапов, удалять старые
    local old_count; old_count=$(ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | tail -n +8 | wc -l)
    if [[ "$old_count" -gt 0 ]]; then
        ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
        info "Удалено старых бэкапов: ${old_count}"
    fi
    local total; total=$(ls "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null | wc -l)
    info "Всего бэкапов: ${total} (хранится последних 7)"
    pause
}

do_restore() {
    cls; box_top " ♻️  Восстановление" "$ORANGE"; box_blank
    local baks=(); while IFS= read -r f; do baks+=("$f"); done < <(ls -t "${BACKUP_DIR}"/xray-backup-*.tar.gz 2>/dev/null)
    if [[ ${#baks[@]} -eq 0 ]]; then box_row "  ${DIM}Нет бэкапов${R}"; box_end; pause; return; fi
    local i=1
    for b in "${baks[@]}"; do
        local sz; sz=$(du -sh "$b" 2>/dev/null | cut -f1)
        mi "$i" "💾" "$(basename "$b")" "  ${sz}"
        ((i++)) || true
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#baks[@]} ]]; then
        local bak="${baks[$((ch-1))]}"
        # Защита от path traversal: проверяем что архив содержит только
        # ожидаемые пути. Покрываем оба варианта: tar без ./ и с ./ префиксом
        # (стандартный вывод tar -czf ... -C / ./usr/... содержит ./-префикс).
        local bad_paths; bad_paths=$(tar -tzf "$bak" 2>/dev/null \
            | grep -v -e '^usr/local/etc/xray/' \
                      -e '^\./usr/local/etc/xray/' \
                      -e '^var/log/xray/' \
                      -e '^\./var/log/xray/' \
                      -e '^\.$' \
                      -e '^\./$' \
            || true)
        if [[ -n "$bad_paths" ]]; then
            err "Архив содержит подозрительные пути — восстановление прервано"
            box_row "  ${RED}Неожиданные пути в архиве:${R}"
            echo "$bad_paths" | head -5 | while IFS= read -r p; do box_row "  ${DIM}${p}${R}"; done
            box_end; pause; return
        fi
        confirm "Восстановить? Текущий конфиг будет перезаписан." && {
            tar -xzf "$bak" -C / 2>/dev/null
            xray_restart; ok "Конфиг восстановлен"
        }
    fi
    pause
}

do_remove_all() {
    cls; box_top " 🗑  Полное удаление" "$RED"; box_blank
    box_row "  ${RED}Удаляет: Xray, Hysteria2, telemt, nginx конфиги, ключи, логи${R}"
    box_blank
    printf "  ${RED}Введите ${BOLD}УДАЛИТЬ${R}${RED} для подтверждения:${R}  "
    local _w; read -r _w < /dev/tty
    [[ "$_w" == "УДАЛИТЬ" ]] || { info "Отменено"; return; }

    # Xray — через официальный установщик
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ remove --purge 2>/dev/null || true
    # Остатки которые установщик не чистит
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    rm -f  /etc/systemd/system/xray.service \
           /etc/systemd/system/xray@.service \
           /etc/systemd/system/multi-user.target.wants/xray.service 2>/dev/null || true
    rm -rf /etc/systemd/system/xray.service.d \
           /etc/systemd/system/xray@.service.d 2>/dev/null || true
    rm -f  /usr/local/bin/xray 2>/dev/null || true
    rm -rf /usr/local/share/xray /run/xray 2>/dev/null || true
    rm -f  "$XRAY_CONF" "$LIMITS_FILE" "${XRAY_KEYS_DIR}"/.keys.* 2>/dev/null || true
    rm -rf "$XRAY_LOG_DIR" 2>/dev/null || true

    # Hysteria2
    systemctl stop hysteria-server 2>/dev/null || true
    systemctl disable hysteria-server 2>/dev/null || true
    rm -f /etc/systemd/system/hysteria-server.service \
          /usr/local/bin/hysteria /usr/bin/hysteria 2>/dev/null || true
    rm -rf /etc/hysteria 2>/dev/null || true
    rm -f /root/hysteria-*.txt 2>/dev/null || true

    # telemt (systemd)
    systemctl stop telemt 2>/dev/null || true
    systemctl disable telemt 2>/dev/null || true
    rm -f /etc/systemd/system/telemt.service /usr/local/bin/telemt 2>/dev/null || true
    rm -rf /etc/telemt /opt/telemt 2>/dev/null || true

    # telemt (Docker)
    { docker compose -f "${HOME}/mtproxy/docker-compose.yml" down 2>/dev/null || true; }
    rm -rf "${HOME}/mtproxy" 2>/dev/null || true

    # Nginx конфиги
    rm -f /etc/nginx/sites-enabled/vpn.conf \
          /etc/nginx/sites-available/vpn.conf \
          /etc/nginx/stream.d/stream-443.conf \
          /etc/nginx/conf.d/stream-443.conf 2>/dev/null || true

    # xray-manager
    rm -f "$MANAGER_BIN" 2>/dev/null || true

    # Systemd таймеры лимитов
    systemctl stop xray-limits.timer 2>/dev/null || true
    systemctl disable xray-limits.timer 2>/dev/null || true
    rm -f /etc/systemd/system/xray-limits.* 2>/dev/null || true

    # Файлы состояния
    rm -f /root/.xray-mgr-install /root/.xray-reality-local-port 2>/dev/null || true

    systemctl daemon-reexec 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true

    ok "Всё удалено"; exit 0
}

# ──────────────────────────────────────────────────────────────────────────────
#  ГЛАВНОЕ МЕНЮ
# ──────────────────────────────────────────────────────────────────────────────


