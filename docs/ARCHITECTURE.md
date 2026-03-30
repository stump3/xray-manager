# Архитектура Xray Manager v2.7.0

Документ описывает внутреннее устройство менеджера, как модули взаимодействуют и почему сделаны такие архитектурные решения.

---

## 🏗️ Структура проекта

```
xray-manager/
├─ scripts/
│  ├─ install.sh              # Главный установщик (собирает бинарник из modules/)
│  └─ certbot-deploy-hook.sh  # Hook для автоматического обновления сертификатов
│
├─ modules/                   # ← Единственный источник истины (source of truth)
│  ├─ 00-header.sh           # POSIX shebang + trap для очистки
│  ├─ 01-constants.sh        # Пути, версии, порты
│  ├─ 02-ui.sh               # Функции UI (меню, боксы)
│  ├─ 03-system.sh           # Системные проверки
│  ├─ 04-xray-core.sh        # Установка Xray-core
│  ├─ 05-config.sh           # JSON манипуляции (cfgw, xray_restart)
│  ├─ 06-limits.sh           # Лимиты на юзеров
│  ├─ 07-links.sh            # Генерация ссылок и QR-кодов
│  ├─ 08-protocols.sh        # Добавление/удаление протоколов (57 KB!)
│  ├─ 09-users.sh            # Управление юзерами (gRPC API)
│  ├─ 10-manage.sh           # Меню управления (статус, логи)
│  ├─ 11-subscription.sh     # HTTP сервер подписей (Python)
│  ├─ 12-system.sh           # BBR, бэкап, удаление
│  ├─ 13-compat.sh           # Обратная совместимость с v6
│  ├─ 14-telemt.sh           # MTProto для Telegram
│  ├─ 15-hysteria2.sh        # Hysteria2 (QUIC/UDP)
│  ├─ 16-routing.sh          # Маршрутизация трафика
│  └─ 99-main.sh             # Точка входа (main_menu)
│
├─ nginx/                     # Конфиги Nginx
│  ├─ base.conf              # Базовая конфигурация
│  └─ stream.d/              # Конфиги для stream (TCP мультиплексирование)
│
├─ configs/
│  └─ xray/
│     ├─ base.json           # Базовый шаблон Xray конфига
│     └─ base-routing.json   # Шаблон для маршрутизации
│
├─ docs/                     # Документация
│  ├─ setup.md               # Пошаговая инструкция
│  ├─ ARCHITECTURE.md        # ← Этот файл
│  └─ ENGINEERING.md         # Инженерные решения
│
├─ README.md                 # Главный README (v2.7.0 версия)
├─ CHANGELOG.md              # История изменений
├─ LICENSE                   # MIT License
└─ Makefile                  # Полезные команды
```

---

## 🔄 Жизненный цикл: от репо к запуску

### 1. Разработка (в репо)

Разработчик работает с **модулями** как с отдельными файлами:

```bash
vim modules/05-config.sh    # Правлю функцию cfgw()
bash modules/99-main.sh     # Тестирую локально

# Или собираю локально для тестирования:
cat modules/*.sh > /tmp/test-manager.sh
bash /tmp/test-manager.sh
```

### 2. Коммит

```bash
git add modules/05-config.sh
git commit -m "fix: cfgw() теперь сбрасывает права"
git push
```

**Важно:** `xray-manager.sh` **никогда** не коммитится! Это артефакт, который собирается на лету.

### 3. Установка (install.sh)

Пользователь запускает:
```bash
curl -fsSL ... | sudo bash
```

install.sh:
1. Скачивает modules/ из репо
2. **Собирает** бинарник:
   ```bash
   cat modules/*.sh > /usr/local/bin/xray-manager
   chmod +x /usr/local/bin/xray-manager
   ```
3. Запускает `/usr/local/bin/xray-manager`

### 4. Запуск

```bash
sudo xray-manager
```

Это выполняет собранный бинарник, который содержит весь код из модулей.

---

## 📦 Модули: назначение и взаимодействие

### Загрузка модулей

**install.sh** выполняет:
```bash
# Собирает в порядке сортировки имён файлов (00, 01, 02, ...)
cat modules/00-header.sh \
    modules/01-constants.sh \
    modules/02-ui.sh \
    ...
    modules/99-main.sh > /usr/local/bin/xray-manager
```

**Порядок важен!** Каждый модуль может использовать функции из предыдущих.

### Модули по категориям

#### 📋 Базовая инфраструктура

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `00-header.sh` | 1.5 KB | POSIX shebang, обработка ошибок, trap для очистки TMPFILES |
| `01-constants.sh` | 2.5 KB | Пути (XRAY_BIN, XRAY_CONF, MANAGER_BIN), версии |
| `02-ui.sh` | 4.5 KB | Функции UI: `tw()`, `cls()`, `mi()`, `ask()`, `confirm()`, `visible_width()` |
| `03-system.sh` | 4.0 KB | Проверки: `need_root()`, `xray_ok()`, `install_deps()`, `server_ip()` |

#### 🔧 Xray управление

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `04-xray-core.sh` | 5.0 KB | Установка/обновление Xray-core из официального릴리즈 |
| `05-config.sh` | 5.0 KB | **Критично!** `cfgw()` (JSON манипуляции), `xray_restart()`, функции инбаундов |
| `09-users.sh` | 25 KB | gRPC API: добавление юзеров, удаление, изменение паспортов |

#### 🌐 Протоколы

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `08-protocols.sh` | 57 KB | **Самый большой!** Добавление/удаление VLESS, VMess, Trojan, SS2022, Hysteria2 |
| `15-hysteria2.sh` | 32 KB | Отдельный сервис Hysteria2 (не встроенно в Xray!) |
| `14-telemt.sh` | 28 KB | Docker контейнер MTProto прокси для Telegram |

#### 🔗 Подписки и ссылки

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `07-links.sh` | 9.5 KB | Генерация ссылок, QR-кодов (через `qrencode`) |
| `11-subscription.sh` | 26 KB | Python HTTP сервер для подписей (Base64 + Clash YAML) |
| `06-limits.sh` | 6.0 KB | Лимиты на скорость и объём данных |

#### ⚙️ Системные функции

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `10-manage.sh` | 4.0 KB | Меню управления (статус, логи, геолокация) |
| `12-system.sh` | 7.0 KB | BBR, бэкап конфигов, удаление (do_remove_all) |
| `16-routing.sh` | 39 KB | Маршрутизация трафика по правилам |

#### 🎯 Точка входа и утилиты

| Модуль | Размер | Назначение |
|--------|--------|-----------|
| `13-compat.sh` | 3.0 KB | Совместимость (функции-обёртки для старых версий) |
| `99-main.sh` | 6.5 KB | `main_menu()` — главное меню и точка входа |

---

## 🔌 Взаимодействие между модулями

### Пример 1: Добавление пользователя

```
[Пользователь выбирает в меню]
      ↓
main_menu() [99-main.sh]
      ↓
menu_users() [09-users.sh]
      ↓
add_user() [09-users.sh]
      ├─ Спрашивает email, протокол
      ├─ Генерирует UUID через `xray api adu` (gRPC)
      ├─ Изменяет config.json через cfgw() [05-config.sh]
      │   └─ 05-config.sh:cfgw() сбрасывает права!
      │
      └─ Обновляет подписку:
          └─ gen_subscription() [11-subscription.sh]
              └─ Регенерирует /var/www/html/sub/ файлы
```

### Пример 2: Исправление БАГ 1 (права на конфиг)

**Сценарий:** Пользователь добавляет протокол через меню

**Старое (v2.6.0) — НЕПРАВИЛЬНО:**
```bash
# В меню (99-main.sh) → выбираем 2) Протоколы
# → Выбираем добавить VLESS

# Вызывается из 08-protocols.sh:
add_protocol_vless()
  → cfgw('.inbounds += [{...}]')  # Пишет config.json
  └─ Права: root:root 600 ❌

# Xray (никто:никто) не может прочитать → ПАДАЕТ
systemctl status xray
  Active: failed (permission denied)
```

**Новое (v2.7.0) — ПРАВИЛЬНО:**
```bash
# То же самое, но в 05-config.sh:
cfgw() {
    local t; t=$(mktemp)
    jq "$1" "$XRAY_CONF" > "$t" || return 1
    mv "$t" "$XRAY_CONF"
    # 🔧 НОВОЕ:
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
}

# Права: никто:никто 640 ✓
# Xray может читать → работает ✓
```

### Пример 3: Управление пользователями через gRPC

```bash
add_user [09-users.sh]
  └─ xray api adu -s 127.0.0.1:10085 [команда из xray]
  │
  └─ Если gRPC недоступен → fallback:
     └─ xray_restart() [05-config.sh]
        └─ systemctl restart xray (полный перезапуск)
```

**Почему не `systemctl reload xray`?**

Xray-core:
- ❌ Не слушает `SIGHUP` (systemctl reload это отправляет)
- ❌ No `ExecReload=` в systemd unit (только `ExecStart=`)
- ✅ **Только** gRPC API или полный перезапуск

Это задокументировано в [ENGINEERING.md](ENGINEERING.md).

---

## 💾 Состояние и конфигурация

### Файлы конфигурации

| Путь | Владелец | Права | Создаёт | Зачем |
|------|----------|-------|---------|-------|
| `/usr/local/etc/xray/config.json` | `nobody:nogroup` | 640 | install.sh | Конфиг Xray-core |
| `/root/.xray-mgr-install` | root | 600 | install.sh | Параметры установки (домен, email, токен) |
| `/usr/local/etc/xray/.keys.*` | `nobody:nogroup` | 600 | менеджер | Приватные ключи REALITY |
| `/var/log/xray/` | syslog | 755 | Xray | Логи (access.log, error.log) |

### TMPFILES и очистка

**В 00-header.sh:**
```bash
_TMPFILES=()
trap '_cleanup' EXIT

_cleanup() {
    # Удаляет все временные файлы из массива _TMPFILES
    for f in "${_TMPFILES[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
```

**Когда добавляется:**
```bash
cfgw() {
    local t; t=$(mktemp)
    _TMPFILES+=("$t")   # ← Регистрируем для очистки
    # ... работа с файлом ...
    # ... в конце cleanup удалит автоматически ...
}
```

---

## 🔐 Процесс изменения конфига (cfgw + xray_restart)

### Диаграмма потока

```
[Пользователь вносит изменение в меню]
           ↓
[Функция из modules/08, 09, 14, 15, 16 вызывает cfgw()]
           ↓
┌─────────────────────────────────────────┐
│ cfgw() [modules/05-config.sh]          │
├─────────────────────────────────────────┤
│ 1. Создаёт временный файл              │
│ 2. Применяет jq фильтр к config.json   │
│ 3. Перемещает tmp → config.json        │
│ 4. ✓ НОВОЕ В 2.7.0:                   │
│    - chown nobody:nogroup              │
│    - chmod 640                         │
│ 5. Регистрирует tmp в _TMPFILES        │
└─────────────────────────────────────────┘
           ↓
[Возврат в вызывающую функцию]
           ↓
[Если нужен перезапуск → вызывается xray_restart()]
           ↓
┌─────────────────────────────────────────┐
│ xray_restart() [modules/05-config.sh]  │
├─────────────────────────────────────────┤
│ 1. Еще раз сбрасывает права (на всякий) │
│ 2. systemctl restart xray               │
│ 3. sleep 1 (ждёт запуска)              │
│ 4. return 0 (всегда успех для меню)    │
└─────────────────────────────────────────┘
           ↓
[Меню продолжает работать]
```

### Почему cfgw() сбрасывает права?

**Проблема (в v2.6.0):**
- `cfgw()` вызывается из 10+ разных мест
- Часть вызывает `xray_restart()` после (права сбрасываются)
- Часть **не вызывает** (права не сбрасываются)
- Результат: **case-by-case** падения Xray

**Решение (v2.7.0):**
- Сбросить права **прямо в cfgw()**
- Теперь независимо от вызывающей функции права всегда корректны

---

## 🎨 UI и рендер меню

### Функция `visible_width()`

**Проблема:** Эмодзи занимают 2 колонки в терминале, но `${#string}` считает их как 1 символ.

```bash
# Без учёта эмодзи
str="🚀 Hysteria2"
echo "${#str}"      # → 12 (думаем что это 12 символов)
# Но на экране это: [ 🚀 Hysteria2]
#                  ^1^2^34567891011
# Видимая ширина = 13!
```

**Решение:**
```bash
visible_width() {
    local text="$1"
    local clean; clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#clean}
    local emoji_count=0
    emoji_count=$(printf "%s" "$clean" | grep -o '[🔧🌐👥⚙️🛠📡🚀🗺]' | wc -l)
    echo $((len + emoji_count))
}

visible_width "🚀 Hysteria2"   # → 13 (корректно!)
```

### Функция `mi()` (menu item)

```bash
mi() {
    local n="$1" ic="$2" lb="$3" badge="${4:-}"
    local w; w=$(tw); local i=$((w-2))  # Ширина терминала минус рамка
    
    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    local vis_lb=$(visible_width "$raw_lb")    # ← Видимая ширина с эмодзи!
    local vis_ic=$(visible_width "$ic")
    
    local raw_badge; raw_badge=$(printf "%b" "$badge" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Считаем реальную заполненность строки
    local used=$(( ${#n} + vis_ic + vis_lb + 8 ))
    local pad=$(( i - used - ${#raw_badge} - 1 ))
    [[ $pad -lt 0 ]] && pad=0
    
    # Рендер с корректным выравниванием
    printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s %b%*s${DIM}│${R}\n" \
        "$n" "$ic" "$lb" "$pad" ""
}
```

**Результат:**
```
│  1) 🔧 Установка / Обновление Xray                      │
│  2) 🌐 Протоколы Xray                (добавить / удалить) │
│  3) 👥 Пользователи Xray            (добавить / лимиты) │
│  4) ⚙️  Управление Xray                (статус / логи)   │
│  5) 🛠 Система                          (BBR / бэкап)    │
│  R) 🗺 Маршрутизация        профиль: custom · 0 правил│
       ↑ всё выровнено правильно!
```

---

## 🚀 Производительность и оптимизации

### Кеширование IP адреса

**Проблема в v2.5.0:**
```bash
gen_link() {
    for each_user in $users; do
        local ip=$(curl icanhazip.com)  # ← БЛОКИРУЕТ! 3 сек за юзера
        # Генерируем ссылку с этим IP
    done
}
```

Если 100 юзеров → 100 × 3 сек = **5 минут** для генерации подписи! 🐢

**Решение (v2.6.0+):**
```bash
_CACHED_SERVER_IP=""

get_server_ip() {
    if [[ -n "$_CACHED_SERVER_IP" ]]; then
        echo "$_CACHED_SERVER_IP"
    else
        _CACHED_SERVER_IP=$(timeout 3 curl -4 -s icanhazip.com || echo "0.0.0.0")
        echo "$_CACHED_SERVER_IP"
    fi
}

gen_link() {
    local ip=$(get_server_ip)  # ← Кеш! Первый раз 3 сек, потом instant
    # Генерируем ссылки (100 юзеров за 0.1 сек)
}
```

**Результат:** 5 минут → **0.5 секунд** (ускорение в 600 раз!) 🚀

---

## 🔗 API интеграции

### Xray gRPC API (127.0.0.1:10085)

**Конфиг (`config.json`):**
```json
{
  "services": {
    "HandlerService": {},
    "StatsService": {}    ← Обязательно для пользовательских команд
  }
}
```

**Команды управления юзерами:**
```bash
# Добавить юзера
xray api adu \
  -s 127.0.0.1:10085 \
  '[
    {
      "inbound": "inbound-tag",
      "user": {
        "email": "user@example.com",
        "password": "123456"
      }
    }
  ]'

# Удалить юзера
xray api rmu \
  -s 127.0.0.1:10085 \
  '[
    {
      "inbound": "inbound-tag",
      "email": "user@example.com"
    }
  ]'
```

**Fallback (если gRPC недоступен):**
```bash
systemctl restart xray  # Полный перезапуск
```

---

## 📊 Структура инбаундов

**Типичный inbound для VLESS+REALITY:**
```json
{
  "tag": "vless-reality",
  "port": 8443,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "uuid-1",
        "email": "user1@example.com"
      },
      {
        "id": "uuid-2",
        "email": "user2@example.com"
      }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "dest": "gstatic.com:443",
      "serverNames": ["gstatic.com"],
      "privateKey": "..."
    }
  }
}
```

**Как изменяется cfgw():**
```bash
# Добавить юзера в VLESS
cfgw('.inbounds[] | select(.tag=="vless-reality").settings.clients += [{"id": "uuid", "email": "user@example.com"}]')

# Удалить юзера
cfgw('.inbounds[] | select(.tag=="vless-reality").settings.clients |= map(select(.email != "user@example.com"))')
```

---

## 🧪 Тестирование новых модулей

### Локальное тестирование

```bash
# 1. Отредактируйте модуль
vim modules/05-config.sh

# 2. Соберите локально
cat modules/*.sh > /tmp/test-manager.sh

# 3. Протестируйте в SANDBOX (не на продакшене!)
bash /tmp/test-manager.sh

# 4. Если OK → коммитьте
git add modules/05-config.sh
git commit -m "fix: описание изменения"
```

### Проверка синтаксиса

```bash
# Синтаксис Bash
bash -n /tmp/test-manager.sh

# Или проверить каждый модуль
for m in modules/*.sh; do
    bash -n "$m" || echo "ERROR in $m"
done
```

---

## 🎓 Лучшие практики разработки

### Добавление нового модуля

1. **Имя файла с номером:**
   ```bash
   modules/17-my-feature.sh  # ← число для сортировки
   ```

2. **Структура:**
   ```bash
   #!/bin/bash
   # Краткое описание функции модуля

   my_function() {
       # Логика
   }

   menu_my_section() {
       cls; box_top " 🎯 Название" "$COLOR"
       box_blank
       # меню-код
       box_blank; box_end; pause
   }
   ```

3. **Вызов из main_menu (99-main.sh):**
   ```bash
   mi "8" "🎯" "Мой раздел"
   # В case:
   8) menu_my_section ;;
   ```

4. **Использование встроенных функций:**
   ```bash
   need_root            # Проверка root
   ok "Сообщение"       # Зелёный OK
   warn "Сообщение"     # Жёлтое WARNING
   err "Сообщение"      # Красная ERROR
   box_top "Заголовок"  # Рамка
   confirm "Вопрос?"    # Подтверждение
   ```

### Обработка ошибок

```bash
# Используйте set -e в начале функции
set -e

# Или проверяйте выход команд
jq ".inbounds" "$XRAY_CONF" >/dev/null || { err "Невалидный JSON"; return 1; }

# Всегда очищайте на выходе
_TMPFILES+=("$tmp_file")
```

### Документирование

```bash
# Каждая функция должна иметь комментарий
cfgw() {
    # Изменить config.json через jq фильтр
    # Args: $1 = jq filter (e.g., '.inbounds += [...]')
    # Returns: 0 if ok, 1 if jq failed
    # Side effects: сбрасывает права на файл
    ...
}
```

---

## 📚 Дополнительные ресурсы

- **[ENGINEERING.md](ENGINEERING.md)** — почему systemctl reload не работает, gRPC vs restart
- **[MIGRATION.md](MIGRATION.md)** — для пользователей, переходящих с v2.6.0
- **[setup.md](setup.md)** — пошаговая настройка
- **[CHANGELOG.md](../CHANGELOG.md)** — история изменений

---

**Версия:** 2.7.0  
**Последнее обновление:** 2026-03-30
