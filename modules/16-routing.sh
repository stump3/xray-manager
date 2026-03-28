# ══════════════════════════════════════════════════════════════════════════════
#  РОУТИНГ — управление правилами маршрутизации
# ══════════════════════════════════════════════════════════════════════════════

PROFILES_DIR="/usr/local/etc/xray/profiles"

# ── Helpers ───────────────────────────────────────────────────────────────────

routing_rules_count() {
    jq '[.routing.rules[]? | select(.inboundTag[0]? != "api")] | length' \
        "$XRAY_CONF" 2>/dev/null || echo 0
}

routing_active_profile() {
    jq -r '.routing._profile // "custom"' "$XRAY_CONF" 2>/dev/null
}

routing_rule_summary() {
    # Выводит читаемое описание правила по индексу
    local idx="$1"
    jq -r --argjson i "$idx" '
        .routing.rules[$i] |
        [
            (if .domain   then "domain:"   + (.domain   | join(",") | .[0:40]) else empty end),
            (if .ip       then "ip:"       + (.ip       | join(",") | .[0:30]) else empty end),
            (if .port     then "port:"     + .port                              else empty end),
            (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
            (if .user     then "user:"     + (.user     | join(","))            else empty end),
            (if .network  then "net:"      + .network                           else empty end),
            (if .inboundTag then "from:"   + (.inboundTag | join(","))          else empty end)
        ] | join(" | ") + " → " + (.outboundTag // .balancerTag // "?")
    ' "$XRAY_CONF" 2>/dev/null
}

# ── Главное меню роутинга ─────────────────────────────────────────────────────

menu_routing() {
    while true; do
        cls; box_top " 🗺  Маршрутизация (Routing)" "$CYAN"
        box_blank

        # Текущее состояние
        local profile; profile=$(routing_active_profile)
        local rules_n; rules_n=$(routing_rules_count)
        local strategy; strategy=$(jq -r '.routing.domainStrategy // "AsIs"' "$XRAY_CONF" 2>/dev/null)

        box_row "  Профиль:         ${YELLOW}${profile}${R}"
        box_row "  Правил:          ${CYAN}${rules_n}${R}  ${DIM}(не считая служебные)${R}"
        box_row "  domainStrategy:  ${DIM}${strategy}${R}"
        box_blank; box_mid

        mi "1" "📋" "Список правил"
        mi "2" "➕" "Добавить правило"
        mi "3" "🗑" "Удалить правило"
        mi "4" "↕️ " "Порядок правил (поднять/опустить)"
        mi "5" "🌐" "domainStrategy"
        box_mid
        mi "6" "💾" "${YELLOW}Профили${R}  ${DIM}(сохранить / загрузить / шаблоны)${R}"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) routing_list ;;
            2) routing_add ;;
            3) routing_del ;;
            4) routing_reorder ;;
            5) routing_strategy ;;
            6) menu_profiles ;;
            0) return ;;
        esac
    done
}

# ── Список правил ─────────────────────────────────────────────────────────────

routing_list() {
    cls; box_top " 📋  Правила маршрутизации" "$CYAN"; box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    if [[ "$total" -eq 0 ]]; then
        box_row "  ${DIM}Нет правил${R}"; box_blank; box_end; pause; return
    fi

    local i=0
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        # Пропустить служебное правило api
        if [[ "$tag" == "api" ]]; then ((i++)); continue; fi

        local outb; outb=$(jq -r --argjson n "$i" '.routing.rules[$n] | .outboundTag // .balancerTag // "?"' "$XRAY_CONF" 2>/dev/null)
        local col="$LIGHT"
        case "$outb" in
            direct) col="$GREEN" ;;
            block)  col="$RED" ;;
            *)      col="$CYAN" ;;
        esac

        local summary; summary=$(routing_rule_summary "$i")
        local idx_disp=$(( i + 1 ))
        box_row "  ${DIM}#${idx_disp}${R}  ${col}→ ${outb}${R}  ${DIM}${summary}${R}"
        ((i++))
    done

    box_blank; box_end; pause
}

# ── Добавить правило ──────────────────────────────────────────────────────────

# ── Мульти-выбор профилей для синхронизации ──────────────────────────────────
# Возвращает список выбранных файлов профилей через newline в переменную $1
# Использование: _profile_multiselect selected_files_var
_profile_multiselect() {
    local __result_var="$1"
    _profiles_init

    # Собрать список профилей
    local -a pnames=() pfiles=()
    while IFS='|' read -r name desc file; do
        pnames+=("$name"); pfiles+=("$file")
    done < <(_profile_list)

    if [[ ${#pnames[@]} -eq 0 ]]; then
        printf -v "$__result_var" '%s' ""
        return
    fi

    # Состояние выбора (0=нет, 1=да)
    local -a selected=()
    for _ in "${pnames[@]}"; do selected+=(0); done

    while true; do
        echo ""
        box_row "  ${CYAN}${BOLD}Выберите профили для синхронизации:${R}"
        box_row "  ${DIM}Пробел — переключить, A — все/сброс, Enter — подтвердить, 0 — пропустить${R}"
        box_blank

        local i=0
        for name in "${pnames[@]}"; do
            local rc; rc=$(_profile_rules_count "${pfiles[$i]}")
            local mark
            if [[ "${selected[$i]}" == "1" ]]; then
                mark="${GREEN}[✓]${R}"
            else
                mark="${DIM}[ ]${R}"
            fi
            printf "${DIM}│${R}  %b ${YELLOW}${BOLD}%s)${R} ${CYAN}%-20s${R} ${DIM}%s правил${R}\n" \
                "$mark" "$((i+1))" "$name" "$rc"
            ((i++))
        done

        local total_sel=0
        for s in "${selected[@]}"; do [[ "$s" == "1" ]] && ((total_sel++)); done

        box_blank
        box_row "  ${DIM}Выбрано: ${YELLOW}${total_sel}${R}${DIM} профилей${R}"
        box_end

        local key
        read -rp "$(printf "${YELLOW}›${R} [1-${#pnames[@]}/A/Enter/0]: ")" key < /dev/tty

        case "$key" in
            0|"")
                if [[ -z "$key" ]]; then
                    # Enter — подтверждение
                    break
                else
                    # 0 — пропустить
                    printf -v "$__result_var" '%s' ""
                    return
                fi
                ;;
            a|A)
                # Все/сброс
                local any=0
                for s in "${selected[@]}"; do [[ "$s" == "1" ]] && { any=1; break; }; done
                if [[ $any -eq 1 ]]; then
                    for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=0; done
                else
                    for ((i=0; i<${#selected[@]}; i++)); do selected[$i]=1; done
                fi
                ;;
            *)
                if [[ "$key" =~ ^[0-9]+$ ]] && [[ "$key" -ge 1 && "$key" -le ${#pnames[@]} ]]; then
                    local idx=$(( key - 1 ))
                    if [[ "${selected[$idx]}" == "1" ]]; then
                        selected[$idx]=0
                    else
                        selected[$idx]=1
                    fi
                fi
                ;;
        esac
    done

    # Вернуть файлы выбранных профилей
    local result=""
    local i=0
    for name in "${pnames[@]}"; do
        if [[ "${selected[$i]}" == "1" ]]; then
            result="${result}${pfiles[$i]}"$'\n'
        fi
        ((i++))
    done
    printf -v "$__result_var" '%s' "${result%$'\n'}"
}

# Применить правило к файлу профиля (добавить в конец, не дублировать)
_profile_add_rule() {
    local file="$1"
    local rule_json="$2"
    [[ ! -f "$file" ]] && return 1
    # Проверить нет ли уже точно такого же правила
    local exists; exists=$(jq --argjson r "$rule_json" \
        '[.rules[]? | . == $r] | any' "$file" 2>/dev/null)
    if [[ "$exists" == "true" ]]; then
        warn "Правило уже есть в $(basename "$file" .json)"
        return 0
    fi
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson r "$rule_json" '.rules += [$r]' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Удалить правило из файла профиля по совпадению полей
_profile_del_rule() {
    local file="$1"
    local rule_json="$2"
    [[ ! -f "$file" ]] && return 1
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson r "$rule_json" \
        '.rules = [.rules[]? | select(. != $r)]' \
        "$file" > "$tmp" && mv "$tmp" "$file"
}

routing_add() {
    cls; box_top " ➕  Добавить правило" "$GREEN"; box_blank

    # Выбор критерия
    box_row "  ${YELLOW}Критерий совпадения:${R}"
    mi "1" "🌐" "По домену          ${DIM}(example.com, geosite:google)${R}"
    mi "2" "🔢" "По IP / CIDR       ${DIM}(1.2.3.4, geoip:ru, 10.0.0.0/8)${R}"
    mi "3" "🔌" "По порту           ${DIM}(443, 80, 1000-2000)${R}"
    mi "4" "📡" "По протоколу       ${DIM}(http, tls, quic, bittorrent)${R}"
    mi "5" "👤" "По пользователю    ${DIM}(alice@xray.com)${R}"
    mi "6" "🏷" "По inbound тегу    ${DIM}(vless-reality, vmess-ws)${R}"
    mi "7" "🌍" "По сети (tcp/udp)"
    mi "8" "✨" "Комбинированное    ${DIM}(несколько критериев сразу)${R}"
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " crit_ch
    [[ "$crit_ch" == "0" ]] && return

    # Формируем JSON правила
    local rule_json="{}"

    case "$crit_ch" in
        1)  # Домен
            box_blank
            box_row "  ${DIM}Примеры: google.com  geosite:google  regexp:\\.fb\\.  full:example.com${R}"
            box_row "  ${DIM}Несколько через пробел: youtube.com geosite:netflix${R}"
            local domains; ask "Домены" domains ""
            [[ -z "$domains" ]] && return
            local darr; darr=$(echo "$domains" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson d "$darr" '{domain: $d}')
            ;;
        2)  # IP
            box_blank
            box_row "  ${DIM}Примеры: 8.8.8.8  geoip:ru  10.0.0.0/8  geoip:private${R}"
            local ips; ask "IP / CIDR" ips ""
            [[ -z "$ips" ]] && return
            local iarr; iarr=$(echo "$ips" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson ip "$iarr" '{ip: $ip}')
            ;;
        3)  # Порт
            local port_val; ask "Порты" port_val "443"
            rule_json=$(jq -n --arg p "$port_val" '{port: $p}')
            ;;
        4)  # Протокол
            box_blank
            box_row "  Варианты: http tls quic bittorrent"
            box_row "  ${YELLOW}⚠ Нужен sniffing в inbound!${R}"
            local protos; ask "Протоколы (через пробел)" protos "bittorrent"
            local parr; parr=$(echo "$protos" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson p "$parr" '{protocol: $p}')
            ;;
        5)  # Пользователь
            local users; ask "Email пользователей (через пробел)" users ""
            [[ -z "$users" ]] && return
            local uarr; uarr=$(echo "$users" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson u "$uarr" '{user: $u}')
            ;;
        6)  # Inbound tag
            box_blank
            box_row "  ${YELLOW}Доступные inbound:${R}"
            ib_list | while IFS='|' read -r tag port proto net sec; do
                box_row "    ${CYAN}${tag}${R}"
            done
            local tags; ask "Теги (через пробел)" tags ""
            [[ -z "$tags" ]] && return
            local tarr; tarr=$(echo "$tags" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))")
            rule_json=$(jq -n --argjson t "$tarr" '{inboundTag: $t}')
            ;;
        7)  # Сеть
            box_blank
            mi "1" "📶" "tcp"; mi "2" "📡" "udp"; mi "3" "🔀" "tcp,udp"
            box_end
            read -rp "$(printf "${YELLOW}›${R} ") " net_ch
            local net_val
            case "$net_ch" in 1) net_val="tcp";; 2) net_val="udp";; *) net_val="tcp,udp";; esac
            rule_json=$(jq -n --arg n "$net_val" '{network: $n}')
            ;;
        8)  # Комбинированное
            box_blank
            box_row "  ${DIM}Оставь пустым то что не нужно${R}"
            local dom_v ip_v port_v net_v
            ask "Домены (пусто = пропустить)" dom_v ""
            ask "IP/CIDR  (пусто = пропустить)" ip_v ""
            ask "Порты    (пусто = пропустить)" port_v ""
            ask "Сеть tcp/udp/tcp,udp (пусто = пропустить)" net_v ""
            rule_json="{}"
            [[ -n "$dom_v" ]]  && { local darr; darr=$(echo "$dom_v" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))"); rule_json=$(echo "$rule_json" | jq --argjson d "$darr" '.domain=$d'); }
            [[ -n "$ip_v" ]]   && { local iarr; iarr=$(echo "$ip_v" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))"); rule_json=$(echo "$rule_json" | jq --argjson ip "$iarr" '.ip=$ip'); }
            [[ -n "$port_v" ]] && rule_json=$(echo "$rule_json" | jq --arg p "$port_v" '.port=$p')
            [[ -n "$net_v" ]]  && rule_json=$(echo "$rule_json" | jq --arg n "$net_v" '.network=$n')
            ;;
    esac

    # Выбор outbound
    box_blank
    box_row "  ${YELLOW}Действие (outbound):${R}"
    mi "1" "✈️ " "${GREEN}direct${R}   — напрямую"
    mi "2" "🚫" "${RED}block${R}    — заблокировать"
    # Показать доступные outbounds
    local i=3
    local -a ob_list=()
    while IFS= read -r t; do
        [[ "$t" == "direct" || "$t" == "block" || "$t" == "api" || "$t" == "metrics_out" ]] && continue
        mi "$i" "🔌" "${CYAN}${t}${R}"
        ob_list+=("$t"); ((i++))
    done < <(jq -r '.outbounds[].tag' "$XRAY_CONF" 2>/dev/null)
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ob_ch

    local outbound_tag
    case "$ob_ch" in
        1) outbound_tag="direct" ;;
        2) outbound_tag="block" ;;
        *)
            local idx=$(( ob_ch - 3 ))
            if [[ $idx -ge 0 && $idx -lt ${#ob_list[@]} ]]; then
                outbound_tag="${ob_list[$idx]}"
            else
                warn "Неверный выбор"; pause; return
            fi
            ;;
    esac

    rule_json=$(echo "$rule_json" | jq --arg o "$outbound_tag" '. + {outboundTag: $o, type: "field"}')

    # Позиция вставки
    box_blank
    local total; total=$(routing_rules_count)
    box_row "  ${YELLOW}Позиция (правила проверяются сверху вниз):${R}"
    mi "1" "⬆️ " "В начало  ${DIM}(высокий приоритет)${R}"
    mi "2" "⬇️ " "В конец   ${DIM}(низкий приоритет, дефолт)${R}"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " pos_ch

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "$pos_ch" == "1" ]]; then
        # Вставить после служебного api-правила (индекс 0)
        jq --argjson r "$rule_json" \
            '.routing.rules = [.routing.rules[0]] + [$r] + .routing.rules[1:]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    else
        jq --argjson r "$rule_json" '.routing.rules += [$r]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    fi

    # Сбросить имя профиля — конфиг изменён вручную
    local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
    jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"

    xray_restart
    ok "Правило добавлено: ${outbound_tag}"

    # Предложить синхронизацию с профилями
    if [[ -d "$PROFILES_DIR" ]] && compgen -G "${PROFILES_DIR}/*.json" >/dev/null 2>&1; then
        box_blank
        box_row "  ${YELLOW}Добавить это правило в профили?${R}"
        box_end
        local sync_files
        _profile_multiselect sync_files
        if [[ -n "$sync_files" ]]; then
            while IFS= read -r pfile; do
                [[ -z "$pfile" ]] && continue
                _profile_add_rule "$pfile" "$rule_json"
                ok "→ $(basename "$pfile" .json)"
            done <<< "$sync_files"
        fi
    fi

    pause
}

# ── Удалить правило ───────────────────────────────────────────────────────────

routing_del() {
    cls; box_top " 🗑  Удалить правило" "$RED"; box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    local -a display_indices=()
    local i=0
    local disp=1
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        if [[ "$tag" != "api" ]]; then
            local summary; summary=$(routing_rule_summary "$i")
            mi "$disp" "📍" "${DIM}${summary}${R}"
            display_indices+=("$i")
            ((disp++))
        fi
        ((i++))
    done

    [[ ${#display_indices[@]} -eq 0 ]] && { box_row "  ${DIM}Нет правил для удаления${R}"; box_end; pause; return; }
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return

    local real_idx="${display_indices[$((ch-1))]}"
    [[ -z "$real_idx" ]] && { warn "Неверный выбор"; pause; return; }

    local del_rule_json; del_rule_json=$(jq -c --argjson n "$real_idx" '.routing.rules[$n]' "$XRAY_CONF" 2>/dev/null)

    confirm "Удалить правило #${ch}?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --argjson n "$real_idx" 'del(.routing.rules[$n])' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
        jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
        xray_restart
        ok "Правило удалено"

        # Предложить синхронизацию с профилями
        if [[ -n "$del_rule_json" ]] && [[ -d "$PROFILES_DIR" ]] && compgen -G "${PROFILES_DIR}/*.json" >/dev/null 2>&1; then
            box_blank
            box_row "  ${YELLOW}Удалить это правило из профилей?${R}"
            box_end
            local sync_files
            _profile_multiselect sync_files
            if [[ -n "$sync_files" ]]; then
                while IFS= read -r pfile; do
                    [[ -z "$pfile" ]] && continue
                    _profile_del_rule "$pfile" "$del_rule_json"
                    ok "→ $(basename "$pfile" .json)"
                done <<< "$sync_files"
            fi
        fi
    }
    pause
}

# ── Порядок правил ────────────────────────────────────────────────────────────

routing_reorder() {
    cls; box_top " ↕️  Порядок правил" "$YELLOW"; box_blank
    box_row "  ${DIM}Правила проверяются сверху вниз. Первое совпадение — победитель.${R}"
    box_blank

    local total; total=$(jq '.routing.rules | length' "$XRAY_CONF" 2>/dev/null || echo 0)
    local -a display_indices=()
    local i=0; local disp=1
    while [[ $i -lt $total ]]; do
        local tag; tag=$(jq -r --argjson n "$i" '.routing.rules[$n].inboundTag[0] // ""' "$XRAY_CONF" 2>/dev/null)
        if [[ "$tag" != "api" ]]; then
            local summary; summary=$(routing_rule_summary "$i")
            mi "$disp" "📍" "${DIM}${summary}${R}"
            display_indices+=("$i"); ((disp++))
        fi
        ((i++))
    done
    [[ ${#display_indices[@]} -le 1 ]] && { box_row "  ${DIM}Нечего перемещать${R}"; box_end; pause; return; }
    box_blank
    box_row "  ${DIM}Введите номер правила для перемещения,${R}"
    box_row "  ${DIM}затем: U — вверх, D — вниз${R}"
    box_end

    local rule_num dir
    read -rp "$(printf "${YELLOW}›${R} Правило: ")" rule_num
    [[ -z "$rule_num" || "$rule_num" == "0" ]] && return
    read -rp "$(printf "${YELLOW}›${R} [U]верх / [D]вниз: ")" dir

    local real_idx="${display_indices[$((rule_num-1))]}"
    [[ -z "$real_idx" ]] && { warn "Неверный номер"; pause; return; }

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    if [[ "${dir,,}" == "u" && "$real_idx" -gt 1 ]]; then
        # Swap с предыдущим (не api)
        local prev_real="${display_indices[$((rule_num-2))]}"
        jq --argjson a "$real_idx" --argjson b "$prev_real" \
            '.routing.rules[$a], .routing.rules[$b] = .routing.rules[$b], .routing.rules[$a]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Правило перемещено вверх"
    elif [[ "${dir,,}" == "d" && "$rule_num" -lt ${#display_indices[@]} ]]; then
        local next_real="${display_indices[$((rule_num))]}"
        jq --argjson a "$real_idx" --argjson b "$next_real" \
            '.routing.rules[$a], .routing.rules[$b] = .routing.rules[$b], .routing.rules[$a]' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Правило перемещено вниз"
    else
        warn "Невозможно переместить"
    fi

    local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
    jq '.routing._profile = "custom"' "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
    xray_restart
    pause
}

# ── domainStrategy ────────────────────────────────────────────────────────────

routing_strategy() {
    cls; box_top " 🌐  domainStrategy" "$BLUE"; box_blank
    local cur; cur=$(jq -r '.routing.domainStrategy // "AsIs"' "$XRAY_CONF" 2>/dev/null)
    box_row "  Текущая: ${CYAN}${cur}${R}"; box_blank

    box_row "  ${YELLOW}Варианты:${R}"
    mi "1" "⚡" "${CYAN}AsIs${R}           — только домен, без резолва  ${DIM}(быстро, по умолчанию)${R}"
    mi "2" "🔍" "${CYAN}IPIfNonMatch${R}   — резолвит если нет совпадения по домену"
    mi "3" "🔎" "${CYAN}IPOnDemand${R}     — резолвит при любом IP-правиле сразу"
    box_blank
    box_row "  ${DIM}IPIfNonMatch: клиент идёт к 1.2.3.4 → нет совпадения по домену${R}"
    box_row "  ${DIM}→ резолвит 1.2.3.4 → google.com → совпадает geosite:google → proxy${R}"
    box_mid; mi "0" "◀" "Назад"; box_end

    read -rp "$(printf "${YELLOW}›${R} ") " ch
    local new_strat
    case "$ch" in
        1) new_strat="AsIs" ;;
        2) new_strat="IPIfNonMatch" ;;
        3) new_strat="IPOnDemand" ;;
        0) return ;;
        *) warn "Неверный выбор"; pause; return ;;
    esac

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg s "$new_strat" '.routing.domainStrategy = $s' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "domainStrategy → ${new_strat}"
    pause
}

# ══════════════════════════════════════════════════════════════════════════════
#  ПРОФИЛИ — сохранение/загрузка наборов правил
# ══════════════════════════════════════════════════════════════════════════════

_profiles_init() { mkdir -p "$PROFILES_DIR"; }

_profile_list() {
    find "$PROFILES_DIR" -name "*.json" 2>/dev/null | sort | while read -r f; do
        local name; name=$(basename "$f" .json)
        local desc; desc=$(jq -r '.description // ""' "$f" 2>/dev/null)
        echo "${name}|${desc}|${f}"
    done
}

_profile_rules_count() {
    jq '[.rules[]? | select(.inboundTag[0]? != "api")] | length' "$1" 2>/dev/null || echo 0
}

menu_profiles() {
    _profiles_init
    while true; do
        cls; box_top " 💾  Профили роутинга" "$YELLOW"
        box_blank
        box_row "  ${DIM}Профиль = сохранённый набор правил. Загрузка заменяет текущие правила.${R}"
        box_blank

        local active; active=$(routing_active_profile)
        box_row "  Активный: ${YELLOW}${active}${R}"
        box_blank

        # Список профилей
        local i=1; local -a pnames=() pfiles=()
        while IFS='|' read -r name desc file; do
            local rc; rc=$(_profile_rules_count "$file")
            local marker=""
            [[ "$name" == "$active" ]] && marker="${GREEN}◄ активен${R}"
            mi "$i" "📄" "${CYAN}${name}${R}  ${DIM}${desc:+— $desc }(${rc} правил)${R}  ${marker}"
            pnames+=("$name"); pfiles+=("$file"); ((i++))
        done < <(_profile_list)

        [[ ${#pnames[@]} -eq 0 ]] && box_row "  ${DIM}(нет сохранённых профилей)${R}"
        box_blank; box_mid

        mi "s" "💾" "Сохранить текущие правила как профиль"
        mi "t" "📋" "Шаблоны  ${DIM}(готовые наборы правил)${R}"
        mi "d" "🗑" "Удалить профиль"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch

        case "$ch" in
            s|S) profile_save ;;
            t|T) menu_profile_templates ;;
            d|D) profile_delete "${pnames[@]}" "${pfiles[@]}" ;;
            0)   return ;;
            *)
                if [[ "$ch" =~ ^[0-9]+$ ]] && [[ "$ch" -ge 1 && "$ch" -le ${#pnames[@]} ]]; then
                    profile_load "${pfiles[$((ch-1))]}" "${pnames[$((ch-1))]}"
                fi
                ;;
        esac
    done
}

profile_save() {
    cls; box_top " 💾  Сохранить профиль" "$YELLOW"; box_blank
    local name desc
    ask "Имя профиля (без пробелов)" name ""
    [[ -z "$name" ]] && return
    name="${name// /_}"
    ask "Описание (необязательно)" desc ""

    # Сохраняем только routing.rules (без служебного api-правила)
    local file="${PROFILES_DIR}/${name}.json"
    jq --arg d "$desc" '{
        description: $d,
        domainStrategy: .routing.domainStrategy,
        rules: [.routing.rules[]? | select(.inboundTag[0]? != "api")]
    }' "$XRAY_CONF" > "$file"

    local rc; rc=$(_profile_rules_count "$file")
    ok "Профиль '${name}' сохранён (${rc} правил)"
    pause
}

profile_load() {
    local file="$1" name="$2"
    [[ ! -f "$file" ]] && { err "Файл профиля не найден"; return; }

    local rc; rc=$(_profile_rules_count "$file")
    cls; box_top " 📂  Загрузить профиль: ${name}" "$CYAN"; box_blank
    box_row "  Правил в профиле: ${CYAN}${rc}${R}"
    box_blank

    # Показать правила профиля
    jq -r '.rules[]? |
        [
            (if .domain   then "domain:"   + (.domain   | join(",") | .[0:35]) else empty end),
            (if .ip       then "ip:"       + (.ip       | join(",") | .[0:25]) else empty end),
            (if .port     then "port:"     + .port                              else empty end),
            (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
            (if .network  then "net:"      + .network                           else empty end)
        ] | join(" | ") + " → " + (.outboundTag // "?")
    ' "$file" | while read -r line; do box_row "  ${DIM}${line}${R}"; done

    box_blank
    box_row "  ${YELLOW}⚠  Текущие правила будут заменены!${R}"
    box_blank; box_end

    confirm "Загрузить профиль '${name}'?" || return

    # Сохраняем api-правило, берём из профиля остальные
    local api_rule; api_rule=$(jq -c '.routing.rules[]? | select(.inboundTag[0]? == "api")' "$XRAY_CONF" 2>/dev/null | head -1)
    local new_strategy; new_strategy=$(jq -r '.domainStrategy // "IPIfNonMatch"' "$file")
    local new_rules; new_rules=$(jq -c '.rules' "$file")

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg strat "$new_strategy" \
       --arg name "$name" \
       --argjson ar "${api_rule:-null}" \
       --argjson rules "$new_rules" \
       '.routing.domainStrategy = $strat |
        .routing._profile = $name |
        .routing.rules = (
            if $ar != null then [$ar] + $rules
            else $rules end
        )' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Профиль '${name}' загружен"
    pause
}

profile_delete() {
    cls; box_top " 🗑  Удалить профиль" "$RED"; box_blank
    local -a pnames=("$@")
    # pnames и pfiles передаются как отдельные массивы — нужно восстановить
    local count=${#pnames[@]}
    local half=$(( count / 2 ))
    local names=("${pnames[@]:0:$half}")
    local files=("${pnames[@]:$half}")

    [[ ${#names[@]} -eq 0 ]] && { box_row "  ${DIM}Нет профилей${R}"; box_end; pause; return; }
    local i=1
    for n in "${names[@]}"; do mi "$i" "📄" "$n"; ((i++)); done
    box_mid; mi "0" "◀" "Отмена"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return
    local sel_name="${names[$((ch-1))]}"
    local sel_file="${files[$((ch-1))]}"
    [[ -z "$sel_name" ]] && return
    confirm "Удалить профиль '${sel_name}'?" && { rm -f "$sel_file"; ok "Удалён"; }
    pause
}

# ── Шаблоны профилей ──────────────────────────────────────────────────────────

menu_profile_templates() {
    cls; box_top " 📋  Шаблоны правил" "$MAGENTA"; box_blank
    box_row "  ${DIM}Готовые наборы. Можно загрузить сразу или сохранить как профиль.${R}"
    box_blank

    mi "1" "🇷🇺" "${CYAN}Россия напрямую${R}          ${DIM}RU/CIS сайты → direct, остальное → proxy${R}"
    mi "2" "🌍" "${CYAN}Всё через прокси${R}         ${DIM}Любой трафик → proxy${R}"
    mi "3" "🚫" "${CYAN}Блокировка рекламы++${R}     ${DIM}Реклама + трекеры + торренты → block${R}"
    mi "4" "👤" "${CYAN}Разные пользователи${R}      ${DIM}alice → proxy, bob → direct (шаблон)${R}"
    mi "5" "🔒" "${CYAN}Только HTTPS напрямую${R}    ${DIM}443 → direct, остальное → block${R}"
    mi "6" "⚡" "${CYAN}Оптимальный (рекомендуется)${R}  ${DIM}Реклама block, RU direct, остальное proxy${R}"
    box_mid; mi "0" "◀" "Назад"; box_end

    read -rp "$(printf "${YELLOW}›${R} ") " ch
    local tpl_rules tpl_name tpl_desc tpl_strategy

    case "$ch" in
        1)
            tpl_name="russia-direct"; tpl_strategy="IPIfNonMatch"
            tpl_desc="RU/CIS сайты и IP напрямую, остальное через proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","domain":["geosite:ru","geosite:yandex","geosite:category-gov-ru"],"outboundTag":"direct"},
                {"type":"field","ip":["geoip:ru","geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        2)
            tpl_name="all-proxy"; tpl_strategy="AsIs"
            tpl_desc="Весь трафик через proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        3)
            tpl_name="block-ads-torrents"; tpl_strategy="AsIs"
            tpl_desc="Блокировка рекламы, трекеров и торрентов"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","protocol":["bittorrent"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"direct"}
            ]'
            ;;
        4)
            tpl_name="per-user"; tpl_strategy="AsIs"
            tpl_desc="Разные outbound по пользователям (шаблон — замени emails)"
            tpl_rules='[
                {"type":"field","user":["alice@xray.com"],"outboundTag":"proxy"},
                {"type":"field","user":["bob@xray.com"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"direct"}
            ]'
            ;;
        5)
            tpl_name="https-only"; tpl_strategy="AsIs"
            tpl_desc="Только HTTPS (443) напрямую, остальное заблокировано"
            tpl_rules='[
                {"type":"field","port":"443","network":"tcp","outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"block"}
            ]'
            ;;
        6)
            tpl_name="optimal"; tpl_strategy="IPIfNonMatch"
            tpl_desc="Оптимальный: реклама block, RU direct, остальное proxy"
            tpl_rules='[
                {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
                {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
                {"type":"field","domain":["geosite:ru","geosite:yandex","geosite:category-gov-ru"],"outboundTag":"direct"},
                {"type":"field","ip":["geoip:ru"],"outboundTag":"direct"},
                {"type":"field","network":"tcp,udp","outboundTag":"proxy"}
            ]'
            ;;
        0) return ;;
        *) warn "Неверный выбор"; pause; return ;;
    esac

    cls; box_top " 📋  Шаблон: ${tpl_name}" "$MAGENTA"; box_blank
    box_row "  ${DIM}${tpl_desc}${R}"; box_blank
    echo "$tpl_rules" | jq -r '.[] | [
        (if .domain   then "domain:"   + (.domain   | join(",") | .[0:40]) else empty end),
        (if .ip       then "ip:"       + (.ip       | join(",") | .[0:30]) else empty end),
        (if .port     then "port:"     + .port                              else empty end),
        (if .protocol then "proto:"    + (.protocol | join(","))            else empty end),
        (if .network  then "net:"      + .network                           else empty end)
    ] | join(" | ") + " → " + (.outboundTag // "?")
    ' | while read -r line; do box_row "  ${DIM}${line}${R}"; done
    box_blank; box_mid
    mi "1" "▶" "Применить сейчас"
    mi "2" "💾" "Сохранить как профиль (не применять)"
    mi "0" "◀" "Назад"
    box_end

    read -rp "$(printf "${YELLOW}›${R} ") " action_ch
    case "$action_ch" in
        1)
            # Применить
            local api_rule; api_rule=$(jq -c '.routing.rules[]? | select(.inboundTag[0]? == "api")' "$XRAY_CONF" 2>/dev/null | head -1)
            local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
            jq --arg strat "$tpl_strategy" \
               --arg name "$tpl_name" \
               --argjson ar "${api_rule:-null}" \
               --argjson rules "$tpl_rules" \
               '.routing.domainStrategy = $strat |
                .routing._profile = $name |
                .routing.rules = (if $ar != null then [$ar] + $rules else $rules end)' \
                "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
            xray_restart
            ok "Шаблон '${tpl_name}' применён"
            ;;
        2)
            # Сохранить
            _profiles_init
            local file="${PROFILES_DIR}/${tpl_name}.json"
            echo "{\"description\":\"${tpl_desc}\",\"domainStrategy\":\"${tpl_strategy}\",\"rules\":${tpl_rules}}" \
                | jq . > "$file"
            ok "Сохранён как профиль '${tpl_name}'"
            ;;
    esac
    pause
}


