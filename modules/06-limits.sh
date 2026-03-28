#  ЛИМИТЫ ПОЛЬЗОВАТЕЛЕЙ
# ──────────────────────────────────────────────────────────────────────────────

_init_limits_file() {
    [[ -f "$LIMITS_FILE" ]] || echo '{}' > "$LIMITS_FILE"
}

limit_set() {
    local tag="$1" email="$2" field="$3" value="$4"
    _init_limits_file
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" --arg f "$field" --arg v "$value" \
        '.[$t][$e][$f] = $v' "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
}

limit_get() {
    local tag="$1" email="$2" field="$3"
    jq -r --arg t "$tag" --arg e "$email" --arg f "$field" \
        '.[$t][$e][$f] // ""' "$LIMITS_FILE" 2>/dev/null
}

limit_del_user() {
    local tag="$1" email="$2"
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" 'del(.[$t][$e])' "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
}

# Получить трафик пользователя через Xray Stats API
get_user_traffic() {
    local email="$1" dir="${2:-uplink}"  # uplink | downlink
    local stat_name="user>>>${email}>>>traffic>>>${dir}"
    "$XRAY_BIN" api statsquery \
        --server="127.0.0.1:${STATS_PORT}" \
        -pattern "$stat_name" 2>/dev/null \
        | jq -r '.[0].value // "0"' 2>/dev/null || echo "0"
}

fmt_bytes() {
    local b="$1"
    if [[ "$b" -ge 1073741824 ]]; then printf "%.2f GB" "$(echo "scale=2; $b/1073741824" | bc)"
    elif [[ "$b" -ge 1048576 ]]; then printf "%.2f MB" "$(echo "scale=2; $b/1048576" | bc)"
    elif [[ "$b" -ge 1024 ]]; then printf "%.2f KB" "$(echo "scale=2; $b/1024" | bc)"
    else echo "${b} B"; fi
}

# Проверить и деактивировать истёкших пользователей
check_limits() {
    _init_limits_file
    local now; now=$(date +%s)
    local changed=0

    # Один батч-запрос вместо N×2 отдельных вызовов xray api statsquery
    local all_stats=""
    if xray_active; then
        all_stats=$("$XRAY_BIN" api statsquery \
            --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || true)
    fi

    # Получить трафик пользователя из заранее загруженного батча
    _traffic_from_batch() {
        local email="$1" dir="$2"
        echo "$all_stats" \
            | jq -r --arg n "user>>>${email}>>>traffic>>>${dir}" \
                '[.[] | select(.name == $n)] | .[0].value // "0"' \
              2>/dev/null || echo "0"
    }

    while IFS='|' read -r tag _ proto _ _; do
        local emails=()
        while IFS= read -r em; do emails+=("$em"); done < <(ib_emails "$tag")

        for email in "${emails[@]}"; do
            # Проверка даты
            local exp; exp=$(limit_get "$tag" "$email" "expire_ts")
            if [[ -n "$exp" && "$exp" != "null" && "$now" -gt "$exp" ]]; then
                _remove_user_from_tag "$tag" "$email"
                xray_api_del_user "$tag" "$email" 2>/dev/null || true
                warn "Пользователь $email@$tag: срок истёк — деактивирован"
                changed=1; continue
            fi
            # Проверка трафика
            local limit_bytes; limit_bytes=$(limit_get "$tag" "$email" "traffic_limit_bytes")
            if [[ -n "$limit_bytes" && "$limit_bytes" != "null" && "$limit_bytes" -gt 0 ]]; then
                local up; up=$(_traffic_from_batch "$email" "uplink")
                local dn; dn=$(_traffic_from_batch "$email" "downlink")
                local total=$(( up + dn ))
                if [[ "$total" -ge "$limit_bytes" ]]; then
                    _remove_user_from_tag "$tag" "$email"
                    xray_api_del_user "$tag" "$email" 2>/dev/null || true
                    warn "Пользователь $email@$tag: трафик исчерпан — деактивирован"
                    changed=1
                fi
            fi
        done
    done < <(ib_list)

    # changed-флаг уже не нужен для restart — API применил изменения горячо
    # Но если API не сработал (xray не активен), делаем restart
    [[ $changed -eq 1 ]] && ! xray_active && xray_restart || true
}

_remove_user_from_tag() {
    local tag="$1" email="$2"
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --arg e "$email" \
        '(.inbounds[]|select(.tag==$t)|.settings.clients) |= (. // [] | map(select(.email!=$e))) | (.inbounds[]|select(.tag==$t)|.settings.users) |= (. // [] | map(select(.email!=$e)))' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
}

# Установить systemd timer для проверки лимитов
install_limits_timer() {
    cat > /etc/systemd/system/xray-limits.service << EOF
[Unit]
Description=Xray Manager: проверка лимитов пользователей

[Service]
Type=oneshot
ExecStart=$MANAGER_BIN --check-limits
EOF
    cat > /etc/systemd/system/xray-limits.timer << 'EOF'
[Unit]
Description=Xray Manager: проверка лимитов (каждые 5 минут)

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now xray-limits.timer 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
#  ГЕНЕРАЦИЯ ССЫЛОК
# ──────────────────────────────────────────────────────────────────────────────

urlencode() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"; }

