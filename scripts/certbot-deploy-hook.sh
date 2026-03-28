#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  certbot-deploy-hook.sh
#  Перезагружает Nginx и Xray после обновления TLS-сертификата.
#
#  Установка:
#    cp scripts/certbot-deploy-hook.sh \
#       /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
#    chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
#
#  Certbot вызывает все скрипты из renewal-hooks/deploy/
#  автоматически после успешного обновления сертификата.
# ══════════════════════════════════════════════════════════════
set -euo pipefail

log() { echo "[certbot-deploy $(date '+%H:%M:%S')] $*"; }

log "Сертификат обновлён для: ${RENEWED_DOMAINS:-unknown}"

# ── Nginx ──────────────────────────────────────────────────────
if systemctl is-active --quiet nginx 2>/dev/null; then
    log "Перезагрузка Nginx..."
    if nginx -t -q 2>/dev/null; then
        systemctl reload nginx
        log "Nginx: ОК"
    else
        log "ОШИБКА: конфиг Nginx невалиден, перезагрузка отменена"
        nginx -t
        exit 1
    fi
fi

# ── Xray ───────────────────────────────────────────────────────
if systemctl is-active --quiet xray 2>/dev/null; then
    log "Перезапуск Xray..."
    systemctl restart xray
    sleep 1
    if systemctl is-active --quiet xray; then
        log "Xray: ОК"
    else
        log "ОШИБКА: Xray не запустился после перезапуска"
        systemctl status xray --no-pager -l
        exit 1
    fi
fi

# ── Hysteria2 (если установлен) ────────────────────────────────
if systemctl is-active --quiet hysteria-server 2>/dev/null; then
    log "Перезапуск Hysteria2..."
    systemctl restart hysteria-server
    log "Hysteria2: ОК"
fi

log "Готово."
