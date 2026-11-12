# Teleproxy на VDS (vds.example.com) — мультипользовательский MTProto

Развёрнуто 2026-11-11. Один порт `2398`; у каждого пользователя свой блок
`[[secret]]` (в примере конфига оставлен один — `default`). Входы `px1`
(`px1.example.com:443`) и `px2` (`px2.example.com:8443`) форвардят на этот
порт, поэтому смена движка на входы не повлияла.

## Что где лежит

| Файл | Назначение |
|---|---|
| `/opt/teleproxy/teleproxy` | бинарь `dist/teleproxy.x86_64` (статическая сборка) |
| `/opt/teleproxy/config.toml` | конфиг: порт, домен, `[[secret]]` (в примере — один) |
| `/etc/systemd/system/teleproxy.service` | unit, автозапуск включён |

Официальный `mtproto-proxy` (`mtproxy.service`) **выключен и снят с автозапуска**,
файлы и `/etc/mtproxy/mtproxy.env` оставлены для отката.

## Две грабли, на которые уже наступили

1. **`user = "0"` обязателен.** Бинарь собран статически, а на Ubuntu
   `getpwnam("nobody")` внутри статического glibc уходит в `libnss_systemd.so.2`
   и падает с stack backtrace сразу после проверки домена:
   `_nss_systemd_is_blocked` → `_nss_systemd_getpwnam_r`. Числовой uid обходит
   `getpwnam` целиком (`server-functions.c`: если первый символ — цифра, идёт
   `setgroups/setgid/setuid` без обращения к `/etc/passwd`).
2. **`stats_port = 8899` слушает `0.0.0.0`.** Наружу он не нужен, закрыт
   правилом: `iptables -I INPUT -p tcp --dport 8899 ! -s 127.0.0.1 -j DROP`.

## Проверка

```sh
systemctl is-active teleproxy
ss -ltnp | grep 2398
journalctl -u teleproxy -n 20 --no-pager
curl -s http://127.0.0.1:8899/stats | head
```

В логе при старте должно быть:

```
loaded config from /opt/teleproxy/config.toml
Proxy domain: cloudflare.com:443
direct mode: connecting directly to Telegram DCs (no ME relay)
secret reload: 0 pinned + 1 active (high-water slot 1)
Successfully checked domain cloudflare.com ...
main loop
```

## Добавить / отозвать пользователя

Дописать или удалить блок `[[secret]]` в `/opt/teleproxy/config.toml`,
затем `systemctl restart teleproxy`. Остальные пользователи не затрагиваются.

Ссылка клиента: `ee` + ключ + `hex("cloudflare.com")` (`636c6f7564666c6172652e636f6d`).

## Откат на официальный движок

```sh
systemctl disable --now teleproxy
systemctl enable --now mtproxy
```

При переезде прежний секрет был добавлен отдельным блоком `[[secret]]` с
меткой `legacy` — чтобы старые ссылки (без `ee`) не отвалились.
