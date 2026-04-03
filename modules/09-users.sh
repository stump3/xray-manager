#  МЕНЮ ПРОТОКОЛОВ
# ──────────────────────────────────────────────────────────────────────────────

# ── Hysteria2 (нативный Xray) ─────────────────────────────────────────────

proto_hysteria_xray() {
    cls; box_top " 🚀  Hysteria2 (нативный Xray)" "$GREEN"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }

    box_row "  ${CYAN}${BOLD}Реализация Hysteria2 внутри Xray — без отдельного бинарника${R}"
    box_row "  ${DIM}Требует домен + TLS-сертификат. Поддерживает Stats API и лимиты Xray.${R}"
    box_blank
    box_row "  ${YELLOW}Отличия от отдельного Hysteria2 (меню 7):${R}"
    box_row "  ${DIM}+ Единый процесс и конфиг / + Статистика через xray api statsquery${R}"
    box_row "  ${DIM}+ Лимиты по трафику/дате через .limits.json${R}"
    box_row "  ${DIM}− Нет встроенного ACME / − Port Hopping требует iptables вручную${R}"
    box_blank

    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен (для SNI и сертификата)" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"

    local up_mbps dn_mbps
    box_blank
    box_row "  ${YELLOW}Алгоритм скорости:${R}"
    mi "1" "🔵" "BBR (0) — стандартный, рекомендуется"
    mi "2" "🔴" "Brutal — задать скорость вручную"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " spd_ch
    if [[ "$spd_ch" == "2" ]]; then
        ask "Download Mbps (сервер→клиент)" dn_mbps "100"
        ask "Upload Mbps   (клиент→сервер)" up_mbps "50"
        ok "Brutal: ↓${dn_mbps} / ↑${up_mbps} Mbps"
    else
        up_mbps="0"; dn_mbps="0"
        ok "BBR (авто)"
    fi

    box_blank
    box_row "  ${YELLOW}Port Hopping (UDP) — необязательно:${R}"
    box_row "  ${DIM}Диапазон портов напр. 20000-29999 (пусто = отключено)${R}"
    local udphop_range
    ask "Port Hopping диапазон" udphop_range ""

    ask "Тег" tag "hysteria-xray"
    [[ -z "$dom" ]]   && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag"  && { err "Тег '$tag' уже занят"; pause; return; }

    local pass; pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
    info "Сгенерирован пароль: $pass"

    kset "$tag" domain   "$dom"
    kset "$tag" port     "$port"
    kset "$tag" type     "hysteria-xray"
    kset "$tag" password "$pass"
    [[ -n "$udphop_range" ]] && kset "$tag" udphop "$udphop_range"

    local ib; ib=$(jq -n \
        --arg  tag   "$tag" \
        --argjson port "$port" \
        --arg  pass  "$pass" \
        --arg  cert  "$cert_p" \
        --arg  key   "$key_p" \
        --arg  sni   "$dom" \
        --arg  up    "$up_mbps" \
        --arg  down  "$dn_mbps" \
        --arg  hop   "$udphop_range" \
        '{
            "tag": $tag,
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "hysteria",
            "settings": {
                "users": [
                    {"email": "main", "password": $pass}
                ]
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": $sni,
                    "alpn": ["h3"],
                    "certificates": [
                        {"certificateFile": $cert, "keyFile": $key}
                    ]
                },
                "hysteriaSettings": ({
                    "version": 2,
                    "up": $up,
                    "down": $down
                } + (if $hop != "" then {"udphop": {"port": $hop, "interval": 30}} else {} end))
            },
            "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
        }')

    ib_add "$ib"; xray_restart

    # UFW для Port Hopping
    if [[ -n "$udphop_range" ]] && command -v ufw &>/dev/null; then
        local hop_start hop_end
        hop_start="${udphop_range%-*}"; hop_end="${udphop_range#*-}"
        if [[ "$hop_start" != "$hop_end" ]]; then
            ufw allow "${hop_start}:${hop_end}/udp" >/dev/null 2>&1
            ok "UFW: открыт диапазон ${udphop_range}/udp"
        fi
    fi
    command -v ufw &>/dev/null && ufw allow "${port}/udp" >/dev/null 2>&1

    # Ссылка: стандартный hy2:// URI — совместим с любым Hysteria2-клиентом
    local server_ip; server_ip=$(server_ip)
    local link="hy2://${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0#${tag}"
    local link_ip="hy2://${pass}@${server_ip}:${port}?sni=${dom}&alpn=h3&insecure=0#${tag}"

    cls; box_top " ✅  Hysteria2 (нативный Xray) добавлен!" "$GREEN"; box_blank
    box_row "  Тег:    ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен:  ${WHITE}${dom}${R}"
    box_row "  Пароль: ${DIM}${pass}${R}"
    box_row "  Скорость: $(  [[ "$up_mbps" == "0" ]] && echo "BBR" || echo "Brutal ↓${dn_mbps}/↑${up_mbps} Mbps" )"
    [[ -n "$udphop_range" ]] && box_row "  Port Hop: ${CYAN}${udphop_range}${R}"
    box_blank
    box_row "  ${CYAN}URI (по домену — рекомендуется):${R}"
    box_row "  ${DIM}${link}${R}"
    box_blank
    box_row "  ${CYAN}URI (по IP — если домен не настроен):${R}"
    box_row "  ${DIM}${link_ip}&allowInsecure=1${R}"
    box_blank
    box_row "  ${YELLOW}QR-код (домен):${R}"
    box_end
    echo ""
    echo "$link" | qrencode -t ansiutf8 2>/dev/null || warn "qrencode не установлен"
    pause
}

menu_protocols() {
    while true; do
        cls; box_top " 🌐  Протоколы" "$MAGENTA"
        box_blank
        # Текущие протоколы
        box_row "  ${YELLOW}Активные протоколы:${R}"
        local cnt=0
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            local label_col="$CYAN"
            box_row "    • ${label_col}${tag}${R}  ${DIM}порт ${port} · ${proto}+${net}+${sec} · ${uc} польз.${R}"
            (( cnt++ )) || true
        done < <(ib_list)
        [[ $cnt -eq 0 ]] && box_row "    ${DIM}(нет протоколов)${R}"
        box_blank; box_mid
        box_row "  ${CYAN}${BOLD}VLESS + REALITY${R}"
        mi "1"  "🌐" "${CYAN}VLESS + TCP + REALITY${R}"          "(рекомендуется)"
        mi "2"  "⚡" "${MAGENTA}VLESS + XHTTP + REALITY${R}"     "(CDN/прямое)"
        mi "12" "🔄" "${MAGENTA}VLESS + gRPC + REALITY${R}"      "(без домена)"
        box_row "  ${BLUE}${BOLD}VLESS + TLS${R}"
        mi "3"  "☁️ " "${BLUE}VLESS + WebSocket + TLS${R}"      "(CDN)"
        mi "4"  "🔄" "${BLUE}VLESS + gRPC + TLS${R}"             "(CDN/Nginx)"
        mi "5"  "🔀" "${BLUE}VLESS + HTTPUpgrade + TLS${R}"      ""
        mi "13" "🌊" "${BLUE}VLESS + SplitHTTP + TLS/H3${R}"     "(QUIC/CDN)"
        box_row "  ${ORANGE}${BOLD}VMess${R}"
        mi "6"  "📦" "${ORANGE}VMess + WebSocket + TLS${R}"      ""
        mi "7"  "📦" "${ORANGE}VMess + TCP + TLS${R}"             ""
        box_row "  ${GREEN}${BOLD}Другие${R}"
        mi "8"  "🔐" "${GREEN}Trojan + TCP + TLS${R}"              ""
        mi "9"  "🌑" "${GRAY}Shadowsocks 2022${R}"                 ""
        box_row "  ${CYAN}${BOLD}Hysteria2${R}"
        mi "10" "🚀" "${CYAN}Hysteria2 (нативный Xray)${R}"       "(TLS-сертификат + Stats API)"
        mi "11" "🚀" "${GREEN}Hysteria2 (отдельный бинарник)${R}" "(ACME + Masquerade + Port Hop)"
        box_mid
        mi "d" "🗑" "${RED}Удалить протокол${R}"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1)  proto_vless_tcp_reality ;;
            2)  proto_vless_xhttp_reality ;;
            3)  proto_vless_ws_tls ;;
            4)  proto_vless_grpc_tls ;;
            5)  proto_vless_httpupgrade_tls ;;
            6)  proto_vmess_ws_tls ;;
            7)  proto_vmess_tcp_tls ;;
            8)  proto_trojan_tls ;;
            9)  proto_shadowsocks ;;
            10) proto_hysteria_xray ;;
            11) hysteria_section ;;
            12) proto_vless_grpc_reality ;;
            13) proto_vless_splithttp_tls ;;
            d|D) menu_del_protocol ;;
            0) return ;;
        esac
    done
}

menu_del_protocol() {
    cls; box_top " 🗑  Удалить протокол" "$RED"; box_blank
    local tags=()
    while IFS='|' read -r t p pr n s; do tags+=("$t|$p|$pr|$n|$s"); done < <(ib_list)
    if [[ ${#tags[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет протоколов${R}"; box_end; pause; return
    fi
    local i=1
    for e in "${tags[@]}"; do
        IFS='|' read -r t p pr n s <<< "$e"
        mi "$i" "🔌" "${CYAN}${t}${R}" "  порт ${p} · ${pr}+${n}"
        (( i++ )) || true
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#tags[@]} ]]; then
        IFS='|' read -r t _ _ _ _ <<< "${tags[$((ch-1))]}"
        confirm "Удалить протокол '${t}'?" && {
            ib_del "$t"; rm -f "$(kfile "$t")"; xray_restart
            ok "Протокол '${t}' удалён"
        }
    fi
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ
# ──────────────────────────────────────────────────────────────────────────────

menu_users() {
    while true; do
        cls; box_top " 👥  Пользователи" "$YELLOW"; box_blank
        # Статистика по протоколам
        while IFS='|' read -r tag port proto net sec; do
            local uc; uc=$(ib_users_count "$tag")
            box_row "  • ${CYAN}${tag}${R}  ${DIM}${proto}+${net}+${sec} · порт ${port}${R}  ${YELLOW}${uc} польз.${R}"
        done < <(ib_list)
        box_blank; box_mid
        mi "1" "➕" "Добавить пользователя"
        mi "2" "➖" "Удалить пользователя"
        mi "3" "📋" "Список всех пользователей"
        mi "4" "🔗" "Показать ссылку / QR-код"
        mi "5" "📊" "Статистика трафика"
        mi "6" "⏱" "Установить лимит (трафик / дата)"
        mi "7" "🔍" "Проверить лимиты сейчас"
        mi "8" "📡" "${CYAN}Подписка (Subscription)${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) user_add ;;
            2) user_del ;;
            3) user_list ;;
            4) user_link ;;
            5) user_stats ;;
            6) user_set_limit ;;
            7) cls; check_limits; pause ;;
            8) menu_subscription ;;
            0) return ;;
        esac
    done
}

user_add() {
    cls; box_top " ➕  Добавить пользователя" "$GREEN"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local email
    ask "Логин пользователя" email ""
    [[ -z "$email" ]] && { err "Логин не может быть пустым"; pause; return; }
    # Допускаем только безопасные символы: буквы, цифры, точка, дефис, подчёркивание, @
    # @ используется как разделитель в конвенции alice@vpn (это не email, просто идентификатор)
    # Запрещаем пробелы, ../ $() и прочие символы, которые попадают в URI и имена файлов
    [[ ! "$email" =~ ^[a-zA-Z0-9._@-]+$ ]] && { err "Логин содержит недопустимые символы. Разрешены: a-z A-Z 0-9 . _ @ -"; pause; return; }
    # Проверка дублей
    local ex; ex=$(jq -r --arg t "$tag" --arg e "$email" \
        '[.inbounds[]|select(.tag==$t)|((.settings.clients//[]) + (.settings.users//[]))[]]|map(select(.email==$e))|.[0].email' "$XRAY_CONF" 2>/dev/null)
    [[ -n "$ex" ]] && { err "Пользователь '$email' уже существует в '$tag'"; pause; return; }

    local proto; proto=$(ib_proto "$tag")
    local net;   net=$(ib_net "$tag")
    local uuid;  uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local client_json

    case "${proto}:${net}" in
        vless:tcp|vless:raw)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"flow":"xtls-rprx-vision"}') ;;
        vless:xhttp)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"flow":""}') ;;
        vless:ws|vless:grpc|vless:httpupgrade)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id}') ;;
        vmess:*)
            client_json=$(jq -n --arg e "$email" --arg id "$uuid" \
                '{"email":$e,"id":$id,"alterId":0}') ;;
        trojan:*)
            local pass; pass=$(openssl rand -hex 16)
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        hysteria:hysteria)
            local pass; pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        shadowsocks:*)
            local pass; pass=$(openssl rand -base64 32)
            client_json=$(jq -n --arg e "$email" --arg p "$pass" \
                '{"email":$e,"password":$p}') ;;
        *)
            err "Неизвестный протокол ${proto}+${net}"; pause; return ;;
    esac

    # Спросить про лимиты сразу
    local set_lim; set_lim="n"
    box_blank
    box_row "  ${YELLOW}Установить лимиты для пользователя?${R}"
    mi "1" "⏱" "Да — задать прямо сейчас"
    mi "2" "⏭" "Нет — без лимитов"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " lim_ch
    [[ "$lim_ch" == "1" ]] && set_lim="y"

    local expire_ts="" traffic_gb=""
    if [[ "$set_lim" == "y" ]]; then
        box_blank
        ask "Дата истечения (YYYY-MM-DD, пусто = без ограничения)" expire_date ""
        ask "Лимит трафика ГБ (пусто = без ограничения)" traffic_gb ""
        if [[ -n "$expire_date" ]]; then
            expire_ts=$(date -d "$expire_date 23:59:59" +%s 2>/dev/null || echo "")
        fi
    fi

    # Добавить клиента (hysteria использует .settings.users, остальные — .settings.clients)
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "${proto}:${net}" == "hysteria:hysteria" ]]; then
        jq --arg t "$tag" --argjson c "$client_json" \
            '(.inbounds[]|select(.tag==$t)|.settings.users) += [$c]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    else
        jq --arg t "$tag" --argjson c "$client_json" \
            '(.inbounds[]|select(.tag==$t)|.settings.clients) += [$c]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi

    # Сохранить лимиты
    if [[ -n "$expire_ts" ]]; then
        limit_set "$tag" "$email" "expire_ts" "$expire_ts"
        limit_set "$tag" "$email" "expire_date" "$expire_date"
    fi
    if [[ -n "$traffic_gb" && "$traffic_gb" -gt 0 ]]; then
        local bytes=$(( traffic_gb * 1073741824 ))
        limit_set "$tag" "$email" "traffic_limit_bytes" "$bytes"
        limit_set "$tag" "$email" "traffic_limit_gb" "$traffic_gb"
    fi

    # Применяем без перезапуска через gRPC API
    if xray_active && xray_api_add_user "$tag" "$client_json" "$proto" "$net"; then
        ok "Пользователь добавлен в работающий Xray (без разрыва соединений)"
    else
        warn "API недоступен — перезапускаем Xray..."
        xray_restart
    fi

    # Автообновление файлов подписки
    if _sub_autoupdate_enabled && _sub_is_running; then
        info "Обновляем файлы подписки..."
        _sub_update_files
    fi

    cls; box_top " ✅  Пользователь добавлен" "$GREEN"; box_blank
    box_row "  Протокол: ${CYAN}${tag}${R}  Имя: ${YELLOW}${email}${R}"
    [[ -n "$expire_date" ]] && box_row "  Срок до: ${ORANGE}${expire_date}${R}"
    [[ -n "$traffic_gb" ]] && box_row "  Лимит трафика: ${ORANGE}${traffic_gb} GB${R}"
    if _sub_autoupdate_enabled && _sub_is_running; then
        box_row "  ${GREEN}✓ Подписка обновлена автоматически${R}"
    fi
    box_blank; box_end
    show_link_qr "$tag" "$email"
}

user_del() {
    cls; box_top " ➖  Удалить пользователя" "$RED"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        local exp; exp=$(limit_get "$tag" "$em" "expire_date")
        local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
        local badge=""
        [[ -n "$exp" ]] && badge="до ${exp}"
        [[ -n "$tlim" ]] && badge="${badge} ${tlim}GB"
        mi "$i" "👤" "$em" "  ${DIM}${badge}${R}"
        (( i++ )) || true
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        local sel="${emails[$((ch-1))]}"
        confirm "Удалить '${sel}' из '${tag}'?" && {
            _remove_user_from_tag "$tag" "$sel"
            limit_del_user "$tag" "$sel"
            xray_reload
            ok "'${sel}' удалён"
        }
    fi
    pause
}

user_list() {
    cls; box_top " 📋  Все пользователи" "$YELLOW"; box_blank
    local total=0
    while IFS='|' read -r tag port proto net sec; do
        box_row "  ${CYAN}${BOLD}${tag}${R}  ${DIM}${proto}+${net}+${sec} · порт ${port}${R}"
        local cnt=0
        while IFS= read -r em; do
            local exp; exp=$(limit_get "$tag" "$em" "expire_date")
            local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
            local info_str=""
            [[ -n "$exp" ]]  && info_str="${info_str} ${ORANGE}до ${exp}${R}"
            [[ -n "$tlim" ]] && info_str="${info_str} ${ORANGE}${tlim}GB${R}"
            # Проверим статус
            local now; now=$(date +%s)
            local ets; ets=$(limit_get "$tag" "$em" "expire_ts")
            local status_icon="✓"
            [[ -n "$ets" && "$ets" != "null" && "$now" -gt "$ets" ]] && status_icon="${RED}✗${R}"
            box_row "    ${status_icon} ${LIGHT}${em}${R}${info_str}"
            (( cnt++ )) || true; (( total++ )) || true
        done < <(ib_emails "$tag")
        [[ $cnt -eq 0 ]] && box_row "    ${DIM}(нет пользователей)${R}"
        box_blank
    done < <(ib_list)
    box_row "  Итого: ${YELLOW}${total}${R} пользователей"
    box_blank; box_end; pause
}

user_link() {
    cls; box_top " 🔗  Ссылка и QR-код" "$CYAN"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(
        ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        mi "$i" "👤" "$em"; (( i++ )) || true
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        show_link_qr "$tag" "${emails[$((ch-1))]}"
    fi
}

user_stats() {
    cls; box_top " 📊  Статистика трафика" "$BLUE"; box_blank
    if ! xray_active; then
        box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return
    fi
    while IFS='|' read -r tag port proto net sec; do
        box_row "  ${CYAN}${BOLD}${tag}${R}  ${DIM}${proto}+${net}${R}"
        while IFS= read -r em; do
            local up dn total_b
            up=$(get_user_traffic "$em" "uplink")
            dn=$(get_user_traffic "$em" "downlink")
            total_b=$(( up + dn ))
            local up_fmt; up_fmt=$(fmt_bytes "$up")
            local dn_fmt; dn_fmt=$(fmt_bytes "$dn")
            local tot_fmt; tot_fmt=$(fmt_bytes "$total_b")
            local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_bytes")
            local lim_str=""
            if [[ -n "$tlim" && "$tlim" != "null" && "$tlim" -gt 0 ]]; then
                local pct=$(( total_b * 100 / tlim ))
                lim_str=" ${ORANGE}${pct}%${R}"
            fi
            box_row "    ${LIGHT}${em}${R}  ↑${up_fmt}  ↓${dn_fmt}  =${tot_fmt}${lim_str}"
        done < <(ib_emails "$tag")
        box_blank
    done < <(ib_list)
    box_end; pause
}

user_set_limit() {
    cls; box_top " ⏱  Установить лимит" "$ORANGE"; box_blank
    local tag
    pick_inbound tag || { pause; return; }
    local emails=()
    while IFS= read -r em; do emails+=("$em"); done < <(
        ib_emails "$tag")
    if [[ ${#emails[@]} -eq 0 ]]; then
        box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return
    fi
    local i=1
    for em in "${emails[@]}"; do
        local exp; exp=$(limit_get "$tag" "$em" "expire_date")
        local tlim; tlim=$(limit_get "$tag" "$em" "traffic_limit_gb")
        mi "$i" "👤" "$em" "  ${DIM}до:${exp:-∞} трафик:${tlim:-∞}GB${R}"
        (( i++ )) || true
    done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    if [[ "$ch" -ge 1 && "$ch" -le ${#emails[@]} ]]; then
        local sel="${emails[$((ch-1))]}"
        box_blank
        box_row "  Пользователь: ${YELLOW}${sel}${R}"
        box_blank
        local expire_date traffic_gb
        ask "Дата истечения (YYYY-MM-DD, пусто = сбросить)" expire_date ""
        ask "Лимит трафика ГБ (0 = сбросить)" traffic_gb ""
        if [[ -n "$expire_date" ]]; then
            local expire_ts; expire_ts=$(date -d "$expire_date 23:59:59" +%s 2>/dev/null || echo "")
            if [[ -n "$expire_ts" ]]; then
                limit_set "$tag" "$sel" "expire_ts" "$expire_ts"
                limit_set "$tag" "$sel" "expire_date" "$expire_date"
                ok "Дата истечения: $expire_date"
            fi
        else
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg t "$tag" --arg e "$sel" 'del(.[$t][$e].expire_ts) | del(.[$t][$e].expire_date)' \
                "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
            ok "Ограничение по дате снято"
        fi
        if [[ -n "$traffic_gb" && "$traffic_gb" -gt 0 ]]; then
            local bytes=$(( traffic_gb * 1073741824 ))
            limit_set "$tag" "$sel" "traffic_limit_bytes" "$bytes"
            limit_set "$tag" "$sel" "traffic_limit_gb" "$traffic_gb"
            ok "Лимит трафика: ${traffic_gb} GB"
        elif [[ "$traffic_gb" == "0" ]]; then
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg t "$tag" --arg e "$sel" 'del(.[$t][$e].traffic_limit_bytes) | del(.[$t][$e].traffic_limit_gb)' \
                "$LIMITS_FILE" > "$tmp" && mv "$tmp" "$LIMITS_FILE"
            ok "Ограничение по трафику снято"
        fi
    fi
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
