<div align="center">

```
██╗  ██╗██████╗  █████╗ ██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗
╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ████╗ ████║██╔════╝ ██╔══██╗
 ╚███╔╝ ██████╔╝███████║ ╚████╔╝     ██╔████╔██║██║  ███╗██████╔╝
 ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝      ██║╚██╔╝██║██║   ██║██╔══██╗
██╔╝ ██╗██║  ██║██║  ██║   ██║       ██║ ╚═╝ ██║╚██████╔╝██║  ██║
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
```

**VPN Infrastructure Manager for Linux**

![Version](https://img.shields.io/badge/version-2.6.0-0ea5e9?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-22c55e?style=flat-square)
![Platform](https://img.shields.io/badge/Ubuntu_22%2B_%7C_Debian_11%2B-orange?style=flat-square)
![Lines](https://img.shields.io/badge/5380_строк-18_модулей-8b5cf6?style=flat-square)

[**Установка**](#-быстрая-установка) · [**Протоколы**](#-протоколы) · [**Подписка**](#-подписка) · [**Архитектура**](#-архитектура) · [**Файлы**](#-структура-файлов) · [**📖 Документация**](https://stump3.github.io/xray-manager/README.html)

</div>

---

## Компоненты

| | Компонент | Описание |
|:---:|---|---|
| 🔐 | **Xray-core** | VLESS, VMess, Trojan, Shadowsocks 2022, Hysteria2. REALITY и SplitHTTP без домена. Лимиты по трафику и дате |
| 📡 | **telemt** (MTProto) | Telegram-прокси на Rust. systemd или Docker. API без перезапуска. SSH-миграция |
| 🚀 | **Hysteria2** | QUIC/UDP. Port Hopping. ACME (LE/ZeroSSL/Buypass). BBR/Brutal. SSH-миграция |

---

## ⚡ Быстрая установка

```bash
cd ~
git clone https://github.com/stump3/xray-manager.git
cd xray-manager
sudo bash scripts/install.sh
```

Скрипт спросит домен, email для Let's Encrypt, порты — и сделает всё остальное сам.

### Требования

| Компонент | Минимум |
|---|---|
| ОС | Ubuntu 22.04+ / Debian 11+ |
| Права | `root` |
| Архитектура | x86_64, arm64 |
| RAM | 256 MB |
| Домен | Обязателен (для Hysteria2 + Nginx HTTPS) |

---

## 🏗 Архитектура

Nginx стоит фронтендом на TCP:443 и принимает все TLS-соединения. REALITY и Hysteria2 работают напрямую на своих портах — Nginx их не касается.

```
Клиент
  ├─ TCP:443  → Nginx ─── /ws          → Xray VLESS+WebSocket
  │                   └── /TOKEN/      → Сервер подписки
  ├─ UDP:443  → Xray Hysteria2 (напрямую)
  └─ TCP:8443 → Xray VLESS+REALITY (напрямую)
```

**Гибкость:** любой новый TLS-протокол добавляется одним `location` в Nginx без перестройки схемы.

### Модульная структура

Исходники разбиты на 18 модулей. Дистрибуция — один файл, собираемый через `make`:

```
make build     # cat modules/*.sh > xray-manager.sh + bash -n
make check     # shellcheck по всем модулям
make release   # сборка + chmod + sha256
```

---

## 📋 Структура меню

```
Главное меню
├─ 1)  🔧  Установка / Обновление Xray
├─ 2)  🌐  Протоколы Xray
│         ├ VLESS + TCP + REALITY         ← без домена ⭐
│         ├ VLESS + XHTTP + REALITY
│         ├ VLESS + gRPC + REALITY        ← без домена
│         ├ VLESS + WebSocket / gRPC / HTTPUpgrade + TLS
│         ├ VLESS + SplitHTTP + TLS/H3   ← QUIC/CDN
│         ├ VMess + WebSocket / TCP + TLS
│         ├ Trojan + TCP + TLS
│         ├ Shadowsocks 2022
│         └ Hysteria2 (нативный Xray)    ← TLS + Stats API ⭐
├─ 3)  👥  Пользователи Xray
│         ├ Добавить · Удалить · Список
│         ├ Ссылка + QR-код
│         ├ Статистика трафика ↑↓
│         ├ Лимиты (дата / ГБ)
│         └ 📡 Подписка
│               ├ Запустить / Остановить
│               ├ Обновить файлы
│               ├ Показать ссылки и QR
│               ├ Подписка для пользователя
│               ├ ⏱ Интервал обновления (1–168 ч)
│               └ 🔁 Автообновление при добавлении
├─ 4)  ⚙️  Управление Xray
├─ 5)  🛠  Система
│         ├ BBR+ · бэкап · восстановление · таймер лимитов
│         ├ Fragment · Noises · Fallbacks
│         ├ Балансировщик + Observatory
│         └ Hysteria2 Outbound (relay/цепочка)
├─ 6)  📡  MTProto (Telegram)
└─ 7)  🚀  Hysteria2 (отдельный бинарник, ACME)
```

---

## 🌐 Протоколы

| Протокол | Транспорт | Домен | Nginx | Порт |
|---|---|:---:|:---:|---|
| VLESS | TCP + REALITY | ✗ | ✗ | любой (8443) |
| VLESS | XHTTP + REALITY | ✗ | ✗ | любой |
| VLESS | gRPC + REALITY | ✗ | ✗ | любой |
| VLESS | WebSocket + TLS | ✓ | ✓ | внутренний |
| VLESS | gRPC + TLS | ✓ | ✓ | внутренний |
| VLESS | HTTPUpgrade + TLS | ✓ | ✓ | внутренний |
| VLESS | SplitHTTP + TLS/H3 | ✓ | ✗ | любой (UDP) |
| VMess | WebSocket + TLS | ✓ | ✓ | внутренний |
| VMess | TCP + TLS | ✓ | ✓ | внутренний |
| Trojan | TCP + TLS | ✓ | ✓ | любой |
| Shadowsocks | TCP | ✗ | ✗ | любой |
| Hysteria2 | UDP (QUIC) | ✓ | ✗ | UDP:443 |

---

## 📡 Подписка

Сервер подписки — python3 на `127.0.0.1:8888`, раздаётся через Nginx.

### Форматы URL

```
https://domain.com/TOKEN/sub              ← Base64 (v2rayN, v2rayNG)
https://domain.com/TOKEN/clash            ← Clash YAML (Mihomo)
https://domain.com/TOKEN/u/alice@vpn      ← Конкретный пользователь
https://domain.com/TOKEN/clash/u/alice@vpn
```

### Особенности

- **Интервал** — настраивается от 1 до 168 часов (заголовок `Profile-Update-Interval`)
- **Автообновление** — файлы пересоздаются автоматически при добавлении пользователя
- **Без перезапуска** — смена интервала вступает в силу при следующем запросе клиента
- **Безопасность** — сервер слушает только `127.0.0.1`, токен в URL обязателен

---

## 👥 Пользователи и лимиты

Имя пользователя — произвольный идентификатор в формате `alice@vpn` или просто `alice`. Реальный email не нужен.

| Лимит | Формат | Триггер |
|---|---|---|
| По дате | `YYYY-MM-DD` | `now > expire_ts` |
| По трафику | Целое число ГБ | `uplink + downlink ≥ лимит` |

Автопроверка каждые 5 минут через `xray-limits.timer`.

### Добавление без разрыва соединений

Пользователи добавляются и удаляются через gRPC API Xray (`xray api adu` / `xray api rmu`) — без `systemctl restart`. Существующие соединения не прерываются. Fallback на `restart` — только если Xray не активен.

---

## 📁 Структура файлов

### Репозиторий

```
xray-manager/
├── Makefile                     ← make build / check / release
├── xray-manager.sh              ← артефакт сборки (cat modules/*.sh)
├── README.md
├── .gitignore
│
├── modules/                     ← 18 исходных модулей
│   ├── 00-header.sh             ← shebang, trap, _TMPFILES
│   ├── 01-constants.sh          ← версия, пути, цвета
│   ├── 02-ui.sh                 ← box_*, ask, spin, ok/err
│   ├── 03-system.sh             ← need_root, deps, BBR
│   ├── 04-xray-core.sh          ← установка ядра
│   ├── 05-config.sh             ← cfg/cfgw, ib_*, kset/kget
│   ├── 06-limits.sh             ← лимиты, check_limits, timer
│   ├── 07-links.sh              ← gen_link, urlencode
│   ├── 08-protocols.sh          ← все proto_*
│   ├── 09-users.sh              ← menu_protocols, user_*
│   ├── 10-manage.sh             ← menu_manage, geodata
│   ├── 11-subscription.sh       ← subscription server
│   ├── 12-system.sh             ← backup/restore/remove
│   ├── 13-compat.sh             ← SSH helpers, compat aliases
│   ├── 14-telemt.sh             ← MTProto
│   ├── 15-hysteria2.sh          ← Hysteria2 standalone
│   ├── 16-routing.sh            ← routing + profiles
│   └── 99-main.sh               ← main_menu, entrypoint
│
├── nginx/
│   ├── nginx.conf
│   └── sites/vpn.conf
│
├── configs/xray/config.example.json
│
├── scripts/
│   ├── install.sh
│   └── certbot-deploy-hook.sh
│
└── docs/
    ├── CHANGELOG.md
    ├── ENGINEERING.md
    ├── README.html              ← GitHub Pages документация
    └── setup.md
```

### Сервер

```
/usr/local/etc/xray/
├── config.json
├── .keys.<tag>                  ← ключи протоколов
├── .limits.json                 ← лимиты пользователей
└── subscriptions/
    ├── .token · .port · .interval · .autoupdate
    ├── all.b64 · all.clash.yaml
    └── user_*.b64 · user_*.clash.yaml
```

---

## 📱 Клиенты

| Платформа | Клиент |
|---|---|
| Windows | v2rayN · Furious |
| Android | v2rayNG |
| iOS / macOS | Happ · Streisand |
| Все | Mihomo (Clash.Meta) — для Clash YAML подписки |

---

## Лицензия

MIT · [Xray-core](https://github.com/XTLS/Xray-core) (MPL 2.0) · [telemt](https://github.com/telemt/telemt) · [Hysteria2](https://github.com/apernet/hysteria) (MIT)
