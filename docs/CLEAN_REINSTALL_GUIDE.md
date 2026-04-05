# Памятка: полная очистка перед установкой «с нуля»

> Цель: удалить все компоненты, которые обычно затрагивает `xray-manager`,
> чтобы следующая установка была максимально чистой.

## 0) Подготовка

```bash
sudo -i
cd ~/xray-manager
```

## 1) Самый простой путь (через меню xray-manager)

Если `xray-manager` уже установлен:

```bash
xray-manager
# Сервер -> Удалить Xray полностью
# Подтвердить фразой: УДАЛИТЬ
```

Этот путь использует встроенную логику удаления в модуле `modules/12-system.sh`.

---

## 2) Ручная полная очистка (если меню недоступно)

### 2.1 Остановить и удалить Xray

```bash
# Официальный uninstall (если бинарь есть)
[[ -x /usr/local/bin/xray ]] && \
  bash -c "$(curl -4 -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge || true

systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

rm -f  /etc/systemd/system/xray.service \
       /etc/systemd/system/xray@.service \
       /etc/systemd/system/multi-user.target.wants/xray.service
rm -rf /etc/systemd/system/xray.service.d \
       /etc/systemd/system/xray@.service.d

rm -f  /usr/local/bin/xray /usr/local/bin/xray-manager
rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray /run/xray
```

### 2.2 Остановить и удалить Hysteria2

```bash
systemctl stop hysteria-server 2>/dev/null || true
systemctl disable hysteria-server 2>/dev/null || true

rm -f  /etc/systemd/system/hysteria-server.service \
       /usr/local/bin/hysteria /usr/bin/hysteria
rm -rf /etc/hysteria
rm -f  /root/hysteria-*.txt
```

### 2.3 Остановить и удалить MTProto (telemt)

#### Вариант A: systemd

```bash
systemctl stop telemt 2>/dev/null || true
systemctl disable telemt 2>/dev/null || true
rm -f /etc/systemd/system/telemt.service /usr/local/bin/telemt
rm -rf /etc/telemt /opt/telemt
```

#### Вариант B: Docker

```bash
docker compose -f "${HOME}/mtproxy/docker-compose.yml" down 2>/dev/null || true
rm -rf "${HOME}/mtproxy"
```

### 2.4 Очистить nginx-конфиги проекта

```bash
rm -f /etc/nginx/sites-enabled/vpn.conf \
      /etc/nginx/sites-available/vpn.conf \
      /etc/nginx/sites-available/acme-temp.conf \
      /etc/nginx/stream.d/stream-443.conf \
      /etc/nginx/conf.d/stream-443.conf

nginx -t && systemctl reload nginx || true
```

> ⚠️ Это удаляет только конфиги, созданные/используемые данным проектом, а не весь nginx целиком.

### 2.4.1 (Опционально) Полностью удалить nginx + certbot

Используйте этот шаг, если nginx установлен/обновлён некорректно и вы хотите полностью переустановить веб-стек.

```bash
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

apt-get remove --purge -y nginx nginx-full nginx-extras nginx-common \
  libnginx-mod-* certbot python3-certbot-nginx || true
apt-get autoremove -y || true

rm -rf /etc/nginx /var/log/nginx /var/cache/nginx /var/lib/nginx
rm -rf /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt
```

> ⚠️ Внимание: этот шаг затронет **все** сайты/проекты на сервере, использующие nginx/certbot.

### 2.4.2 Очистить APT-артефакты nginx.org (чтобы не было prompt `Overwrite?`)

Если раньше уже добавляли ключ/репозиторий `nginx.org`, при повторной установке может появиться вопрос:
`File '/usr/share/keyrings/nginx-archive-keyring.gpg' exists. Overwrite?`

Перед новым запуском установщика удалите старые артефакты:

```bash
rm -f /usr/share/keyrings/nginx-archive-keyring.gpg
rm -f /etc/apt/sources.list.d/nginx.list
apt-get update
```

> После этого `scripts/install.sh` заново создаст keyring и `.list` без интерактивного вопроса.

### 2.5 Очистить таймеры/состояние xray-manager

```bash
systemctl stop xray-limits.timer 2>/dev/null || true
systemctl disable xray-limits.timer 2>/dev/null || true
rm -f /etc/systemd/system/xray-limits.*

rm -f /root/.xray-mgr-install /root/.xray-reality-local-port
```

### 2.6 Перечитать systemd

```bash
systemctl daemon-reexec 2>/dev/null || true
systemctl daemon-reload
```

---

## 3) Проверка, что система действительно «чистая»

```bash
# сервисы
systemctl status xray telemt hysteria-server --no-pager 2>/dev/null || true

# бинари
command -v xray || true
command -v xray-manager || true
command -v hysteria || true
command -v telemt || true

# остатки конфигов
ls -la /usr/local/etc/xray 2>/dev/null || true
ls -la /etc/hysteria 2>/dev/null || true
ls -la /etc/telemt 2>/dev/null || true
ls -la /etc/nginx/stream.d 2>/dev/null || true
```

Если всё удалено — можно запускать чистую установку:

```bash
cd ~/xray-manager
sudo bash scripts/install.sh
```

---

## 4) Быстрый one-shot скрипт очистки

```bash
bash -c '
set -e
systemctl stop xray hysteria-server telemt xray-limits.timer 2>/dev/null || true
systemctl disable xray hysteria-server telemt xray-limits.timer 2>/dev/null || true

rm -f /etc/systemd/system/xray.service /etc/systemd/system/xray@.service /etc/systemd/system/telemt.service /etc/systemd/system/hysteria-server.service /etc/systemd/system/xray-limits.*
rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d

rm -f /usr/local/bin/xray /usr/local/bin/xray-manager /usr/local/bin/hysteria /usr/bin/hysteria /usr/local/bin/telemt
rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray /run/xray /etc/hysteria /etc/telemt /opt/telemt "$HOME/mtproxy"

rm -f /etc/nginx/sites-enabled/vpn.conf /etc/nginx/sites-available/vpn.conf /etc/nginx/sites-available/acme-temp.conf /etc/nginx/stream.d/stream-443.conf /etc/nginx/conf.d/stream-443.conf
rm -f /root/.xray-mgr-install /root/.xray-reality-local-port

systemctl daemon-reexec 2>/dev/null || true
systemctl daemon-reload

echo "DONE: очистка завершена"
'
```

---

## 5) Важное замечание

Полный purge nginx/certbot вынесен в отдельный шаг **2.4.1**. Используйте его только при необходимости.
