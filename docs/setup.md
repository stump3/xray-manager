# Пошаговая установка

> **Версия:** 2.6.0 · [README](../README.md) · [CHANGELOG](CHANGELOG.md)

## Архитектура

```
Клиент
  ├─ TCP:443  → Nginx (HTTPS)
  │               ├─ /ws           → Xray VLESS+WebSocket  (127.0.0.1:10001)
  │               ├─ /TOKEN/       → Сервер подписки       (127.0.0.1:8888)
  │               └─ /*            → Заглушка-сайт (маскировка)
  │
  ├─ UDP:443  → Xray Hysteria2 (напрямую, без Nginx)
  │
  └─ TCP:8443 → Xray VLESS+REALITY (напрямую, без Nginx)
```

Nginx — постоянный фронтенд. Любой новый TLS-протокол добавляется одним `location`.
REALITY, SplitHTTP и Hysteria2 работают напрямую — Nginx их не касается.

## Требования

| | |
|---|---|
| ОС | Ubuntu 22.04+ / Debian 11+ |
| Права | root |
| Архитектура | x86_64, arm64 |
| RAM | 256 MB+ |
| Домен | Обязателен (нужен для Hysteria2, SplitHTTP и Nginx HTTPS) |
| DNS | A-запись домена → IP сервера до запуска |

---

## Шаг 1 — Клонировать репозиторий

```bash
git clone https://github.com/stump3/xray-manager.git
cd xray-manager
```

## Шаг 2 — Запустить install.sh

```bash
sudo bash scripts/install.sh
```

Скрипт интерактивно спросит:

```
? Ваш домен (напр. vpn.example.com): vpn.mydomain.com
? Email для Let's Encrypt: me@gmail.com
? Порт VLESS+WebSocket (внутренний) [10001]:
? Порт VLESS+REALITY (снаружи) [8443]:

→ Домен:        vpn.mydomain.com
→ Email (LE):   me@gmail.com
→ WS порт:      10001
→ REALITY порт: 8443

? Всё верно? [Y/n]:
```

После подтверждения скрипт:
1. Установит nginx, certbot, jq, qrencode, python3
2. Откроет порты в UFW (22, 80, 443 TCP/UDP, 8443 TCP)
3. Выпустит TLS-сертификат через Let's Encrypt
4. Настроит Nginx с SUB_TOKEN (генерируется автоматически)
5. Установит Xray-core
6. Установит xray-manager как системную команду
7. Сохранит параметры в `/root/.xray-mgr-install`

В конце выведет:
```
  SUB_TOKEN:   abc123def456...
  URL подписки:
    Base64  https://vpn.mydomain.com/abc123.../sub
    Clash   https://vpn.mydomain.com/abc123.../clash
```

## Шаг 3 — Настроить протоколы

```bash
sudo xray-manager
```

### VLESS + TCP + REALITY (без домена, рекомендуется)

```
→ 2) Протоколы → 1) VLESS + TCP + REALITY
  Порт:  8443
  SNI:   www.microsoft.com
  Тег:   vless-reality
```

Скрипт сгенерирует x25519 ключевую пару и shortId. Домен и TLS-сертификат не нужны.

### VLESS + gRPC + REALITY (без домена)

```
→ 2) Протоколы → 12) VLESS + gRPC + REALITY
  Порт:            8444
  SNI:             www.yahoo.com
  gRPC ServiceName: grpc
  Тег:             vless-grpc-reality
```

Аналогично TCP+REALITY, но использует gRPC-транспорт. Совместим с клиентами, поддерживающими gRPC.

### VLESS + WebSocket + TLS (через Nginx на TCP:443)

```
→ 2) Протоколы → 3) VLESS + WebSocket + TLS
  Порт:   10001
  Домен:  vpn.mydomain.com
  Path:   /ws
  Cert:   /etc/letsencrypt/live/vpn.mydomain.com/fullchain.pem
  Key:    /etc/letsencrypt/live/vpn.mydomain.com/privkey.pem
```

### VLESS + SplitHTTP + TLS/H3 (QUIC)

```
→ 2) Протоколы → 13) VLESS + SplitHTTP + TLS/H3
  Порт:   443
  Домен:  vpn.mydomain.com
  Path:   /split
  Режим:  [1] h3 — прямое HTTP/3
          [2] h2,http/1.1 — через CDN
```

Открыть UDP:443: `ufw allow 443/udp`

### Hysteria2 (напрямую на UDP:443)

```
→ 2) Протоколы → 10) Hysteria2 (нативный Xray)
  Порт:   443
  Домен:  vpn.mydomain.com
  Cert:   /etc/letsencrypt/live/vpn.mydomain.com/fullchain.pem
  Key:    /etc/letsencrypt/live/vpn.mydomain.com/privkey.pem
  Скорость: BBR (рекомендуется)
```

## Шаг 4 — Добавить пользователей

```
→ 3) Пользователи → 1) Добавить
  Выбрать inbound → ввести логин (alice, bob@vpn, user1 — реальный email не нужен)
```

Допустимые символы: `a-z A-Z 0-9 . _ @ -`

Пользователь добавляется **без перезапуска** — через gRPC API (`xray api adu`). Соединения не рвутся.

Повторить для каждого протокола.

## Шаг 5 — Запустить сервер подписки

```
→ 3) Пользователи → 8) Подписка → 1) Запустить сервер подписки
  Порт:   8888
  Токен:  (введите SUB_TOKEN из вывода install.sh)
```

### Настройка интервала обновления

```
→ 3) Пользователи → 8) Подписка → 6) Интервал обновления
  Введите часы (1–168), дефолт: 12
```

Изменение вступает в силу при следующем запросе клиента — перезапуск не нужен.

### Автообновление файлов при добавлении пользователя

```
→ 3) Пользователи → 8) Подписка → 7) Автообновление при добавлении
  Включить? [Y/n]
```

## Шаг 6 — Проверить

```bash
# Nginx
curl -I https://vpn.mydomain.com

# Подписка
curl https://vpn.mydomain.com/TOKEN/sub | base64 -d | head -3

# Xray
systemctl status xray
systemctl status xray-sub

# Статистика трафика
sudo xray-manager → 3) Пользователи → 5) Статистика
```

---

## Добавление протокола позже

### TLS-based (VMess, Trojan, gRPC)

1. `sudo xray-manager → 2) Протоколы` → выбрать, указать порт (напр. 10002)
2. Добавить в `/etc/nginx/sites-available/vpn.conf`:

```nginx
# WebSocket
location /vmess {
    proxy_pass         http://127.0.0.1:10002;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade $http_upgrade;
    proxy_set_header   Connection "upgrade";
    proxy_read_timeout 86400s;
}

# gRPC — grpc_pass, не proxy_pass
location /GrpcServiceName {
    grpc_pass grpc://127.0.0.1:10003;
}
```

3. `sudo nginx -t && sudo systemctl reload nginx`

### REALITY-based (без Nginx)

1. `sudo xray-manager → 2) Протоколы → VLESS+REALITY или gRPC+REALITY` → новый порт
2. `ufw allow <port>/tcp`
3. Nginx не трогать

### SplitHTTP/H3

1. `sudo xray-manager → 2) Протоколы → 13) SplitHTTP`
2. `ufw allow 443/udp` (или выбранный порт)
3. Nginx не трогать — SplitHTTP слушает напрямую

---

## Сборка из исходников (разработка)

```bash
git clone https://github.com/stump3/xray-manager.git
cd xray-manager

# Сборка монолита из модулей
make build

# Проверка синтаксиса всех модулей
make check

# Собрать + chmod + sha256
make release

# Посмотреть состав и размеры
make ls
```

---

## Структура файлов на сервере

```
/usr/local/etc/xray/
├── config.json
├── .keys.<tag>                  ← x25519 ключи, SNI, shortId, port
├── .limits.json                 ← лимиты пользователей
└── subscriptions/
    ├── server.py                ← HTTP-сервер подписки
    ├── .token · .port · .interval · .autoupdate
    ├── all.b64 · all.clash.yaml
    └── user_NAME_at_DOMAIN.{b64,clash.yaml}

/etc/nginx/sites-available/vpn.conf
/etc/letsencrypt/live/DOMAIN/     ← TLS сертификат

/etc/systemd/system/
├── xray.service
├── xray-sub.service             ← сервер подписки
├── xray-limits.service          ← проверка лимитов (oneshot)
└── xray-limits.timer            ← каждые 5 минут

/root/.xray-mgr-install          ← параметры установки (домен, токен)
/root/xray-backups/              ← последние 7 бэкапов конфига
/etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
```

---

## Обновление сертификата

```bash
certbot renew --dry-run
systemctl status certbot.timer
```

После обновления `scripts/certbot-deploy-hook.sh` перезагружает nginx и xray автоматически.

---

## Удаление

```bash
# Xray + менеджер
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
rm -f /usr/local/etc/xray/.keys.* /usr/local/etc/xray/.limits.json
rm -rf /usr/local/etc/xray/subscriptions
rm -f /usr/local/bin/xray-manager
systemctl disable --now xray-limits.timer xray-sub 2>/dev/null || true

# Nginx конфиг
rm -f /etc/nginx/sites-{enabled,available}/vpn.conf
systemctl reload nginx

# Сертификат (опционально)
certbot delete --cert-name vpn.mydomain.com
```
