# Changelog

> Все значимые изменения документируются здесь.  
> Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)

---

## [2.8.3] — 2026-04-03

### 🔴 Исправлено (критичные)

**Nginx stream: нет скорости в REALITY через stream-режим** (`scripts/install.sh`)

Три бага в генерируемом `/etc/nginx/stream.d/stream-443.conf`:

1. **`default nginx_https`** — REALITY-трафик (SNI = `github.com`) попадал в nginx HTTPS вместо Xray. Клиент получал HTML-ответ вместо VPN-туннеля. Исправлено: `default xray_local`.

2. **`proxy_protocol on`** — nginx отправлял Proxy Protocol заголовок в Xray, который настроен с `"xver": 0` и не принимает его. Соединение обрывалось на уровне протокола. Убрано.

3. **Отсутствовал `upstream xray_local`** — map ссылался на несуществующий upstream. Добавлено:
   ```nginx
   upstream xray_local { server 127.0.0.1:${XRAY_LOCAL_PORT}; }
   ```

**Переименование upstream:** `xray_reality` → `xray_local` для точности (Xray не занимается REALITY-хендшейком на уровне nginx; nginx лишь проксирует TCP на localhost).

### ✨ Новое

**`ext_port` в `.keys.<tag>`** (`modules/07-links.sh`, `modules/08-protocols.sh`)

В stream-режиме при добавлении REALITY-протокола сохраняется `ext_port: 443`. `gen_link()` читает его и подставляет в URI-ссылку вместо внутреннего порта (18443). Клиент получает корректный адрес подключения `:443`.

**`_link_name()` в `07-links.sh`**

Отображаемое имя в URI-фрагменте (`#name`): для первого пользователя (`email=main`) показывает тег протокола (`vless-de`), для остальных — `tag@email` (`vless-de@alice`).

**Сводная таблица портов при USE_STREAM=true в summary** (`scripts/install.sh`)

До подтверждения [Y/n] показывается реальный порт Xray:
```
REALITY порт: 443 (stream → Xray inbound: 18443)
```

---

## [2.6.0] — 2026-03-26

### 🏗 Архитектура — модульная сборка

Скрипт разбит на 18 модулей. Дистрибуция по-прежнему одним файлом: сборка через `make build` → `cat modules/*.sh > xray-manager.sh`. Никаких `source` в рантайме — trap, `_TMPFILES`, `set -euo pipefail` работают без изменений.

```
modules/
├── 00-header.sh        13   shebang, trap, _TMPFILES
├── 01-constants.sh     32   версия, пути, цвета
├── 02-ui.sh           109   box_*, ask, spin, ok/err/warn
├── 03-system.sh        71   need_root, deps, BBR
├── 04-xray-core.sh    104   установка ядра
├── 05-config.sh        67   cfg/cfgw, ib_*, kset/kget, gRPC API
├── 06-limits.sh       141   лимиты, check_limits, systemd timer
├── 07-links.sh        182   gen_link, urlencode, pick_inbound
├── 08-protocols.sh   1091   все proto_*
├── 09-users.sh        544   menu_protocols, user_*
├── 10-manage.sh        71   menu_manage, geodata
├── 11-subscription.sh 674   subscription server
├── 12-system.sh       126   backup/restore/remove
├── 13-compat.sh        58   SSH helpers, compat aliases
├── 14-telemt.sh       622   MTProto
├── 15-hysteria2.sh    541   Hysteria2 standalone
├── 16-routing.sh      834   routing + profiles
└── 99-main.sh         100   main_menu, entrypoint
```

**Makefile:** `make build` — сборка + `bash -n`, `make check` — shellcheck, `make release` — +sha256, `make ls` — таблица модулей.

### ➕ Новые протоколы (из официальных Xray-examples)

**VLESS + gRPC + REALITY** (`proto_vless_grpc_reality`) — gRPC поверх REALITY без домена и TLS-сертификата. Генерирует x25519 + shortId. `flow` пустой (Vision несовместим с gRPC). Пункт **12** в меню протоколов.

**VLESS + SplitHTTP + TLS/H3** (`proto_vless_splithttp_tls`) — транспорт `splithttp` поверх QUIC. Два режима ALPN: `h3` (прямое подключение) и `h2,http/1.1` (через CDN). Требует домен и TLS-сертификат. Пункт **13** в меню протоколов.

Оба протокола добавлены в `gen_link`:
- `vless:grpc_reality` → `vless://...?security=reality&type=grpc&serviceName=...`
- `vless:splithttp` → `vless://...?security=tls&type=splithttp&path=...`

### 🔒 Безопасность и корректность (из Xray-examples)

- **`dest` → `target` в `proto_vless_tcp_reality`** — поле `realitySettings.dest` переименовано в `target` начиная с Xray 24.10.31. Старое поле не обрабатывается — Xray не запускался. TCP был единственным незафиксированным местом (XHTTP был исправлен в 2.0.0).
- **`sniffing.routeOnly: true`** во всех REALITY-inbound — sniffing применяется только для маршрутизации, не переопределяет реальный адрес назначения. Корректная семантика для REALITY, где `target` — камуфляжный хост.
- **`sniffing.destOverride` + `"quic"`** в `proto_vless_tcp_reality` — добавлен пропущенный тип; все примеры Xray-examples используют `["http","tls","quic"]`.

### ⚡ Улучшения

- **`spiderX` в `gen_link`** для TCP+REALITY, XHTTP+REALITY и gRPC+REALITY — детерминированный `/hex8` от sha256(email). Уникален для каждого пользователя, не меняется между вызовами. Официально рекомендован для улучшения маскировки.
- **`kset()` — устранена гонка состояний** — заменён хардкод `/tmp/_k` на `mktemp` + регистрацию в `_TMPFILES`. Параллельные вызовы `kset` (например, при добавлении нескольких пользователей быстро) больше не конфликтуют.

---

## [2.5.1] — 2026-03-25

> Мерж v5 (база) + точечные улучшения из v6 и синтез.

### 🔒 Безопасность

- **`do_restore()` — расширен whitelist path traversal** — добавлены паттерны `^\./usr/local/etc/xray/` и `^\./var/log/xray/`, `^\.$`, `^\./$`. Архивы, созданные через `tar -czf ... -C / ./usr/...`, содержат `./`-префикс — без этих паттернов они ложно срабатывали как подозрительные.
- **`do_restore()` — диагностический вывод** — подозрительные пути выводятся через `box_row` (до 5 строк) вместо одной строки `info`.

### ⚡ Производительность

- **`gen_link()` — тройной fallback IP** — `$3` (явный) → `_CACHED_SERVER_IP` (env) → `server_ip()`. Обратно совместим.
- **`_sub_links_for_email()` — локальный кеш IP** — `sip` вычисляется один раз до цикла, передаётся как `$3`. При вызове из `_sub_all_links` HTTP-запрос не выполняется совсем.

### 🔧 Исправления

- **`cfgw()` — регистрация в `_TMPFILES`** — последний `mktemp` без регистрации.
- **`do_backup()` — информативная ротация** — выводится `info "Удалено старых бэкапов: N"` + `info "Всего: N"`.

---

## [2.5.0] — 2026-03-25

### 🔒 Безопасность

- **Защита от path traversal в `do_restore()`** — перед распаковкой архива проверяются все пути через `tar -tz`. Закрывает класс атак через специально сформированный `.tar.gz`.
- **Улучшена валидация имени пользователя** — разрешены только `a-zA-Z0-9._@-`. Предотвращает инъекцию спецсимволов в URI и имена файлов.

### ⚡ Производительность

- **`check_limits` — один батч-запрос вместо N×2 форков** — при 50 пользователях снижает количество форков с 100 до 1 на каждый цикл таймера.
- **`server_ip()` кешируется до цикла генерации ссылок** — через `export _CACHED_SERVER_IP` в `_sub_all_links()`.

### 🔧 Исправления

- **Переобъявление цветовых переменных в compat-секции** — блок с одинарными кавычками переопределял цвета. Весь UI блока Hysteria2 (~1500 строк) получал невалидный вывод.
- **Ротация бэкапов** — `do_backup()` хранит последние 7 архивов.
- **`trap _cleanup EXIT`** — все `mktemp` регистрируются в `_TMPFILES[]`.

---

## [2.4.0] — 2026-03-24

### ➕ Подписка — расширенные настройки

- `sub_set_interval()` — интервал 1–168 ч, без перезапуска
- `sub_toggle_autoupdate()` — автопересоздание файлов при `user_add`
- Пункты **6) ⏱ Интервал** и **7) 🔁 Автообновление** в меню подписки

### 🔧 Горячее добавление/удаление пользователей

- `xray_api_add_user()` / `xray_api_del_user()` — через `xray api adu/rmu` на `127.0.0.1:10085`
- Fallback на `restart` только если Xray не активен

### 🏗 Структура репозитория

- `nginx/`, `configs/xray/`, `scripts/install.sh`, `scripts/certbot-deploy-hook.sh`, `docs/setup.md`

---

## [2.3.0] — 2026-03-22

### ➕ Расширенные функции (меню 5)

- **Fragment + Noises** — фрагментация TLS ClientHello, UDP-шум
- **Fallbacks** — интерактивное управление, `fallback_add/show/clear`
- **Hysteria2 Outbound** — relay/цепочка VPS1 → VPS2
- **Балансировщик + Observatory** — `random/roundRobin/leastPing/leastLoad`
- **Metrics endpoint** — `/debug/vars` + `/debug/pprof/`

---

## [2.2.0] — 2026-03-22

### ➕ Hysteria2 нативный Xray — новый протокол

- `proto_hysteria_xray()` — `protocol: hysteria`, `network: hysteria`, `settings.users`
- Port Hopping через `hysteriaSettings.udphop`
- Полная интеграция со Stats API и `.limits.json`

### 🔧 Рефакторинг

- `ib_emails()` — унифицированный хелпер для `.clients` и `.users`
- `_remove_user_from_tag()` — очищает оба поля

---

## [2.1.0] — 2026-03-22

### 📡 MTProto (telemt)

- systemd и Docker режимы, REST API без перезапуска, SSH-миграция

### 🚀 Hysteria2 (отдельный бинарник)

- ACME (LE/ZeroSSL/Buypass), Port Hopping, Masquerade, SSH-миграция

---

## [2.0.0] — 2026-03-22

### ➕ Протоколы, лимиты, Stats API

| Протокол | Транспорт | Особенность |
|---|---|---|
| VLESS | gRPC + TLS | HTTP/2, `grpc_pass` |
| VLESS | HTTPUpgrade + TLS | Без ALPN fingerprint |
| VMess | WebSocket + TLS | `vmess://base64(JSON)` |
| VMess | TCP + TLS | Простейшая конфигурация |
| Shadowsocks | TCP | `2022-blake3-aes-256-gcm`, multi-user |

### 🐛 Исправлено

| Баг | Влияние |
|---|---|
| `pbk` читался из `/Password/` вместо `/PublicKey/` | **Критический** |
| XHTTP: `dest` вместо `target` в `realitySettings` | Xray не запускался |
| XHTTP `flow` должен быть `""` | Ошибка подключения |

---

## [1.0.0] — 2026-03-01

### 🎉 Первый релиз

VLESS+TCP+REALITY, VLESS+XHTTP+REALITY, VLESS+WebSocket+TLS, Trojan+TCP+TLS. Пользователи, QR-коды, бэкап, псевдографика.

---

## Запланировано

- [ ] Xray: ежемесячный сброс счётчика трафика (subscription-модель 30 GB/мес)
- [ ] Xray: формат подписки sing-box JSON (`/{token}/singbox`)
- [ ] Xray: массовый импорт пользователей из CSV
- [ ] Xray: TLS-сертификат через certbot/acme.sh
- [ ] Уведомления в Telegram при истечении лимитов
- [ ] IPv6-поддержка в генерации ссылок
- [ ] REALITY «без кражи трафика» — dokodemo-door защита от CF-сканеров
