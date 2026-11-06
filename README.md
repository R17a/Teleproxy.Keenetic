# Teleproxy.Keenetic

**MTProto-прокси с fake-TLS для роутеров Keenetic (Entware) · форк [teleproxy/teleproxy](https://github.com/teleproxy/teleproxy)**

[![Language: C11](https://img.shields.io/badge/C-11-blue?logo=c&logoColor=white)](src)
[![Upstream](https://img.shields.io/badge/upstream-teleproxy%2Fteleproxy-lightgrey)](https://github.com/teleproxy/teleproxy)
[![Entware required](https://img.shields.io/badge/Entware-required-orange)](README.md)
[![Architectures](https://img.shields.io/badge/arch-mipsel%20%7C%20mips%20%7C%20aarch64%20%7C%20armv7-lightgrey)](README.md)
[![License](https://img.shields.io/badge/license-GPLv2-blue)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/R17a/Teleproxy.Keenetic/total)](https://github.com/R17a/Teleproxy.Keenetic/releases)

[![Donate CloudTips](https://img.shields.io/badge/donate-CloudTips-598bd7.svg?style=flat)](https://pay.cloudtips.ru/p/dcbf5f2e)
[![Donate DonationAlerts](https://img.shields.io/badge/donate-DonationAlerts-f5a623.svg?style=flat)](https://www.donationalerts.com/r/dmitriy_r17a)
[![Join Telegram group](https://img.shields.io/badge/Telegram_group-Join-blue.svg?style=social&logo=telegram)](https://t.me/Susanin_Keenetic)

> Это README нашего форка. Документация upstream (сборка, конфиг, тесты) —
> в репозитории [`teleproxy/teleproxy`](https://github.com/teleproxy/teleproxy#readme).
> Исходники те же, плюс патчи ниже; каталоги docs/, tests/, fuzz/, Docker-обвязка
> в этом форке не нужны и удалены.

<hr>

## Зачем этот форк

Оригинальный [MTProxy](https://github.com/TelegramMessenger/MTProxy) (C) не умеет
fake-TLS, а Python-прокси на слабом роутере съедает 45–50 МБ RAM и валит память
(проверено на Keenetic Viva: 124 МБ, вместе с Xray остаётся ~10 МБ — дальше
reclaim, load 10+ и зависание сети).

`teleproxy` — C-форк с fake-TLS (режим EE), direct-to-DC, динамическим размером
записей и низким потреблением памяти. На MIPS он вписывается в роутер.

Этот репозиторий — тот же код плюс минимальные правки, чтобы он собирался и
работал на архитектурах Keenetic, и готовые артефакты в `dist/`.

**Статус:** собирается и запускается на `mipsel` (Keenetic Viva, MT7621).
Выход в туннель — по uid через [Susanin.Keenetic](https://github.com/R17a/Susanin.Keenetic)
0.4.5 (`proxy_uid` / `proxy_egress`), без SOCKS и без `ip route` в main-таблице.

> Готовые бинарники `teleproxy.<arch>` и пакеты `.ipk` лежат в
> [Releases](https://github.com/R17a/Teleproxy.Keenetic/releases), а не в git:
> каталог `dist/` добавлен в `.gitignore`.

## Что изменено относительно upstream

| Файл | Правка | Причина |
|---|---|---|
| `src/mtproto/mtproto-proxy-stats.c` | переменная `_mips` → `_maxips` | GCC на MIPS предопределяет макрос `_mips`; объявление превращалось в `int 1 = ...` |
| `src/common/precise-time.h` | добавлена ветка `#else` для `rdtsc()` | в upstream `rdtsc` есть только для x86/aarch64; на MIPS — `clock_gettime(CLOCK_MONOTONIC)` |
| `src/common/compat-atomic64.c` | новый файл | libatomic на mipsel не экспортирует `__sync_fetch_and_add_8` и родственные; шим через `__atomic_*` |
| `Makefile` | `compat-atomic64.o` в `LIB_OBJS_NORMAL` | чтобы файл собирался штатно |
| `src/net/net-connections.h` | `MAX_CONNECTIONS` под `#ifndef` | дефолт 65536 → BSS ~114 МБ; для роутера 2048 |
| `src/net/net-events.h` | `MAX_EVENTS` под `#ifndef` | дефолт 1<<19 → ~40 МБ BSS; для роутера 8192 |
| `src/mtproto/mtproto-proxy.c` | `EXT_CONN_TABLE_SIZE` под `#ifndef` | дефолт 1<<22 → 64 МБ BSS; для роутера 16384 |
| `.gitignore` | `dist/` | бинарники не коммитим |

Правок в логике протокола нет — только портируемость и размеры статических таблиц.
Итог: BSS 8,9 МБ вместо 120 МБ, без этого процесс падает на старте на 124 МБ RAM.

## Архитектуры

| Архитектура | Модели | Статус |
|---|---|---|
| `mipsel` (MIPS32 rel2) | Viva (KN-1910), Giga, Ultra (часть), Air | собирается, проверяется |
| `mips` (big-endian) | старые Keenetic | собирается |
| `aarch64` | Giga (KN-1011), Ultra (KN-1811), Hopper | собирается |
| `armv7` | часть младших моделей | собирается |
| `x86_64` | Entware на ПК/VM | собирается |

Статическая сборка: на роутер кладётся один бинарник, зависимостей нет.

## Сборка

Нужен WSL/Debian с кросс-компиляторами, `make`, `curl`, `perl`
(OpenSSL и zlib собираются скриптом в `~/tp-build/out/<arch>` и переиспользуются):

```bash
sudo apt install -y build-essential curl perl \
  gcc-mipsel-linux-gnu gcc-mips-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf
git clone https://github.com/R17a/Teleproxy.Keenetic
cd Teleproxy.Keenetic

bash tools/build-arch.sh mipsel     # -> dist/teleproxy.mipsel
bash tools/build-arch.sh all        # mipsel mips aarch64 armv7 x86_64
file dist/teleproxy.mipsel
```

Скрипт сам выбирает цель OpenSSL (`linux-generic32`/`linux-aarch64`/`linux-armv4`/
`linux-x86_64`), собирает `libcrypto.a` и `libz.a` под нужную архитектуру и линкует
`teleproxy` статически. Лимиты памяти (`MAX_CONNECTIONS`, `MAX_EVENTS`,
`EXT_CONN_TABLE_SIZE`) можно переопределить переменными окружения.

## Установка на роутер

Быстрее всего — пакетом из релиза (создаёт пользователя `teleproxy`, каталоги и
конфиг-пример, существующий конфиг не трогает):

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Или вручную из `dist/`:

| Файл | Куда | Права |
|---|---|---|
| `teleproxy.<arch>` | `/opt/sbin/teleproxy` | `chmod +x` |
| `config.toml` | `/opt/etc/teleproxy/config.toml` | `chown root:teleproxy`, `chmod 640` |
| `init/S99teleproxy` | `/opt/etc/init.d/S99teleproxy` | `chmod +x` |

```sh
adduser -S -D -H -s /sbin/nologin teleproxy
mkdir -p /opt/etc/teleproxy /opt/var/log /opt/var/run
chmod +x /opt/sbin/teleproxy /opt/etc/init.d/S99teleproxy
chown root:teleproxy /opt/etc/teleproxy/config.toml
chmod 640 /opt/etc/teleproxy/config.toml
/opt/etc/init.d/S99teleproxy start
/opt/etc/init.d/S99teleproxy status
netstat -ltn | grep 8443
```

Ссылку для клиента собирает отдельный хелпер (прокси её не печатает):

```sh
sh tools/make-link.sh <32-hex-secret> <EXTERNAL_IP> 8443 cloudflare.com
# -> tg://proxy?server=...&port=8443&secret=ee<secret><hex(domain)>
```

## Конфигурация

```toml
port = 8443              # 443 на роутере обычно занят (ocserv/nginx, веб-конфигуратор)
stats_port = 8899
http_stats = true
direct = true
user = "teleproxy"                 # отдельный uid: по нему Susanin метит трафик
workers = 0
max_connections = 512
domain = "cloudflare.com"          # домен-прикрытие для fake-TLS (EE)

[[secret]]
key = "…32 hex…"
label = "myphone"
```

- **Порт.** Не занимайте `443`, если на роутере работает OpenConnect-сервер или
  веб-конфигуратор Keenetic: перехват 443 ломает OC+ (проверено).
- **SOCKS5 не используется.** Выход в туннель обеспечивает Susanin по uid
  (см. раздел «Совместно с Susanin 0.4.5») — так остаётся одна крипто-схема:
  MTProto + WireGuard в ядре.
- **Секретов может быть несколько**: каждый блок `[[secret]]` — отдельный
  пользователь/устройство со своим ключом и меткой.

## Ссылки для клиентов

Teleproxy, в отличие от Python-версии, ссылку не печатает — она собирается из
ключа, адреса, порта и домена-прикрытия:

```text
secret = "ee" + <32-hex key> + hex(<domain>)
tg://proxy?server=<host>&port=<port>&secret=<secret>
```

`hex("cloudflare.com")` = `636c6f7564666c6172652e636f6d`

Готовый хелпер:

```sh
sh tools/make-link.sh <32-hex key> <host> <port> [domain]
# пример:
sh tools/make-link.sh 72995647c48776f584339f198f0ad2b7 <EXTERNAL_IP> 8443 cloudflare.com
```

Вывод:

```text
tg://proxy?server=<EXTERNAL_IP>&port=8443&secret=ee72995647c48776f584339f198f0ad2b7636c6f7564666c6172652e636f6d
https://t.me/proxy?server=<EXTERNAL_IP>&port=8443&secret=ee72995647c48776f584339f198f0ad2b7636c6f7564666c6172652e636f6d
```

Важно: **порт в ссылке — внешний**, тот, что проброшен на роутер (например `8443`,
а не локальный, если проброс идёт `443 → 8443`). Для пересылки в чат удобнее форма
`https://t.me/proxy?…` — секрет тот же.

## Совместно с Susanin 0.4.5

Схема: прокси работает под отдельным пользователем, Susanin метит **его**
исходящие соединения по uid и отправляет в интерфейс туннеля. LAN-клиенты при
этом продолжают ходить своим путём (Xray/tproxy) — правила не пересекаются.

1. Создать пользователя и отдать ему конфиг:
   ```sh
   adduser -S -D -H -s /sbin/nologin teleproxy    # busybox
   chown root:teleproxy /opt/etc/teleproxy/config.toml
   chmod 640 /opt/etc/teleproxy/config.toml
   ```
2. В `/opt/susanin/etc/susanin.conf`:
   ```ini
   proxy_uid=teleproxy
   proxy_egress=nwg0
   proxy_table=110
   proxy_mark=0x01000000
   ```
3. `susanin restart`, затем проверить:
   ```sh
   susanin check | grep proxy_egress
   ip rule show | grep 'lookup 110'
   iptables -t mangle -S OUTPUT | grep uid-owner
   ```
4. Запустить прокси:
   ```sh
   /opt/etc/init.d/S99teleproxy start
   ```
5. Проверка маршрута процесса:
   ```sh
   ip route get 149.154.167.51 uid $(id -u teleproxy)
   ```
   Должно быть `dev nwg0`.

## Проброс порта

Внешний **8443 → `192.168.1.1:8443`** (не 443):

```sh
WAN=$(ip route show default | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
iptables -t nat -I PREROUTING 1 -i "$WAN" -p tcp --dport 8443 -j REDIRECT --to-ports 8443
iptables -I INPUT 1 -i "$WAN" -p tcp --dport 8443 -j ACCEPT
```

Правила живут до перезагрузки; для постоянства — отдельный init-скрипт (см.
`init/S99teleproxy` и историю Susanin.Keenetic).

## Требования

- роутер Keenetic с Entware (нужен `opkg`);
- **поднятый туннель WireGuard/AmneziaWG** («Другое подключение» Keenetic, интерфейс
  вида `nwg0`), через который доступны серверы Telegram;
- [Susanin.Keenetic](https://github.com/R17a/Susanin.Keenetic) **0.4.5+** с
  настроенным `proxy_uid=teleproxy` и `proxy_egress=nwg0` — он направляет трафик
  прокси в туннель по uid;
- публичный IP и проброс внешнего порта на роутер.

Xray/VLESS и SOCKS-вход **не нужны**: прокси работает в режиме `direct = true` и
выходит в интернет через WireGuard-интерфейс. Без Susanin прокси тоже запустится,
но пойдёт напрямую — из РФ серверы Telegram при этом недоступны.

## Ветка и обновление с upstream

Проект ведётся одной веткой `main` (как Susanin.Keenetic); в upstream ничего не
отправляем, только забираем исправления.

```bash
git fetch upstream
git merge upstream/main        # конфликты возможны в изменённых файлах (см. таблицу патчей)
git push origin main
```

Отдельного зеркала апстрима нет: часть каталогов upstream (docs/, tests/, fuzz/,
Docker-обвязка) удалена, поэтому при мерже возможны конфликты типа
«modify/delete» — их решаем в пользу нашей версии.

## Откат

```sh
/opt/etc/init.d/S99teleproxy stop
chmod -x /opt/etc/init.d/S99teleproxy
iptables -t nat -D PREROUTING 1
```

## Лицензия

GPLv2, как у upstream (`LICENSE`). Автор upstream — команда teleproxy;
портирование под Keenetic — R17a.

## Поддержка и связь

- Релизы и загрузка: [Teleproxy.Keenetic releases](https://github.com/R17a/Teleproxy.Keenetic/releases)
- Обсуждение: Telegram-группа [@Susanin_Keenetic](https://t.me/Susanin_Keenetic)
- Донат: [CloudTips](https://pay.cloudtips.ru/p/dcbf5f2e) · [DonationAlerts](https://www.donationalerts.com/r/dmitriy_r17a)

Проект не связан и не аффилирован с Keenetic, Telegram или авторами upstream.