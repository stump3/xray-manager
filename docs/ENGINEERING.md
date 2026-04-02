# Engineering Document

> Xray Manager v2.7.4 — архитектура, дизайн-решения, протоколы данных.

---

## Обзор

Скрипт разбит на 18 bash-модулей. Сборка через Makefile: `cat modules/*.sh > xray-manager.sh`. Дистрибуция — один файл, устанавливаемый через `git clone` или `wget`. Никаких `source` в рантайме.

### Компоненты и стек

| Компонент | Язык | Управление | Конфиг |
|---|---|---|---|
| **Xray-core** | Go | systemd | JSON |
| **telemt** | Rust | systemd / Docker | TOML |
| **Hysteria2** | Go (QUIC) | systemd | YAML |

---

## Архитектура

### Модули

```
modules/
│
├─ 00-header.sh      (13)    shebang · set -euo pipefail · _TMPFILES=() · trap _cleanup EXIT
├─ 01-constants.sh   (32)    MANAGER_VERSION · пути · ANSI-цвета
├─ 02-ui.sh         (109)    box_* · mi · ask · confirm · spin_start/stop · ok/err/warn/info
├─ 03-system.sh      (71)    need_root · install_deps · server_ip · enable_bbr · menu_bbr_tune
├─ 04-xray-core.sh  (104)    install_xray_core · install_self · _init_config · _enable_stats_api
│
├─ 05-config.sh      (67)    ── Ядро зависимостей ──
│                             kfile/kset/kget · cfg/cfgw
│                             ib_exists/list/del/proto/net/port/emails/users_count
│                             ib_add · xray_restart · xray_api_add_user/del_user
│
├─ 06-limits.sh     (141)    _init_limits_file · limit_set/get/del · _traffic_from_batch
│                             fmt_bytes · check_limits · _remove_user_from_tag
│                             install_limits_timer
│
├─ 07-links.sh      (182)    urlencode · gen_link · show_link_qr · pick_inbound
│
├─ 08-protocols.sh (1091)    proto_vless_tcp_reality · proto_vless_xhttp_reality
│                             proto_vless_grpc_reality · proto_vless_splithttp_tls
│                             proto_vless_ws_tls · proto_vless_grpc_tls
│                             proto_vless_httpupgrade_tls
│                             proto_vmess_ws_tls · proto_vmess_tcp_tls
│                             proto_trojan_tls · proto_shadowsocks
│                             proto_hysteria_xray
│                             menu_freedom_fragment/noises · menu_fallbacks · fallback_*
│                             menu_metrics · menu_hysteria_outbound · menu_balancer · balancer_*
│
├─ 09-users.sh      (544)    menu_protocols · menu_del_protocol
│                             menu_users · user_add/del/list/link/stats/set_limit
│
├─ 10-manage.sh      (71)    menu_manage · show_global_stats · update_geodata
│
├─ 11-subscription.sh(674)   _sub_links_for_email · _sub_all_links · _sub_clash_for_email
│                             _sub_is_running · _sub_start · _sub_update_files
│                             menu_subscription · sub_setup · sub_set_interval
│                             sub_toggle_autoupdate · sub_show_links · sub_user_links
│
├─ 12-system.sh     (126)    menu_system · do_backup · do_restore · do_remove_all
│
├─ 13-compat.sh      (58)    NC/die/header/gen_secret/get_public_ip/get_telemt_version
│                             ensure_sshpass · ask_ssh_target · init_ssh_helpers · check_ssh_connection
│
├─ 14-telemt.sh     (622)    telemt_* (установка, управление, пользователи, миграция)
│
├─ 15-hysteria2.sh  (541)    hy_* · hysteria_* (установка, управление, пользователи, миграция)
│
├─ 16-routing.sh    (834)    routing_* · menu_routing · routing_list/add/del/reorder/strategy
│                             _profiles_init · menu_profiles · profile_save/load/delete
│                             menu_profile_templates
│
└─ 99-main.sh       (100)    main_menu · entrypoint (need_root · main_menu)
```

### Граф зависимостей модулей

```
00-header  ←── всё (trap, _TMPFILES, set -euo)
01-constants ←── всё (XRAY_CONF, цвета)
02-ui      ←── всё что выводит UI
05-config  ←── 06 07 08 09 10 11 12 13 14 15 16
06-limits  ←── 09 (user_add/del, check_limits)
07-links   ←── 08 09 11 (gen_link используется в proto, users, subscription)
08-protocols ←── 09 (menu_protocols вызывает proto_*)
```

Зависимость строго однонаправленная: высокие номера могут вызывать низкие, не наоборот.

### Makefile

```makefile
MODULES := $(sort $(wildcard modules/*.sh))
OUT     := xray-manager.sh

build:  # cat + bash -n
check:  # shellcheck -S warning -e SC2034,SC2086
release: build  # chmod + sha256sum
ls:     # таблица модулей с размерами
```

---

## Дизайн-решения

### 1. Сборка в монолит вместо source

Bash `source` ломает `trap EXIT` (не наследуется подпроцессами), создаёт неочевидные области видимости для `_TMPFILES`, и усложняет дистрибуцию. Вместо этого — сборка: `cat modules/*.sh > xray-manager.sh`. Все мехaнизмы безопасности (trap, _TMPFILES) работают как в монолите.

Порог для пересмотра: ~8000 строк, 2+ автора одновременно, CI с тестами. В таком случае — `cat modules/*.sh > release.sh` перед тегом.

### 2. Compat Layer вместо рефакторинга

MTProto и Hysteria секции заимствованы из `server-manager` с другим набором утилит. Тонкий слой совместимости в `13-compat.sh`:

```bash
NC="$R"                          # server-manager → NC, xray-manager → R
die()    { printf "${RED}✗ %s${R}\n" "$*" >&2; exit 1; }
get_public_ip() { server_ip; }   # псевдоним
```

### 3. Атомарные операции с конфигом

Все записи через `mktemp + mv`. `mv` в пределах одного раздела — атомарная операция на уровне ОС:

```bash
local tmp; tmp=$(mktemp); _TMPFILES+=("$tmp")
jq '.inbounds += [$ib]' "$XRAY_CONF" > "$tmp" && mv "$tmp" "$XRAY_CONF"
```

Аналогично `kset()` — использует `mktemp` вместо хардкода `/tmp/_k` (устранена гонка состояний при параллельных вызовах).

### 4. Разделение ключей и конфига

Ключи в `.keys.<tag>`, а не в `config.json`:

```
.keys.vless-reality
  privateKey: <x25519 private>
  publicKey:  <x25519 public>   ← нужен только для gen_link
  shortId:    <hex8>
  sni:        www.microsoft.com
  port:       443
  type:       vless-reality
```

`publicKey` избыточен в конфиге Xray, но нужен при генерации ссылок.

### 5. spiderX — детерминированный per-user

```bash
local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"
```

Уникален для каждого пользователя, не меняется между вызовами `gen_link`. Официально рекомендован XTLS для улучшения маскировки.

### 6. SSH-миграция через замыкания

```bash
init_ssh_helpers() {
    RUN() { sshpass -p "$_SSH_PASS" ssh  $opts "${_SSH_USER}@${_SSH_IP}" "$@"; }
    PUT() { sshpass -p "$_SSH_PASS" scp -rp $opts "$@"; }
}
```

`RUN` и `PUT` — замыкания, захватывающие `_SSH_*` переменные. Режим `telemt` использует `accept-new` вместо `no` — запоминает ключ хоста при первом подключении.

### 7. telemt: API как единственный способ управления

```
POST 127.0.0.1:9091/v1/users {"username": "alice", ...}
→ telemt применяет мгновенно, соединения не разрываются
```

### 8. Hysteria2 DNS до ACME

```bash
server_ip=$(server_ip)
domain_ips=$(hy_resolve_a "$domain")
if ! echo "$domain_ips" | grep -qx "$server_ip"; then
    warn "Домен не указывает на этот сервер!"
fi
```

Самая частая причина ошибок при установке — несоответствие DNS.

### 9. Hysteria2 — два режима, одна кодовая база

```
Нативный Xray:    protocol:"hysteria" + network:"hysteria"
                  settings.users: [{email, password}]

Все остальные:    settings.clients: [{email, id/password}]
```

Универсальный хелпер `ib_emails()` читает из обоих полей:

```bash
ib_emails() {
    jq -r --arg t "$tag" '
        .inbounds[]|select(.tag==$t)|
        ((.settings.clients//[]) + (.settings.users//[]))[].email
    ' "$XRAY_CONF"
}
```

### 10. gen_link — матрица protocol:network

```bash
gen_link() {
  # spiderX для всех REALITY-протоколов
  local spx; spx="/$(printf '%s' "${email}" | sha256sum | head -c8)"

  case "${proto}:${net}" in
    vless:tcp|vless:raw)      # → vless://...?security=reality&flow=xtls-rprx-vision&spx=...
    vless:xhttp)              # → vless://...?type=xhttp&mode=auto&spx=...
    vless:grpc_reality)       # → vless://...?security=reality&type=grpc&serviceName=...&spx=...
    vless:ws)                 # → vless://...?security=tls&type=ws
    vless:grpc)               # → vless://...?type=grpc&serviceName=...
    vless:httpupgrade)        # → vless://...?type=httpupgrade
    vless:splithttp)          # → vless://...?security=tls&type=splithttp
    vmess:ws|vmess:tcp)       # → vmess://base64(JSON)
    trojan:tcp|trojan:raw)    # → trojan://password@domain:port
    hysteria:hysteria)        # → hy2://password@domain:port?sni=...
    shadowsocks:tcp)          # → ss://base64(method:serverPass:userPass)@ip:port
  esac
}
```

### 11. REALITY: target vs dest (исторический баг)

```json
// TCP + REALITY → realitySettings
{ "dest": "github.com:443" }      // ← устаревшее поле (до Xray 24.10.31)
{ "target": "github.com:443" }    // ← актуальное поле

// XHTTP + REALITY → realitySettings
{ "target": "github.com:443" }    // ← всегда было target
```

`dest` переименовано в `target` в версии 24.10.31. В v2.6.0 исправлено для TCP — XHTTP был правильным с v2.0.0.

### 12. sniffing.routeOnly в REALITY-inbound

```json
"sniffing": {
  "enabled": true,
  "destOverride": ["http", "tls", "quic"],
  "routeOnly": true   // ← sniff для маршрутизации, не переопределяет dest
}
```

Без `routeOnly: true` sniffing может переопределить реальный адрес назначения — что неверно для REALITY, где `target` — камуфляжный хост, не реальный сервер.

### 13. SplitHTTP: два режима ALPN

```json
// Прямое подключение по HTTP/3 (QUIC)
"alpn": ["h3"]

// Через CDN (CDN не поддерживает H3 на transport уровне)
"alpn": ["h2", "http/1.1"]
```

Клиент → CDN → сервер: CDN не передаёт QUIC, только HTTP/2 или HTTP/1.1. Режим выбирается при установке протокола.

---

## Расширенные функции

### Fragment и Noises

Оба модифицируют существующий `freedom` outbound:

```bash
# Fragment
jq '(.outbounds[]|select(.protocol=="freedom")|.settings) |= (. // {} | .fragment = $frag)'

# Noises — аналогично
```

Fragment — только TCP, Noises — только UDP.

### Fallbacks

Хранятся в `settings.fallbacks[]` внутри inbound. Работают только с `network:"raw"/"tcp"` + `security:"tls"`. При REALITY — неприменимы (перехват до TLS-рукопожатия).

### Observatory + Balancer

```json
{"observatory": {"subjectSelector": ["out-"], "probeUrl": "...", "probeInterval": "30s"}}
{"balancers": [{"tag": "lb", "selector": ["out-"], "strategy": {"type": "leastPing"}}]}
```

`leastPing` / `leastLoad` требуют Observatory. `random` / `roundRobin` работают без него.

### Metrics vs Stats API

| Аспект | Stats API | Metrics |
|---|---|---|
| Транспорт | gRPC через `dokodemo-door` inbound | HTTP `metrics.listen` |
| Запрос | `xray api statsquery --server=:10085` | `curl :PORT/debug/vars` |
| Дополнительно | — | pprof, expvars |

---

## Протоколы данных

### `.limits.json`

```json
{
  "<inbound-tag>": {
    "<email>": {
      "expire_ts":           "1767225599",
      "expire_date":         "2025-12-31",
      "traffic_limit_bytes": "10737418240",
      "traffic_limit_gb":    "10"
    }
  }
}
```

### `.keys.<tag>`

```
privateKey: <base64>
publicKey:  <base64>
shortId:    <hex8>
sni:        www.microsoft.com
port:       443
type:       vless-reality
```

Для gRPC+REALITY дополнительно: `serviceName`.  
Для SplitHTTP: `domain`, `path`.

### Xray `config.json` — минимальная структура

```json
{
  "stats": {},
  "api":    {"tag": "api", "services": ["StatsService"]},
  "policy": {"levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}}},
  "inbounds": [
    {"tag": "api", "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door"},
    {"tag": "vless-reality", "port": 443, "protocol": "vless", ...}
  ],
  "outbounds": [{"protocol": "freedom"}, {"protocol": "blackhole"}],
  "routing": {
    "rules": [
      {"inboundTag": ["api"], "outboundTag": "api"},
      {"domain": ["geosite:category-ads-all"], "outboundTag": "block"}
    ]
  }
}
```

### telemt `telemt.toml`

```toml
[general]
use_middle_proxy = true

[server.api]
enabled   = true
listen    = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32"]

[censorship]
tls_domain = "petrovich.ru"
mask       = true

[access.users]
alice = "hex32secret1"
```

### Hysteria2 `config.yaml`

```yaml
listen: 0.0.0.0:8443

acme:
  type: http
  domains: [cdn.example.com]
  ca: letsencrypt

auth:
  type: userpass
  userpass:
    admin: "password"

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
```

---

## Зависимости

### Автоустанавливаемые пакеты

| Пакет | Назначение |
|---|---|
| `curl` | Загрузка бинарников, определение IP |
| `jq` | Работа с JSON |
| `openssl` | Пароли, ключи, hex |
| `qrencode` | QR в терминале |
| `python3` | URL-кодирование, парсинг API-ответов |
| `dnsutils` | `dig` для проверки DNS (Hysteria) |
| `sshpass` | SSH-миграция (по запросу) |

### Устанавливаемые бинарники

| Бинарник | Источник | Команды |
|---|---|---|
| `xray` | github.com/XTLS/Xray-core | `uuid`, `x25519`, `api statsquery` |
| `telemt` | github.com/telemt/telemt | `--version`; REST API :9091 |
| `hysteria` | get.hy2.sh | `version`; systemd сервис |

---

## Безопасность

| Аспект | Решение |
|---|---|
| Ключи REALITY | `xray x25519` — встроенный генератор ядра |
| Пароли | `openssl rand -base64 24` или `openssl rand -hex 16` |
| Stats API | `127.0.0.1:10085` — только localhost |
| telemt API | `127.0.0.1:9091` + whitelist `127.0.0.1/32` |
| Атомарность | Все записи: `jq > tmp && mv tmp config` |
| kset() | `mktemp` + `_TMPFILES` — нет гонки при параллельных вызовах |
| path traversal | `do_restore()` проверяет все пути через `tar -tz` с полным whitelist |
| Systemd telemt | `NoNewPrivileges=true`, `CapabilityBoundingSet=CAP_NET_BIND_SERVICE` |

---

## Известные ограничения

| # | Ограничение | Обходной путь |
|---|---|---|
| 1 | Stats API сбрасывает счётчики при перезапуске Xray | Внешняя БД (roadmap) |
| 2 | `systemctl reload hysteria-server` разрывает соединения | HTTP auth режим (roadmap) |
| 3 | telemt миграция — только systemd-режим | Docker: ручная копия docker-compose.yml |
| 4 | `server_ip()` возвращает IPv4 | IPv6-серверы: правка ссылок вручную |
| 5 | BBR требует ядро ≥ 4.9 | Предупреждение в UI, нефатально |
| 6 | Shadowsocks multi-user URI — нестандартный формат | Часть клиентов не поддерживает |
| 7 | REALITY+Cloudflare dest: CF работает как прокси для любого | Dokodemo-door защита (roadmap) |
| 8 | `config.json` пишется от `root`, сервис читает от `nobody` → `permission denied` после смены конфига | `chown nobody:nogroup /usr/local/etc/xray/config.json` (см. раздел Удаление / переустановка) |
| 9 | `sudo xray-manager` сбрасывает `TERM` → меню не рендерится | Запускать как `xray-manager` (уже root) или `sudo TERM=$TERM xray-manager` |

---

## Удаление / чистая переустановка

Порядок важен: сначала официальный uninstall-скрипт XTLS (он корректно убирает systemd-юнит `xray.service`), затем всё остальное вручную.

### 1. Xray-core — официальный uninstall

```bash
bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
```

Убирает: `/usr/local/bin/xray`, `/etc/systemd/system/xray.service`, `/usr/local/share/xray/`.

### 2. xray-manager + systemd-таймер лимитов

```bash
systemctl disable --now xray-limits.timer xray-limits.service 2>/dev/null || true
rm -f /usr/local/bin/xray-manager
rm -f /etc/systemd/system/xray-limits.service
rm -f /etc/systemd/system/xray-limits.timer
systemctl daemon-reload
```

### 3. Конфиги, ключи, логи

```bash
rm -rf /usr/local/etc/xray/
rm -rf /var/log/xray/
rm -rf /usr/local/share/xray/
rm -f /root/.xray-mgr-install
```

### 4. Nginx

```bash
rm -f /etc/nginx/sites-enabled/vpn.conf
rm -f /etc/nginx/sites-available/vpn.conf
rm -f /etc/nginx/sites-available/acme-temp.conf
rm -f /etc/nginx/stream.d/stream-443.conf
rm -f /etc/nginx/conf.d/stream-443.conf   # ← от старых установок, conf.d тоже чистим
# Восстановить оригинальный nginx.conf, если был сохранён бэкап
ls /etc/nginx/nginx.conf.bak.* 2>/dev/null && \
  cp "$(ls -t /etc/nginx/nginx.conf.bak.* | head -1)" /etc/nginx/nginx.conf
nginx -t && systemctl reload nginx
```

### 5. Let's Encrypt

```bash
rm -f /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
# Удалить сертификат (замени домен на свой)
certbot delete --cert-name vpn.example.com --non-interactive
```

### 6. Hysteria2 (если устанавливался)

```bash
systemctl disable --now hysteria-server 2>/dev/null || true
rm -f /usr/local/bin/hysteria
rm -rf /etc/hysteria/
rm -f /etc/systemd/system/hysteria-server.service
systemctl daemon-reload
```

### 7. Опционально — бэкапы и UFW

```bash
rm -rf /root/xray-backups/
# Убрать нестандартный порт REALITY (если менялся, например 8443)
ufw delete allow 8443/tcp 2>/dev/null || true
# Порты 22, 80, 443 трогать не нужно
```

### Финальная проверка

```bash
which xray xray-manager 2>/dev/null || echo "OK: бинарники удалены"
ls /usr/local/etc/xray/ 2>/dev/null || echo "OK: конфиг-директория удалена"
systemctl list-units --all | grep -E "xray|hysteria" || echo "OK: сервисы отсутствуют"
ls /etc/nginx/sites-enabled/
```

### Известная проблема: права на config.json

Xray-core запускается от пользователя `nobody`, но менеджер пишет `config.json` от `root`. После каждого изменения конфига через менеджер права сбрасываются → сервис падает с `permission denied`.

Быстрый фикс (до исправления в коде):

```bash
chown nobody:nogroup /usr/local/etc/xray/config.json
chown nobody:nogroup /usr/local/etc/xray/.keys.* 2>/dev/null || true
chmod 640 /usr/local/etc/xray/config.json
systemctl start xray
```

Правильное исправление — добавить в `xray_restart()` в `05-config.sh`:

```bash
xray_restart() {
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
    systemctl restart xray
}
```

### Известная проблема: xray.service в состоянии failed

После официального uninstall сервис может остаться в статусе `failed` (юнит-файл удалён, но запись в systemd не сброшена). Симптом в `list-units`:

```
● xray.service   not-found failed   failed
```

Исправление:

```bash
systemctl reset-failed xray.service 2>/dev/null || true
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/xray@.service
systemctl daemon-reload
```

---

---

## Версионирование

### Где менять версию при бампе

При выпуске новой версии нужно обновить **все** следующие файлы и строки:

| Файл | Строка | Что менять | Пример |
|---|---|---|---|
| `modules/01-constants.sh` | ~8 | `MANAGER_VERSION="X.Y.Z"` | `MANAGER_VERSION="2.7.4"` |
| `modules/00-header.sh` | ~4 | `#  Xray Manager vX.Y.Z` | `#  Xray Manager v2.7.4` |
| `scripts/install.sh` | ~89 | `Установка стека vX.Y.Z` | `Установка стека v2.7.4` |
| `CHANGELOG.md` | верх файла | добавить блок `## [X.Y.Z] — ДАТА` | см. формат ниже |
| `docs/ENGINEERING.md` | ~3 | `> Xray Manager vX.Y.Z` | `> Xray Manager v2.7.4` |

> ⚠️ `xray-manager.sh` в корне **не редактировать вручную** — это артефакт сборки.  
> Он пересобирается из модулей командой `make build` или `cat modules/*.sh > xray-manager.sh`.

### Автоматическая проверка консистентности

```bash
# Извлечь версии из всех файлов и сравнить
grep -h 'MANAGER_VERSION=\|Xray Manager v\|стека v' \
    modules/01-constants.sh modules/00-header.sh scripts/install.sh \
    | grep -oP '[\d]+\.[\d]+\.[\d]+'
```

Все четыре строки должны давать одинаковое значение.

### Формат записи CHANGELOG.md

```markdown
## [X.Y.Z] — YYYY-MM-DD

### 🔴 Исправлено (критичные)

**`файл` — краткое название**  
Причина и симптом. Исправлено: что сделано.

### 🟡 Исправлено

**`файл` — краткое название**  
Описание.

### ✨ Новое

**Название фичи** — описание.
```

---

## Тестирование

```bash
# Синтаксис собранного файла
bash -n xray-manager.sh

# Сборка + проверка через Makefile
make build
make check

# Синтаксис отдельного модуля
bash -n modules/08-protocols.sh
```

### Известные предупреждения shellcheck

| Код | Место | Причина |
|---|---|---|
| SC2034 | Весь скрипт | Динамический `printf -v` — переменные используются |
| SC2086 | jq-фильтры | Намеренно — jq требует нераскрытые переменные |
| SC2046 | SSH opts | Намеренно — opts это список флагов |
