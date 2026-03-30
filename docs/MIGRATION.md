# Миграция с v2.6.0 на v2.7.0

Это руководство описывает процесс обновления xray-manager с версии 2.6.0 на версию 2.7.0 и объясняет основные изменения архитектуры.

---

## 📋 Краткая миграция (5 минут)

Если у вас уже установлена v2.6.0:

```bash
# 1. Скачать новый install.sh
curl -O https://raw.githubusercontent.com/stump3/xray-manager/main/scripts/install.sh

# 2. Запустить
sudo bash install.sh

# 3. Подтвердить параметры установки
# (старые параметры из /root/.xray-mgr-install будут предложены по умолчанию)

# 4. Готово!
sudo xray-manager
```

---

## ⚠️ Что изменилось

### Главное: xray-manager.sh больше не хранится в репо

**v2.6.0:**
```
Repository:
├─ xray-manager.sh      (261 KB — собранный монолит)
├─ modules/             (268 KB — модули)
└─ scripts/install.sh
```

**v2.7.0:**
```
Repository:
├─ modules/             (268 KB — только источники)
└─ scripts/install.sh   (сам собирает бинарник из modules/)
```

### Почему?

- **Дублирование кода**: xray-manager.sh = concat(modules/*.sh)
- **Синхронизация**: изменение в модуле требовало ручного пересобора монолита
- **Автоматизм**: install.sh теперь сам собирает бинарник — никакого ручного вмешательства

### Как это влияет на вас?

✅ **Вам ничего не нужно делать!**

- install.sh v2.7.0 **автоматически** удалит старый `xray-manager.sh`
- Собирает новый из modules/
- Устанавливает в `/usr/local/bin/xray-manager`

---

## 🐛 Исправленные баги

### БАГ 1: Права на конфиг падают после каждого изменения

**Было (v2.6.0):**
```
# После добавления протокола через меню:
-rw-r--r-- root root /usr/local/etc/xray/config.json
│           ↑
│           Xray не может прочитать → ERROR: permission denied

systemctl status xray
  ● xray.service - Xray Service
    Active: failed (permission denied)
```

**Стало (v2.7.0):**
```bash
cfgw() {
    # ... изменения конфига ...
    chown nobody:nogroup "$XRAY_CONF"
    chmod 640 "$XRAY_CONF"  # ← права сбрасываются ВНУТРИ cfgw()
}
```

**Как вы узнаёте, что это исправлено:**
```bash
# После добавления протокола
ls -la /usr/local/etc/xray/config.json
# Output: -rw-r----- nobody nogroup config.json  ← корректно!

sudo xray-manager
# Xray статус: ● работает (не падает)
```

**Читайте:** [CHANGELOG.md — БАГ 1](../CHANGELOG.md#bug-1-права-на-конфиг-падают-после-каждого-изменения)

---

### БАГ 2: Меню вываливается из рамки

**Было (v2.6.0):**
```
│  R) 🗺 Маршрутизация  профиль: production · 123 правил\e[2m │
                                                          ↑
                                        Отвисает за границу!
```

**Стало (v2.7.0):**
```
│  R) 🗺 Маршрутизация  профиль: production · 123 правил │
                                                      ↑
                                         Выравнивается правильно
```

**Как вы узнаёте, что это исправлено:**
```bash
sudo xray-manager
# Визуально проверить: меню ровное, без отвисающих символов
# Нет странных `\e[2m` в конце строк
```

**Читайте:** [CHANGELOG.md — БАГ 2](../CHANGELOG.md#bug-2-меню-вываливается-из-рамки-отвисающий-e2m)

---

### БАГ 4: `do_remove_all()` удаляет неполностью

**Было (v2.6.0):**
```bash
sudo xray-manager
# → Выбрать: 5) Система → 7) Удалить Xray
# → Подтвердить

# Проверить что осталось:
ls -la /etc/nginx/conf.d/
  xray-vless-*.conf      ← ЭТИ ФАЙЛЫ ОСТАЮТСЯ! 😱
  xray-reality-*.conf    ← ЭТИ ФАЙЛЫ ОСТАЮТСЯ! 😱

ls -la /root/.xray-mgr-install
  # Файл всё ещё здесь
```

**Стало (v2.7.0):**
```bash
sudo xray-manager
# → Выбрать: 5) Система → 7) Удалить Xray
# → Подтвердить

# Проверить что осталось:
ls -la /etc/nginx/conf.d/
  # Все xray-конфиги удалены ✓
  
ls -la /root/.xray-mgr-install
  # Файл удалён ✓
  
ls -la /etc/systemd/system/xray-limits.*
  # Таймеры удалены ✓
```

**Читайте:** [CHANGELOG.md — БАГ 4](../CHANGELOG.md#bug-4-do_remove_all-удаляет-неполностью)

---

### БАГ 5: Эмодзи смещают меню

**Было (v2.6.0):**
```
│  5) 🛠  Система                (BBR / бэкап / удалить)   │
│  6) 📡 MTProto (Telegram)       ● 3.3.32                │
                ↑
           Смещено на 1 символ из-за эмодзи
```

**Стало (v2.7.0):**
```
│  5) 🛠 Система                    (BBR / бэкап / удалить) │
│  6) 📡 MTProto (Telegram)         ● 3.3.32                │
         ↑
    Выравнивается правильно (видимая ширина эмодзи учитывается)
```

**Как вы узнаёте, что это исправлено:**
```bash
sudo xray-manager
# Визуально: все строки выровнены по правой границе
# Нет смещений из-за эмодзи
```

**Читайте:** [CHANGELOG.md — БАГ 5](../CHANGELOG.md#bug-5-эмодзи-в-меню-не-считаются-правильно)

---

## 🔄 Процесс обновления подробно

### Шаг 1: Сделать бэкап (рекомендуется)

```bash
# Бэкап конфига Xray
sudo cp /usr/local/etc/xray/config.json \
        /usr/local/etc/xray/config.json.backup.$(date +%Y%m%d-%H%M%S)

# Бэкап параметров установки
sudo cp /root/.xray-mgr-install \
        /root/.xray-mgr-install.backup.$(date +%Y%m%d-%H%M%S)

# Проверить что скопировалось
sudo ls -la /usr/local/etc/xray/config.json*
```

### Шаг 2: Скачать новый install.sh

```bash
# Способ 1: Через curl
curl -L -o /tmp/install-v2.7.0.sh \
    https://raw.githubusercontent.com/stump3/xray-manager/main/scripts/install.sh

# Способ 2: Клонировать весь репо
cd /tmp
git clone https://github.com/stump3/xray-manager.git xray-mgr-v2.7.0
cd xray-mgr-v2.7.0
```

### Шаг 3: Запустить install.sh

```bash
sudo bash /tmp/install-v2.7.0.sh
```

**Он попросит:**
```
[1/7] Проверка зависимостей
  ✓ curl, jq, qrencode, openssl, python3 установлены

[2/7] Параметры установки
  Введите домен (по умолчанию: sub.graycloudx.mooo.com): ← ENTER (используется старый)
  Введите email для Let's Encrypt: ← ENTER (используется старый)
  ...
```

**Просто нажимайте ENTER** — он предложит значения из старого `/root/.xray-mgr-install`.

### Шаг 4: Проверить что всё работает

```bash
# Проверить менеджер
sudo xray-manager
# Должно открыться меню без ошибок

# Проверить Xray статус
sudo systemctl status xray
# Active: active (running)

# Проверить конфиг прав
ls -la /usr/local/etc/xray/config.json
# -rw-r----- nobody nogroup  ← корректно!

# Проверить что старый бинарник заменён
ls -la /usr/local/bin/xray-manager
# Дата должна быть свежей (после обновления)

# Проверить что xray-manager.sh больше не нужен
ls -la xray-manager.sh 2>/dev/null
# Файл должен отсутствовать (или быть пустым)
```

---

## 🔧 Как откатиться, если что-то пошло не так

### Откат на v2.6.0 (если срочно нужно)

```bash
# Остановить менеджер (если запущен)
sudo xray-manager  # → выбрать 0) Выход

# Восстановить бэкап конфига
sudo cp /usr/local/etc/xray/config.json.backup.* \
        /usr/local/etc/xray/config.json

# Сбросить права
sudo chown nobody:nogroup /usr/local/etc/xray/config.json
sudo chmod 640 /usr/local/etc/xray/config.json

# Перезагрузить Xray
sudo systemctl restart xray

# Проверить статус
sudo systemctl status xray
```

### Откат менеджера на v2.6.0

Если по какой-то причине нужен старый менеджер:

```bash
# Удалить v2.7.0
sudo rm /usr/local/bin/xray-manager

# Склонировать старую версию
cd /tmp
git clone https://github.com/stump3/xray-manager.git xray-mgr-v2.6.0
cd xray-mgr-v2.6.0
git checkout v2.6.0

# Установить
sudo bash scripts/install.sh
```

---

## ✅ Контрольный список миграции

- [ ] Сделал бэкап конфига и параметров
- [ ] Скачал новый install.sh v2.7.0
- [ ] Запустил `sudo bash install.sh`
- [ ] Подтвердил (или переуказал) параметры установки
- [ ] Запустил `sudo xray-manager` — меню открывается
- [ ] Проверил `sudo systemctl status xray` — статус OK
- [ ] Проверил `ls -la /usr/local/etc/xray/config.json` — права корректны (`nobody:nogroup 640`)
- [ ] Проверил, что меню отображается ровно (без смещений эмодзи)
- [ ] Проверил логи: `sudo tail -20 /var/log/xray/error.log` — нет ошибок

---

## 🆘 Что делать если что-то не работает

### Проблема: "xray-manager: command not found"

```bash
# Проверить что менеджер установлен
ls -la /usr/local/bin/xray-manager

# Если нет → переустановить
sudo bash scripts/install.sh
```

### Проблема: Xray падает с "permission denied"

```bash
# Проверить права
ls -la /usr/local/etc/xray/config.json

# Если права неверные (root:root 600) → сбросить
sudo chown nobody:nogroup /usr/local/etc/xray/config.json
sudo chmod 640 /usr/local/etc/xray/config.json

# Перезапустить Xray
sudo systemctl restart xray

# Проверить статус
sudo systemctl status xray
```

### Проблема: Меню выглядит странно (смещения, непонятные символы)

```bash
# Это должно быть исправлено в v2.7.0
# Если всё ещё видны проблемы:

# 1. Проверить размер терминала
stty size
# Output: 24 80  (высота x ширина)

# 2. Если ширина < 80 символов — расширить окно

# 3. Проверить что используется v2.7.0
sudo xray-manager --version 2>/dev/null || grep "MANAGER_VERSION" /usr/local/bin/xray-manager
```

### Проблема: После добавления протокола Xray падает

**ДО v2.7.0:** Это был БАГ 1 (права на конфиг)

**Теперь в v2.7.0:** Это должно быть исправлено.

Если проблема ещё есть:
```bash
# Проверить логи
sudo journalctl -u xray -n 50
tail -50 /var/log/xray/error.log

# Проверить что конфиг валидный JSON
sudo jq . /usr/local/etc/xray/config.json >/dev/null && echo "OK" || echo "INVALID"

# Если конфиг невалидный — восстановить из бэкапа
sudo cp /usr/local/etc/xray/config.json.backup.* \
        /usr/local/etc/xray/config.json
sudo systemctl restart xray
```

---

## 📞 Нужна помощь?

- **Документация**: [README.md](../README.md), [ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md) — полный список всех изменений
- **Issues**: [GitHub Issues](https://github.com/stump3/xray-manager/issues)

---

**Успешной миграции!** 🚀
