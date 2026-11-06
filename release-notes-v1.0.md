# Teleproxy.Keenetic v1.0

Первый релиз форка: upstream-код teleproxy, портированный под архитектуры
Keenetic (Entware), плюс готовые статические бинарники.

## Что внутри

- `teleproxy.<arch>` — статические бинарники (~4–6 МБ), зависимостей нет:
  `mipsel`, `mips`, `aarch64`, `armv7`, `x86_64`;
- `teleproxy-keenetic_1.0_<arch>.ipk` — пакеты Entware для тех же архитектур;
- `config.toml` — пример: fake-TLS на `cloudflare.com`, порт `8443`,
  `user = "teleproxy"`, один секрет-заглушка;
- `init/S99teleproxy` — init-скрипт для Entware (start/stop/status/reload);
- `install-keenetic.sh` — установщик пакета из релиза;
- `README.md` — установка, сборка, ссылки, совместная работа с Susanin 0.4.5.

## Архитектуры

| arch | модели | файл |
|---|---|---|
| mipsel | Viva, Giga, Ultra (часть), Air | `teleproxy.mipsel` |
| mips | старые Keenetic | `teleproxy.mips` |
| aarch64 | Giga (KN-1011), Ultra (KN-1811), Hopper | `teleproxy.aarch64` |
| armv7 | часть младших моделей | `teleproxy.armv7` |
| x86_64 | Entware на ПК/VM | `teleproxy.x86_64` |

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

## Установка (одной командой)

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Скрипт определяет архитектуру через `opkg print-architecture`, скачивает нужный
`.ipk` из этого релиза и ставит его. Postinst создаёт пользователя `teleproxy`,
каталоги и `/opt/etc/teleproxy/config.toml` (существующий конфиг не трогает).

Дальше — вписать свои секреты в `/opt/etc/teleproxy/config.toml` и запустить:

```sh
/opt/etc/init.d/S99teleproxy start
```

## Установка пакетом вручную

```sh
cd /opt/tmp
wget https://github.com/R17a/Teleproxy.Keenetic/releases/download/v1.0/teleproxy-keenetic_1.0_mipsel-3.4.ipk
opkg install ./teleproxy-keenetic_1.0_mipsel-3.4.ipk
```

Свою архитектуру показывает `opkg print-architecture`:

| opkg arch | файл |
|---|---|
| mipsel-3.4 | `teleproxy-keenetic_1.0_mipsel-3.4.ipk` |
| mips-3.4 | `teleproxy-keenetic_1.0_mips-3.4.ipk` |
| aarch64-3.10 | `teleproxy-keenetic_1.0_aarch64-3.10.ipk` |
| armv7sf-k3.2 | `teleproxy-keenetic_1.0_armv7sf-k3.2.ipk` |
| x86-64 | `teleproxy-keenetic_1.0_x86-64.ipk` |

## Установка бинарником (без пакета)

```sh
adduser -S -D -H -s /sbin/nologin teleproxy
mkdir -p /opt/etc/teleproxy /opt/var/log /opt/var/run
# teleproxy.<arch> -> /opt/sbin/teleproxy
# config.toml      -> /opt/etc/teleproxy/config.toml
# S99teleproxy     -> /opt/etc/init.d/S99teleproxy
chmod +x /opt/sbin/teleproxy /opt/etc/init.d/S99teleproxy
chown root:teleproxy /opt/etc/teleproxy/config.toml
chmod 640 /opt/etc/teleproxy/config.toml
/opt/etc/init.d/S99teleproxy start
```

## Секреты и ссылки

Секреты — 32 hex-символа на пользователя, блоки `[[secret]]` в конфиге.
Ссылка собирается как `ee` + ключ + `hex(domain)`:

```sh
sh tools/make-link.sh <32-hex-ключ> <EXTERNAL_IP> 8443 cloudflare.com
# -> tg://proxy?server=<EXTERNAL_IP>&port=8443&secret=ee<ключ><hex(домена)>
```

Порт в ссылке — **внешний** (тот, что проброшен на роутер).

## Выход в туннель (Susanin 0.4.5)

```ini
# /opt/susanin/etc/susanin.conf
proxy_uid=teleproxy
proxy_egress=nwg0
```

```sh
susanin restart && susanin check | grep proxy_egress
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
