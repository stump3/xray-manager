# ──────────────────────────────────────────────────────────────────────────────
#  КЛЮЧИ ПРОТОКОЛОВ
# ──────────────────────────────────────────────────────────────────────────────

kfile()   { echo "${XRAY_KEYS_DIR}/.keys.${1}"; }
kset()    { local f; f=$(kfile "$1"); local _kt; _kt=$(mktemp); _TMPFILES+=("$_kt"); grep -v "^${2}:" "$f" 2>/dev/null > "$_kt" || true; echo "${2}: ${3}" >> "$_kt"; mv "$_kt" "$f"; }
kget()    { grep "^${2}:" "$(kfile "$1")" 2>/dev/null | cut -d' ' -f2-; }

# ──────────────────────────────────────────────────────────────────────────────
#  КОНФИГ HELPERS
# ──────────────────────────────────────────────────────────────────────────────

cfg()     { jq -r "$1" "$XRAY_CONF" 2>/dev/null; }
cfgw()    {
    local t; t=$(mktemp); _TMPFILES+=("$t")
    jq "$1" "$XRAY_CONF" > "$t" || return 1
    mv "$t" "$XRAY_CONF"
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
}
ib_exists() { [[ -n "$(jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.tag' "$XRAY_CONF" 2>/dev/null)" ]]; }
ib_list()   { jq -r '.inbounds[]|select(.tag!="api")|"\(.tag)|\(.port)|\(.protocol)|\(.streamSettings.network//"tcp")|\(.streamSettings.security//"none")"' "$XRAY_CONF" 2>/dev/null; }
ib_del()    { cfgw "del(.inbounds[]|select(.tag==\"$1\"))"; }
ib_proto()  { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.protocol' "$XRAY_CONF"; }
ib_net()    { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.streamSettings.network//"tcp"' "$XRAY_CONF"; }
ib_port()   { jq -r --arg t "$1" '.inbounds[]|select(.tag==$t)|.port' "$XRAY_CONF"; }
ib_emails() {
    # Returns emails from .settings.clients (most protocols) or .settings.users (hysteria)
    local tag="$1"
    jq -r --arg t "$tag" '
        .inbounds[]|select(.tag==$t)|
        ((.settings.clients//[]) + (.settings.users//[]))[].email
    ' "$XRAY_CONF" 2>/dev/null
}
ib_users_count() { jq --arg t "$1" '[.inbounds[]|select(.tag==$t)|(.settings.clients//empty,.settings.users//empty)[]?]|length' "$XRAY_CONF" 2>/dev/null || echo 0; }

ib_add() {
    local json="$1"; local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --argjson ib "$json" '.inbounds += [$ib]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
}

xray_restart() {
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"

    # Валидация конфига перед перезапуском — ловим ошибки до того, как
    # сервис упадёт и все клиенты потеряют соединение.
    local test_out
    if ! test_out=$("$XRAY_BIN" run -test -c "$XRAY_CONF" 2>&1); then
        err "Конфиг содержит ошибки — перезапуск отменён:"
        printf '%s
' "$test_out" | grep -v "^$" | head -10 >&2
        return 1
    fi

    systemctl restart xray 2>/dev/null || true
    sleep 1
    # Намеренно возвращаем 0 при незапущенном сервисе — set -e не должен
    # убивать меню если Xray не поднялся (например занят порт).
    if ! xray_active 2>/dev/null; then
        warn "Xray не запустился — проверь порт: journalctl -u xray -n 5 --no-pager"
    fi
    return 0
}
# Добавить пользователя в работающий Xray без перезапуска (gRPC API)
xray_api_add_user() {
    local tag="$1" client_json="$2" proto="$3" net="$4"
    # Hysteria использует settings.users, остальные — settings.clients
    local field="clients"
    [[ "${proto}:${net}" == "hysteria:hysteria" ]] && field="users"
    # Формируем минимальный inbound JSON для xray api adu
    local tmp; tmp=$(mktemp /tmp/xray-adu-XXXXXX.json); _TMPFILES+=("$tmp")
    local protocol; protocol=$(ib_proto "$tag")
    jq -n \
        --arg tag "$tag" --arg proto "$protocol" \
        --arg field "$field" --argjson user "$client_json" \
        '{"inbounds":[{"tag":$tag,"protocol":$proto,"settings":{($field):[$user]}}]}' \
        > "$tmp"
    "$XRAY_BIN" api adu \
        --server="127.0.0.1:${STATS_PORT}" \
        "$tmp" 2>/dev/null
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# Удалить пользователя из работающего Xray без перезапуска (gRPC API)
xray_api_del_user() {
    local tag="$1" email="$2"
    "$XRAY_BIN" api rmu \
        --server="127.0.0.1:${STATS_PORT}" \
        -tag="$tag" "$email" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
#  NGINX HELPERS — динамическое добавление location-блоков в vpn.conf
# ──────────────────────────────────────────────────────────────────────────────

NGINX_VHOST="/etc/nginx/sites-available/vpn.conf"

# Проверить: nginx есть и vhost существует
nginx_ok() {
    command -v nginx &>/dev/null && [[ -f "$NGINX_VHOST" ]]
}

# Атомарно вставить/заменить location-блок в HTTPS server {}
# Аргументы: $1=location-path (напр. /ws), $2=полный текст блока (многострочный)
_nginx_upsert_location() {
    local loc_path="$1" block="$2"
    local backup="${NGINX_VHOST}.bak.$$"
    cp "$NGINX_VHOST" "$backup"

    python3 - "$NGINX_VHOST" "$loc_path" "$block" << 'PYEOF'
import sys, re

path_file, loc_path, block = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path_file).read()

# Удалить существующий location с этим path (если есть)
pat = re.compile(
    r'\n[ \t]*location[ \t]+' + re.escape(loc_path) + r'[ \t]*\{[^}]*\}',
    re.DOTALL
)
text = pat.sub('', text)

# Найти последний } HTTPS server-блока (listen ... ssl) и вставить перед ним
https_block = re.search(r'(listen\s+\d+\s+ssl.*?)(}[ \t]*\n?$)', text, re.DOTALL)
if not https_block:
    print("NGINX_UPSERT_ERROR: HTTPS server block not found", file=sys.stderr)
    sys.exit(1)

insert_pos = text.rfind('\n}')
if insert_pos == -1:
    sys.exit(1)

text = text[:insert_pos] + '\n' + block + '\n}' + text[insert_pos+2:]
open(path_file, 'w').write(text)
PYEOF

    local rc=$?
    if [[ $rc -ne 0 ]]; then
        cp "$backup" "$NGINX_VHOST"
        rm -f "$backup"
        warn "nginx_upsert_location: python patch failed, rollback applied"
        return 1
    fi

    if ! nginx -t 2>/dev/null; then
        cp "$backup" "$NGINX_VHOST"
        rm -f "$backup"
        warn "nginx -t: конфиг невалиден после патча, выполнен rollback"
        return 1
    fi

    rm -f "$backup"
    nginx -s reload 2>/dev/null || systemctl reload nginx 2>/dev/null || true
    return 0
}

# Добавить WebSocket / HTTPUpgrade location в nginx vhost
# Аргументы: $1=path (напр. /vless), $2=port (напр. 10001)
nginx_add_ws_location() {
    local path_v="$1" port="$2"
    nginx_ok || return 0
    local block
    block=$(printf '    location %s {\n        proxy_pass          http://127.0.0.1:%s;\n        proxy_http_version  1.1;\n        proxy_set_header    Upgrade    $http_upgrade;\n        proxy_set_header    Connection "upgrade";\n        proxy_set_header    Host       $host;\n        proxy_set_header    X-Real-IP  $remote_addr;\n        proxy_read_timeout  86400s;\n        proxy_send_timeout  86400s;\n    }' "$path_v" "$port")
    _nginx_upsert_location "$path_v" "$block" \
        && ok "nginx: location ${path_v} → 127.0.0.1:${port} добавлен" \
        || warn "nginx location не обновлён — добавьте вручную: proxy_pass http://127.0.0.1:${port};"
}

# Добавить gRPC location в nginx vhost
# Аргументы: $1=serviceName (напр. xray), $2=port (напр. 10003)
nginx_add_grpc_location() {
    local svc="$1" port="$2"
    nginx_ok || return 0
    local loc_path="/${svc}"
    local block
    block=$(printf '    location %s {\n        grpc_pass grpc://127.0.0.1:%s;\n        grpc_set_header Host $host;\n    }' "$loc_path" "$port")
    _nginx_upsert_location "$loc_path" "$block" \
        && ok "nginx: gRPC location ${loc_path} → 127.0.0.1:${port} добавлен" \
        || warn "nginx gRPC location не обновлён — добавьте вручную: grpc_pass grpc://127.0.0.1:${port};"
}
