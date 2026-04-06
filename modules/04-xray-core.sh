# ──────────────────────────────────────────────────────────────────────────────
#  04-xray-core.sh — установка, конфиг, сервис, обновление, Reality
# ──────────────────────────────────────────────────────────────────────────────

XRAY_RELEASES_URL="https://github.com/XTLS/Xray-core/releases/latest/download"
XRAY_RELEASES_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
SYSTEMD_UNIT="/etc/systemd/system/xray.service"

# ── Установка бинарника ───────────────────────────────────────────────────────

install_xray_core() {
    box_top " ⬇  Xray-core — загрузка и установка" "$CYAN"
    box_blank

    detect_arch

    local zip_name="Xray-linux-${XRAY_ARCH}.zip"
    local url="${XRAY_RELEASES_URL}/${zip_name}"
    local tmp_dir; tmp_dir="$(mktemp -d)"; _TMPFILES+=("$tmp_dir")

    info "Загружаем ${zip_name}..."
    curl -fL --progress-bar -o "${tmp_dir}/xray.zip" "$url" \
        || die "Не удалось загрузить Xray-core. Проверьте интернет."
    log_info "Скачано: ${url}"

    info "Распаковываем..."
    unzip -qo "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray/" \
        || die "Не удалось распаковать архив"

    install -m 755 "${tmp_dir}/xray/xray" "$XRAY_BIN" \
        || die "Не удалось установить бинарник в ${XRAY_BIN}"

    mkdir -p "$XRAY_DAT" "$XRAY_CONF_DIR" "$XRAY_LOG_DIR"

    for _dat in geoip.dat geosite.dat; do
        [[ -f "${tmp_dir}/xray/${_dat}" ]] \
            && install -m 644 "${tmp_dir}/xray/${_dat}" "${XRAY_DAT}/${_dat}" \
            || true
    done

    local _ver; _ver="$("$XRAY_BIN" version 2>/dev/null | head -1)"
    ok "${_ver}"
    log_ok "install_xray_core: ${_ver}"
    box_blank
}

# Разрешить привязку к порту < 1024 без root
set_cap_net_bind() {
    local port="${1:-443}"
    (( port < 1024 )) || return 0
    info "CAP_NET_BIND_SERVICE для порта ${port}..."
    setcap cap_net_bind_service=+ep "$XRAY_BIN" \
        || warn "Не удалось выставить capability — запускайте xray от root"
    log_ok "setcap cap_net_bind_service"
}

# ── Базовый конфиг ────────────────────────────────────────────────────────────

# Создаёт минимальный config.json: stats API + freedom + blackhole
_init_config() {
    [[ -f "$XRAY_CONF" ]] && backup_file "$XRAY_CONF"
    mkdir -p "$(dirname "$XRAY_CONF")"

    jq -n --argjson api_port "$STATS_PORT" '{
        log: {
            access:   "/var/log/xray/access.log",
            error:    "/var/log/xray/error.log",
            loglevel: "warning"
        },
        stats: {},
        api: { tag: "api", services: ["StatsService"] },
        policy: {
            levels: { "0": { statsUserUplink: true, statsUserDownlink: true } },
            system: { statsInboundUplink: false, statsInboundDownlink: false }
        },
        inbounds: [{
            tag:      "api",
            listen:   "127.0.0.1",
            port:     $api_port,
            protocol: "dokodemo-door",
            settings: { address: "127.0.0.1" }
        }],
        outbounds: [
            { protocol: "freedom",   tag: "direct" },
            { protocol: "blackhole", tag: "block"  }
        ],
        routing: {
            domainStrategy: "IPIfNonMatch",
            rules: [
                { type: "field", inboundTag: ["api"],                  outboundTag: "api"    },
                { type: "field", domain: ["geosite:category-ads-all"], outboundTag: "block"  },
                { type: "field", ip: ["geoip:private"],                outboundTag: "direct" }
            ]
        }
    }' > "$XRAY_CONF" || die "Не удалось создать базовый конфиг"

    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
    log_ok "_init_config: ${XRAY_CONF}"
}

# Атомарно добавить inbound в config.json через jq
_config_add_inbound() {
    local ib_json="$1"
    local tmp; tmp="$(mktemp)"; _TMPFILES+=("$tmp")

    jq --argjson ib "$ib_json" '.inbounds += [$ib]' "$XRAY_CONF" > "$tmp" \
        && mv "$tmp" "$XRAY_CONF" \
        || die "Ошибка при записи inbound в конфиг"

    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
    log_ok "_config_add_inbound"
}

# Проверка конфига через встроенный xray -test
validate_xray_config() {
    info "Проверяем конфиг..."
    if "$XRAY_BIN" run -test -c "$XRAY_CONF" > /dev/null 2>&1; then
        ok "Конфиг валиден"
        log_ok "xray -test OK"
    else
        err "Конфиг содержит ошибки:"
        "$XRAY_BIN" run -test -c "$XRAY_CONF" 2>&1 | head -20 >&2
        die "Исправьте конфиг: ${XRAY_CONF}"
    fi
}

# ── Systemd ───────────────────────────────────────────────────────────────────

create_service() {
    box_top " ⚙  Настройка systemd" "$CYAN"
    box_blank

    mkdir -p "$XRAY_LOG_DIR"
    chown nobody:nogroup "$XRAY_LOG_DIR" 2>/dev/null || true

    cat > "$SYSTEMD_UNIT" << EOF
[Unit]
Description=Xray-core proxy server
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_BIN} run -c ${XRAY_CONF}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1000000
ReadWritePaths=${XRAY_CONF_DIR} ${XRAY_LOG_DIR}

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SYSTEMD_UNIT"
    systemctl daemon-reload
    ok "systemd unit создан: ${SYSTEMD_UNIT}"
    log_ok "create_service"
    box_blank
}

enable_and_start_service() {
    info "Запускаем xray..."
    systemctl enable xray >> "$LOG_FILE" 2>&1 || true
    systemctl start  xray >> "$LOG_FILE" 2>&1

    sleep 1

    if systemctl is-active --quiet xray; then
        ok "xray запущен и добавлен в автозапуск"
        log_ok "xray active"
    else
        err "xray не запустился. Последние строки журнала:"
        journalctl -u xray -n 20 --no-pager >&2
        die "Диагностика: journalctl -u xray -f"
    fi
}

# Перезапуск с исправлением прав (используется везде при изменении конфига)
xray_restart() {
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
    systemctl restart xray
    sleep 1
}

# ── Фаервол ───────────────────────────────────────────────────────────────────

_detect_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

open_firewall_port() {
    local port="${1:-443}"
    local fw; fw="$(_detect_firewall)"

    if [[ "$fw" == "none" ]]; then
        warn "Активный фаервол не найден. Откройте порт ${port}/tcp вручную."
        return 0
    fi

    info "Фаервол: ${fw} — открываем порт ${port}/tcp..."
    case "$fw" in
        ufw)       ufw allow "${port}/tcp" comment "xray-manager" \
                       >> "$LOG_FILE" 2>&1 ;;
        firewalld) firewall-cmd --permanent --add-port="${port}/tcp" \
                       >> "$LOG_FILE" 2>&1
                   firewall-cmd --reload >> "$LOG_FILE" 2>&1 ;;
        iptables)  iptables -I INPUT -p tcp --dport "$port" -j ACCEPT \
                       >> "$LOG_FILE" 2>&1 ;;
    esac

    ok "Порт ${port}/tcp открыт (${fw})"
    log_ok "open_firewall_port: ${port} via ${fw}"
}

ask_firewall() {
    local port="${SERVER_PORT:-443}"
    box_blank
    confirm "Открыть порт ${port}/tcp в фаерволе?" "y" \
        && open_firewall_port "$port" \
        || info "Порт ${port}/tcp — откройте вручную если нужно"
}

# ── Reality: проверка домена ──────────────────────────────────────────────────

_CURL_TIMEOUT=10

_check_not_cloudflare() {
    local domain="$1"
    local headers
    headers="$(curl -fsSL -I --max-time "$_CURL_TIMEOUT" \
        "https://$domain" 2>/dev/null | tr '[:upper:]' '[:lower:]')" || return 0
    echo "$headers" | grep -q "cf-ray:" && return 1
    return 0
}

_check_tls13() {
    local domain="$1"
    local code
    code="$(curl -fsSL --tlsv1.3 --tls-max 1.3 --max-time "$_CURL_TIMEOUT" \
        -o /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null)" || return 1
    [[ "$code" =~ ^[0-9]+$ ]] && (( code > 0 ))
}

_check_http2() {
    local domain="$1"
    curl -fsSL --http2 -v --max-time "$_CURL_TIMEOUT" -o /dev/null \
        "https://$domain" 2>&1 | grep -q "< HTTP/2"
}

check_reality_domain() {
    local domain="$1"
    local cf_ok=false tls_ok=false h2_ok=false

    info "Проверяем: ${BOLD}${domain}${R}"
    msg_divider

    _check_not_cloudflare "$domain" && cf_ok=true
    $cf_ok \
        && printf "  ${GREEN}✓${R}  %-16s не использует Cloudflare\n" "Cloudflare:" \
        || printf "  ${RED}✗${R}  %-16s использует Cloudflare (Reality несовместима)\n" "Cloudflare:"

    _check_tls13 "$domain" && tls_ok=true
    $tls_ok \
        && printf "  ${GREEN}✓${R}  %-16s поддерживается\n" "TLS 1.3:" \
        || printf "  ${RED}✗${R}  %-16s не поддерживается\n" "TLS 1.3:"

    _check_http2 "$domain" && h2_ok=true
    $h2_ok \
        && printf "  ${GREEN}✓${R}  %-16s поддерживается\n" "HTTP/2:" \
        || printf "  ${RED}✗${R}  %-16s не поддерживается\n" "HTTP/2:"

    msg_divider

    if $cf_ok && $tls_ok && $h2_ok; then
        ok "Домен ${domain} пригоден для Reality"; return 0
    else
        warn "Домен ${domain} — найдены проблемы"; return 1
    fi
}

ask_reality_domain() {
    box_top " 🌐  Домен-маска для Reality" "$CYAN"
    box_blank
    info "Reality маскирует ваш сервер под этот сайт."
    info "Домен не должен использовать Cloudflare и должен поддерживать TLS 1.3 + HTTP/2."
    box_blank
    printf "  ${DIM}Примеры: microsoft.com  apple.com  addons.mozilla.org${R}\n"
    box_blank

    while true; do
        ask "Домен-маска" REALITY_DOMAIN "microsoft.com"
        [[ -n "$REALITY_DOMAIN" ]] || continue
        echo
        check_reality_domain "$REALITY_DOMAIN" && return 0
        echo
        confirm "Использовать несмотря на предупреждения?" "n" && return 0
        confirm "Попробовать другой домен?" "y" || die "Домен не выбран"
        echo
    done
}

# ── Reality: ключи и inbound ──────────────────────────────────────────────────

generate_reality_keypair() {
    local keypair; keypair="$("$XRAY_BIN" x25519 2>/dev/null)" \
        || die "Ошибка генерации ключевой пары x25519"
    REALITY_PRIV_KEY="$(echo "$keypair" | awk '/Private/ {print $NF}')"
    REALITY_PUB_KEY="$(echo  "$keypair" | awk '/Public/  {print $NF}')"
    REALITY_SHORT_ID="$(openssl rand -hex 8 2>/dev/null)"
    log_info "generate_reality_keypair: pub=${REALITY_PUB_KEY} sid=${REALITY_SHORT_ID}"
}

# Сохраняет ключи в /usr/local/etc/xray/.keys.<tag>
# gen_link() читает их при генерации ссылок
save_reality_keys() {
    local tag="$1"
    local kf="${XRAY_CONF_DIR}/.keys.${tag}"

    cat > "$kf" << EOF
privateKey: ${REALITY_PRIV_KEY}
publicKey:  ${REALITY_PUB_KEY}
shortId:    ${REALITY_SHORT_ID}
sni:        ${REALITY_DOMAIN}
port:       ${SERVER_PORT:-443}
type:       vless-reality
EOF

    chmod 600 "$kf"
    log_ok "save_reality_keys: ${kf}"
}

# Добавить VLESS+Reality inbound в текущий config.json
add_reality_inbound() {
    local tag="${1:-vless-reality}"

    info "Добавляем inbound ${tag} (порт ${SERVER_PORT:-443})..."

    local ib_json
    ib_json="$(jq -n \
        --arg  tag     "$tag" \
        --argjson port "${SERVER_PORT:-443}" \
        --arg  uuid    "$CLIENT_UUID" \
        --arg  email   "${CLIENT_EMAIL:-user-1}" \
        --arg  domain  "$REALITY_DOMAIN" \
        --arg  privkey "$REALITY_PRIV_KEY" \
        --arg  sid     "$REALITY_SHORT_ID" \
    '{
        tag:      $tag,
        listen:   "0.0.0.0",
        port:     $port,
        protocol: "vless",
        settings: {
            clients: [{
                id:    $uuid,
                email: $email,
                flow:  "xtls-rprx-vision"
            }],
            decryption: "none"
        },
        streamSettings: {
            network:  "raw",
            security: "reality",
            realitySettings: {
                target:      ($domain + ":443"),
                serverNames: [$domain],
                privateKey:  $privkey,
                shortIds:    [$sid]
            }
        },
        sniffing: {
            enabled:      true,
            destOverride: ["http","tls","quic"],
            routeOnly:    true
        }
    }')"

    _config_add_inbound "$ib_json"
    save_reality_keys "$tag"
    ok "Inbound ${tag} добавлен"
    log_ok "add_reality_inbound: tag=${tag}"
}

# ── Установка xray-manager ────────────────────────────────────────────────────

install_self() {
    local repo_dir="$1"

    info "Сборка xray-manager из модулей..."
    local tmp; tmp="$(mktemp)"; _TMPFILES+=("$tmp")

    # Сортированный cat всех модулей (как в Makefile)
    # shellcheck disable=SC2046
    cat $(ls -1 "${repo_dir}/modules/"*.sh | sort) > "$tmp" \
        || die "Ошибка сборки монолита из модулей"

    bash -n "$tmp" || die "Синтаксическая ошибка в собранном xray-manager"

    mv "$tmp" "$MANAGER_BIN"
    chmod +x "$MANAGER_BIN"

    ok "xray-manager установлен: ${MANAGER_BIN}"
    log_ok "install_self → ${MANAGER_BIN}"
}

# ── Обновление xray-core (TUI) ────────────────────────────────────────────────

_xray_installed_ver() {
    [[ -x "$XRAY_BIN" ]] || { echo ""; return; }
    local out; out="$("$XRAY_BIN" version 2>/dev/null || true)"
    echo "${out%%$'\n'*}" | grep -oP '[\d.]+' | head -1 || true
}

_xray_latest_ver() {
    curl -fsSL --max-time 10 "$XRAY_RELEASES_API" 2>/dev/null \
        | grep '"tag_name"' \
        | grep -oP '(?<=")[vV]?\K[\d.]+(?=")' \
        | head -1 || true
}

update_xray_core() {
    box_top " 🔄  Обновление Xray-core" "$CYAN"
    box_blank

    local cur; cur="$(_xray_installed_ver)"
    [[ -n "$cur" ]] || { warn "Xray-core не установлен"; box_blank; return 1; }

    info "Установлена: v${cur}"
    info "Проверяем GitHub..."
    local latest; latest="$(_xray_latest_ver)"

    if [[ -z "$latest" ]]; then
        err "Не удалось получить версию с GitHub"
        box_blank; return 1
    fi

    if [[ "$cur" == "$latest" ]]; then
        ok "Актуальная версия (v${cur})"
        box_blank; return 0
    fi

    warn "Доступно: v${cur} → v${latest}"
    confirm "Обновить сейчас?" "y" || { info "Отменено"; box_blank; return 0; }

    local was_running=false
    systemctl is-active --quiet xray 2>/dev/null && was_running=true
    $was_running && { info "Останавливаем xray..."; systemctl stop xray; }

    rm -f "$XRAY_BIN"
    install_xray_core
    set_cap_net_bind 443

    $was_running && {
        systemctl start xray
        systemctl is-active --quiet xray \
            && ok "xray перезапущен" \
            || err "xray не запустился после обновления"
    }

    ok "Обновление: v${cur} → v$(_xray_installed_ver)"
    log_ok "update_xray_core: ${cur} → ${latest}"
    box_blank
}

menu_xray_update() {
    update_xray_core
    pause
}
