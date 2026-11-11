# Teleproxy на серверной стороне (Aeza, x86_64)

Прокси с **несколькими ключами** (по ключу на пользователя). Собирается тем же
`tools/build-arch.sh x86_64`, кладётся в `/opt/teleproxy/teleproxy`.

## Зачем здесь socks5, а не прямой выход

Хостинг Aeza фильтрует подсети Telegram. Замер 2026-11-11 с самого Aeza:

```
149.154.167.51 direct FAIL   149.154.167.51 socks ok
149.154.175.53 direct FAIL   149.154.175.53 socks ok
91.108.56.130  direct FAIL   91.108.56.130  socks ok
```

`socks5` — это локальный Xray (`127.0.0.1:11080`), который уходит на VDS
`<IP-VDS>` (VLESS), а уже VDS соединяется с DC Telegram. Поэтому в
`config.toml` стоит `socks5 = "socks5://127.0.0.1:11080"`.

## Порты

| Порт | Что | Статус |
|---|---|---|
| 8443 | `socat` → `<IP-VDS>:2398` (официальный MTProxy, один секрет) | рабочий, не трогаем |
| 8444 | Teleproxy, 5 ключей (этот каталог) | тестовый |

Когда 8444 подтверждён — Teleproxy переносится на 8443, `socat` отключается:
один порт, много ключей, у каждого пользователя своя ссылка.

## Установка

```sh
mkdir -p /opt/teleproxy
cp teleproxy /opt/teleproxy/teleproxy && chmod +x /opt/teleproxy/teleproxy
cp config.toml /opt/teleproxy/config.toml
cp teleproxy.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now teleproxy
ss -ltnp | grep 8444
```

Порт открывается в firewall (если nft/ufw включены), проверка:
`curl -s http://127.0.0.1:8899/stats | head`.

## Ссылки клиентам

```
secret = "ee" + <32-hex key> + hex("cloudflare.com")   # hex = 636c6f7564666c6172652e636f6d
tg://proxy?server=vpn.example.com&port=8444&secret=<secret>
```

Пример для метки `den` (ключ подставляется из `config.toml` на сервере — в
репозиторий живые ключи не кладём):

```
https://t.me/proxy?server=vpn.example.com&port=8444&secret=ee<32-hex key>636c6f7564666c6172652e636f6d
```

Собрать ссылку: `sh tools/make-link.sh <key> vpn.example.com 8444 cloudflare.com`.

## Добавить или отозвать пользователя

Дописать/удалить блок `[[secret]]` в `/opt/teleproxy/config.toml` и выполнить
`systemctl restart teleproxy`. Клиентов это не затрагивает — у каждого свой
ключ, отзыв одного не рвёт остальных.

## Отличие от пакета для роутера

В `packaging/config.toml.example` намеренно **один** `[[secret]]` — как пример
формата. Несколько ключей живут только на сервере, в `deploy/aeza/config.toml`.
