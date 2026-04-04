# Формирует отображаемое имя для URI-фрагмента (#name).
# email="main" (первый/единственный пользователь) → показывает тег протокола.
# Остальные пользователи → "tag@email" (например vless-de@alice).
_link_name() {
    local tag="$1" email="$2"
    [[ "$email" == "main" ]] && echo "$tag" || echo "${tag}@${email}"
}

gen_link() {
    local tag="$1" email="$2"
    local proto; proto=$(ib_proto "$tag")
    local net;   net=$(ib_net "$tag")
    local port;  port=$(ib_port "$tag")
    # IP принимаем тремя способами (приоритет по убыванию):
    #   1) явный $3 — вызывающий закешировал сам (локальный вызов)
    #   2) _CACHED_SERVER_IP — экспортированный родителем (_sub_all_links)
    #   3) server_ip() — одиночный вызов без кеша
    local sip; sip="${3:-${_CACHED_SERVER_IP:-$(server_ip)}}"

    case "${proto}:${net}" in

      vless:tcp|vless:raw)  # VLESS + TCP + REALITY
        local uuid sni pbk sid
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey"); sid=$(kget "$tag" "shortId")
        # stream-режим: клиент коннектится на внешний порт (443), не на внутренний (18443)
        local ext_port; ext_port=$(kget "$tag" "ext_port" 2>/dev/null || true)
        [[ -n "$ext_port" ]] && port="$ext_port"
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=tcp&flow=xtls-rprx-vision&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vless:xhttp)  # VLESS + XHTTP + REALITY
        local uuid sni pbk sid path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
        sid=$(kget "$tag" "shortId"); path_v=$(kget "$tag" "path")
        # stream-режим: клиент коннектится на внешний порт (443), не на внутренний (18443)
        local ext_port; ext_port=$(kget "$tag" "ext_port" 2>/dev/null || true)
        [[ -n "$ext_port" ]] && port="$ext_port"
        local ep; ep=$(urlencode "$path_v")
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&path=${ep}&mode=auto&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=xhttp&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vless:ws)  # VLESS + WS + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=ws&path=${ep}&host=${dom}&sni=${dom}&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vless:grpc)  # VLESS + gRPC + TLS
        local uuid dom svc
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); svc=$(kget "$tag" "serviceName")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=grpc&serviceName=${svc}&sni=${dom}&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vless:httpupgrade)  # VLESS + HTTPUpgrade + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=httpupgrade&path=${ep}&host=${dom}&sni=${dom}&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vmess:ws)  # VMess + WS + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        # VMess link format (base64 JSON)
        local vmess_json; vmess_json=$(jq -nc \
            --arg id "$uuid" --arg add "$dom" --argjson port "$port" \
            --arg path "$path_v" --arg host "$dom" --arg tls "tls" \
            '{"v":"2","ps":"'"$email"'","add":$add,"port":$port,"id":$id,"aid":0,"scy":"auto","net":"ws","type":"none","host":$host,"path":$path,"tls":$tls,"sni":$host,"alpn":""}')
        echo "vmess://$(echo -n "$vmess_json" | base64 -w0)"
        ;;

      vmess:tcp|vmess:raw)  # VMess + TCP + TLS
        local uuid dom
        uuid=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        local vmess_json; vmess_json=$(jq -nc \
            --arg id "$uuid" --arg add "$dom" --argjson port "$port" \
            --arg tls "tls" \
            '{"v":"2","ps":"'"$email"'","add":$add,"port":$port,"id":$id,"aid":0,"scy":"auto","net":"tcp","type":"none","host":$add,"path":"/","tls":$tls,"sni":$add,"alpn":""}')
        echo "vmess://$(echo -n "$vmess_json" | base64 -w0)"
        ;;

      trojan:tcp|trojan:raw)  # Trojan + TCP + TLS
        local pass dom
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        echo "trojan://${pass}@${dom}:${port}?security=tls&sni=${dom}&type=tcp#$(_link_name "$tag" "$email")"
        ;;

      hysteria:hysteria)  # Hysteria2 нативный Xray
        local pass dom
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.users[]|select(.email==$e)|.password' "$XRAY_CONF")
        dom=$(kget "$tag" "domain")
        echo "hy2://${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0#$(_link_name "$tag" "$email")"
        ;;

      shadowsocks:tcp|shadowsocks:raw)  # Shadowsocks 2022
        local pass method
        pass=$(jq -r --arg t "$tag" --arg e "$email" \
            '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
        method=$(jq -r --arg t "$tag" \
            '.inbounds[]|select(.tag==$t)|.settings.method' "$XRAY_CONF")
        local sp; sp=$(kget "$tag" "serverPassword")
        # SS URI
        local userinfo; userinfo=$(echo -n "${method}:${sp}:${pass}" | base64 -w0)
        echo "ss://${userinfo}@${sip}:${port}#$(_link_name "$tag" "$email")"
        ;;

      vless:grpc_reality|vless:grpc-reality)  # VLESS + gRPC + REALITY
        local uuid sni pbk sid svc
        uuid=$(jq -r --arg t "$tag" --arg e "$email"             '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
        sid=$(kget "$tag" "shortId"); svc=$(kget "$tag" "serviceName")
        # stream-режим: клиент коннектится на внешний порт (443), не на внутренний (18443)
        local ext_port; ext_port=$(kget "$tag" "ext_port" 2>/dev/null || true)
        [[ -n "$ext_port" ]] && port="$ext_port"
        local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
        echo "vless://${uuid}@${sip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=$(urlencode "${spx}")&type=grpc&serviceName=${svc}&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      vless:splithttp)  # VLESS + SplitHTTP + TLS
        local uuid dom path_v
        uuid=$(jq -r --arg t "$tag" --arg e "$email"             '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
        dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
        local ep; ep=$(urlencode "$path_v")
        echo "vless://${uuid}@${dom}:${port}?security=tls&type=splithttp&path=${ep}&host=${dom}&sni=${dom}&encryption=none#$(_link_name "$tag" "$email")"
        ;;

      *)
        echo ""
        ;;
    esac
}

show_link_qr() {
    local tag="$1" email="$2"
    local link; link=$(gen_link "$tag" "$email")
    if [[ -z "$link" ]]; then warn "Не удалось сгенерировать ссылку для ${proto}+${net}"; return; fi
    cls; box_top " 🔗  Подключение: $(_link_name "$tag" "$email")" "$CYAN"
    box_blank
    box_row "  ${CYAN}${BOLD}Ссылка:${R}"
    # Wrap long link across lines
    local w; w=$(tw); local chunk=$((w-6)); local i=0
    while [[ $i -lt ${#link} ]]; do
        box_row "  ${DIM}${link:$i:$chunk}${R}"
        i=$((i+chunk))
    done
    box_blank
    box_row "  ${YELLOW}QR-код:${R}"
    box_end
    echo ""
    echo "$link" | qrencode -t ansiutf8 2>/dev/null || warn "qrencode не найден"
    pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  ВЫБОР ИНБАУНДА
# ──────────────────────────────────────────────────────────────────────────────

pick_inbound() {
    local __var="$1"
    local tags=()
    while IFS='|' read -r t p pr n s; do tags+=("$t|$p|$pr|$n|$s"); done < <(ib_list)
    if [[ ${#tags[@]} -eq 0 ]]; then err "Нет настроенных протоколов"; return 1; fi
    if [[ ${#tags[@]} -eq 1 ]]; then
        IFS='|' read -r t _ _ _ _ <<< "${tags[0]}"
        printf -v "$__var" '%s' "$t"; return 0
    fi
    local i=1
    for e in "${tags[@]}"; do
        IFS='|' read -r t p pr n s <<< "$e"
        local uc; uc=$(ib_users_count "$t")
        mi "$i" "🔌" "${CYAN}${t}${R}" "  порт ${p} · ${uc} польз."
        (( i++ )) || true
    done
    read -rp "$(printf "${YELLOW}›${R} Протокол: ")" idx
    [[ "$idx" -ge 1 && "$idx" -le ${#tags[@]} ]] || return 1
    IFS='|' read -r t _ _ _ _ <<< "${tags[$((idx-1))]}"
    printf -v "$__var" '%s' "$t"; return 0
}
