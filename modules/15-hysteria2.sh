# ══════════════════════════════════════════════════════════════════════════════
#  Hysteria2 — СЕКЦИЯ
# ══════════════════════════════════════════════════════════════════════════════

HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
HYSTERIA_DIR="/etc/hysteria"
HYSTERIA_SVC="hysteria-server"

hy_is_installed() { command -v hysteria &>/dev/null; }
hy_is_running()   { systemctl is-active --quiet hysteria-server 2>/dev/null; }

hy_port_is_free() {
    ss -tulpn 2>/dev/null | awk '{print $5}' | grep -qE ":${1}$" && return 1 || return 0
}

hy_port_label() {
    if hy_port_is_free "$1"; then echo "свободен ✓"
    else
        local proc; proc=$(ss -tulpn 2>/dev/null | awk '{print $5,$7}' | grep ":${1} " \
            | grep -oP 'users:\(\("K[^"]+' | head -1 || true)
        [ -n "$proc" ] && echo "занят ($proc) ✗" || echo "занят ✗"
    fi
}

hy_is_valid_fqdn() {
    local d="$1"
    [[ "$d" == *.* ]] || return 1
    [[ "${#d}" -le 253 ]] || return 1
    [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

hy_resolve_a() {
    local domain="$1"
    if command -v dig &>/dev/null; then
        dig +short A "$domain" 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+\.' || true
    else
        getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' || true
    fi
}

hy_get_domain() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ""; return 1; }
    awk '/domains:/{f=1;next} f&&/^  - /{gsub(/[[:space:]]*-[[:space:]]*/,""); print; exit}' "$HYSTERIA_CONFIG"
}

hy_get_port() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ""; return 1; }
    awk '/^listen:/{match($0,/[0-9]+$/); print substr($0,RSTART,RLENGTH); exit}' "$HYSTERIA_CONFIG"
}

hy_get_domain_port() {
    [ -f "$HYSTERIA_CONFIG" ] || { echo ":"; return 1; }
    awk '
        /^listen:/{match($0,/[0-9]+$/); port=substr($0,RSTART,RLENGTH)}
        /domains:/{f=1; next}
        f&&/^  - /{gsub(/[[:space:]]*-[[:space:]]*/,""); dom=$0; f=0}
        END{print dom ":" port}
    ' "$HYSTERIA_CONFIG"
}

hysteria_install() {
    header "Установка / Переустановка Hysteria2"

    if hy_is_installed; then
        echo ""; echo -e "  ${YELLOW}Hysteria2 уже установлена.${R}"
        echo -e "  ${BOLD}1)${R} Переустановить (сохранить пользователей и настройки)"
        echo -e "  ${BOLD}2)${R} Переустановить полностью (сброс конфига)"
        echo -e "  ${BOLD}0)${R} Отмена"; echo ""
        local reinstall_ch; read -rp "  Выбор: " reinstall_ch < /dev/tty
        case "$reinstall_ch" in
            1)
                info "Переустановка с сохранением конфига..."
                local backup_cfg="/tmp/hysteria_backup_$(date +%Y%m%d_%H%M%S).yaml"
                cp "$HYSTERIA_CONFIG" "$backup_cfg" 2>/dev/null && info "Конфиг сохранён: $backup_cfg"
                systemctl stop "$HYSTERIA_SVC" 2>/dev/null || true
                bash <(curl -fsSL https://get.hy2.sh/) || { err "Ошибка установки"; return 1; }
                cp "$backup_cfg" "$HYSTERIA_CONFIG"
                systemctl restart "$HYSTERIA_SVC"; ok "Hysteria2 переустановлена, конфиг восстановлен"; return 0 ;;
            2)
                warn "Конфиг будет удалён!"
                local _yn; read -rp "  Продолжить? (y/N): " _yn < /dev/tty
                [[ "${_yn:-N}" =~ ^[yY]$ ]] || return 1
                systemctl stop "$HYSTERIA_SVC" 2>/dev/null || true; rm -f "$HYSTERIA_CONFIG" ;;
            0) return 0 ;; *) warn "Неверный выбор"; return 1 ;;
        esac
    fi

    # ── Домен ────────────────────────────────────────────────────
    local domain=""
    while true; do
        read -rp "  Домен (например cdn.example.com): " domain < /dev/tty
        hy_is_valid_fqdn "$domain" && break
        warn "Некорректный домен. Нужен FQDN вида sub.example.com"
    done
    local email=""; read -rp "  Email для ACME (необязателен): " email < /dev/tty; email="${email// /}"

    # ── CA ───────────────────────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Центр сертификации (CA):${R}"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  1) Let's Encrypt  — стандарт, рекомендуется            │"
    echo "  │  2) ZeroSSL        — резерв если LE заблокирован         │"
    echo "  │  3) Buypass        — сертификат на 180 дней              │"
    echo "  └──────────────────────────────────────────────────────────┘"
    local ca_choice="" ca_name
    while [[ ! "$ca_choice" =~ ^[123]$ ]]; do read -rp "  Выбор [1]: " ca_choice < /dev/tty; ca_choice="${ca_choice:-1}"; done
    case "$ca_choice" in 1) ca_name="letsencrypt" ;; 2) ca_name="zerossl" ;; 3) ca_name="buypass" ;; esac

    # ── Порт / Port Hopping ─────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Режим порта:${R}"
    echo "  ┌────────────────────────────────────────────────────────┐"
    echo "  │  1) Один порт      — стандарт                          │"
    echo "  │  2) Port Hopping   — диапазон UDP (обход блокировок)   │"
    echo "  └────────────────────────────────────────────────────────┘"
    local port_mode=""; while [[ ! "$port_mode" =~ ^[12]$ ]]; do read -rp "  Выбор [1]: " port_mode < /dev/tty; port_mode="${port_mode:-1}"; done
    local port port_hop_start port_hop_end listen_addr uri_port
    if [ "$port_mode" = "2" ]; then
        read -rp "  Начало диапазона [20000]: " port_hop_start < /dev/tty; port_hop_start="${port_hop_start:-20000}"
        read -rp "  Конец диапазона [29999]: "  port_hop_end   < /dev/tty; port_hop_end="${port_hop_end:-29999}"
        port="$port_hop_start"; listen_addr="0.0.0.0:${port_hop_start}-${port_hop_end}"
        uri_port="${port_hop_start}-${port_hop_end}"; ok "Port Hopping: UDP ${port_hop_start}-${port_hop_end}"
    else
        echo ""; echo -e "  ${WHITE}Выберите UDP порт:${R}"
        local l8443 l2053 l2083 l2087
        l8443=$(hy_port_label 8443); l2053=$(hy_port_label 2053); l2083=$(hy_port_label 2083); l2087=$(hy_port_label 2087)
        echo "  ┌──────────────────────────────────────────────────────────┐"
        printf "  │  1) 8443  — рекомендуется  [%-26s]  │\n" "$l8443"
        printf "  │  2) 2053  — альтернатива   [%-26s]  │\n" "$l2053"
        printf "  │  3) 2083  — альтернатива   [%-26s]  │\n" "$l2083"
        printf "  │  4) 2087  — альтернатива   [%-26s]  │\n" "$l2087"
        echo "  │  5) Ввести свой порт                                     │"
        echo "  └──────────────────────────────────────────────────────────┘"
        local port_choice=""; while [[ ! "$port_choice" =~ ^[12345]$ ]]; do read -rp "  Выбор [1]: " port_choice < /dev/tty; port_choice="${port_choice:-1}"; done
        case "$port_choice" in 1) port=8443 ;; 2) port=2053 ;; 3) port=2083 ;; 4) port=2087 ;;
            5) while true; do read -rp "  Порт (1-65535): " port < /dev/tty
               [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) && break; warn "Некорректный порт"; done ;;
        esac
        listen_addr="0.0.0.0:${port}"; uri_port="$port"
        hy_port_is_free "$port" || { warn "Порт $port занят!"; local fp; read -rp "  Продолжить? (y/N): " fp < /dev/tty; [[ "${fp:-N}" =~ ^[yY]$ ]] || { warn "Отмена"; return 1; }; }
        ok "Порт: $port"
    fi

    # ── IPv6 ────────────────────────────────────────────────────
    local use_ipv6=false
    if ip -6 addr show 2>/dev/null | grep -q "inet6.*global"; then
        local ipv6_ch; read -rp "  Включить IPv6 поддержку? (y/N): " ipv6_ch < /dev/tty
        [[ "${ipv6_ch:-N}" =~ ^[yY]$ ]] && {
            use_ipv6=true
            [ "$port_mode" = "2" ] && listen_addr="[::]:${port_hop_start}-${port_hop_end}" \
                                   || listen_addr="[::]:${port}"
            ok "IPv6 включён"
        }
    fi

    # ── Пользователь ────────────────────────────────────────────
    local username pass
    read -rp "  Логин [admin]: " username < /dev/tty; username="${username:-admin}"
    read -rp "  Пароль (пусто = авто): " pass < /dev/tty
    if [ -z "$pass" ]; then
        pass=$(openssl rand -base64 24 | tr -d '\n' | tr '+/' '-_' | tr -d '=')
        info "Сгенерирован пароль: $pass"
    fi
    local conn_name; read -rp "  Название подключения [Hysteria2]: " conn_name < /dev/tty; conn_name="${conn_name:-Hysteria2}"

    # ── Masquerade ──────────────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Режим маскировки:${R}"
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │  1) bing.com          — рекомендуется, поддерживает HTTP/3  │"
    echo "  │  2) yahoo.com         — стабильный, поддерживает HTTP/3     │"
    echo "  │  3) cdn.apple.com     — нейтральный                         │"
    echo "  │  4) speed.hetzner.de  — нейтральный                         │"
    echo "  │  5) /var/www/html     — локальная заглушка                  │"
    echo "  │  6) Ввести свой URL                                          │"
    echo "  └─────────────────────────────────────────────────────────────┘"
    local masq_choice="" masq_type masq_url; masq_type="proxy"; masq_url=""
    while [[ ! "$masq_choice" =~ ^[123456]$ ]]; do read -rp "  Выбор [1]: " masq_choice < /dev/tty; masq_choice="${masq_choice:-1}"; done
    case "$masq_choice" in
        1) masq_url="https://www.bing.com" ;;
        2) masq_url="https://www.yahoo.com" ;;
        3) masq_url="https://cdn.apple.com" ;;
        4) masq_url="https://speed.hetzner.de" ;;
        5) masq_type="file"
           [ ! -d /var/www/html ] && { mkdir -p /var/www/html
               printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Please wait</title></head><body style="background:#080808;color:#ccc;text-align:center;padding:100px">Loading...</body></html>' \
                   > /var/www/html/index.html; ok "Заглушка создана: /var/www/html"; } ;;
        6) while true; do read -rp "  URL (https://...): " masq_url < /dev/tty
           [[ "$masq_url" =~ ^https?:// ]] && break; warn "URL должен начинаться с https://"; done ;;
    esac

    # ── Алгоритм скорости ───────────────────────────────────────
    echo ""; echo -e "  ${WHITE}Алгоритм контроля скорости:${R}"
    echo "  [1] BBR    — стандартный, рекомендуется"
    echo "  [2] Brutal — агрессивный, для нестабильных каналов"
    local speed_mode use_brutal=false bw_up bw_down
    read -rp "  Выбор [1]: " speed_mode < /dev/tty; speed_mode="${speed_mode:-1}"
    if [ "$speed_mode" = "2" ]; then
        use_brutal=true
        read -rp "  Download (Mbps) [100]: " bw_down < /dev/tty; bw_down="${bw_down:-100}"
        read -rp "  Upload (Mbps) [50]: "   bw_up   < /dev/tty; bw_up="${bw_up:-50}"
        ok "Brutal: ↓${bw_down}/↑${bw_up} Mbps"
    fi

    # ── Зависимости ────────────────────────────────────────────
    info "Установка зависимостей..."
    apt-get update -y -q && apt-get install -y -q curl ca-certificates openssl qrencode dnsutils

    # ── Проверка DNS ────────────────────────────────────────────
    info "Проверка DNS..."
    local server_ip; server_ip=$(server_ip)
    [ -z "$server_ip" ] && { err "Не удалось определить IP сервера"; return 1; }
    ok "IP сервера: $server_ip"
    local domain_ips; domain_ips=$(hy_resolve_a "$domain" || true)
    [ -z "$domain_ips" ] && { err "Домен $domain не резолвится. Создайте A-запись → $server_ip"; return 1; }
    echo "  A-записи: $(echo "$domain_ips" | tr '\n' ' ')"
    if ! echo "$domain_ips" | grep -qx "$server_ip"; then
        warn "Домен не указывает на этот сервер ($server_ip)!"
        local fc; read -rp "  Продолжить принудительно? (y/N): " fc < /dev/tty
        [[ "${fc:-N}" =~ ^[yY]$ ]] || { warn "Исправьте DNS и запустите снова"; return 1; }
    else
        ok "DNS корректен: $domain → $server_ip"
    fi

    # ── Установка бинарника ────────────────────────────────────
    info "Установка Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) || { err "Ошибка установки"; return 1; }
    command -v hysteria &>/dev/null || { err "Бинарник hysteria не найден"; return 1; }
    ok "Hysteria2 установлен: $(hysteria version 2>/dev/null | grep Version | awk '{print $2}')"

    # ── Конфиг ─────────────────────────────────────────────────
    info "Запись конфигурации..."
    install -d -m 0755 "$HYSTERIA_DIR"
    local acme_email_line=""; [ -n "$email" ] && acme_email_line="  email: ${email}"
    local bw_block=""
    $use_brutal && bw_block="
bandwidth:
  up: ${bw_up} mbps
  down: ${bw_down} mbps"
    local masq_block
    if [ "$masq_type" = "file" ]; then
        masq_block="masquerade:
  type: file
  file:
    dir: /var/www/html"
    else
        masq_block="masquerade:
  type: proxy
  proxy:
    url: ${masq_url}
    rewriteHost: true"
    fi
    cat > "$HYSTERIA_CONFIG" << EOF
listen: ${listen_addr}

acme:
  type: http
  domains:
    - ${domain}
  ca: ${ca_name}
${acme_email_line}

auth:
  type: userpass
  userpass:
    ${username}: "${pass}"
${bw_block}
${masq_block}

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
EOF
    ok "Конфигурация записана: $HYSTERIA_CONFIG"

    # ── Сервис ─────────────────────────────────────────────────
    systemctl daemon-reload
    command -v ufw &>/dev/null && ufw allow 80/tcp >/dev/null 2>&1 && ufw --force enable >/dev/null 2>&1
    systemctl enable --now "$HYSTERIA_SVC"
    info "Ждём получения сертификата..."
    local i=0
    while [ $i -lt 30 ]; do
        journalctl -u "$HYSTERIA_SVC" -n 20 --no-pager 2>/dev/null | grep -q "server up and running" && break
        sleep 1; i=$((i+1))
    done
    command -v ufw &>/dev/null && ufw delete allow 80/tcp >/dev/null 2>&1
    ok "Сервис $HYSTERIA_SVC запущен"

    # ── UFW ────────────────────────────────────────────────────
    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp >/dev/null 2>&1
        if [ "$port_mode" = "2" ]; then
            ufw allow "${port_hop_start}:${port_hop_end}/udp" >/dev/null 2>&1
            ok "UFW: открыт диапазон ${port_hop_start}-${port_hop_end}/udp"
        else
            ufw allow "${port}/udp" >/dev/null 2>&1; ufw allow "${port}/tcp" >/dev/null 2>&1
            ok "UFW: открыт ${port}/udp и ${port}/tcp"
        fi
        ufw --force enable >/dev/null 2>&1
    fi

    # ── URI и итог ─────────────────────────────────────────────
    local uri="hy2://${username}:${pass}@${domain}:${uri_port}?sni=${domain}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    local txt_file="/root/hysteria-${domain}.txt"; echo "$uri" > "$txt_file"

    echo ""; echo -e "${BOLD}${GREEN}  ✓ Hysteria2 установлен${R}"
    echo ""; echo -e "${BOLD}${WHITE}  Конфигурация${R}"
    echo -e "${GRAY}  ──────────────────────────────${R}"
    echo -e "  ${GRAY}Сервер    ${R}${domain}:${uri_port}"
    echo -e "  ${GRAY}Логин     ${R}${username}"
    echo -e "  ${GRAY}Пароль    ${R}${pass}"
    echo -e "  ${GRAY}Алгоритм  ${R}$( $use_brutal && echo "Brutal ↓${bw_down}/↑${bw_up} Mbps" || echo "BBR" )"
    echo ""; echo -e "${BOLD}${WHITE}  URI подключения${R}"
    echo -e "${GRAY}  ──────────────────────────────${R}"
    echo -e "  ${CYAN}${uri}${R}"
    echo ""
    command -v qrencode &>/dev/null && { echo -e "${BOLD}${WHITE}  QR-код${R}"; qrencode -t ANSIUTF8 "$uri" 2>/dev/null || true; echo ""; }
    ok "URI сохранён: $txt_file"
}

hysteria_status() {
    header "Hysteria2 — Статус"
    hy_is_installed && echo -e "  Версия:  $(hysteria version 2>/dev/null | head -1)"
    systemctl --no-pager status "$HYSTERIA_SVC" 2>/dev/null || warn "Сервис не найден"
    if [ -f "$HYSTERIA_CONFIG" ]; then
        echo ""; echo -e "  ${WHITE}Конфигурация:${R}"
        local dp dom port
        dp=$(hy_get_domain_port 2>/dev/null || true)
        dom="${dp%%:*}"; [ -z "$dom" ] && dom="—"
        port="${dp##*:}"; [ -z "$port" ] && port="—"
        echo "    Домен: $dom    Порт: $port"
    fi
}

hysteria_logs()    { header "Hysteria2 — Логи"; journalctl -u "$HYSTERIA_SVC" -n 80 --no-pager 2>/dev/null || warn "Логи недоступны"; }
hysteria_restart() { systemctl restart "$HYSTERIA_SVC" && ok "Hysteria2 перезапущен" || warn "Ошибка перезапуска"; }

hysteria_add_user() {
    header "Hysteria2 — Добавить пользователя"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден. Сначала установите Hysteria2"; return 1; }
    local new_user new_pass
    local existing; existing=$(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:" | sed 's/:.*//' | tr -d ' ' | tr '\n' ' ')
    [ -n "$existing" ] && info "Существующие пользователи: ${existing}"
    while true; do
        read -rp "  Имя пользователя: " new_user < /dev/tty
        [ -z "$new_user" ] && { warn "Имя не может быть пустым"; continue; }
        if grep -qE "^    ${new_user}:" "$HYSTERIA_CONFIG" 2>/dev/null; then
            warn "Пользователь '${new_user}' уже существует."
            echo -e "  ${BOLD}1)${R} Ввести другое имя"; echo -e "  ${BOLD}2)${R} Заменить пароль"; echo -e "  ${BOLD}0)${R} Отмена"
            local ch; read -rp "  Выбор: " ch < /dev/tty
            case "$ch" in
                1) continue ;;
                2) read -rp "  Новый пароль (пусто = авто): " new_pass < /dev/tty
                   [ -z "$new_pass" ] && { new_pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '='); info "Пароль: $new_pass"; }
                   sed -i "s/^    ${new_user}:.*$/    ${new_user}: \"${new_pass}\"/" "$HYSTERIA_CONFIG"
                   systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
                   ok "Пароль для '${new_user}' обновлён"; return 0 ;;
                *) return 0 ;;
            esac
        else
            break
        fi
    done
    read -rp "  Пароль (пусто = авто): " new_pass < /dev/tty
    [ -z "$new_pass" ] && { new_pass=$(openssl rand -base64 18 | tr -d '\n' | tr '+/' '-_' | tr -d '='); info "Сгенерирован пароль: $new_pass"; }
    sed -i "/^  userpass:/a\\    ${new_user}: \"${new_pass}\"" "$HYSTERIA_CONFIG"
    systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
    ok "Пользователь '${new_user}' добавлен"
    local dom; dom=$(hy_get_domain)
    local port; port=$(hy_get_port)
    local conn_name; read -rp "  Название подключения [${new_user}]: " conn_name < /dev/tty; conn_name="${conn_name:-$new_user}"
    local uri="hy2://${new_user}:${new_pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    echo ""; echo -e "  ${CYAN}URI:${R}"; echo "  $uri"; echo ""
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$uri" 2>/dev/null || true
    echo "$uri" >> "/root/hysteria-${dom}-users.txt"
    ok "URI сохранён: /root/hysteria-${dom}-users.txt"
}

hysteria_delete_user() {
    header "Hysteria2 — Удалить пользователя"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден"; return 1; }
    local -a users=()
    while IFS= read -r line; do
        local u; u=$(echo "$line" | sed 's/:.*//' | tr -d ' ')
        [ -n "$u" ] && users+=("$u")
    done < <(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:")
    [ ${#users[@]} -eq 0 ] && { warn "Пользователи не найдены"; return 1; }
    echo -e "  ${WHITE}Выберите пользователя для удаления:${R}"; echo ""
    local i=1
    for u in "${users[@]}"; do echo -e "  ${BOLD}${i})${R} ${u}"; i=$((i+1)); done
    echo ""; echo -e "  ${BOLD}0)${R} Назад"; echo ""
    local ch; read -rp "  Выбор: " ch < /dev/tty
    [[ "$ch" == "0" ]] && return
    if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -lt 1 ] || [ "$ch" -gt ${#users[@]} ]; then
        warn "Неверный выбор"; return 1
    fi
    local selected="${users[$((ch-1))]}"
    local _yn; read -rp "  Удалить '${selected}'? (y/N): " _yn < /dev/tty
    [[ "${_yn:-N}" =~ ^[yY]$ ]] || { warn "Отменено"; return; }
    sed -i "/^    ${selected}:/d" "$HYSTERIA_CONFIG"
    systemctl reload "$HYSTERIA_SVC" 2>/dev/null || systemctl restart "$HYSTERIA_SVC"
    ok "Пользователь '${selected}' удалён"
}

hysteria_show_links() {
    header "Hysteria2 — Пользователи и ссылки"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Конфиг не найден"; return 1; }
    local dom port; dom=$(hy_get_domain); port=$(hy_get_port)
    local -a users=()
    while IFS= read -r line; do
        local u; u=$(echo "$line" | sed 's/:.*//' | tr -d ' ')
        [ -n "$u" ] && users+=("$u")
    done < <(awk '/^  userpass:/,/^[^ ]/' "$HYSTERIA_CONFIG" | grep -E "^    [^:]+:")
    [ ${#users[@]} -eq 0 ] && { warn "Пользователи не найдены"; return 1; }
    echo -e "  ${WHITE}Выберите пользователя:${R}"; echo ""
    local i=1
    for u in "${users[@]}"; do echo -e "  ${BOLD}${i})${R} ${u}"; i=$((i+1)); done
    echo ""; echo -e "  ${BOLD}0)${R} Назад"; echo ""
    local ch; read -rp "  Выбор: " ch < /dev/tty
    [[ "$ch" == "0" ]] && return
    if ! [[ "$ch" =~ ^[0-9]+$ ]] || [ "$ch" -lt 1 ] || [ "$ch" -gt ${#users[@]} ]; then
        warn "Неверный выбор"; return 1
    fi
    local selected="${users[$((ch-1))]}"
    local pass; pass=$(python3 -c "
import sys, re
cfg = open('$HYSTERIA_CONFIG').read()
m = re.search(r'^ {4}' + re.escape('${selected}') + r':\s*[\"\'']?([^\"\''\n]+)[\"\'']?', cfg, re.M)
print(m.group(1).strip() if m else '')
" 2>/dev/null)
    local conn_name; conn_name=$(grep -a "hy2://${selected}:" "/root/hysteria-${dom}.txt" 2>/dev/null | sed 's/.*#//' | tail -1 || echo "$selected")
    local uri="hy2://${selected}:${pass}@${dom}:${port}?sni=${dom}&alpn=h3&insecure=0&allowInsecure=0#${conn_name}"
    echo ""; echo -e "  ${CYAN}Пользователь:${R} ${selected}"
    echo -e "  ${CYAN}Сервер:${R}       ${dom}:${port}"
    echo ""; echo -e "  ${CYAN}URI:${R}"; echo "  $uri"; echo ""
    command -v qrencode &>/dev/null && qrencode -t ANSIUTF8 "$uri" 2>/dev/null || warn "qrencode не установлен"
    echo ""; read -rp "  Enter для возврата..." < /dev/tty
}

hysteria_migrate() {
    header "Hysteria2 — Перенос на новый сервер"
    [ -f "$HYSTERIA_CONFIG" ] || { warn "Hysteria2 не установлена"; return 1; }
    ensure_sshpass
    ask_ssh_target
    init_ssh_helpers hysteria
    local rip="$_SSH_IP" ruser="$_SSH_USER"
    info "Проверка подключения..."; RUN echo ok >/dev/null 2>&1 || { err "Не удалось подключиться"; return 1; }
    ok "Подключение успешно"
    local domain; domain=$(hy_get_domain)
    local hy_port; hy_port=$(hy_get_port)
    info "Установка Hysteria2 на новом сервере..."
    RUN "bash <(curl -fsSL https://get.hy2.sh/)" || { err "Ошибка установки"; return 1; }
    info "Копирование конфигурации..."; RUN "mkdir -p /etc/hysteria"
    PUT "$HYSTERIA_CONFIG" "${ruser}@${rip}:/etc/hysteria/config.yaml"; ok "Конфиг скопирован"
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        info "Копирование SSL-сертификата..."
        PUT /etc/letsencrypt/live    "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        PUT /etc/letsencrypt/archive "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        PUT /etc/letsencrypt/renewal "${ruser}@${rip}:/etc/letsencrypt/" 2>/dev/null || true
        ok "Сертификат скопирован"
    else
        warn "Сертификат не найден — Hysteria переиздаст его через ACME после смены DNS"
    fi
    info "Запуск сервиса..."
    RUN bash << REMOTE
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow ${hy_port}/udp >/dev/null 2>&1 || true
ufw allow ${hy_port}/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
systemctl daemon-reload; systemctl enable --now hysteria-server
REMOTE
    ok "Перенос завершён!"
    echo ""; echo -e "  ${YELLOW}Следующие шаги:${R}"
    echo -e "  1. Обновите DNS A-запись: ${CYAN}${domain}${R} → ${WHITE}${rip}${R}"
    echo -e "  2. После DNS: systemctl restart hysteria-server (на новом сервере)"
    echo -e "  3. Проверьте работу, затем остановите старый: ${CYAN}systemctl stop hysteria-server${R}"
}

hysteria_submenu_manage() {
    while true; do
        clear; header "Hysteria2 — Управление"
        echo -e "  ${BOLD}1)${R} 📊  Статус"; echo -e "  ${BOLD}2)${R} 📋  Логи"
        echo -e "  ${BOLD}3)${R} 🔄  Перезапустить"; echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_status  || true; read -rp "  Enter..." < /dev/tty ;;
            2) hysteria_logs    || true; read -rp "  Enter..." < /dev/tty ;;
            3) hysteria_restart || true; read -rp "  Enter..." < /dev/tty ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}

hysteria_submenu_users() {
    while true; do
        clear; header "Hysteria2 — Пользователи"
        echo -e "  ${BOLD}1)${R} ➕  Добавить пользователя"
        echo -e "  ${BOLD}2)${R} ➖  Удалить пользователя"
        echo -e "  ${BOLD}3)${R} 👥  Пользователи и ссылки"
        echo ""; echo -e "  ${BOLD}0)${R} ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_add_user    || true; read -rp "  Enter..." < /dev/tty ;;
            2) hysteria_delete_user || true; read -rp "  Enter..." < /dev/tty ;;
            3) hysteria_show_links  || true ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}

hysteria_section() {
    local ver dp dom port
    ver=$(get_hysteria_version 2>/dev/null || true)
    dp=$(hy_get_domain_port 2>/dev/null || true)
    dom="${dp%%:*}"; port="${dp##*:}"
    while true; do
        clear; echo ""; echo -e "${BOLD}${WHITE}  🚀  Hysteria2${R}"
        echo -e "${GRAY}  ────────────────────────────────────────────${R}"
        [ -n "$ver" ] && echo -e "  ${GRAY}Версия  ${R}${ver}"
        [ -n "$dom" ] && echo -e "  ${GRAY}Сервер  ${R}${dom}${port:+:$port}"
        echo ""
        echo -e "  ${BOLD}1)${R}  🔧  Установка"
        echo -e "  ${BOLD}2)${R}  ⚙️  Управление"
        echo -e "  ${BOLD}3)${R}  👥  Пользователи"
        echo -e "  ${BOLD}4)${R}  📦  Миграция на другой сервер"
        echo ""; echo -e "  ${BOLD}0)${R}  ◀️  Назад"; echo ""
        local ch; read -rp "  Выбор: " ch < /dev/tty
        case "$ch" in
            1) hysteria_install         || true; ver=$(get_hysteria_version 2>/dev/null||true); dp=$(hy_get_domain_port 2>/dev/null||true); dom="${dp%%:*}"; port="${dp##*:}" ;;
            2) hysteria_submenu_manage  || true ;;
            3) hysteria_submenu_users   || true ;;
            4) hysteria_migrate         || true; read -rp "  Enter..." < /dev/tty ;;
            0) return ;; *) warn "Неверный выбор" ;;
        esac
    done
}


# ──────────────────────────────────────────────────────────────────────────────
#  ГЛАВНОЕ МЕНЮ
# ──────────────────────────────────────────────────────────────────────────────

