# Xray Manager

Bash-инструмент для управления VPN-сервером на базе Xray-core.  
Поддерживает VLESS, VMess, Trojan, Shadowsocks 2022, Hysteria2 и MTProto из единого интерактивного меню.

![Version](https://img.shields.io/badge/version-2.7.1-0ea5e9?style=flat-square)
![Platform](https://img.shields.io/badge/Ubuntu_22%2B_%7C_Debian_11%2B-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-22c55e?style=flat-square)

---

## Быстрый старт

```bash
git clone https://github.com/stump3/xray-manager.git
cd xray-manager
sudo bash scripts/install.sh
```

Скрипт интерактивно спросит домен, email для Let's Encrypt и порты — и сделает всё остальное.

После установки:

```bash
sudo xray-manager
```

### Требования

| | Минимум |
|---|---|
| ОС | Ubuntu 22.04+ / Debian 11+ |
| Права | root |
| Архитектура | x86_64, arm64 |
| RAM | 256 MB |
| Домен | Обязателен (для TLS-протоколов и подписки) |

---

## Протоколы

| Протокол | Транспорт | Домен | Через Nginx |
|---|---|:---:|:---:|
| VLESS | TCP + REALITY | ✗ | ✗ |
| VLESS | XHTTP + REALITY | ✗ | ✗ |
| VLESS | gRPC + REALITY | ✗ | ✗ |
| VLESS | WebSocket + TLS | ✓ | ✓ |
| VLESS | gRPC + TLS | ✓ | ✓ |
| VLESS | HTTPUpgrade + TLS | ✓ | ✓ |
| VLESS | SplitHTTP + TLS/H3 | ✓ | ✓ |
| VMess | WebSocket + TLS | ✓ | ✓ |
| VMess | TCP + TLS | ✓ | ✓ |
| Trojan | TCP + TLS | ✓ | ✓ |
| Shadowsocks 2022 | TCP | ✗ | ✗ |
| Hysteria2 | UDP/QUIC | ✓ | ✗ |
| MTProto | TCP | ✗ | ✗ |

---

## Архитектура сети

```
Клиент
  ├─ TCP:443  → Nginx ─── /ws          → Xray (WebSocket/gRPC/HTTPUpgrade)
  │                   └── /TOKEN/      → Сервер подписки (python3, 127.0.0.1:8888)
  ├─ UDP:443  → Xray Hysteria2 (напрямую)
  └─ TCP:8443 → Xray VLESS+REALITY    (напрямую)
```

Для одновременной работы REALITY и HTTPS на порту 443 установщик предлагает Nginx stream с SNI-маршрутизацией:

```
TCP:443 → Nginx stream (SNI)
  ├─ домен → Nginx HTTPS (порт 4443)
  └─ остальное → Xray REALITY
```

---

## Возможности

**Пользователи**
- Добавление/удаление через gRPC API без разрыва соединений
- Лимиты по дате и объёму трафика (автодеактивация каждые 5 минут)
- Статистика трафика через Stats API
- QR-коды и ссылки подключения

**Подписка**
- Форматы Base64 (v2rayN/NG) и Clash YAML (Mihomo)
- Эндпоинты: `/TOKEN/sub`, `/TOKEN/clash`, `/TOKEN/u/alice`
- Настраиваемый интервал обновления 1–168 часов
- Автообновление при добавлении пользователя

**Система**
- Бэкап и восстановление конфигурации (ротация: последние 7)
- Обновление геоданных (geoip.dat, geosite.dat)
- BBR+ оптимизация
- Маршрутизация с профилями (bypass-ru, block-ads, full-proxy и др.)
- Балансировщик нагрузки + Observatory

**MTProto (telemt)**
- Установка через systemd или Docker
- Управление пользователями через REST API без перезапуска
- SSH-миграция конфига между серверами

**Hysteria2**
- Отдельный бинарник с ACME (Let's Encrypt / ZeroSSL / Buypass)
- Port Hopping, Masquerade, BBR/Brutal
- SSH-миграция с сертификатами

---

## Структура репозитория

```
xray-manager/
├── modules/               ← исходники (18 модулей)
│   ├── 00-header.sh       — shebang, trap, tmpfiles
│   ├── 01-constants.sh    — пути, порты, версия
│   ├── 02-ui.sh           — box_*, mi(), visible_width()
│   ├── 03-system.sh       — root, зависимости, BBR
│   ├── 04-xray-core.sh    — установка/обновление Xray
│   ├── 05-config.sh       — cfgw(), ib_*, xray_restart()
│   ├── 06-limits.sh       — лимиты, check_limits, timer
│   ├── 07-links.sh        — gen_link(), show_link_qr()
│   ├── 08-protocols.sh    — proto_vless_*, proto_vmess_* ...
│   ├── 09-users.sh        — user_add/del/list/stats
│   ├── 10-manage.sh       — меню управления Xray
│   ├── 11-subscription.sh — HTTP-сервер подписки (python3)
│   ├── 12-system.sh       — бэкап, restore, do_remove_all
│   ├── 13-compat.sh       — псевдонимы для MTProto/Hysteria
│   ├── 14-telemt.sh       — MTProto (telemt)
│   ├── 15-hysteria2.sh    — Hysteria2 (отдельный бинарник)
│   ├── 16-routing.sh      — маршрутизация, профили
│   └── 99-main.sh         — main_menu()
│
├── scripts/
│   ├── install.sh                ← точка входа установки
│   └── certbot-deploy-hook.sh   ← авторестарт после обновления сертификата
│
├── nginx/
│   ├── nginx.conf                ← базовый конфиг (с поддержкой stream.d)
│   └── sites/vpn.conf           ← vhost-шаблон
│
├── configs/xray/
│   └── config.example.json      ← аннотированный шаблон конфига Xray
│
└── docs/
    ├── ENGINEERING.md            ← архитектура и дизайн-решения
    ├── ARCHITECTURE.md           ← внутреннее устройство (v2.7+)
    ├── MIGRATION.md              ← миграция с предыдущих версий
    └── setup.md                  ← пошаговое руководство
```

`install.sh` собирает бинарник на лету: `cat modules/*.sh > /usr/local/bin/xray-manager`. В репозитории нет предсобранного монолита.

---

## Файлы на сервере

```
/usr/local/bin/xray-manager          ← бинарник (собирается при установке)
/usr/local/etc/xray/config.json      ← конфиг Xray
/usr/local/etc/xray/.keys.<tag>      ← ключи протоколов (x25519, shortId, sni)
/usr/local/etc/xray/.limits.json     ← лимиты пользователей
/usr/local/etc/xray/subscriptions/   ← файлы подписок
/root/.xray-mgr-install              ← параметры установки (домен, порты, токен)
/root/xray-backups/                  ← бэкапы конфига
```

---

## Клиенты

| Платформа | Клиент |
|---|---|
| Windows | v2rayN, Furious |
| Android | v2rayNG |
| iOS / macOS | Happ, Streisand |
| Все | Mihomo (Clash.Meta) — для Clash YAML подписки |

---

## Лицензия

MIT · [Xray-core](https://github.com/XTLS/Xray-core) (MPL 2.0) · [telemt](https://github.com/telemt/telemt) · [Hysteria2](https://github.com/apernet/hysteria) (MIT)
