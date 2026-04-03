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
    systemctl restart xray 2>/dev/null || true
    sleep 1
    # Намеренно всегда возвращаем 0 — set -e не должен убивать меню
    # если Xray не поднялся (например занят порт). Пользователь увидит
    # статус в шапке главного меню при следующем открытии.
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
