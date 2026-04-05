# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + TCP/RAW + REALITY
#
#  Источник: xray-examples/VLESS-TCP-XTLS-Vision-REALITY + xray-install/config.sh
#  Ключевые правила:
#    - network: "raw"  (не "tcp" — устаревшее имя в новых ядрах)
#    - realitySettings.dest (не "target" — молча игнорируется ядром)
#    - flow: "xtls-rprx-vision"  обязателен для XTLS Vision
#    - shortIds: ["", <random>]  "" разрешает клиентам с пустым shortId
#    - outbounds freedom всегда первый (без него трафик блокируется)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_tcp_reality() {
    cls; box_top " 🌐  VLESS + REALITY (TCP/RAW)" "$CYAN"
    box_blank
    box_row "  ${DIM}Не требует домена и сертификата — Reality маскирует трафик${R}"
    box_row "  ${DIM}Самый надёжный протокол против DPI${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }

    local port sni tag
    local _stream_port=""
    [[ -f /root/.xray-reality-local-port ]] && _stream_port=$(cat /root/.xray-reality-local-port)

    if [[ -n "$_stream_port" ]]; then
        port="$_stream_port"
        box_row "  ${YELLOW}ℹ Nginx stream-режим — Xray слушает на 127.0.0.1:${port}${R}"
        box_row "  ${DIM}Внешний порт: 443 (через nginx stream SNI-routing)${R}"
        box_blank
    else
        ask "Порт Xray inbound" port "443"
    fi

    ask "SNI (камуфляжный домен — должен поддерживать TLS 1.3)" sni "www.microsoft.com"
    ask "Тег" tag "vless-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local _listen_addr
    [[ -n "$_stream_port" ]] && _listen_addr="127.0.0.1" || _listen_addr="0.0.0.0"

    spin_start "Генерация ключей x25519 и shortId"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo  "$kout" | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"

    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId   "$sid";   kset "$tag" sni        "$sni"
    kset "$tag" port      "$port";  kset "$tag" type       "vless-reality"
    [[ -n "$_stream_port" ]] && kset "$tag" ext_port "443"

    local ib; ib=$(jq -n \
        --arg  tag    "$tag"         \
        --argjson port "$port"       \
        --arg  uuid   "$uuid"        \
        --arg  priv   "$priv"        \
        --arg  sni    "$sni"         \
        --arg  sid    "$sid"         \
        --arg  dest   "${sni}:443"   \
        --arg  listen "$_listen_addr" '{
        "tag":$tag, "listen":$listen, "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main","flow":"xtls-rprx-vision"}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"raw",
            "security":"reality",
            "realitySettings":{
                "show":false,
                "dest":$dest,
                "xver":0,
                "serverNames":[$sni],
                "privateKey":$priv,
                "shortIds":[$sid,""]
            }
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
    }')

    ib_add "$ib"; xray_restart

    cls; box_top " ✅  VLESS + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег:       ${CYAN}${tag}${R}"
    box_row "  Порт:      ${YELLOW}${port}${R}$( [[ -n "$_stream_port" ]] && echo "  ${DIM}(внутренний; внешний: 443)${R}" )"
    box_row "  SNI:       ${WHITE}${sni}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_row "  ShortId:   ${DIM}${sid}${R}"
    if [[ -n "$_stream_port" ]]; then
        box_blank
        box_row "  ${YELLOW}ℹ Тест задержки в клиенте покажет -1 — это нормально.${R}"
        box_row "  ${DIM}Клиент тестирует TCP:443 без Reality-рукопожатия → таймаут.${R}"
        box_row "  ${DIM}Реальный туннель работает: SNI → nginx stream → Xray → OK.${R}"
    fi
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + REALITY
#
#  Источник: xray-examples/VLESS-gRPC-REALITY
#  Используй когда TCP блокируется и нужен fallback через gRPC
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_reality() {
    cls; box_top " 🔄  VLESS + gRPC + REALITY" "$MAGENTA"
    box_blank
    box_row "  ${DIM}Reality через gRPC — обход блокировок когда TCP/RAW фильтруется${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }

    local port sni svc tag
    local _stream_port=""
    [[ -f /root/.xray-reality-local-port ]] && _stream_port=$(cat /root/.xray-reality-local-port)
    [[ -n "$_stream_port" ]] && {
        box_row "  ${YELLOW}ℹ Nginx stream — Xray слушает на 127.0.0.1:${_stream_port}${R}"; box_blank; }

    ask "Порт" port "${_stream_port:-443}"
    ask "SNI (камуфляжный домен)" sni "www.yahoo.com"
    ask "gRPC ServiceName" svc "grpc"
    ask "Тег" tag "vless-grpc-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local _listen_addr
    [[ -n "$_stream_port" ]] && _listen_addr="127.0.0.1" || _listen_addr="0.0.0.0"

    spin_start "Генерация ключей x25519"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo  "$kout" | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"

    kset "$tag" privateKey "$priv"; kset "$tag" publicKey  "$pub"
    kset "$tag" shortId   "$sid";   kset "$tag" sni         "$sni"
    kset "$tag" port      "$port";  kset "$tag" serviceName "$svc"
    kset "$tag" type "vless-grpc-reality"
    [[ -n "$_stream_port" ]] && kset "$tag" ext_port "443"

    local ib; ib=$(jq -n \
        --arg  tag    "$tag"         \
        --argjson port "$port"       \
        --arg  uuid   "$uuid"        \
        --arg  priv   "$priv"        \
        --arg  sni    "$sni"         \
        --arg  sid    "$sid"         \
        --arg  svc    "$svc"         \
        --arg  dest   "${sni}:443"   \
        --arg  listen "$_listen_addr" '{
        "tag":$tag, "listen":$listen, "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main","flow":""}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"grpc",
            "security":"reality",
            "grpcSettings":{"serviceName":$svc,"multiMode":false},
            "realitySettings":{
                "show":false,
                "dest":$dest,
                "xver":0,
                "serverNames":[$sni],
                "privateKey":$priv,
                "shortIds":[$sid,""]
            }
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
    }')

    ib_add "$ib"; xray_restart

    cls; box_top " ✅  VLESS + gRPC + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  SNI: ${WHITE}${sni}${R}  ServiceName: ${CYAN}${svc}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}  ShortId: ${DIM}${sid}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + XHTTP + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_xhttp_reality() {
    cls; box_top " ⚡  VLESS + XHTTP + REALITY" "$MAGENTA"
    box_blank
    box_row "  ${DIM}XHTTP (SplitHTTP) + Reality — меньший fingerprint чем WS${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }

    local port sni path_v tag mode_v
    local _stream_port=""
    [[ -f /root/.xray-reality-local-port ]] && _stream_port=$(cat /root/.xray-reality-local-port)
    [[ -n "$_stream_port" ]] && {
        box_row "  ${YELLOW}ℹ Nginx stream — Xray слушает на 127.0.0.1:${_stream_port}${R}"; box_blank; }

    ask "Порт" port "${_stream_port:-443}"
    ask "SNI" sni "www.microsoft.com"
    ask "Path" path_v "/"
    ask "Режим (auto/packet-up/stream-up/stream-one)" mode_v "auto"
    ask "Тег" tag "vless-xhttp"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local _listen_addr
    [[ -n "$_stream_port" ]] && _listen_addr="127.0.0.1" || _listen_addr="0.0.0.0"

    spin_start "Генерация ключей"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo  "$kout" | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"

    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId   "$sid";   kset "$tag" sni        "$sni"
    kset "$tag" port      "$port";  kset "$tag" path       "$path_v"
    kset "$tag" type "vless-xhttp"
    [[ -n "$_stream_port" ]] && kset "$tag" ext_port "443"

    local ib; ib=$(jq -n \
        --arg  tag    "$tag"         \
        --argjson port "$port"       \
        --arg  uuid   "$uuid"        \
        --arg  priv   "$priv"        \
        --arg  sni    "$sni"         \
        --arg  sid    "$sid"         \
        --arg  path   "$path_v"      \
        --arg  mode   "$mode_v"      \
        --arg  dest   "${sni}:443"   \
        --arg  listen "$_listen_addr" '{
        "tag":$tag, "listen":$listen, "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main","flow":""}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"xhttp",
            "security":"reality",
            "xhttpSettings":{"path":$path,"mode":$mode},
            "realitySettings":{
                "show":false,
                "dest":$dest,
                "xver":0,
                "serverNames":[$sni],
                "privateKey":$priv,
                "shortIds":[$sid,""]
            }
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
    }')

    ib_add "$ib"; xray_restart

    cls; box_top " ✅  VLESS + XHTTP + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  SNI: ${WHITE}${sni}${R}  Path: ${CYAN}${path_v}${R}  Режим: ${DIM}${mode_v}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + WebSocket + TLS (через nginx)
#
#  Источник: xray-examples/VLESS-WSS-Nginx
#  Архитектура: nginx:443 (TLS) → proxy_pass → Xray:127.0.0.1:PORT (no TLS)
#
#  КРИТИЧНО:
#    - Xray НЕ держит сертификат — TLS уже снят nginx
#    - "security":"none" — иначе двойной TLS → рукопожатие падает
#    - "listen":"127.0.0.1" — не слушаем на публичном интерфейсе
#    - nginx location добавляется автоматически в vpn.conf
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_ws_tls() {
    cls; box_top " ☁️  VLESS + WebSocket + TLS (через nginx)" "$BLUE"
    box_blank
    box_row "  ${CYAN}TLS терминирует nginx → Xray принимает plaintext на loopback${R}"
    box_row "  ${DIM}⚡ Рекомендуется XHTTP — WS имеет заметный ALPN-fingerprint${R}"
    box_blank
    xray_ok  || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    nginx_ok || { box_row "  ${RED}nginx vhost не найден — сначала запустите install.sh${R}"; box_end; pause; return; }

    local port path_v tag
    ask "Внутренний порт (Xray слушает на 127.0.0.1)" port "10001"
    ask "Path" path_v "/vless"
    ask "Тег" tag "vless-ws"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local dom;  dom=$(nginx_domain)
    kset "$tag" domain "${dom:-}"; kset "$tag" port "$port"
    kset "$tag" path   "$path_v";  kset "$tag" type "vless-ws"

    local ib; ib=$(jq -n \
        --arg  tag  "$tag"  \
        --argjson port "$port" \
        --arg  uuid "$uuid" \
        --arg  path "$path_v" '{
        "tag":$tag, "listen":"127.0.0.1", "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main"}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{"path":$path}
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}
    }')

    ib_add "$ib"
    nginx_add_ws_location "$path_v" "$port"
    xray_restart

    cls; box_top " ✅  VLESS + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег:         ${CYAN}${tag}${R}"
    box_row "  Внутр.порт:  ${YELLOW}${port}${R}  Path: ${WHITE}${path_v}${R}"
    [[ -n "$dom" ]] && \
        box_row "  Клиент:      ${DIM}${dom}:443${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + TLS (через nginx)
#
#  Источник: xray-examples/All-in-One (gRPC inbound секция)
#  Архитектура: nginx:443 (TLS) → grpc_pass → Xray:127.0.0.1:PORT (no TLS)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_tls() {
    cls; box_top " 🔄  VLESS + gRPC + TLS (через nginx)" "$BLUE"
    box_blank
    box_row "  ${CYAN}TLS терминирует nginx → Xray принимает plaintext gRPC на loopback${R}"
    box_blank
    xray_ok  || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    nginx_ok || { box_row "  ${RED}nginx vhost не найден — сначала запустите install.sh${R}"; box_end; pause; return; }

    local port svc tag
    ask "Внутренний порт (Xray слушает на 127.0.0.1)" port "10003"
    ask "ServiceName" svc "xray"
    ask "Тег" tag "vless-grpc"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local dom;  dom=$(nginx_domain)
    kset "$tag" domain "${dom:-}"; kset "$tag" port        "$port"
    kset "$tag" serviceName "$svc"; kset "$tag" type "vless-grpc"

    local ib; ib=$(jq -n \
        --arg  tag  "$tag"  \
        --argjson port "$port" \
        --arg  uuid "$uuid" \
        --arg  svc  "$svc"  '{
        "tag":$tag, "listen":"127.0.0.1", "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main"}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"grpc",
            "security":"none",
            "grpcSettings":{"serviceName":$svc,"multiMode":false}
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}
    }')

    ib_add "$ib"
    nginx_add_grpc_location "$svc" "$port"
    xray_restart

    cls; box_top " ✅  VLESS + gRPC + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег:         ${CYAN}${tag}${R}"
    box_row "  Внутр.порт:  ${YELLOW}${port}${R}  ServiceName: ${CYAN}${svc}${R}"
    [[ -n "$dom" ]] && \
        box_row "  Клиент:      ${DIM}${dom}:443/${svc}${R}"
    box_row "  ${DIM}nginx grpc_pass: grpc://127.0.0.1:${port} — добавлен автоматически${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + HTTPUpgrade + TLS (через nginx)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_httpupgrade_tls() {
    cls; box_top " 🔀  VLESS + HTTPUpgrade + TLS (через nginx)" "$BLUE"
    box_blank
    box_row "  ${CYAN}TLS терминирует nginx → Xray принимает HTTPUpgrade на loopback${R}"
    box_row "  ${DIM}⚡ Рекомендуется XHTTP — HTTPUpgrade имеет заметный fingerprint${R}"
    box_blank
    xray_ok  || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    nginx_ok || { box_row "  ${RED}nginx vhost не найден — сначала запустите install.sh${R}"; box_end; pause; return; }

    local port path_v tag
    ask "Внутренний порт (Xray слушает на 127.0.0.1)" port "10002"
    ask "Path" path_v "/upgrade"
    ask "Тег" tag "vless-httpupgrade"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local dom;  dom=$(nginx_domain)
    kset "$tag" domain "${dom:-}"; kset "$tag" port "$port"
    kset "$tag" path   "$path_v";  kset "$tag" type "vless-httpupgrade"

    local ib; ib=$(jq -n \
        --arg  tag   "$tag"         \
        --argjson port "$port"      \
        --arg  uuid  "$uuid"        \
        --arg  path  "$path_v"      \
        --arg  host  "${dom:-localhost}" '{
        "tag":$tag, "listen":"127.0.0.1", "port":$port, "protocol":"vless",
        "settings":{
            "clients":[{"id":$uuid,"email":"main"}],
            "decryption":"none"
        },
        "streamSettings":{
            "network":"httpupgrade",
            "security":"none",
            "httpupgradeSettings":{"path":$path,"host":$host}
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}
    }')

    ib_add "$ib"
    nginx_add_ws_location "$path_v" "$port"
    xray_restart

    cls; box_top " ✅  VLESS + HTTPUpgrade + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег:        ${CYAN}${tag}${R}"
    box_row "  Внутр.порт: ${YELLOW}${port}${R}  Path: ${WHITE}${path_v}${R}"
    [[ -n "$dom" ]] && \
        box_row "  Клиент:     ${DIM}${dom}:443${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + WebSocket + TLS (через nginx)
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_ws_tls() {
    cls; box_top " 📦  VMess + WebSocket + TLS (через nginx)" "$ORANGE"
    box_blank
    box_row "  ${CYAN}TLS терминирует nginx → Xray принимает VMess WS на loopback${R}"
    box_blank
    xray_ok  || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    nginx_ok || { box_row "  ${RED}nginx vhost не найден — сначала запустите install.sh${R}"; box_end; pause; return; }

    local port path_v tag
    ask "Внутренний порт (Xray слушает на 127.0.0.1)" port "10004"
    ask "Path" path_v "/vmess"
    ask "Тег" tag "vmess-ws"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }

    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local dom;  dom=$(nginx_domain)
    kset "$tag" domain "${dom:-}"; kset "$tag" port "$port"
    kset "$tag" path   "$path_v";  kset "$tag" type "vmess-ws"

    local ib; ib=$(jq -n \
        --arg  tag   "$tag"         \
        --argjson port "$port"      \
        --arg  uuid  "$uuid"        \
        --arg  path  "$path_v"      \
        --arg  host  "${dom:-localhost}" '{
        "tag":$tag, "listen":"127.0.0.1", "port":$port, "protocol":"vmess",
        "settings":{
            "clients":[{"id":$uuid,"email":"main","alterId":0}]
        },
        "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{"path":$path,"headers":{"Host":$host}}
        },
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}
    }')

    ib_add "$ib"
    nginx_add_ws_location "$path_v" "$port"
    xray_restart

    cls; box_top " ✅  VMess + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег:        ${CYAN}${tag}${R}"
    box_row "  Внутр.порт: ${YELLOW}${port}${R}  Path: ${WHITE}${path_v}${R}"
    [[ -n "$dom" ]] && \
        box_row "  Клиент:     ${DIM}${dom}:443${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + TCP + TLS (Xray держит TLS напрямую)
#  Не зависит от nginx. Xray сам терминирует TLS.
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_tcp_tls() {
    cls; box_top " 📦  VMess + TCP + TLS" "$ORANGE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_row "  ${DIM}Xray держит TLS напрямую — nginx не нужен для этого протокола${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vmess-tcp"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"; kset "$tag" type "vmess-tcp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg cert "$cert_p" --arg key "$key_p" --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vmess",
        "settings":{"clients":[{"id":$uuid,"email":"main","alterId":0}]},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VMess + TCP + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: Trojan + TLS (Xray держит TLS напрямую)
# ──────────────────────────────────────────────────────────────────────────────

proto_trojan_tls() {
    cls; box_top " 🔐  Trojan + TCP + TLS" "$GREEN"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "trojan"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local pass; pass=$(openssl rand -hex 16)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"; kset "$tag" type "trojan"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg pass "$pass" \
        --arg cert "$cert_p" --arg key "$key_p" --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"trojan",
        "settings":{"clients":[{"email":"main","password":$pass}]},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  Trojan + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_row "  Пароль: ${DIM}${pass}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: Shadowsocks 2022
# ──────────────────────────────────────────────────────────────────────────────

proto_shadowsocks() {
    cls; box_top " 🌑  Shadowsocks 2022" "$GRAY"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port method tag
    box_row "  Методы: 2022-blake3-aes-128-gcm / 2022-blake3-aes-256-gcm / 2022-blake3-chacha20-poly1305"
    ask "Порт" port "8388"
    ask "Метод" method "2022-blake3-aes-256-gcm"
    ask "Тег" tag "shadowsocks"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local sp; sp=$(openssl rand -base64 32)
    local up; up=$(openssl rand -base64 32)
    kset "$tag" serverPassword "$sp"; kset "$tag" port "$port"
    kset "$tag" method "$method"; kset "$tag" type "shadowsocks"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" \
        --arg method "$method" --arg sp "$sp" --arg up "$up" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"shadowsocks",
        "settings":{"method":$method,"password":$sp,
            "clients":[{"email":"main","password":$up}]},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  Shadowsocks добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Метод: ${WHITE}${method}${R}"
    box_row "  Серверный пароль: ${DIM}${sp}${R}"
    box_row "  Польз. пароль:    ${DIM}${up}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  VLESS + SplitHTTP + TLS (HTTP/3 / QUIC)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_splithttp_tls() {
    cls; box_top " 🌊  VLESS + SplitHTTP + TLS/H3" "$CYAN"
    box_blank
    box_row "  ${DIM}HTTP/3 (QUIC) напрямую или через CDN (alpn: h2,http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag alpn_mode cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/split"
    ask "Режим ALPN: [1] h3 (прямое) [2] h2,http/1.1 (CDN)" alpn_mode "1"
    ask "Тег" tag "vless-splithttp"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    local alpn_json
    [[ "$alpn_mode" == "2" ]] && alpn_json='["h2","http/1.1"]' || alpn_json='["h3"]'
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-splithttp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg dom "$dom" \
        --arg cert "$cert_p" --arg key "$key_p" \
        --argjson alpn "$alpn_json" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"id":$uuid,"email":"main"}],"decryption":"none"},
        "streamSettings":{
            "network":"splithttp","security":"tls",
            "splithttpSettings":{"path":$path,"host":$dom},
            "tlsSettings":{
                "rejectUnknownSni":true,"minVersion":"1.3",
                "alpn":$alpn,
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + SplitHTTP + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен: ${WHITE}${dom}${R}  Path: ${CYAN}${path_v}${R}"
    local alpn_label; [[ "$alpn_mode" == "2" ]] && alpn_label="h2,http/1.1 (CDN)" || alpn_label="h3 (прямое)"
    box_row "  ALPN: ${DIM}${alpn_label}${R}"
    box_blank
    [[ "$alpn_mode" != "2" ]] && box_row "  ${YELLOW}UDP/443 должен быть открыт для QUIC${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  FRAGMENT / NOISES / FALLBACKS / METRICS / BALANCER
#  (остаются без изменений — копия из оригинала)
# ──────────────────────────────────────────────────────────────────────────────

_fragment_get_freedom_tag() {
    jq -r '.outbounds[]|select(.protocol=="freedom" and (.tag=="direct" or .tag==null or .tag=="freedom"))|.tag' \
        "$XRAY_CONF" 2>/dev/null | head -1
}

_fragment_is_enabled() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && return 1
    local pkt; pkt=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.packets // ""' "$XRAY_CONF" 2>/dev/null)
    [[ -n "$pkt" ]]
}

_fragment_show_status() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { box_row "  ${RED}Freedom outbound не найден${R}"; return; }
    local pkt len inv
    pkt=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.packets // ""' "$XRAY_CONF" 2>/dev/null)
    len=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.length // ""' "$XRAY_CONF" 2>/dev/null)
    inv=$(jq -r --arg t "$tag" '.outbounds[]|select(.tag==$t)|.settings.fragment.interval // ""' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$pkt" ]]; then
        box_row "  Статус:   ${GREEN}${BOLD}● ВКЛЮЧЕНО${R}"
        box_row "  Режим:    ${CYAN}${pkt}${R}  Размер: ${YELLOW}${len:-—}${R}  Интервал: ${YELLOW}${inv:-—}${R} мс"
    else
        box_row "  Статус:   ${DIM}○ ВЫКЛЮЧЕНО${R}  (outbound: ${CYAN}${tag}${R})"
    fi
}

_fragment_enable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }
    cls; box_top " 🧩  Настройка фрагментации" "$CYAN"; box_blank
    box_row "  ${CYAN}${BOLD}Фрагментация TLS Client Hello${R}"
    box_row "  ${DIM}Разбивает первый пакет — DPI не собирает SNI${R}"
    box_blank
    mi "1" "🔐" "${CYAN}tlshello${R}  — только TLS ClientHello ${DIM}(рекомендуется)${R}"
    mi "2" "📦" "${CYAN}1-3${R}       — первые 1-3 TCP write'а"
    box_end
    read -rp "$(printf "${YELLOW}›${R} Режим [1]: ")" pkt_ch
    local packets; case "${pkt_ch:-1}" in 2) packets="1-3";; *) packets="tlshello";; esac
    local length interval
    ask "Размер фрагмента (байты, диапазон)" length "100-200"
    ask "Интервал между фрагментами (мс)"    interval "10-20"
    local frag_json; frag_json=$(jq -n \
        --arg pkt "$packets" --arg len "$length" --arg inv "$interval" \
        '{"packets":$pkt,"length":$len,"interval":$inv}')
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --argjson fr "$frag_json" \
        '(.outbounds[]|select(.tag==$t)|.settings) |= (. // {} | .fragment = $fr)' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "Фрагментация включена (режим: ${packets}, размер: ${length}, интервал: ${interval} мс)"
}

_fragment_disable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" 'del(.outbounds[]|select(.tag==$t)|.settings.fragment)' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart; ok "Фрагментация выключена"
}

menu_freedom_fragment() {
    while true; do
        cls; box_top " 🧩  Фрагментация TLS (Fragment)" "$CYAN"; box_blank
        _fragment_show_status; box_blank; box_mid
        if _fragment_is_enabled; then
            mi "1" "⏹" "${RED}Выключить${R}"; mi "2" "🔄" "Перенастроить"
        else
            mi "1" "▶" "${GREEN}Включить фрагментацию${R}"
        fi
        box_blank
        box_row "  ${DIM}Работает только для direct-трафика (freedom outbound).${R}"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        if _fragment_is_enabled; then
            case "$ch" in 1) _fragment_disable; pause;; 2) _fragment_enable; pause;; 0) return;; esac
        else
            case "$ch" in 1) _fragment_enable; pause;; 0) return;; esac
        fi
    done
}

menu_fallbacks() {
    while true; do
        cls; box_top " 🛡️  Fallbacks — защита от зондирования" "$YELLOW"; box_blank
        box_row "  ${YELLOW}⚠  Работает только с: VLESS+TCP+TLS и Trojan+TCP+TLS${R}"
        box_blank; box_mid
        mi "1" "➕" "Добавить fallback к протоколу"
        mi "2" "📋" "Показать текущие fallbacks"
        mi "3" "🗑" "Удалить все fallbacks у протокола"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in 1) fallback_add;; 2) fallback_show;; 3) fallback_clear;; 0) return;; esac
    done
}

fallback_add() {
    cls; box_top " ➕  Добавить fallback" "$YELLOW"; box_blank
    local eligible=()
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] && eligible+=("$tag")
    done < <(ib_list)
    if [[ ${#eligible[@]} -eq 0 ]]; then
        box_row "  ${RED}Нет подходящих протоколов (нужен VLESS или Trojan + TCP + TLS)${R}"
        box_end; pause; return
    fi
    local tag
    if [[ ${#eligible[@]} -eq 1 ]]; then
        tag="${eligible[0]}"; box_row "  Протокол: ${CYAN}${tag}${R}"
    else
        local i=1; for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)) || true; done
        box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx; tag="${eligible[$((idx-1))]}"
    fi
    box_blank
    local dest sni_match alpn_match path_match
    ask "Dest (порт или addr:port)" dest "80"
    ask "SNI (пусто = любой)" sni_match ""
    ask "ALPN (h2/http/1.1, пусто = любой)" alpn_match ""
    ask "Path (пусто = любой)" path_match ""
    local fb_obj; fb_obj=$(jq -n \
        --arg dest "$dest" --arg name "$sni_match" \
        --arg alpn "$alpn_match" --arg path "$path_match" \
        '{dest: (if ($dest|test("^[0-9]+$")) then ($dest|tonumber) else $dest end)}
         + (if $name != "" then {name: $name} else {} end)
         + (if $alpn != "" then {alpn: $alpn} else {} end)
         + (if $path != "" then {path: $path} else {} end)')
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --argjson fb "$fb_obj" \
        '(.inbounds[]|select(.tag==$t)|.settings.fallbacks) |= (. // [] | . + [$fb])
         | (.inbounds[]|select(.tag==$t)|.streamSettings.tlsSettings.alpn) |=
             if (. == null or (map(select(. == "http/1.1")) | length) == 0)
             then (. // []) + ["http/1.1"] else . end' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart; ok "Fallback добавлен: → ${dest}"; pause
}

fallback_show() {
    cls; box_top " 📋  Текущие fallbacks" "$YELLOW"; box_blank
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] || continue
        local fallbacks; fallbacks=$(jq -r --arg t "$tag" \
            '.inbounds[]|select(.tag==$t)|.settings.fallbacks[]?|
             "  dest=\(.dest) name=\(.name//"*") alpn=\(.alpn//"*") path=\(.path//"*")"' \
            "$XRAY_CONF" 2>/dev/null)
        if [[ -n "$fallbacks" ]]; then
            box_row "  ${CYAN}${tag}${R}"
            while IFS= read -r line; do box_row "$line"; done <<< "$fallbacks"
            box_blank
        fi
    done < <(ib_list)
    box_end; pause
}

fallback_clear() {
    cls; box_top " 🗑  Удалить fallbacks" "$RED"; box_blank
    local eligible=()
    while IFS='|' read -r tag _ proto net sec; do
        [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]] && eligible+=("$tag")
    done < <(ib_list)
    [[ ${#eligible[@]} -eq 0 ]] && { box_row "  ${DIM}Нет подходящих протоколов${R}"; box_end; pause; return; }
    local i=1; for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)) || true; done
    box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
    local tag="${eligible[$((idx-1))]}"
    confirm "Удалить все fallbacks у '${tag}'?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --arg t "$tag" 'del(.inbounds[]|select(.tag==$t)|.settings.fallbacks)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        xray_restart; ok "Fallbacks удалены"
    }
    pause
}

menu_metrics() {
    cls; box_top " 📈  Metrics Endpoint" "$BLUE"; box_blank
    local cur_metrics; cur_metrics=$(jq -r '.metrics.listen // ""' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$cur_metrics" ]]; then
        box_row "  ${GREEN}● Metrics включён:${R} ${CYAN}http://${cur_metrics}/debug/vars${R}"
        box_blank; mi "1" "🔄" "Изменить порт"; mi "2" "🗑" "Отключить"; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            2) local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
               jq 'del(.metrics)' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
               xray_restart; ok "Metrics отключён"; pause; return;;
            0) return;;
        esac
    fi
    local port; ask "Порт Metrics" port "11111"
    local listen="127.0.0.1:${port}"
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg l "$listen" '.metrics = {"tag":"metrics_out","listen":$l}' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    local has_m; has_m=$(jq -r '.outbounds[]|select(.tag=="metrics_out")|.tag' "$XRAY_CONF" 2>/dev/null)
    if [[ -z "$has_m" ]]; then
        local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
        jq '.outbounds += [{"tag":"metrics_out","protocol":"blackhole"}]' \
            "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
    fi
    xray_restart
    cls; box_top " ✅  Metrics включён" "$GREEN"; box_blank
    box_row "  URL: ${CYAN}http://${listen}/debug/vars${R}"
    box_row "  ${DIM}curl -s http://${listen}/debug/vars | python3 -m json.tool${R}"
    box_blank; box_end; pause
}

menu_hysteria_outbound() {
    cls; box_top " 🚀  Hysteria2 Outbound (relay)" "$GREEN"; box_blank
    local addr port pass tag sni up_mbps dn_mbps allow_insecure
    ask "Адрес сервера" addr ""; ask "Порт" port "443"
    ask "Пароль" pass ""; ask "SNI" sni "$addr"; ask "Тег" tag "hy2-relay"
    [[ -z "$addr" || -z "$pass" ]] && { err "Адрес и пароль обязательны"; pause; return; }
    mi "1" "🔵" "BBR (0) — стандартный"; mi "2" "🔴" "Brutal — задать Mbps"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " spd_ch
    if [[ "$spd_ch" == "2" ]]; then
        ask "Download Mbps" dn_mbps "100"; ask "Upload Mbps" up_mbps "50"
    else up_mbps="0"; dn_mbps="0"; fi
    allow_insecure="false"
    confirm "Разрешить небезопасный TLS?" "n" && allow_insecure="true"
    local out_json; out_json=$(jq -n \
        --arg tag "$tag" --arg addr "$addr" --argjson port "$port" \
        --arg pass "$pass" --arg sni "$sni" --arg up "$up_mbps" \
        --arg dn "$dn_mbps" --argjson ins "$allow_insecure" '{
        "tag":$tag,"protocol":"hysteria",
        "settings":{"address":$addr,"port":$port},
        "streamSettings":{"network":"hysteria","security":"tls",
            "tlsSettings":{"serverName":$sni,"allowInsecure":$ins,"alpn":["h3"]},
            "hysteriaSettings":{"version":2,"auth":$pass,"up":$up,"down":$dn}}}')
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson ob "$out_json" '.outbounds += [$ob]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    cls; box_top " ✅  Hysteria2 Outbound добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Сервер: ${WHITE}${addr}:${port}${R}"
    box_blank; box_end; pause
}
