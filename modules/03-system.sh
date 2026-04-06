# ──────────────────────────────────────────────────────────────────────────────
#  СИСТЕМНЫЕ ПРОВЕРКИ
# ──────────────────────────────────────────────────────────────────────────────

need_root() {
    [[ "$(id -u)" -eq 0 ]] || { err "Требуются права root: sudo bash $0"; exit 1; }
}

xray_ok()      { [[ -x "$XRAY_BIN" ]]; }
xray_active()  { systemctl is-active --quiet xray 2>/dev/null; }
xray_ver()     { xray_ok && "$XRAY_BIN" version 2>/dev/null | awk 'NR==1{print $2}' || echo "—"; }

port_check() {
    local port="$1"
    local owner; owner=$(ss -tlnp "sport = :${port}" 2>/dev/null         | awk 'NR>1 && /LISTEN/{match($0,/users:\(\("([^"]+)/,a); print a[1]}'         | head -1)
    [[ -z "$owner" || "$owner" == "xray" ]] && return 0
    warn "Порт ${port} занят: ${owner} — Xray не запустится"
    return 1
}

cert_check() {
    local cert="$1" key="$2"
    [[ -f "$cert" ]] || { err "Cert не найден: ${cert}"; return 1; }
    [[ -f "$key"  ]] || { err "Key не найден: ${key}";   return 1; }
}
server_ip()    { timeout 3 curl -4 -s https://icanhazip.com 2>/dev/null || timeout 3 curl -4 -s https://api.ipify.org 2>/dev/null || echo "0.0.0.0"; }

# ──────────────────────────────────────────────────────────────────────────────
#  ЗАВИСИМОСТИ
# ──────────────────────────────────────────────────────────────────────────────

install_deps() {
    local need=()
    for p in curl unzip jq qrencode openssl python3; do
        command -v "$p" &>/dev/null || need+=("$p")
    done
    [[ ${#need[@]} -eq 0 ]] && { ok "Все зависимости установлены"; return 0; }

    info "Устанавливаем: ${need[*]}"

    # Если detect_os уже вызван — используем PKG_INSTALL
    if [[ -n "${PKG_INSTALL[*]+x}" ]]; then
        "${PKG_UPDATE[@]}" 2>/dev/null || true
        "${PKG_INSTALL[@]}" "${need[@]}" 2>/dev/null \
            || { err "Не удалось установить зависимости"; return 1; }
    else
        # Fallback: Debian/Ubuntu
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq "${need[@]}" 2>/dev/null \
            || { err "Не удалось установить зависимости"; return 1; }
    fi

    ok "Зависимости установлены"
}

# ──────────────────────────────────────────────────────────────────────────────
#  BBR
# ──────────────────────────────────────────────────────────────────────────────

enable_bbr() {
    local cur; cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [[ "$cur" == "bbr" ]]; then ok "BBR уже активен"; return; fi
    grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || {
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    }
    sysctl -p -q 2>/dev/null
    ok "BBR включён"
}

menu_bbr_tune() {
    cls; box_top " 🔧  Оптимизация сети (BBR + sysctl)" "$ORANGE"
    box_blank
    enable_bbr
    # Дополнительные оптимизации TCP
    local tune_file="/etc/sysctl.d/99-xray-tune.conf"
    if [[ ! -f "$tune_file" ]]; then
        cat > "$tune_file" << 'EOF'
# Xray Manager — оптимизация сети
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.tcp_rmem = 4096 87380 26214400
net.ipv4.tcp_wmem = 4096 65536 26214400
EOF
        sysctl -p "$tune_file" -q 2>/dev/null
        ok "TCP Fast Open + буферы оптимизированы"
    else
        ok "Оптимизации уже применены"
    fi
    box_blank
    box_row "  ${GREEN}Активный алгоритм:${R} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    box_blank; box_end; pause
}

# ──────────────────────────────────────────────────────────────────────────────
