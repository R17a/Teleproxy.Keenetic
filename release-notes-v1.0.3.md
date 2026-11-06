# Teleproxy.Keenetic v1.0.3

Точечное дополнение к 1.0.2: после установки служба запускается сама.

## Что изменилось

- **`postinst` запускает прокси** (`S99teleproxy restart`), а не только печатает
  подсказку. Теперь установка полностью автоматическая: пользователь, права,
  ключи P5, проброс 8443 и запуск службы — всё делает пакет.

Остальное как в 1.0.2:

- пользователь `teleproxy` создаётся с записью в `/etc/passwd` (busybox `adduser`
  на Keenetic ненадёжен);
- ключи `proxy_uid`/`proxy_egress` дописываются в `susanin.conf`, Susanin
  перезапускается — создаётся правило метки по uid;
- `S98teleproxy-fw` ставит проброс `WAN:8443 → localhost:8443` (и для LAN по
  внешнему IP) при установке и при каждой загрузке;
- порт `443` не трогается — там ocserv/nginx (OC+ и веб-конфигуратор).

## Установка / обновление

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Ожидаемый вывод postinst:

```
[teleproxy] пользователь teleproxy: uid=1001
[teleproxy] в susanin.conf добавлены proxy_uid/proxy_egress   (или: P5 уже настроен)
[teleproxy] susanin перезапущен (правило метки пересоздано)
[teleproxy] служба запущена
```

## Проверка после установки

```sh
susanin check | grep proxy_egress        # mark_rules=1 ip_rule=1 default_route=1
iptables -t nat -S PREROUTING | grep 8443
/opt/etc/init.d/S99teleproxy status
ip route get 149.154.167.51 uid $(id -u teleproxy)   # dev nwg0
```
