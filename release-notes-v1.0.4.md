# Teleproxy.Keenetic v1.0.4

Установка на Keenetic, где `/etc/passwd` только для чтения: пользователя
`teleproxy` создать нельзя, поэтому переходим на **числовой uid** — он не требует
записи в passwd.

## Что изменено

- **Teleproxy принимает числовой uid в `user`.** В `change_user_group()`
  добавлена ветка: если значение начинается с цифры, выполняется
  `setuid(N)/setgid(N)` без `getpwnam()`. На Keenetic это единственный способ
  запустить прокси под отдельным uid — `adduser` и запись в `/etc/passwd`
  блокируются read-only корнем прошивки.

- **`postinst` выбирает идентификатор автоматически:** если пользователя создать
  удалось — `user = "teleproxy"`; если нет — `user = "1001"` (свободный uid) и
  `proxy_uid=1001` в `susanin.conf`. `iptables --uid-owner 1001` работает без
  записи в passwd.

- **postinst больше ничего не пропускает:** права `root:1001 640`, ключи P5,
  перезапуск Susanin, проброс 8443 (`S98teleproxy-fw`) и запуск службы.

## Совместимость

- требует **Susanin.Keenetic 0.4.6+** — в нём `proxy_uid` тоже понимает число
  (без этого `backend_ready` считал бы правило отсутствующим и перепровижнил
  датаплейн каждые 15 с);
- со старым Susanin 0.4.5 прокси работать будет, но с лишними репровижнами.

## Установка / обновление

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Ожидаемый вывод:

```
[teleproxy] идентификатор: 1001 (режим: numeric)
[teleproxy] config.toml: user = "1001"
[teleproxy] susanin.conf: proxy_uid=1001, proxy_egress=nwg0
[teleproxy] susanin перезапущен (правило метки пересоздано)
teleproxy-fw: порт 8443 проброшен (wan=ppp0)
[teleproxy] служба запущена
```

## Проверка

```sh
susanin check | grep proxy_egress           # mark_rules=1 ip_rule=1 default_route=1
iptables -t mangle -S OUTPUT | grep uid-owner
iptables -t nat -S PREROUTING | grep 8443
ip route show table 110                      # default dev nwg0
/opt/etc/init.d/S99teleproxy status
```
