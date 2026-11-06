# Teleproxy.Keenetic v1.0.2

Автоматизация установки: пользователь, ключи Susanin и проброс порта делаются
самим пакетом.

## Что нового

- **`postinst` создаёт пользователя надёжно, с последним рубежом.** Если
  `adduser -S -D -H` (busybox Keenetic) и `useradd -r -M` не сработали, запись
  добавляется прямо в `/etc/passwd` и `/etc/group` со свободным uid. Именно
  отсутствие пользователя ломало всё дальше: `iptables -m owner --uid-owner
  teleproxy` не ставится, метка не появляется, трафик идёт мимо туннеля
  (`susanin check` показывал `mark_rules=0`).

- **Ключи P5 добавляются автоматически.** Если найден
  `/opt/susanin/etc/susanin.conf` и в нём нет `proxy_uid`, postinst дописывает
  `proxy_uid/proxy_egress/proxy_table/proxy_mark` и перезапускает Susanin.

- **Проброс порта 8443 создаётся при установке.** Новый
  `/opt/etc/init.d/S98teleproxy-fw` ставит правила идемпотентно:
  `WAN:8443 → localhost:8443`, `INPUT ACCEPT`, и то же для LAN по внешнему IP
  (чтобы ссылка работала и из WiFi). Скрипт запускается при установке и при
  загрузке (S98 раньше S99), ждёт появления WAN до 60 секунд.
  `S98teleproxy-fw stop` снимает правила; `prerm` делает это при удалении.

- **Порт 443 не трогается** — на роутере он занят ocserv/nginx (OC+ и
  веб-конфигуратор).

## Установка / обновление

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Проверка после установки:

```sh
id teleproxy
ls -l /opt/etc/teleproxy/config.toml          # root:teleproxy, -rw-r-----
susanin check | grep proxy_egress              # mark_rules=1 ip_rule=1 default_route=1
iptables -t mangle -S OUTPUT | grep uid-owner
iptables -t nat -S PREROUTING | grep 8443
ip route get 149.154.167.51 uid $(id -u teleproxy)   # dev nwg0
```

## Если пользователь всё же не создался

```sh
echo 'teleproxy:x:1001:1001::/opt/var/empty:/sbin/nologin' >> /etc/passwd
echo 'teleproxy:x:1001:' >> /etc/group
chown root:teleproxy /opt/etc/teleproxy/config.toml
chmod 640 /opt/etc/teleproxy/config.toml
susanin restart
```

Либо `user = "root"` в конфиге (тогда P5 по uid работать не будет).
