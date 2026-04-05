
# Changelog

> Все значимые изменения документируются здесь.  
> Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)

---

## [3.0.4] — 2026-04-05

### 🔧 Исправлено

**`scripts/install.sh` — dpkg-прогресс пробивался сквозь spinner**

`apt-get -qq` подавляет вывод apt, но не dpkg — он открывает псевдотерминал
и пишет `Unpacking ...` / `Setting up ...` напрямую поверх spinner-строки.
Добавлен флаг `-o Dpkg::Use-Pty=0` в `apt_install_quiet()`: запрещает dpkg
открывать pty, весь вывод идёт только через apt-канал и подавляется `-qq`.

Шаг 1 теперь выглядит как ожидается:
```
[1/7] Установка зависимостей
 ✓ Индексы обновлены
 ✓ nginx 1.29.7: обновлён из nginx.org
 → Устанавливаем: certbot python3-certbot-nginx ...
 ⠸ apt-get install...
 ✓ [2/7] ...
```

---


## [3.0.3] — 2026-04-05

### 🔴 Исправлено (критичные)

**`scripts/install.sh` — `SUB_TOKEN: unbound variable` при выборе архитектуры**

При рефакторинге блока параметров (введён выбор архитектуры nginx ↔ Xray)
строка `SUB_TOKEN=$(openssl rand -hex 16)` была удалена из оригинального блока
вместе с остальным кодом, но не добавлена в новый блок до сводки.
Установщик падал с `line 429: SUB_TOKEN: unbound variable` сразу после
подтверждения параметров.

Исправлено: `SUB_TOKEN` генерируется явно перед выводом сводки.

### ✨ Новое

**`scripts/install.sh` — выбор архитектуры nginx ↔ Xray при установке**

Вместо автоматического определения конфликта порта 443 пользователь явно
выбирает один из трёх режимов:

| # | Режим | Описание |
|---|---|---|
| 1 | `stream` | nginx stream на 443, SNI-routing: домен → nginx(4443), чужой сайт → Xray Reality(18443). Рекомендуется |
| 2 | `nginx-only` | nginx HTTPS на 443, proxy_pass к Xray на loopback. WS/gRPC/HTTPUpgrade. Reality — на отдельном порту |
| 3 | `xray-direct` | Xray слушает :443 напрямую, nginx не нужен. Только Reality-протоколы |

Сохраняется в `/root/.xray-mgr-install` как `ARCH_MODE`.

**`modules/08-protocols.sh` — полная переписка всех Xray-протоколов**

Переписка на основе рабочих конфигов из xray-install и xray-examples.

*Reality-протоколы (VLESS+REALITY, gRPC+REALITY, XHTTP+REALITY):*
- `"network":"raw"` вместо `"tcp"` — корректное имя транспорта в Xray-core ≥ 24.x
- `realitySettings.dest` вместо `realitySettings.target` — поле `target` молча игнорировалось ядром, camouflage forwarding не работал
- `"shortIds": [$sid, ""]` — пустой shortId разрешает клиентов без shortId
- `"flow":"xtls-rprx-vision"` обязателен для TCP/RAW, пустой для gRPC/XHTTP

*nginx-proxied протоколы (WS, gRPC, HTTPUpgrade, VMess-WS):*
- `"listen":"127.0.0.1"` — Xray не слушает на публичном интерфейсе
- `"security":"none"` — TLS снят nginx до Xray; двойной TLS → рукопожатие падало
- Убраны вопросы про cert/key/домен — сертификат принадлежит nginx
- После `ib_add` автоматически вызывается `nginx_add_ws_location` / `nginx_add_grpc_location`

**`modules/05-config.sh` — nginx-хелперы для динамического управления location-блоками**

| Функция | Описание |
|---|---|
| `nginx_ok()` | Проверяет наличие nginx и vhost |
| `nginx_domain()` | Читает домен из установленного vpn.conf |
| `_nginx_upsert_block(id, block)` | Атомарно вставляет/заменяет именованный блок; при `nginx -t` failure — rollback из .bak |
| `nginx_add_ws_location(path, port)` | WS/HTTPUpgrade proxy_pass блок |
| `nginx_add_grpc_location(svc, port)` | gRPC grpc_pass блок |
| `nginx_del_location(type, port)` | Удаляет location при удалении протокола |

**`nginx/sites/vpn.conf` — убран хардкод WS location, добавлен плейсхолдер**

Хардкод `location /ws { proxy_pass http://127.0.0.1:WS_PORT; }` удалён.
Добавлен маркер `# XRAY_LOCATIONS_PLACEHOLDER` — location-блоки вставляются
автоматически при добавлении протокола.

---

## [3.0.2] — 2026-04-05

### 🔴 Исправлено (критичные)

**`scripts/install.sh` — `nginx -t` падал с "No such file or directory" для `nginx.conf`**

На системах где nginx.org был установлен через `_ensure_nginx_official`, но `/etc/nginx/nginx.conf` по какой-либо причине отсутствовал (неполная установка, повторный запуск после сбоя, конфликт пакетов), `nginx -t` в шаге 3 завершался с:
```
nginx: [emerg] open() "/etc/nginx/nginx.conf" failed (2: No such file or directory)
```

**Три исправления:**
- `mkdir -p /var/log/nginx /var/lib/nginx` до `nginx -t` — устраняет сопутствующую ошибку `error.log: No such file or directory`
- Guard `[[ -f /etc/nginx/nginx.conf ]]` перед бэкапом — бэкап не падает если файла ещё нет
- Fallback `elif [[ ! -f /etc/nginx/nginx.conf ]]` — если репозиторный `nginx.conf` недоступен (`REPO_DIR` некорректен) и системного тоже нет, генерируется минимальный валидный конфиг с `include sites-enabled/*` и `include conf.d/*.conf`

**`modules/08-protocols.sh` — steal-yourself несовместим с nginx stream-режимом**

В stream-режиме (REALITY + HTTPS на порту 443) SNI нашего домена маршрутизируется nginx → HTTPS backend (4443). `target = 127.0.0.1:${NGINX_PORT}` при таком SNI создавал замкнутый круг: Xray маскировался под наш домен, но сам пробрасывал трафик обратно в nginx, который его снова возвращал. Клиент не мог подключиться.

Все три функции (`proto_vless_tcp_reality`, `proto_vless_xhttp_reality`, `proto_vless_grpc_reality`) возвращены к классическому внешнему `target = SNI:443`. Интерактивный выбор `_nginx_port`/`_domain` и smart-detect логика удалены.

---

## [3.0.1] — 2026-04-05

### 🔴 Исправлено (критичные)

**`scripts/install.sh` — certbot HTTP-01 всегда падал при установке nginx из nginx.org**

**Симптом:** certbot возвращал `Some challenges have failed`, диагностика показывала `✓ HTTP :80 доступен (статус 404)` — что маскировало реальную проблему.

**Причина:** nginx.org при установке создаёт собственный `nginx.conf` с `include conf.d/*.conf` — без `sites-enabled/*`. Репозиторный `nginx.conf` (с обоими include) устанавливался только в шаге 5, **после** certbot в шаге 4. Поэтому `acme-temp.conf`, размещённый в `sites-enabled/`, nginx физически не загружал. Запросы на `/.well-known/acme-challenge/` обслуживал `conf.d/default.conf` от nginx.org, возвращая 404.

**Исправление:**
- Репозиторный `nginx.conf` устанавливается в **шаге 3** (до ACME), а не в шаге 5.
- `conf.d/default.conf` и `sites-enabled/default` удаляются там же — перед первым `systemctl restart nginx`.
- Создание `sites-available/`, `sites-enabled/`, `stream.d/`, `conf.d/` перенесено в шаг 3.
- Блок в шаге 5, дублировавший установку `nginx.conf`, заменён однострочным `mkdir -p /etc/nginx/stream.d`.

**`scripts/install.sh` — `load_module` для dynamic stream терялся при перезаписи `nginx.conf`**

В шаге 1, при установке stream-модуля как dynamic `.so` (Ubuntu/Debian пакет), патч `load_module` добавлялся в `nginx.conf`. В шаге 3 `nginx.conf` перезаписывался репозиторным — патч терялся. nginx падал с `unknown directive "stream"` при следующем `nginx -t`.

**Исправление:** блок `load_module` перенесён из шага 1 в шаг 3 — применяется **после** копирования репозиторного `nginx.conf`. Репозиторный конфиг уже содержит `include /etc/nginx/modules-enabled/*.conf`, который покрывает большинство дистрибутивов; `load_module` используется только как fallback для систем без `modules-enabled` symlink.

**`scripts/install.sh` — `diagnose_certbot_failure` трактовала 404 на ACME path как успех**

`/.well-known/acme-challenge/test` возвращал 404 → функция печатала `✓ HTTP :80 доступен` зелёным. Это скрывало именно ту проблему, которую диагностика должна была выявлять.

**Исправление:** три ветки вместо двух:
- `200` → `✓` webroot корректен
- `404` → `⚠` nginx запущен, но ACME path не обслуживается — webroot не загружен + подсказка `nginx -T | grep include`
- всё остальное → `✗` nginx не отвечает на порт 80

---

## [3.0.0] — 2026-04-05

### ✨ Новое

**`scripts/install.sh` — `diagnose_certbot_failure()`**  
При провале `certbot certonly` (Some challenges have failed) вместо сырого traceback выводится структурированная диагностика: проверяются DNS A-запись, HTTP доступность `/.well-known/`, UFW, Cloudflare Proxy по диапазону IP, `nginx -t`. Для каждого провала — конкретная инструкция. В конце — 5 типовых сценариев и путь к `/var/log/letsencrypt/letsencrypt.log`.

**`scripts/install.sh` — `--dry-run` режим (preflight без изменений)**  
`sudo bash scripts/install.sh --dry-run` — выводит план установки без записи конфигов и изменения системы. Позволяет предвалидировать домен/порты/параметры до запуска.

**`scripts/install.sh` — `load_module` edge-case для dynamic stream**  
После установки stream-модуля проверяется что директива `load_module` присутствует в `nginx.conf`. На Ubuntu/Debian .so-файл устанавливается, но `load_module` может отсутствовать — это вызывает скрытый `nginx: [emerg] unknown directive "stream"` при первом тесте конфига. Если директива отсутствует, она добавляется автоматически.

### 🟡 Улучшено

**`scripts/install.sh` — многоступенчатый fallback stream-модуля**  
Цепочка попыток: `nginx-module-stream` → `nginx-full` → `libnginx-mod-stream`. При неудаче всех трёх — явный `err` + `exit 1` с actionable подсказками вместо тихого падения.

**`scripts/install.sh` — устойчивость nginx keyring**  
`rm` старого keyring + `gpg --dearmor --yes` перед записью нового — устраняет сбои идемпотентности при повторном запуске.

**`modules/02-ui.sh`, `modules/99-main.sh` — детерминированный `printf` для рамок**  
`printf '%*s' "$i"` → `printf '%*s' "$i" ""` в отрисовке рамок/разделителей.

**`modules/11-subscription.sh` — локализация переменных**  
`local confirm` в `sub_toggle_autoupdate()` — устраняет утечку во внешнюю область видимости.

### 📄 Документация

`docs/CODE_AUDIT_REPORT.md`, `docs/DIFF_LINES_REPORT.md`, `docs/IMPROVEMENT_UNIFIED.md` — инженерная обратная связь по аудиту, line-level diff и roadmap улучшений.

---

## [2.9.1] — 2026-04-05

### 🟡 Улучшено (стабильность install-flow)

**`scripts/install.sh` — keyring nginx.org и stream-модуль стали надёжнее**  
Добавлено удаление старого keyring + `gpg --dearmor --yes` перед записью нового — устраняет сбои при повторном запуске. Stream-модуль устанавливается по цепочке приоритетов: `nginx-module-stream` → `nginx-full` → `libnginx-mod-stream`; при неудаче выводится явный `err` и `exit 1` с подсказкой вместо тихого падения. Добавлено создание `sites-available` / `sites-enabled` до конфигурирования vhost.

**`modules/02-ui.sh`, `modules/99-main.sh` — детерминированный `printf` для рамок**  
`printf '%*s' "$i"` заменено на `printf '%*s' "$i" ""` в местах отрисовки рамок и разделителей — устраняет неоднозначность поведения printf в разных shell-окружениях.

**`modules/11-subscription.sh` — локализация переменных в `sub_toggle_autoupdate()`**  
Добавлен `local confirm` в обеих ветках функции — устраняет утечку переменной во внешнюю область видимости.

### 📄 Документация

Добавлены `docs/CODE_AUDIT_REPORT.md`, `docs/DIFF_LINES_REPORT.md`, `docs/IMPROVEMENT_UNIFIED.md` — инженерная обратная связь по аудиту, line-level diff и roadmap улучшений.

---

## [2.9.1] — 2026-04-05

### 🔧 Исправлено

**`scripts/install.sh` — падение установки при отсутствии stream module под `set -e`**

Одиночный вызов `apt_install_quiet nginx-full` завершался с ненулевым кодом на системах, где пакет недоступен или конфликтует. Под `set -euo pipefail` это прерывало весь установщик с незакрытым spinner'ом.

Заменено на трёхуровневую fallback-цепочку с явным управлением spinner:

| Попытка | Пакет | Применимость |
|---|---|---|
| 1 | `nginx-module-stream` | nginx.org mainline (уже включён в пакет) |
| 2 | `nginx-full` | Ubuntu/Debian — собран с `--with-stream` |
| 3 | `libnginx-mod-stream` | Debian-специфичный пакет модуля |

При полном провале: `spin_stop "err"` + два `warn` + `USE_STREAM=false` — установка продолжается без stream-режима вместо аварийного выхода.

**`modules/02-ui.sh`, `modules/99-main.sh` — нестабильная отрисовка рамок**

`printf '%*s' "$i"` без второго аргумента не определено стандартом POSIX: `%s` без аргумента может подставить мусор или пустую строку в зависимости от реализации. Исправлено на явный пустой аргумент `printf '%*s' "$i" ""` во всех 10 местах (5 в каждом файле).

### ✨ Новое

Все изменения Phase 1 из v2.9.0 (dry-run, APT-обёртки, confirm_word, render_status_bar, unified status bar) теперь задокументированы в `docs/ENGINEERING.md` §15–16 и полностью отражены в `CHANGELOG.md`.

---

## [2.9.0] — 2026-04-04

### 🔴 Исправлено (критичные)

**`modules/05-config.sh` — `xray_restart()` перезапускал Xray без валидации конфига**  
При любой ошибке в JSON (сломанный конфиг, неверное jq-выражение в `cfgw`) Xray падал молча, все клиентские подключения обрывались, а функция возвращала 0 — ошибка не всплывала. Исправлено: перед `systemctl restart` выполняется `xray run -test -c config.json`; при ошибке валидации перезапуск отменяется, выводится сообщение об ошибке, возвращается код 1.

**`modules/04-xray-core.sh` — `_init_config()` перезаписывала весь конфиг при обновлении ядра**  
При вызове «Обновить Xray-core» функция проверяла наличие `stats`/`api`/`policy` через один jq-вызов. Если хотя бы один блок отсутствовал — перезаписывала `config.json` с `"inbounds": []`, уничтожая все настроенные протоколы. Исправлено: хирургический jq-merge добавляет только отсутствующие блоки без изменения `inbounds`. Базовый шаблон вынесен в `_write_base_config()` и вызывается только при полном отсутствии файла.

### 🟡 Исправлено

**`scripts/install.sh` — `mkdir stream.d` выполнялся только при замене nginx.conf**  
При повторной установке, когда nginx.conf уже содержал `include stream.d/*.conf`, директория не создавалась — nginx падал при первом же `nginx -t`. Исправлено: `mkdir -p /etc/nginx/stream.d` вынесен безусловно перед условными блоками.

**`scripts/install.sh` — nginx из системного репозитория Ubuntu (1.24) устаревший**  
Ubuntu 22.04/24.04 поставляет nginx 1.24: нет stream module по умолчанию (нужен `nginx-full`), старый синтаксис `http2` в listen. Добавлена функция `_ensure_nginx_official()`: при версии < 1.25 подключается репозиторий `nginx.org/packages/mainline`, устанавливается актуальный nginx с включённым stream module. Fallback на системный nginx при недоступности репозитория.

**`nginx/sites/vpn.conf` — `HTTP2_DIRECTIVE` отсутствовал на IPv6 listen**  
`listen [::]:NGINX_PORT ssl;` не содержал плейсхолдер `HTTP2_DIRECTIVE` — IPv6-клиенты подключались по HTTP/1.1. Исправлено добавлением плейсхолдера; `sed` в `install.sh` уже заменяет его глобально, дополнительных изменений не требовалось.

**`modules/08-protocols.sh` — steal-yourself без проверки доступности nginx**  
При выборе SNI равного домену сервера Xray направляет TLS на `127.0.0.1:nginx_port`. Если nginx не запущен — конфиг записывался, Xray стартовал, но клиенты не могли подключиться без видимой ошибки. Добавлена проверка `ss -tlnp` перед записью конфига; при отсутствии nginx выводится предупреждение с запросом подтверждения.

### 🟡 Исправлено (статический анализ)

**`SC2155` — `local` маскировал ненулевой exit-код команд-подстановок** (`modules/14-telemt.sh`, `modules/15-hysteria2.sh`, `modules/07-links.sh`)

`local var="…$(cmd)…"` всегда возвращает 0 независимо от `cmd`. Разделено на `local var; var="…$(cmd)…"` во всех трёх местах: путь к бэкапу в Hysteria2, timestamp бэкапа nginx-stream в telemt, fallback-цепочка `${3:-${_CACHED_SERVER_IP:-$(server_ip)}}` в `gen_link`.

**`SC2164` — `cd` без обработки ошибки** (`modules/14-telemt.sh:379`)

`cd "$TELEMT_WORK_DIR_DOCKER"` перед `docker compose up` не имел fallback — при отсутствии директории `docker compose` запускался бы в непредсказуемом рабочем каталоге. Добавлено `|| die "Директория не найдена: $TELEMT_WORK_DIR_DOCKER"` в соответствии с паттерном остальных `cd`-вызовов в том же модуле.

**`SC2059` — `printf` с переменной в позиции format-строки** (`modules/02-ui.sh`)

22 строки UI-функций (`box_top`, `box_end`, `mi`, `ok`, `err` …) используют ANSI-переменные (`${DIM}`, `${R}`, `${GREEN}` …) как часть format-строки printf. ANSI escape-последовательности никогда не содержат `%`, поэтому предупреждение ложноположительное; добавлен точечный `# shellcheck disable=SC2059` с комментарием вместо переписывания 22 строк.

### 🔧 Рефакторинг

**`Makefile` — качество lint-сигнала**

В таргет `check` добавлены `--shell=bash` (снимает ложный `SC2148` «нет shebang» на фрагментах модулей) и `-e SC2148` (явная исключение). После этого `make check` показывает только реально actionable предупреждения.

### ✨ Новое

**`--dry-run` режим установщика** (`scripts/install.sh`)

```bash
sudo bash scripts/install.sh --dry-run
```

После ввода параметров выводит полный план установки (APT update, preflight, пакеты, certbot, Xray, nginx) и выходит без единого изменения в системе. Реализован через `run_step()` — тонкую обёртку, которая в dry-run печатает `[dry-run] описание: команда`, в реальном режиме просто исполняет её.

**APT-обёртки** (`scripts/install.sh`)

| Функция | Что делает |
|---|---|
| `preflight_repo_check url name` | HEAD-запрос с таймаутом 12 с; при недоступности — `warn` + `return 1`, установка продолжается без репозитория |
| `apt_update_quiet` | `apt-get update` с `Acquire::Retries=3`, `Timeout=15` |
| `apt_install_quiet …` | `DEBIAN_FRONTEND=noninteractive`, `--force-confdef/confold` |
| `apt_remove_quiet …` | Аналогично, для удаления пакетов |

`preflight_repo_check` применяется перед добавлением `nginx.org` — если репозиторий недоступен (прокси, файрвол), установщик явно предупреждает и продолжает с системным nginx вместо зависания на `apt-get update`.

**`confirm_word(phrase)`** (`modules/02-ui.sh`)

Примитив для деструктивных операций: просит ввести конкретное слово, возвращает 0 только при точном совпадении. Использование: `confirm_word "УДАЛИТЬ" || return`.

**`render_status_bar(xray, nginx, sub, ip)`** (`modules/02-ui.sh`)

Унифицированная строка статуса через `box_row`. Принимает уже сформированные строки для каждого компонента.

**Единый статус-бар в главном меню** (`modules/99-main.sh`)

Добавлены `ngx_ic` (nginx) и `sub_ic` (подписка) рядом с Xray-статусом; все три компонента отображаются через `render_status_bar()`. Ранее статус nginx в меню отсутствовал.

**Защита `do_remove_all()`** (`modules/12-system.sh`)

Двойной `y/n`-confirm заменён на `confirm_word "УДАЛИТЬ"`. Случайное нажатие Enter больше не инициирует полное удаление.

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
