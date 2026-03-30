# Changelog

Все значительные изменения в этом проекте задокументированы в этом файле.

---

## [2.7.0] — 2026-03-30

### 🔥 Критичные исправления (5 багов)

#### БАГ 1: Права на конфиг падают после каждого изменения ⚠️
**Проблема:**  
`cfgw()` писал конфиг с правами `root:root` (600). Юзеры не могли прочитать конфиг → Xray падал с `permission denied`.

**Причина:**  
- Xray запускается от `nobody:nogroup`
- `cfgw()` вызывается из разных мест без `xray_restart()`
- `xray_restart()` сбрасывает права, но далеко не всегда вызывается

**Решение:**  
Добавлен `chown nobody:nogroup` + `chmod 640` **внутри самой `cfgw()`** — теперь права сбрасываются при **каждом** изменении конфига.

**Файл:** `modules/05-config.sh`

```bash
cfgw() {
    local t; t=$(mktemp); _TMPFILES+=("$t")
    jq "$1" "$XRAY_CONF" > "$t" || return 1
    mv "$t" "$XRAY_CONF"
    # 🔧 Сброс прав при любом изменении
    chown nobody:nogroup "$XRAY_CONF" 2>/dev/null || true
    chmod 640 "$XRAY_CONF"
}
```

---

#### БАГ 2: Меню вываливается из рамки (отвисающий `\e[2m`) 🎨
**Проблема:**  
Строка маршрутизации:
```
│  R) 🗺 Маршрутизация  профиль: custom · 0 правил\e[2m │
                                                      ↑ отвисает за рамку
```

**Причина:**  
Использовался **зафиксированный offset** `$((i-56))` для расчёта отступа:
- Когда профиль длиннее "custom" (например "production" = 10 символов вместо 6)
- Счётчик правил → от 0 до 99+ (тоже переменная длина)
- Расчёт становится неверным → отступ уходит в минус

**Решение:**  
Динамический расчёт смещения по реальной длине текста профиля и счётчика:

```bash
local _routing_txt="профиль: $_rp · $_rn правил"
local _routing_vis=$(visible_width "$_routing_txt")
local _routing_pad=$(( i - ${#n} - 4 - 2 - ${#ic} - 2 - 12 - _routing_vis - 1 ))
printf "${DIM}│${R}  ${YELLOW}${BOLD}%s)${R} %s ${CYAN}Маршрутизация${R}  ${DIM}%s${R}%*s${DIM}│${R}\n" \
    "R" "🗺" "$_routing_txt" "$_routing_pad" ""
```

**Файл:** `modules/99-main.sh`

---

#### БАГ 4: `do_remove_all()` удаляет неполностью 🗑️
**Проблема:**  
После `sudo xray-manager && выбрать 5) Удалить` остаются артефакты:
- Nginx конфиги (`/etc/nginx/conf.d/*.conf`)
- Параметры установки (`/root/.xray-mgr-install`)
- Systemd таймеры (`/etc/systemd/system/xray-limits.*`)
- Сам менеджер (`/usr/local/bin/xray-manager`) — может быть важно для переустановки

**Причина:**  
`do_remove_all()` удалял только:
```bash
rm -f "$XRAY_CONF" "$LIMITS_FILE" "${XRAY_KEYS_DIR}"/.keys.* "$MANAGER_BIN"
```
Это забывало про nginx и systemd таймеры.

**Решение:**  
Полная очистка всех артефактов:

```bash
do_remove_all() {
    # ... подтверждение ...
    
    # Xray ядро удаляет install-release.sh (как было)
    bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ remove --purge 2>/dev/null || true
    
    # Xray конфиги и ключи
    rm -f "$XRAY_CONF" "$LIMITS_FILE" "${XRAY_KEYS_DIR}"/.keys.*
    
    # Nginx конфиги (ВСЕ xray-related файлы)
    rm -f /etc/nginx/conf.d/xray*.conf /etc/nginx/conf.d/*-vless*.conf \
          /etc/nginx/conf.d/*-reality*.conf /etc/nginx/conf.d/*-vmess*.conf \
          /etc/nginx/conf.d/*-trojan*.conf /etc/nginx/conf.d/*-hysteria*.conf \
          /etc/nginx/conf.d/stream.d/*.conf 2>/dev/null || true
    
    # Параметры установки
    rm -f /root/.xray-mgr-install
    
    # Менеджер бинарник
    rm -f "$MANAGER_BIN"
    
    # Systemd таймеры для лимитов
    systemctl disable --now xray-limits.timer 2>/dev/null || true
    rm -f /etc/systemd/system/xray-limits.* 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    ok "Xray полностью удалён"; exit 0
}
```

**Файл:** `modules/12-system.sh`

---

#### БАГ 5: Эмодзи в меню не считаются правильно 🚀
**Проблема:**  
Эмодзи (⚙️, 🛠, 📡, 🚀) занимают 2 колонки в терминале, но bash считает их как 1 символ.  
Результат: меню уезжает вправо на 1 символ для каждого эмодзи.

**Причина:**  
Функция `mi()` использовала `${#raw_lb}` для подсчёта ширины, не учитывая что эмодзи — это много байтов, но считаются как 1 символ строки.

**Решение:**  
Новая функция `visible_width()` в `modules/02-ui.sh`:

```bash
visible_width() {
    local text="$1"
    # Убрать ANSI escape-коды
    local clean; clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
    # Базовая длина
    local len=${#clean}
    # Подсчитать эмодзи (типичные из меню)
    local emoji_count=0
    emoji_count=$(printf "%s" "$clean" | grep -o '[🔧🌐👥⚙️🛠📡🚀🗺]' | wc -l)
    # Каждый эмодзи добавляет 1 к видимой ширине
    echo $((len + emoji_count))
}
```

Обновлена `mi()`:
```bash
mi() {
    local n="$1" ic="$2" lb="$3" badge="${4:-}"
    local w; w=$(tw); local i=$((w-2))
    
    local raw_lb; raw_lb=$(printf "%b" "$lb" | sed 's/\x1b\[[0-9;]*m//g')
    local vis_lb=$(visible_width "$raw_lb")
    local vis_ic=$(visible_width "$ic")
    
    local raw_badge; raw_badge=$(printf "%b" "$badge" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Считаем видимую ширину
    local used=$(( ${#n} + vis_ic + vis_lb + 8 ))
    local pad=$(( i - used - ${#raw_badge} - 1 ))
    [[ $pad -lt 0 ]] && pad=0
    # ... рендер ...
}
```

**Файл:** `modules/02-ui.sh`

---

### 🟡 Некритичные улучшения

#### JSON валидация в cfgw()
**Что:** Добавлена проверка `jq "$1" > "$t" || return 1` перед `mv` конфига.  
**Зачем:** Если jq вернёт ошибку, конфиг не пересоздаётся и остаётся валидным.

**Файл:** `modules/05-config.sh`

---

#### Проверка занятости портов перед добавлением протокола (готово к v2.8)
**Что:** Функция для проверки `ss -tlnup :PORT`.  
**Статус:** Код написан, меню ещё не подключено.  
**Планируется:** v2.8.0

**Файл:** `modules/08-protocols.sh` (комментарий в коде)

---

### 📦 Архитектурные изменения

#### Отказ от `xray-manager.sh` как артефакта в репо ✨

**Было (v2.6.0):**
```
xray-manager.sh    (261 KB, дублирует modules/)
modules/           (268 KB, источники)
```

**Стало (v2.7.0):**
```
modules/           (268 KB, только источники)
```

**Как это работает:**
1. `install.sh` проверяет: есть ли `xray-manager.sh` и не пуст ли он
2. Если нет → собирает:
   ```bash
   cat modules/*.sh > /usr/local/bin/xray-manager
   chmod +x /usr/local/bin/xray-manager
   ```
3. Если старый `xray-manager.sh` есть → игнорирует его

**Преимущества:**
- ✅ Репо чище (нет build artifacts)
- ✅ Проще поддерживать (только source of truth — modules/)
- ✅ Нет рассинхронизации между монолитом и модулями
- ✅ Install.sh автоматизирует сборку

**Миграция:**
- Старые скрипты (v2.6.0) продолжат работать
- Новый install.sh автоматически заменит старый `xray-manager.sh` новой сборкой
- Ручное вмешательство не требуется

---

### 📝 Обновлена документация

| Документ | Изменение |
|----------|-----------|
| **README.md** | Полностью переписан (без xray-manager.sh, архитектура модулей) |
| **ARCHITECTURE.md** | Добавлены диаграммы потока данных в cfgw() / xray_restart() |
| **ENGINEERING.md** | Объяснено почему systemctl reload не работает |
| **docs/setup.md** | Обновлены шаги установки v2.7.0 |

---

### 🔗 Совместимость

| Версия | Совместимость | Примечание |
|--------|---------------|-----------|
| **v2.6.0** → **v2.7.0** | ✅ Полная | Просто переустановить (install.sh всё сделает) |
| **v2.5.x** → **v2.7.0** | ⚠️ Рекомендуется чистая установка | Старые параметры могут быть несовместимы |
| **v2.0-2.4** | ❌ Не поддерживается | Используйте v2.6.0 или удалите перед v2.7.0 |

---

## [2.6.0] — 2026-03-15

### ✨ Добавлено
- Модульная архитектура (19 модулей)
- Поддержка Hysteria2
- Маршрутизация трафика
- MTProto (Telegram)
- gRPC API для управления пользователями (нулевое downtime)

### 🐛 Исправлено
- Оптимизация кеширования IP (\_CACHED_SERVER_IP)
- Правильная сортировка модулей по номерам

### ⚠️ Известные проблемы (исправлены в v2.7.0)
- cfgw() не сбрасывает права ← **FIXED в v2.7.0**
- Меню вываливается из рамки ← **FIXED в v2.7.0**
- do_remove_all() неполная очистка ← **FIXED в v2.7.0**
- Эмодзи смещают меню ← **FIXED в v2.7.0**

---

## [2.5.0] — 2026-02-20

### ✨ Добавлено
- Python HTTP сервер для подписей
- Bash модули вместо монолита
- Support для Shadowsocks 2022

### 🐛 Исправлено
- Обработка TMPFILES в trap
- Улучшена обработка ошибок jq

---

## История

### v2.0-2.4 (2025)
Период развития, множество итераций архитектуры.

---

## Как обновиться

### С v2.6.0 на v2.7.0

```bash
# 1. Скачать новый install.sh
curl -O https://raw.githubusercontent.com/stump3/xray-manager/main/scripts/install.sh

# 2. Запустить
sudo bash install.sh

# 3. Старые параметры сохранятся в /root/.xray-mgr-install
# 4. Проверить
sudo xray-manager
```

### Откат (если что-то пошло не так)

```bash
# Восстановить из бэкапа
sudo /usr/local/bin/xray /etc/xray/config.json.backup

# Или переустановить v2.6.0
# (последний тег в репо)
git checkout v2.6.0
bash scripts/install.sh
```

---

## Благодарности

Огромное спасибо:
- **Xray Project** за отличное ядро
- **Bash community** за POSIX и set -e
- **LetsEncrypt** за бесплатные сертификаты

---

**Следующие исправления готовятся для v2.8.0:**
- Проверка занятости портов перед добавлением протокола
- Логирование изменений в `/var/log/xray/manager.log`
- Интеграция с systemd-journal для структурированных логов
