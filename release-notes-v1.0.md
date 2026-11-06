# Teleproxy.Keenetic v1.0 (mipsel)

Первый релиз форка: upstream-код teleproxy, портированный под MIPS32 (Keenetic),
плюс готовый статический бинарник.

## Что внутри

- `teleproxy.mipsel` — статический бинарник (5.6 МБ), зависимостей нет;
- `config.toml` — пример: fake-TLS на `cloudflare.com`, порт `8443`,
  `user = "teleproxy"`, без SOCKS;
- `S99teleproxy` — init-скрипт для Entware (start/stop/status/reload);
- `README.md` — установка, сборка, совместная работа с Susanin 0.4.5.

## Патчи к upstream

| Файл | Правка | Зачем |
|---|---|---|
| `src/common/precise-time.h` | `rdtsc()` для MIPS | в upstream только x86/aarch64 |
| `src/mtproto/mtproto-proxy-stats.c` | `_mips` → `_maxips` | GCC на MIPS определяет `_mips` |
| `src/common/compat-atomic64.c` | шим `__sync_*_8` | libatomic на mipsel не экспортирует их |
| `Makefile` | сборка шима | — |
| `src/engine/engine.h` | `OUR_SIGRTMAX` = 127 на MIPS | иначе assert на старте |
| `src/net/net-connections.h` | `MAX_CONNECTIONS` под `#ifndef` | дефолт 65536 → BSS ~114 МБ |
| `src/net/net-events.h` | `MAX_EVENTS` под `#ifndef` | дефолт 1<<19 → ~40 МБ BSS |
| `src/mtproto/mtproto-proxy.c` | `EXT_CONN_TABLE_SIZE` под `#ifndef` | дефолт 1<<22 → 64 МБ BSS |

Итого BSS 8,9 МБ вместо 120 МБ — без этого на 124 МБ роутера процесс падает на старте.

## Установка

```sh
# 1. пользователь (для матча по uid в Susanin 0.4.5)
adduser -S -D -H -s /sbin/nologin teleproxy

# 2. файлы
mkdir -p /opt/etc/teleproxy
# teleproxy.mipsel -> /opt/sbin/teleproxy
# config.toml      -> /opt/etc/teleproxy/config.toml
# S99teleproxy     -> /opt/etc/init.d/S99teleproxy
chmod +x /opt/sbin/teleproxy /opt/etc/init.d/S99teleproxy
chown root:teleproxy /opt/etc/teleproxy/config.toml
chmod 640 /opt/etc/teleproxy/config.toml

# 3. запуск
/opt/etc/init.d/S99teleproxy start
```

Выход в туннель настраивается в Susanin 0.4.5:

```ini
proxy_uid=teleproxy
proxy_egress=nwg0
```

## Проверка

```sh
/opt/etc/init.d/S99teleproxy status
netstat -ltn | grep 8443
ip route get 149.154.167.51 uid $(id -u teleproxy)   # ожидаем dev nwg0
```

## Совместимость

- Keenetic Viva (MT7621, MIPS32 rel2), Entware, KeeneticOS 4.9+/5.x;
- Susanin.Keenetic 0.4.5 (`proxy_uid`) — рекомендуется; без него прокси работает,
  но ходит напрямую.

## Поддержка

- CloudTips: https://pay.cloudtips.ru/p/dcbf5f2e
- DonationAlerts: https://www.donationalerts.com/r/dmitriy_r17a
- Telegram: https://t.me/Susanin_Keenetic
