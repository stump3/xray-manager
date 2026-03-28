# ══════════════════════════════════════════════════════════════════════════════
#  ПОДПИСКА (Subscription)
# ══════════════════════════════════════════════════════════════════════════════

SUB_DIR="/usr/local/etc/xray/subscriptions"
SUB_SVC_FILE="/etc/systemd/system/xray-sub.service"
SUB_PORT_FILE="${SUB_DIR}/.port"
SUB_INTERVAL_FILE="${SUB_DIR}/.interval"
SUB_AUTOUPDATE_FILE="${SUB_DIR}/.autoupdate"

# ── Собрать все ссылки для email по всем inbound ──────────────────────────────
_sub_links_for_email() {
    local email="$1"
    local links=""
    # Кешируем IP один раз до цикла — gen_link может вызываться N×M раз
    local sip; sip="${_CACHED_SERVER_IP:-$(server_ip)}"
    while IFS='|' read -r tag port proto net sec; do
        # Проверить есть ли этот email в данном inbound
        local exists; exists=$(jq -r \
            --arg t "$tag" --arg e "$email" \
            '[.inbounds[]|select(.tag==$t)|
              ((.settings.clients//[]) + (.settings.users//[]))[]]
             | map(select(.email==$e)) | length' \
            "$XRAY_CONF" 2>/dev/null)
        [[ "$exists" -gt 0 ]] || continue

        local link; link=$(gen_link "$tag" "$email" "$sip")
        [[ -n "$link" ]] && links="${links}${link}"$'\n'
    done < <(ib_list)

    # Hysteria2 отдельного бинарника
    if [[ -f "$HYSTERIA_CONFIG" ]]; then
        local dom; dom=$(hy_get_domain 2>/dev/null || true)
        local hport; hport=$(hy_get_port 2>/dev/null || true)
        if [[ -n "$dom" && -n "$hport" ]]; then
            # Найти пароль пользователя
            local hpass; hpass=$(python3 -c "
import sys, re
try:
    cfg = open('$HYSTERIA_CONFIG').read()
    m = re.search(r'^ {4}' + re.escape('${email}'.split('@')[0]) + r':\s*[\"\'']?([^\"\''\n]+)', cfg, re.M)
    if m: print(m.group(1).strip())
except: pass
" 2>/dev/null)
            [[ -n "$hpass" ]] && links="${links}hy2://${hpass}@${dom}:${hport}?sni=${dom}&alpn=h3&insecure=0#${email}-hy2"$'\n'
        fi
    fi

    echo -n "$links"
}

# ── Собрать все ссылки всех пользователей ─────────────────────────────────────
_sub_all_links() {
    local -A seen_emails=()
    local all_links=""
    # Кешируем IP один раз — gen_link вызывается N×M раз в цикле
    local _CACHED_SERVER_IP; _CACHED_SERVER_IP=$(server_ip)
    export _CACHED_SERVER_IP

    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen_emails[$em]}" ]] && continue
            seen_emails["$em"]=1
            local lnk; lnk=$(_sub_links_for_email "$em")
            [[ -n "$lnk" ]] && all_links="${all_links}${lnk}"
        done < <(ib_emails "$tag")
    done < <(ib_list)

    echo -n "$all_links"
}

# ── Clash/Mihomo YAML для одного пользователя ─────────────────────────────────
_sub_clash_for_email() {
    local email="$1"
    local proxies=""
    local proxy_names=""

    while IFS='|' read -r tag port proto net sec; do
        local exists; exists=$(jq -r \
            --arg t "$tag" --arg e "$email" \
            '[.inbounds[]|select(.tag==$t)|
              ((.settings.clients//[]) + (.settings.users//[]))[]]
             | map(select(.email==$e)) | length' \
            "$XRAY_CONF" 2>/dev/null)
        [[ "$exists" -gt 0 ]] || continue

        local name="${email}-${tag}"
        local sip; sip=$(server_ip)
        local p=""

        case "${proto}:${net}" in
            vless:tcp|vless:raw)
                local uuid pbk sid sni
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey"); sid=$(kget "$tag" "shortId")
                p="  - name: ${name}
    type: vless
    server: ${sip}
    port: ${port}
    uuid: ${uuid}
    tls: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${pbk}
      short-id: ${sid}
    servername: ${sni}
    client-fingerprint: firefox
    udp: true"
                ;;
            vless:xhttp)
                local uuid pbk sid sni path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                sni=$(kget "$tag" "sni"); pbk=$(kget "$tag" "publicKey")
                sid=$(kget "$tag" "shortId"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vless
    server: ${sip}
    port: ${port}
    uuid: ${uuid}
    tls: true
    network: xhttp
    xhttp-opts:
      path: ${path_v}
      mode: auto
    reality-opts:
      public-key: ${pbk}
      short-id: ${sid}
    servername: ${sni}
    client-fingerprint: firefox
    udp: true"
                ;;
            vless:ws)
                local uuid dom path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vless
    server: ${dom}
    port: 443
    uuid: ${uuid}
    tls: true
    network: ws
    ws-opts:
      path: ${path_v}
    servername: ${dom}
    udp: true"
                ;;
            vmess:ws)
                local uuid dom path_v
                uuid=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.id' "$XRAY_CONF")
                dom=$(kget "$tag" "domain"); path_v=$(kget "$tag" "path")
                p="  - name: ${name}
    type: vmess
    server: ${dom}
    port: 443
    uuid: ${uuid}
    alterId: 0
    cipher: auto
    tls: true
    network: ws
    ws-opts:
      path: ${path_v}
      headers:
        Host: ${dom}"
                ;;
            trojan:tcp|trojan:raw)
                local pass dom
                pass=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.clients[]|select(.email==$e)|.password' "$XRAY_CONF")
                dom=$(kget "$tag" "domain")
                p="  - name: ${name}
    type: trojan
    server: ${dom}
    port: ${port}
    password: ${pass}
    sni: ${dom}
    udp: true"
                ;;
            hysteria:hysteria)
                local pass dom
                pass=$(jq -r --arg t "$tag" --arg e "$email" \
                    '.inbounds[]|select(.tag==$t)|.settings.users[]|select(.email==$e)|.password' "$XRAY_CONF")
                dom=$(kget "$tag" "domain")
                p="  - name: ${name}
    type: hysteria2
    server: ${dom}
    port: ${port}
    password: ${pass}
    sni: ${dom}
    alpn: [h3]"
                ;;
        esac

        if [[ -n "$p" ]]; then
            proxies="${proxies}${p}"$'\n'
            proxy_names="${proxy_names}    - ${name}"$'\n'
        fi
    done < <(ib_list)

    [[ -z "$proxies" ]] && return

    cat << YAML
proxies:
${proxies}
proxy-groups:
  - name: PROXY
    type: select
    proxies:
$(echo "$proxy_names" | sed 's/^//')    - DIRECT

  - name: AUTO
    type: url-test
    url: https://www.google.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
${proxy_names}
rules:
  - GEOIP,LAN,DIRECT
  - MATCH,PROXY
YAML
}

# ── HTTP сервер подписки ───────────────────────────────────────────────────────

_sub_is_running() {
    systemctl is-active --quiet xray-sub 2>/dev/null
}

_sub_get_port() {
    [[ -f "$SUB_PORT_FILE" ]] && cat "$SUB_PORT_FILE" || echo "8888"
}

_sub_get_interval() {
    [[ -f "$SUB_INTERVAL_FILE" ]] && cat "$SUB_INTERVAL_FILE" || echo "12"
}

_sub_autoupdate_enabled() {
    [[ -f "$SUB_AUTOUPDATE_FILE" ]] && [[ "$(cat "$SUB_AUTOUPDATE_FILE")" == "1" ]]
}

_sub_start() {
    local port="$1"
    mkdir -p "$SUB_DIR"
    echo "$port" > "$SUB_PORT_FILE"

    # Обновить файлы подписок
    _sub_update_files

    # Создать Python HTTP-сервер
    cat > "${SUB_DIR}/server.py" << 'PYSERVER'
#!/usr/bin/env python3
import http.server, os, base64, sys

SUB_DIR = os.path.dirname(os.path.abspath(__file__))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8888

def get_interval():
    f = os.path.join(SUB_DIR, ".interval")
    try:
        return open(f).read().strip() if os.path.exists(f) else "12"
    except Exception:
        return "12"

class SubHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # тихий режим

    def do_GET(self):
        path = self.path.strip("/")
        # Токен безопасности: первая часть пути
        parts = path.split("/", 1)
        if len(parts) < 2:
            self.send_response(404); self.end_headers(); return

        token, rest = parts[0], parts[1] if len(parts) > 1 else ""

        # Проверить токен
        token_file = os.path.join(SUB_DIR, ".token")
        if os.path.exists(token_file):
            with open(token_file) as f:
                expected = f.read().strip()
            if token != expected:
                self.send_response(403); self.end_headers(); return

        # Маршруты
        if rest == "" or rest == "sub":
            # Базовая base64 подписка — все пользователи
            fn = os.path.join(SUB_DIR, "all.b64")
        elif rest == "clash":
            fn = os.path.join(SUB_DIR, "all.clash.yaml")
        elif rest.startswith("u/"):
            email = rest[2:]
            safe = email.replace("@", "_at_").replace(".", "_")
            fn = os.path.join(SUB_DIR, f"user_{safe}.b64")
        elif rest.startswith("clash/u/"):
            email = rest[8:]
            safe = email.replace("@", "_at_").replace(".", "_")
            fn = os.path.join(SUB_DIR, f"user_{safe}.clash.yaml")
        else:
            self.send_response(404); self.end_headers(); return

        if not os.path.exists(fn):
            self.send_response(404); self.end_headers(); return

        with open(fn, "rb") as f:
            data = f.read()

        ct = "text/plain; charset=utf-8"
        if fn.endswith(".yaml"):
            ct = "text/yaml; charset=utf-8"

        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Profile-Update-Interval", get_interval())
        self.send_header("Content-Disposition", "inline")
        self.end_headers()
        self.wfile.write(data)

if __name__ == "__main__":
    print(f"Subscription server on port {PORT}", flush=True)
    server = http.server.HTTPServer(("127.0.0.1", PORT), SubHandler)
    server.serve_forever()
PYSERVER

    # Systemd unit
    cat > "$SUB_SVC_FILE" << EOF
[Unit]
Description=Xray Subscription Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SUB_DIR}/server.py ${port}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray-sub
    sleep 1
    _sub_is_running && ok "Сервер подписки запущен на 127.0.0.1:${port}" || warn "Не удалось запустить"
}

_sub_update_files() {
    mkdir -p "$SUB_DIR"
    local -A seen=()

    # ── Все пользователи — base64 ──
    local all_links; all_links=$(_sub_all_links)
    echo -n "$all_links" | base64 -w0 > "${SUB_DIR}/all.b64"

    # ── Clash — все пользователи (первый найденный) ──
    local first_email=""
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1
            [[ -z "$first_email" ]] && first_email="$em"

            # Индивидуальная base64
            local ulinks; ulinks=$(_sub_links_for_email "$em")
            local safe="${em//@/_at_}"; safe="${safe//./_}"
            echo -n "$ulinks" | base64 -w0 > "${SUB_DIR}/user_${safe}.b64"

            # Индивидуальный Clash
            _sub_clash_for_email "$em" > "${SUB_DIR}/user_${safe}.clash.yaml"
        done < <(ib_emails "$tag")
    done < <(ib_list)

    # Clash для всех: берём первого пользователя как шаблон (или объединяем)
    [[ -n "$first_email" ]] && \
        _sub_clash_for_email "$first_email" > "${SUB_DIR}/all.clash.yaml"

    ok "Файлы подписок обновлены"
}

# ── Главное меню подписки ──────────────────────────────────────────────────────

menu_subscription() {
    while true; do
        cls; box_top " 📡  Подписка (Subscription)" "$CYAN"
        box_blank

        local sub_status sub_port sub_token="" sub_interval
        sub_port=$(_sub_get_port)
        sub_interval=$(_sub_get_interval)
        [[ -f "${SUB_DIR}/.token" ]] && sub_token=$(cat "${SUB_DIR}/.token")

        if _sub_is_running; then
            box_row "  Статус:  ${GREEN}● работает${R}  порт ${YELLOW}${sub_port}${R}  интервал ${CYAN}${sub_interval}ч${R}"
        else
            box_row "  Статус:  ${DIM}○ не запущен${R}"
        fi

        if [[ -n "$sub_token" ]]; then
            local sip; sip=$(server_ip)
            box_row "  Токен:   ${DIM}${sub_token}${R}"
            box_blank
            box_row "  ${YELLOW}Ссылки (через обратный прокси/туннель):${R}"
            box_row "  ${DIM}Все       http://127.0.0.1:${sub_port}/${sub_token}/sub${R}"
            box_row "  ${DIM}Clash     http://127.0.0.1:${sub_port}/${sub_token}/clash${R}"
            box_row "  ${DIM}Польз.    http://127.0.0.1:${sub_port}/${sub_token}/u/EMAIL${R}"
        fi

        box_blank; box_mid
        if _sub_is_running; then
            mi "1" "🔄" "Обновить файлы подписок"
            mi "2" "🔗" "Показать ссылки и QR"
            mi "3" "👤" "Подписка для конкретного пользователя"
            mi "4" "⏹" "${RED}Остановить сервер${R}"
        else
            mi "1" "▶" "${GREEN}Запустить сервер подписки${R}"
        fi
        mi "5" "📋" "Показать содержимое подписки"
        mi "6" "⏱" "Интервал обновления  ${DIM}(сейчас: ${sub_interval}ч)${R}"
        if _sub_autoupdate_enabled; then
            mi "7" "🔁" "Автообновление при добавлении  ${GREEN}[вкл]${R}"
        else
            mi "7" "🔁" "Автообновление при добавлении  ${DIM}[выкл]${R}"
        fi
        box_mid; mi "0" "◀" "Назад"; box_end

        read -rp "$(printf "${YELLOW}›${R} ") " ch

        if _sub_is_running; then
            case "$ch" in
                1) _sub_update_files; pause ;;
                2) sub_show_links ;;
                3) sub_user_links ;;
                4)
                    systemctl stop xray-sub
                    systemctl disable xray-sub
                    ok "Сервер остановлен"
                    pause
                    ;;
                5) sub_show_content ;;
                6) sub_set_interval ;;
                7) sub_toggle_autoupdate ;;
                0) return ;;
            esac
        else
            case "$ch" in
                1) sub_setup ;;
                5) sub_show_content ;;
                6) sub_set_interval ;;
                7) sub_toggle_autoupdate ;;
                0) return ;;
            esac
        fi
    done
}

sub_setup() {
    cls; box_top " ▶  Запуск сервера подписки" "$GREEN"; box_blank
    box_row "  ${CYAN}${BOLD}Что это:${R}"
    box_row "  ${DIM}Сервер отдаёт base64-список ссылок и Clash YAML по HTTP.${R}"
    box_row "  ${DIM}Клиент (v2rayN, Mihomo) периодически скачивает и обновляет.${R}"
    box_blank
    box_row "  ${YELLOW}⚠  Сервер слушает только 127.0.0.1 — доступен через SSH-туннель или Nginx.${R}"
    box_blank

    local port token
    ask "Порт сервера" port "8888"
    ask "Токен безопасности (Enter = сгенерировать)" token ""
    if [[ -z "$token" ]]; then
        token=$(openssl rand -hex 12)
        info "Сгенерирован токен: ${token}"
    fi

    mkdir -p "$SUB_DIR"
    echo "$token" > "${SUB_DIR}/.token"

    _sub_start "$port"

    cls; box_top " ✅  Сервер подписки запущен" "$GREEN"; box_blank
    box_row "  Порт:  ${YELLOW}${port}${R}"
    box_row "  Токен: ${CYAN}${token}${R}"
    box_blank
    box_row "  ${YELLOW}Прямой доступ (только с этого сервера):${R}"
    box_row "  ${DIM}Base64  http://127.0.0.1:${port}/${token}/sub${R}"
    box_row "  ${DIM}Clash   http://127.0.0.1:${port}/${token}/clash${R}"
    box_blank
    box_row "  ${YELLOW}Для клиентов снаружи — SSH-туннель:${R}"
    box_row "  ${DIM}ssh -L ${port}:127.0.0.1:${port} user@$(server_ip)${R}"
    box_row "  ${DIM}Затем в клиенте: http://127.0.0.1:${port}/${token}/sub${R}"
    box_blank
    box_row "  ${YELLOW}Или Nginx location (если есть домен):${R}"
    box_row "  ${DIM}location /${token}/ { proxy_pass http://127.0.0.1:${port}; }${R}"
    box_blank; box_end; pause
}


sub_set_interval() {
    cls; box_top " ⏱  Интервал обновления подписки" "$CYAN"; box_blank
    local cur; cur=$(_sub_get_interval)
    box_row "  Текущий интервал: ${CYAN}${cur} ч${R}"
    box_row "  ${DIM}Клиент обновляет подписку раз в N часов.${R}"
    box_row "  ${DIM}Рекомендуется: 12 (умеренно), 1 (быстро), 24 (редко).${R}"
    box_blank; box_end
    local val
    ask "Новый интервал в часах" val "$cur"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -lt 1 ]] || [[ "$val" -gt 168 ]]; then
        err "Введите число от 1 до 168"; pause; return
    fi
    mkdir -p "$SUB_DIR"
    echo "$val" > "$SUB_INTERVAL_FILE"
    ok "Интервал установлен: ${val} ч"
    box_row "  ${DIM}Вступит в силу при следующем запросе клиента.${R}"
    box_row "  ${DIM}Перезапуск сервера не требуется.${R}"
    box_end; pause
}

sub_toggle_autoupdate() {
    cls; box_top " 🔁  Автообновление подписки" "$CYAN"; box_blank
    if _sub_autoupdate_enabled; then
        box_row "  Текущий режим: ${GREEN}включено${R}"
        box_row "  ${DIM}Файлы подписки обновляются автоматически${R}"
        box_row "  ${DIM}при каждом добавлении пользователя.${R}"
        box_blank; box_end
        ask "Выключить автообновление? [y/N]" confirm "n"
        if [[ "${confirm,,}" == "y" ]]; then
            echo "0" > "$SUB_AUTOUPDATE_FILE"
            ok "Автообновление выключено"
        else
            info "Без изменений"
        fi
    else
        box_row "  Текущий режим: ${DIM}выключено${R}"
        box_row "  ${DIM}Файлы подписки обновляются только вручную${R}"
        box_row "  ${DIM}через пункт \"Обновить файлы подписок\".${R}"
        box_blank; box_end
        ask "Включить автообновление? [Y/n]" confirm "y"
        if [[ "${confirm,,}" != "n" ]]; then
            mkdir -p "$SUB_DIR"
            echo "1" > "$SUB_AUTOUPDATE_FILE"
            ok "Автообновление включено"
        else
            info "Без изменений"
        fi
    fi
    pause
}
sub_show_links() {
    cls; box_top " 🔗  Ссылки подписки" "$CYAN"; box_blank
    local port; port=$(_sub_get_port)
    local token=""
    [[ -f "${SUB_DIR}/.token" ]] && token=$(cat "${SUB_DIR}/.token")
    [[ -z "$token" ]] && { warn "Токен не найден"; pause; return; }

    local sip; sip=$(server_ip)

    box_row "  ${YELLOW}Для вставки в клиент (через SSH-туннель или Nginx):${R}"
    box_blank
    box_row "  ${CYAN}Все пользователи — Base64 (v2rayN, v2rayNG):${R}"
    box_row "  ${DIM}http://127.0.0.1:${port}/${token}/sub${R}"
    box_blank
    box_row "  ${CYAN}Все пользователи — Clash YAML (Mihomo):${R}"
    box_row "  ${DIM}http://127.0.0.1:${port}/${token}/clash${R}"
    box_blank
    box_row "  ${YELLOW}Индивидуальные подписки (по пользователю):${R}"
    local -A seen=()
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1
            box_row "  ${DIM}${em}${R}"
            box_row "    ${DIM}Base64  http://127.0.0.1:${port}/${token}/u/${em}${R}"
            box_row "    ${DIM}Clash   http://127.0.0.1:${port}/${token}/clash/u/${em}${R}"
        done < <(ib_emails "$tag")
    done < <(ib_list)
    box_blank
    box_row "  ${YELLOW}Через публичный Nginx (замени domain.com):${R}"
    box_row "  ${DIM}https://domain.com/${token}/sub${R}"
    box_blank; box_end; pause
}

sub_user_links() {
    cls; box_top " 👤  Подписка пользователя" "$YELLOW"; box_blank

    # Собрать список пользователей
    local -A seen=()
    local -a emails=()
    while IFS='|' read -r tag _ _ _ _; do
        while IFS= read -r em; do
            [[ -z "$em" || -n "${seen[$em]}" ]] && continue
            seen["$em"]=1; emails+=("$em")
        done < <(ib_emails "$tag")
    done < <(ib_list)

    [[ ${#emails[@]} -eq 0 ]] && { box_row "  ${DIM}Нет пользователей${R}"; box_end; pause; return; }

    local i=1
    for em in "${emails[@]}"; do mi "$i" "👤" "$em"; ((i++)); done
    box_mid; mi "0" "◀" "Назад"; box_end
    read -rp "$(printf "${YELLOW}›${R} ") " ch
    [[ "$ch" == "0" || -z "$ch" ]] && return

    local sel_email="${emails[$((ch-1))]}"
    [[ -z "$sel_email" ]] && return

    cls; box_top " 🔗  Подписка: ${sel_email}" "$CYAN"; box_blank

    # Показать все ссылки этого пользователя
    local links; links=$(_sub_links_for_email "$sel_email")
    if [[ -z "$links" ]]; then
        box_row "  ${DIM}Нет ссылок для этого пользователя${R}"
    else
        local cnt=0
        while IFS= read -r lnk; do
            [[ -z "$lnk" ]] && continue
            ((cnt++))
            # Укоротить ссылку для отображения
            local disp="${lnk:0:80}"
            [[ ${#lnk} -gt 80 ]] && disp="${disp}..."
            box_row "  ${DIM}${cnt})${R} ${CYAN}${disp}${R}"
        done <<< "$links"
        box_blank
        box_row "  Итого ссылок: ${YELLOW}${cnt}${R}"
        box_blank
        # Base64 для копирования
        local b64; b64=$(echo -n "$links" | base64 -w0)
        box_row "  ${YELLOW}Base64 (вставить в клиент как URL подписки):${R}"
        box_row "  ${DIM}${b64:0:100}...${R}"
        box_blank
        # QR-код base64 URL (если короткий)
        if [[ ${#b64} -lt 500 ]] && command -v qrencode &>/dev/null; then
            box_row "  ${YELLOW}QR (Base64):${R}"
            box_end
            echo "$b64" | qrencode -t ansiutf8 2>/dev/null || true
        fi
    fi

    box_blank; box_end; pause
}

sub_show_content() {
    cls; box_top " 📋  Содержимое подписки" "$DIM"; box_blank
    local all_links; all_links=$(_sub_all_links)
    if [[ -z "$all_links" ]]; then
        box_row "  ${DIM}Нет ссылок — добавьте протоколы и пользователей${R}"
        box_blank; box_end; pause; return
    fi

    local cnt=0
    while IFS= read -r lnk; do
        [[ -z "$lnk" ]] && continue
        ((cnt++))
        local proto_mark
        case "$lnk" in
            vless://*) proto_mark="${CYAN}VLESS${R}" ;;
            vmess://*) proto_mark="${ORANGE}VMess${R}" ;;
            trojan://*) proto_mark="${GREEN}Trojan${R}" ;;
            ss://*) proto_mark="${MAGENTA}SS${R}" ;;
            hy2://*) proto_mark="${GREEN}HY2${R}" ;;
            *) proto_mark="${DIM}?${R}" ;;
        esac
        # Извлечь имя (#fragment)
        local name; name=$(echo "$lnk" | grep -oP '#\K.*' || echo "")
        printf "${DIM}│${R}  %b %-30s ${DIM}%s${R}\n" \
            "$proto_mark" "$name" "${lnk:0:50}..."
    done <<< "$all_links"

    box_blank
    box_row "  Итого: ${YELLOW}${cnt}${R} ссылок"
    box_blank; box_end; pause
}

