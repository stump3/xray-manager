# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + TCP + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_tcp_reality() {
    cls; box_top " 🌐  VLESS + TCP + REALITY" "$CYAN"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni tag
    # stream-режим: читаем сохранённый внутренний порт
    local _stream_port=""
    [[ -f /root/.xray-reality-local-port ]] && _stream_port=$(cat /root/.xray-reality-local-port)
    [[ -n "$_stream_port" ]] && {
        box_row "  ${YELLOW}ℹ Nginx stream — Xray слушает на 127.0.0.1:${_stream_port}${R}"; box_blank; }
    ask "Порт (Xray inbound)" port "${_stream_port:-443}"
    ask "SNI (камуфляжный домен)" sni "www.microsoft.com"
    ask "Тег (уникальный ID)" tag "vless-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local _listen_addr; [[ -n "$_stream_port" ]] && _listen_addr="127.0.0.1" || _listen_addr="0.0.0.0"
    spin_start "Генерация ключей x25519"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo "$kout" | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid"; kset "$tag" sni "$sni"
    kset "$tag" port "$port"; kset "$tag" type "vless-reality"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" \
        --arg listen "$_listen_addr" '{
        "tag":$tag,"listen":$listen,"port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":"xtls-rprx-vision"}],"decryption":"none"},
        "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
            "show":false,"target":($sni+":443"),"xver":0,
            "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + TCP + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_row "  ShortId:   ${DIM}${sid}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + XHTTP + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_xhttp_reality() {
    cls; box_top " ⚡  VLESS + XHTTP + REALITY" "$MAGENTA"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni path_v tag mode_v
    ask "Порт" port "443"
    ask "SNI" sni "www.microsoft.com"
    ask "Path" path_v "/"
    ask "Режим (auto/packet-up/stream-up/stream-one)" mode_v "auto"
    ask "Тег" tag "vless-xhttp"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    spin_start "Генерация ключей"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo "$kout" | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid"; kset "$tag" sni "$sni"
    kset "$tag" port "$port"; kset "$tag" path "$path_v"
    kset "$tag" type "vless-xhttp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" \
        --arg path "$path_v" --arg mode "$mode_v" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":""}],"decryption":"none"},
        "streamSettings":{"network":"xhttp","security":"reality",
            "xhttpSettings":{"path":$path,"mode":$mode},
            "realitySettings":{"show":false,"target":($sni+":443"),"xver":0,
                "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + XHTTP + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  Path: ${WHITE}${path_v}${R}  Режим: ${CYAN}${mode_v}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + WebSocket + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_ws_tls() {
    cls; box_top " ☁️  VLESS + WebSocket + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_row "  ${DIM}⚡ Рекомендуется перейти на XHTTP — WebSocket имеет заметный ALPN-отпечаток (http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт (Xray слушает)" port "8443"
    ask "Домен" dom ""
    ask "Path" path_v "/vless"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-ws"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-ws"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"ws","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "wsSettings":{"path":$path}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_row "  Path: ${WHITE}${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_tls() {
    cls; box_top " 🔄  VLESS + gRPC + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom svc tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "ServiceName" svc "xray"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-grpc"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" serviceName "$svc"; kset "$tag" type "vless-grpc"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg svc "$svc" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"grpc","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "grpcSettings":{"serviceName":$svc,"multiMode":false}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + gRPC + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}"
    box_row "  Домен: ${WHITE}${dom}${R}  ServiceName: ${CYAN}${svc}${R}"
    box_blank
    box_row "  ${YELLOW}Nginx (grpc_pass):${R}"
    box_row "  ${DIM}grpc_pass grpc://127.0.0.1:${port};${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + HTTPUpgrade + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_httpupgrade_tls() {
    cls; box_top " 🔀  VLESS + HTTPUpgrade + TLS" "$BLUE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_row "  ${DIM}⚡ Рекомендуется перейти на XHTTP — HTTPUpgrade имеет заметный ALPN-отпечаток (http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/upgrade"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vless-httpupgrade"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-httpupgrade"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{"network":"httpupgrade","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "httpupgradeSettings":{"path":$path,"host":$sni}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + HTTPUpgrade + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Path: ${WHITE}${path_v}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + WS + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_ws_tls() {
    cls; box_top " 📦  VMess + WebSocket + TLS" "$ORANGE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/vmess"
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    ask "Тег" tag "vmess-ws"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vmess-ws"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg cert "$cert_p" --arg key "$key_p" \
        --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vmess",
        "settings":{"clients":[{"email":"main","id":$uuid,"alterId":0}]},
        "streamSettings":{"network":"ws","security":"tls",
            "tlsSettings":{"serverName":$sni,"alpn":["h2","http/1.1"],
                "certificates":[{"certificateFile":$cert,"keyFile":$key}]},
            "wsSettings":{"path":$path,"headers":{"Host":$sni}}},
        "sniffing":{"enabled":true,"destOverride":["http","tls"]}}')
    cert_check "$cert_p" "$key_p" || { pause; return; }
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VMess + WS + TLS добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  Домен: ${WHITE}${dom}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VMess + TCP + TLS
# ──────────────────────────────────────────────────────────────────────────────

proto_vmess_tcp_tls() {
    cls; box_top " 📦  VMess + TCP + TLS" "$ORANGE"
    box_blank
    box_row "  ${YELLOW}⚠  Требуется домен с TLS-сертификатом${R}"
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
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" type "vmess-tcp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg cert "$cert_p" --arg key "$key_p" --arg sni "$dom" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vmess",
        "settings":{"clients":[{"email":"main","id":$uuid,"alterId":0}]},
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
#  ПРОТОКОЛ: Trojan + TLS
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
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" type "trojan"
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
    box_row "  Методы: 2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305"
    ask "Порт" port "8388"
    ask "Метод" method "2022-blake3-aes-256-gcm"
    ask "Тег" tag "shadowsocks"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    # Генерация сервер-пароля (base64, 32 bytes для 256-gcm)
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
    box_row "  Пользов. пароль:  ${DIM}${up}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  FREEDOM + FRAGMENT (обход фрагментацией TLS)
# ──────────────────────────────────────────────────────────────────────────────

# ── Fragment helpers ─────────────────────────────────────────────────────────

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
        box_row "  Статус:    ${GREEN}${BOLD}● ВКЛЮЧЕНО${R}"
        box_row "  Outbound:  ${CYAN}${tag}${R}"
        box_row "  Режим:     ${CYAN}${pkt}${R}"
        box_row "  Размер:    ${YELLOW}${len:-—}${R} байт"
        box_row "  Интервал:  ${YELLOW}${inv:-—}${R} мс"
    else
        box_row "  Статус:    ${DIM}○ ВЫКЛЮЧЕНО${R}"
        box_row "  Outbound:  ${CYAN}${tag}${R}"
    fi
}

_fragment_enable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }

    cls; box_top " 🧩  Настройка фрагментации" "$CYAN"; box_blank
    box_row "  ${CYAN}${BOLD}Фрагментация TLS Client Hello${R}"
    box_row "  ${DIM}Разбивает первый пакет на куски — DPI не собирает SNI${R}"
    box_blank
    box_row "  ${YELLOW}Режим пакетов:${R}"
    mi "1" "🔐" "${CYAN}tlshello${R}  — только TLS ClientHello  ${DIM}(рекомендуется)${R}"
    mi "2" "📦" "${CYAN}1-3${R}       — первые 1-3 TCP write'а"
    box_end

    read -rp "$(printf "${YELLOW}›${R} Режим [1]: ")" pkt_ch
    local packets
    case "${pkt_ch:-1}" in
        2) packets="1-3" ;;
        *) packets="tlshello" ;;
    esac

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
    ok "Фрагментация включена  (режим: ${packets}, размер: ${length}, интервал: ${interval} мс)"
}

_fragment_disable() {
    local tag; tag=$(_fragment_get_freedom_tag)
    [[ -z "$tag" ]] && { err "Freedom outbound не найден"; return 1; }
    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" 'del(.outbounds[]|select(.tag==$t)|.settings.fragment)' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
    xray_restart
    ok "Фрагментация выключена"
}

menu_freedom_fragment() {
    while true; do
        cls; box_top " 🧩  Фрагментация TLS (Fragment)" "$CYAN"
        box_blank
        _fragment_show_status
        box_blank
        box_mid

        if _fragment_is_enabled; then
            mi "1" "⏹" "${RED}Выключить фрагментацию${R}"
            mi "2" "🔄" "Перенастроить (изменить параметры)"
        else
            mi "1" "▶" "${GREEN}Включить фрагментацию${R}"
        fi

        box_blank
        box_row "  ${DIM}Работает только для direct-трафика (freedom outbound).${R}"
        box_row "  ${DIM}VLESS/VMess/Trojan используют собственный транспорт.${R}"
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch
        if _fragment_is_enabled; then
            case "$ch" in
                1) _fragment_disable; pause ;;
                2) _fragment_enable;  pause ;;
                0) return ;;
            esac
        else
            case "$ch" in
                1) _fragment_enable; pause ;;
                0) return ;;
            esac
        fi
    done
}

menu_freedom_noises() {
    cls; box_top " 🔊  Freedom outbound + Noises (UDP шум)" "$MAGENTA"
    box_blank
    box_row "  ${CYAN}${BOLD}UDP Noise — отправка случайных пакетов перед соединением${R}"
    box_row "  ${DIM}Маскирует начало UDP-потока под случайный трафик${R}"
    box_blank
    box_row "  ${YELLOW}⚠  Порт 53 (DNS) автоматически исключается${R}"
    box_blank

    local noise_type noise_size noise_delay
    box_row "  Тип пакета:"
    mi "1" "🎲" "rand   — случайные байты"
    mi "2" "📝" "str    — строка"
    mi "3" "📦" "base64 — бинарные данные (base64)"
    box_end
    read -rp "$(printf "${YELLOW}›${R} Тип [1]: ")" type_ch
    type_ch="${type_ch:-1}"
    case "$type_ch" in
        2) noise_type="str"; ask "Строка" noise_size "hello" ;;
        3) noise_type="base64"; ask "Base64 данные" noise_size "7nQBAAABAAAAAAAABnQtcmluZwZtc2VkZ2UDbmV0AAABAAE=" ;;
        *) noise_type="rand"; ask "Размер (байты или диапазон)" noise_size "50-100" ;;
    esac
    ask "Задержка после пакета (мс, диапазон)" noise_delay "10-20"

    local noise_json; noise_json=$(jq -n \
        --arg t "$noise_type" --arg p "$noise_size" --arg d "$noise_delay" \
        '[{"type":$t,"packet":$p,"delay":$d}]')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    local has_freedom; has_freedom=$(jq -r '.outbounds[]|select(.protocol=="freedom" and (.tag=="direct" or .tag==null))|.tag' "$XRAY_CONF" 2>/dev/null | head -1)

    if [[ -n "$has_freedom" ]]; then
        jq --arg t "${has_freedom:-direct}" --argjson nz "$noise_json" \
            '(.outbounds[]|select(.protocol=="freedom" and .tag==$t)|.settings) |= (. // {} | .noises = $nz)' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        ok "Noises добавлен к outbound '${has_freedom:-direct}'"
    else
        warn "Freedom outbound не найден"
    fi

    xray_restart
    cls; box_top " ✅  Noises настроен" "$GREEN"; box_blank
    box_row "  Тип:      ${CYAN}${noise_type}${R}"
    box_row "  Данные:   ${DIM}${noise_size}${R}"
    box_row "  Задержка: ${YELLOW}${noise_delay}${R} мс"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  FALLBACKS (защита от зондирования)
# ──────────────────────────────────────────────────────────────────────────────

menu_fallbacks() {
    while true; do
        cls; box_top " 🛡️  Fallbacks — защита от зондирования" "$YELLOW"
        box_blank
        box_row "  ${CYAN}${BOLD}Что это:${R}"
        box_row "  ${DIM}Если кто-то подключается без правильного протокола — вместо разрыва${R}"
        box_row "  ${DIM}соединение перенаправляется на реальный сайт. Прокси не детектируется.${R}"
        box_blank
        box_row "  ${YELLOW}⚠  Работает только с: VLESS+TCP+TLS и Trojan+TCP+TLS${R}"
        box_row "  ${DIM}   Не работает с REALITY, WebSocket, gRPC, XHTTP${R}"
        box_blank

        # Показать текущие fallbacks
        local has_fb=0
        while IFS='|' read -r tag _ proto net sec; do
            if [[ ("$proto" == "vless" || "$proto" == "trojan") && "$net" == "tcp" && "$sec" == "tls" ]]; then
                local fb_count; fb_count=$(jq --arg t "$tag" \
                    '.inbounds[]|select(.tag==$t)|.settings.fallbacks|length' "$XRAY_CONF" 2>/dev/null || echo 0)
                if [[ "$fb_count" -gt 0 ]]; then
                    box_row "  ${GREEN}✓${R} ${CYAN}${tag}${R}: ${fb_count} fallback(s) настроено"
                    has_fb=1
                else
                    box_row "  ${DIM}○ ${tag}: нет fallbacks${R}"
                fi
            fi
        done < <(ib_list)
        box_blank; box_mid
        mi "1" "➕" "Добавить fallback к протоколу"
        mi "2" "📋" "Показать текущие fallbacks"
        mi "3" "🗑" "Удалить все fallbacks у протокола"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) fallback_add ;;
            2) fallback_show ;;
            3) fallback_clear ;;
            0) return ;;
        esac
    done
}

fallback_add() {
    cls; box_top " ➕  Добавить fallback" "$YELLOW"; box_blank

    # Выбрать подходящий inbound
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
        tag="${eligible[0]}"
        box_row "  Протокол: ${CYAN}${tag}${R}"
    else
        local i=1
        for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)); done
        box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
        tag="${eligible[$((idx-1))]}"
    fi
    box_blank

    box_row "  ${YELLOW}Куда перенаправлять (dest):${R}"
    box_row "  ${DIM}Формат: порт (напр. 80) или адрес:порт (напр. 127.0.0.1:8080)${R}"

    local dest sni_match alpn_match path_match
    ask "Dest (порт или addr:port)" dest "80"
    ask "SNI для совпадения (пусто = любой)" sni_match ""
    ask "ALPN для совпадения (h2 / http/1.1, пусто = любой)" alpn_match ""
    ask "Path для совпадения (пусто = любой)" path_match ""

    local fb_obj; fb_obj=$(jq -n \
        --arg dest "$dest" \
        --arg name "$sni_match" \
        --arg alpn "$alpn_match" \
        --arg path "$path_match" \
        '{dest: (if ($dest|test("^[0-9]+$")) then ($dest|tonumber) else $dest end)}
        + (if $name != "" then {name: $name} else {} end)
        + (if $alpn != "" then {alpn: $alpn} else {} end)
        + (if $path != "" then {path: $path} else {} end)')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg t "$tag" --argjson fb "$fb_obj" \
        '(.inbounds[]|select(.tag==$t)|.settings.fallbacks) |= (. // [] | . + [$fb])
         | (.inbounds[]|select(.tag==$t)|.streamSettings.tlsSettings.alpn) |=
             if (. == null or (map(select(. == "http/1.1")) | length) == 0)
             then (. // []) + ["http/1.1"]
             else . end' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Fallback добавлен: → ${dest}"
    pause
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
    local i=1
    for t in "${eligible[@]}"; do mi "$i" "🔌" "$t"; ((i++)); done
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

# ──────────────────────────────────────────────────────────────────────────────
#  METRICS ENDPOINT
# ──────────────────────────────────────────────────────────────────────────────

menu_metrics() {
    cls; box_top " 📈  Metrics Endpoint" "$BLUE"
    box_blank
    box_row "  ${CYAN}${BOLD}HTTP JSON статистика — альтернатива Stats API${R}"
    box_row "  ${DIM}Слушает 127.0.0.1:PORT → /debug/vars (JSON) + /debug/pprof${R}"
    box_blank

    local cur_metrics; cur_metrics=$(jq -r '.metrics.listen // ""' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$cur_metrics" ]]; then
        box_row "  ${GREEN}● Metrics уже включён:${R} ${CYAN}http://${cur_metrics}/debug/vars${R}"
        box_blank
        mi "1" "🔄" "Изменить порт"
        mi "2" "🗑" "Отключить"
        mi "0" "◀" "Назад"
        box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) ;;
            2)
                local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
                jq 'del(.metrics)' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
                xray_restart; ok "Metrics отключён"; pause; return ;;
            0) return ;;
        esac
    fi

    local port; ask "Порт Metrics" port "11111"
    local listen="127.0.0.1:${port}"

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg l "$listen" '.metrics = {"tag":"metrics_out","listen":$l}' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    # Добавить outbound для metrics если нет
    local has_m; has_m=$(jq -r '.outbounds[]|select(.tag=="metrics_out")|.tag' "$XRAY_CONF" 2>/dev/null)
    if [[ -z "$has_m" ]]; then
        local tmp2; tmp2=$(mktemp); _TMPFILES+=("$tmp2")
        jq '.outbounds += [{"tag":"metrics_out","protocol":"blackhole"}]' \
            "$XRAY_CONF" > "$tmp2" && mv "$tmp2" "$XRAY_CONF"
    fi

    xray_restart
    cls; box_top " ✅  Metrics включён" "$GREEN"; box_blank
    box_row "  URL: ${CYAN}http://${listen}/debug/vars${R}"
    box_blank
    box_row "  ${YELLOW}Эндпоинты:${R}"
    box_row "  ${DIM}/debug/vars     — JSON статистика (inbound/outbound/user трафик)${R}"
    box_row "  ${DIM}/debug/pprof/   — профилировщик Go (память, CPU, горутины)${R}"
    box_blank
    box_row "  ${YELLOW}Пример запроса:${R}"
    box_row "  ${DIM}curl -s http://${listen}/debug/vars | python3 -m json.tool${R}"
    box_blank
    box_row "  ${YELLOW}Разница с Stats API:${R}"
    box_row "  ${DIM}Stats API → gRPC на :${STATS_PORT} → xray api statsquery${R}"
    box_row "  ${DIM}Metrics   → HTTP JSON на :${port} → curl / Grafana / Netdata${R}"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  HYSTERIA2 OUTBOUND (клиентский режим — relay/цепочка)
# ──────────────────────────────────────────────────────────────────────────────

menu_hysteria_outbound() {
    cls; box_top " 🚀  Hysteria2 Outbound (relay / цепочка)" "$GREEN"
    box_blank
    box_row "  ${CYAN}${BOLD}Этот VPS подключается к другому Hysteria2-серверу${R}"
    box_blank
    box_row "  ${YELLOW}Схема:${R}"
    box_row "  ${DIM}Клиент → [VLESS/REALITY → этот VPS] → [Hysteria2 → VPS2] → интернет${R}"
    box_blank
    box_row "  ${YELLOW}Требует:${R} Hysteria2-сервер на другом VPS (меню 7 или меню 10)${R}"
    box_blank

    # Показать существующие Hysteria outbounds
    local existing; existing=$(jq -r '.outbounds[]|select(.protocol=="hysteria")|.tag' "$XRAY_CONF" 2>/dev/null)
    if [[ -n "$existing" ]]; then
        box_row "  ${YELLOW}Существующие Hysteria outbounds:${R}"
        while IFS= read -r t; do box_row "    ${CYAN}${t}${R}"; done <<< "$existing"
        box_blank
    fi
    box_end

    local addr port pass tag up_mbps dn_mbps sni insecure
    ask "Адрес сервера (домен или IP)" addr ""
    ask "Порт"                         port "443"
    ask "Пароль (от удалённого сервера)" pass ""
    ask "SNI (домен сертификата)"      sni  "$addr"
    ask "Тег outbound"                 tag  "hy2-relay"

    [[ -z "$addr" || -z "$pass" ]] && { err "Адрес и пароль обязательны"; pause; return; }

    box_blank
    box_row "  ${YELLOW}Алгоритм скорости:${R}"
    mi "1" "🔵" "BBR (0) — стандартный"
    mi "2" "🔴" "Brutal — задать Mbps"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " spd_ch
    if [[ "$spd_ch" == "2" ]]; then
        ask "Download Mbps" dn_mbps "100"
        ask "Upload Mbps"   up_mbps "50"
    else
        up_mbps="0"; dn_mbps="0"
    fi

    local allow_insecure="false"
    confirm "Разрешить небезопасный TLS (если нет валидного сертификата)?" "n" && allow_insecure="true"

    local out_json; out_json=$(jq -n \
        --arg tag "$tag" \
        --arg addr "$addr" \
        --argjson port "$port" \
        --arg pass "$pass" \
        --arg sni "$sni" \
        --arg up "$up_mbps" \
        --arg dn "$dn_mbps" \
        --argjson ins "$allow_insecure" \
        '{
            "tag": $tag,
            "protocol": "hysteria",
            "settings": {
                "address": $addr,
                "port": $port
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": $sni,
                    "allowInsecure": $ins,
                    "alpn": ["h3"]
                },
                "hysteriaSettings": {
                    "version": 2,
                    "auth": $pass,
                    "up": $up,
                    "down": $dn
                }
            }
        }')

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson ob "$out_json" '.outbounds += [$ob]' \
        "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    cls; box_top " ✅  Hysteria2 Outbound добавлен" "$GREEN"; box_blank
    box_row "  Тег:    ${CYAN}${tag}${R}"
    box_row "  Сервер: ${WHITE}${addr}:${port}${R}"
    box_row "  SNI:    ${DIM}${sni}${R}"
    box_blank
    box_row "  ${YELLOW}Следующий шаг — добавить routing-правило:${R}"
    box_row "  ${DIM}Настройки → Маршрутизация → направить нужный трафик на '${tag}'${R}"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  БАЛАНСИРОВЩИК НАГРУЗКИ + OBSERVATORY
# ──────────────────────────────────────────────────────────────────────────────

menu_balancer() {
    while true; do
        cls; box_top " ⚖️  Балансировщик нагрузки" "$MAGENTA"
        box_blank
        box_row "  ${CYAN}${BOLD}Автоматический выбор лучшего outbound${R}"
        box_row "  ${DIM}Observatory пингует серверы → Balancer выбирает быстрейший${R}"
        box_blank

        # Текущее состояние
        local obs_url; obs_url=$(jq -r '.observatory.probeUrl // ""' "$XRAY_CONF" 2>/dev/null)
        local bal_count; bal_count=$(jq '.balancers|length // 0' "$XRAY_CONF" 2>/dev/null || echo 0)
        if [[ -n "$obs_url" ]]; then
            box_row "  ${GREEN}● Observatory:${R} ping → ${DIM}${obs_url}${R}"
            box_row "  ${GREEN}● Balancers:${R} ${CYAN}${bal_count}${R} настроено"
        else
            box_row "  ${DIM}○ Observatory не настроен${R}"
        fi

        box_blank; box_mid
        mi "1" "🔭" "Настроить Observatory (мониторинг)"
        mi "2" "⚖️ " "Добавить балансировщик"
        mi "3" "🗑" "Удалить балансировщик"
        mi "4" "📋" "Показать текущие балансировщики"
        mi "5" "📊" "Результаты Observatory"
        box_mid; mi "0" "◀" "Назад"; box_end
        read -rp "$(printf "${YELLOW}›${R} ") " ch
        case "$ch" in
            1) balancer_setup_observatory ;;
            2) balancer_add ;;
            3) balancer_del ;;
            4) balancer_show ;;
            5) balancer_results ;;
            0) return ;;
        esac
    done
}

balancer_setup_observatory() {
    cls; box_top " 🔭  Observatory — мониторинг outbounds" "$BLUE"; box_blank

    local probe_url probe_interval
    ask "URL для пинга" probe_url "https://www.google.com/generate_204"
    ask "Интервал проверки (напр. 30s, 5m)" probe_interval "30s"

    local selector_prefix
    ask "Префикс тегов для мониторинга (пусто = все)" selector_prefix "out-"

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg url "$probe_url" \
       --arg inv "$probe_interval" \
       --arg sel "$selector_prefix" \
       '.observatory = {
           "subjectSelector": (if $sel != "" then [$sel] else [""] end),
           "probeUrl": $url,
           "probeInterval": $inv,
           "enableConcurrency": false
       }' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Observatory настроен — пингует каждые ${probe_interval}"
    pause
}

balancer_add() {
    cls; box_top " ➕  Добавить балансировщик" "$MAGENTA"; box_blank

    # Показать outbounds
    local outbounds; outbounds=$(jq -r '.outbounds[].tag' "$XRAY_CONF" 2>/dev/null)
    box_row "  ${YELLOW}Доступные outbounds:${R}"
    while IFS= read -r t; do [[ "$t" != "direct" && "$t" != "block" && "$t" != "api" ]] && box_row "    ${CYAN}${t}${R}"; done <<< "$outbounds"
    box_blank

    local tag selector strategy
    ask "Тег балансировщика"       tag      "lb-main"
    ask "Префикс тегов outbounds"  selector "out-"
    box_blank
    box_row "  Стратегия:"
    mi "1" "🎲" "random    — случайный"
    mi "2" "🔄" "roundRobin — по очереди"
    mi "3" "⚡" "leastPing  — наименьшая задержка ${DIM}(нужен Observatory)${R}"
    mi "4" "📊" "leastLoad  — наименьшая нагрузка ${DIM}(нужен Observatory)${R}"
    box_end
    read -rp "$(printf "${YELLOW}›${R} ") " strat_ch
    case "$strat_ch" in
        2) strategy="roundRobin" ;;
        3) strategy="leastPing" ;;
        4) strategy="leastLoad" ;;
        *) strategy="random" ;;
    esac

    local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg tag "$tag" --arg sel "$selector" --arg strat "$strategy" '
        if .routing.balancers == null then .routing.balancers = [] else . end |
        .routing.balancers += [{
            "tag": $tag,
            "selector": [$sel],
            "strategy": {"type": $strat}
        }]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"

    xray_restart
    ok "Балансировщик '${tag}' добавлен (стратегия: ${strategy})"
    box_blank
    box_row "  ${YELLOW}Использование в routing:${R}"
    box_row "  ${DIM}{\"inboundTag\":[\"your-inbound\"],\"balancerTag\":\"${tag}\"}${R}"
    pause
}

balancer_del() {
    cls; box_top " 🗑  Удалить балансировщик" "$RED"; box_blank
    local bals; bals=$(jq -r '.routing.balancers[]?.tag' "$XRAY_CONF" 2>/dev/null)
    [[ -z "$bals" ]] && { box_row "  ${DIM}Нет балансировщиков${R}"; box_end; pause; return; }
    local i=1; local -a btags=()
    while IFS= read -r t; do mi "$i" "⚖️ " "$t"; btags+=("$t"); ((i++)); done <<< "$bals"
    box_end; read -rp "$(printf "${YELLOW}›${R} ") " idx
    local sel_tag="${btags[$((idx-1))]}"
    confirm "Удалить балансировщик '${sel_tag}'?" && {
        local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
        jq --arg t "$sel_tag" 'del(.routing.balancers[]|select(.tag==$t))' \
            "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
        xray_restart; ok "Удалён"
    }
    pause
}

balancer_show() {
    cls; box_top " 📋  Балансировщики" "$MAGENTA"; box_blank
    local info; info=$(jq -r '.routing.balancers[]? |
        "  \(.tag)  стратегия: \(.strategy.type//"random")  selector: \(.selector|join(","))"' \
        "$XRAY_CONF" 2>/dev/null)
    [[ -z "$info" ]] && info="  (нет балансировщиков)"
    while IFS= read -r line; do box_row "$line"; done <<< "$info"
    box_blank; box_end; pause
}

balancer_results() {
    cls; box_top " 📊  Результаты Observatory" "$BLUE"; box_blank
    xray_active || { box_row "  ${RED}Xray не запущен${R}"; box_end; pause; return; }
    local obs; obs=$("$XRAY_BIN" api statsonline --server="127.0.0.1:${STATS_PORT}" 2>/dev/null || echo "")
    if [[ -z "$obs" ]]; then
        box_row "  ${DIM}Данные Observatory недоступны через Stats API${R}"
        box_row "  ${DIM}Включите Metrics endpoint для просмотра результатов Observatory${R}"
        box_row "  ${DIM}curl -s http://127.0.0.1:11111/debug/vars | python3 -m json.tool${R}"
    fi
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + gRPC + REALITY
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_grpc_reality() {
    cls; box_top " 🔄  VLESS + gRPC + REALITY" "$MAGENTA"
    box_blank
    box_row "  ${DIM}Не требует домена и сертификата — REALITY камуфлирует трафик${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port sni svc tag
    ask "Порт" port "443"
    ask "SNI (камуфляжный домен)" sni "www.yahoo.com"
    ask "gRPC ServiceName" svc "grpc"
    ask "Тег" tag "vless-grpc-reality"
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    spin_start "Генерация ключей x25519"
    local kout; kout=$("$XRAY_BIN" x25519 2>/dev/null)
    local priv; priv=$(echo "$kout" | grep -i 'private' | awk '{print $NF}')
    local pub;  pub=$(echo "$kout"  | grep -i 'public'  | awk '{print $NF}')
    local sid;  sid=$(openssl rand -hex 8)
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    spin_stop "ok"
    kset "$tag" privateKey "$priv"; kset "$tag" publicKey "$pub"
    kset "$tag" shortId "$sid";     kset "$tag" sni "$sni"
    kset "$tag" port "$port";       kset "$tag" serviceName "$svc"
    kset "$tag" type "vless-grpc-reality"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg priv "$priv" --arg sni "$sni" --arg sid "$sid" --arg svc "$svc" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid,"flow":""}],"decryption":"none"},
        "streamSettings":{"network":"grpc","security":"reality",
            "grpcSettings":{"serviceName":$svc,"multiMode":false},
            "realitySettings":{"show":false,"target":($sni+":443"),"xver":0,
                "serverNames":[$sni],"privateKey":$priv,"shortIds":[$sid]}},
        "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}')
    ib_add "$ib"; xray_restart
    cls; box_top " ✅  VLESS + gRPC + REALITY добавлен" "$GREEN"; box_blank
    box_row "  Тег: ${CYAN}${tag}${R}  Порт: ${YELLOW}${port}${R}  SNI: ${WHITE}${sni}${R}"
    box_row "  ServiceName: ${CYAN}${svc}${R}"
    box_row "  PublicKey: ${DIM}${pub}${R}"
    box_row "  ShortId:   ${DIM}${sid}${R}"
    box_blank; box_end
    show_link_qr "$tag" "main"
}

# ──────────────────────────────────────────────────────────────────────────────
#  ПРОТОКОЛ: VLESS + SplitHTTP + TLS (HTTP/3 / QUIC)
# ──────────────────────────────────────────────────────────────────────────────

proto_vless_splithttp_tls() {
    cls; box_top " 🌊  VLESS + SplitHTTP + TLS/H3" "$CYAN"
    box_blank
    box_row "  ${DIM}HTTP/3 (QUIC) напрямую или через CDN (alpn: h2,http/1.1)${R}"
    box_blank
    xray_ok || { box_row "  ${RED}Установите ядро Xray!${R}"; box_end; pause; return; }
    local port dom path_v tag cert_p key_p alpn_mode
    ask "Порт" port "443"
    ask "Домен" dom ""
    ask "Path" path_v "/split"
    ask "Режим ALPN: [1] h3 (прямое) [2] h2,http/1.1 (CDN)" alpn_mode "1"
    ask "Тег" tag "vless-splithttp"
    [[ -z "$dom" ]] && { err "Домен обязателен"; pause; return; }
    ib_exists "$tag" && { err "Тег '$tag' уже занят"; pause; return; }
    port_check "$port" || { pause; return; }
    local cert_p key_p
    ask "Cert (fullchain.pem)" cert_p "/etc/letsencrypt/live/${dom}/fullchain.pem"
    ask "Key  (privkey.pem)"   key_p  "/etc/letsencrypt/live/${dom}/privkey.pem"
    local uuid; uuid=$("$XRAY_BIN" uuid 2>/dev/null)
    # Формируем alpn-массив
    local alpn_json
    if [[ "$alpn_mode" == "2" ]]; then
        alpn_json='["h2","http/1.1"]'
    else
        alpn_json='["h3"]'
    fi
    kset "$tag" domain "$dom"; kset "$tag" port "$port"
    kset "$tag" path "$path_v"; kset "$tag" type "vless-splithttp"
    local ib; ib=$(jq -n \
        --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" \
        --arg path "$path_v" --arg dom "$dom" \
        --arg cert "$cert_p" --arg key "$key_p" \
        --argjson alpn "$alpn_json" '{
        "tag":$tag,"listen":"0.0.0.0","port":$port,"protocol":"vless",
        "settings":{"clients":[{"email":"main","id":$uuid}],"decryption":"none"},
        "streamSettings":{
            "network":"splithttp","security":"tls",
            "splithttpSettings":{"path":$path,"host":$dom},
            "tlsSettings":{
                "rejectUnknownSni":true,
                "minVersion":"1.3",
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
    if [[ "$alpn_mode" == "2" ]]; then
        box_row "  ${YELLOW}CDN-режим: убедитесь что CDN поддерживает gRPC/WebSocket${R}"
    else
        box_row "  ${YELLOW}UDP/443 должен быть открыт для QUIC${R}"
    fi
    box_blank; box_end
    show_link_qr "$tag" "main"
}

