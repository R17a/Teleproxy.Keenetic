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
работал на архитектурах Keenetic. Готовые пакеты публикуются в
[Releases](https://github.com/R17a/Teleproxy.Keenetic/releases); каталог `dist/`
— локальный, в git его нет (см. `.gitignore`), он появляется после
`tools/build-arch.sh`.

**Статус:** собирается и запускается на `mipsel` (Keenetic Viva, MT7621).
Выход в туннель — либо по uid через [Susanin.Keenetic](https://github.com/R17a/Susanin.Keenetic)
0.4.5+ (`proxy_uid` / `proxy_egress=nwg0`, «Другое подключение» Keenetic),
либо через SOCKS5 локального Xray — см. раздел «Выход в интернет».

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

Быстрее всего — пакетом из релиза (сам определит архитектуру, создаст
пользователя `teleproxy`, каталоги и конфиг-пример; существующий конфиг не трогает):

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Пакетом вручную — сначала архитектура:

```sh
opkg print-architecture | awk '{print $2}'
```

| что выведет opkg | пакет |
|---|---|
| `mipsel-3.4` | `teleproxy-keenetic_1.0_mipsel-3.4.ipk` |
| `mips-3.4` | `teleproxy-keenetic_1.0_mips-3.4.ipk` |
| `aarch64-3.10` | `teleproxy-keenetic_1.0_aarch64-3.10.ipk` |
| `armv7sf-k3.2` | `teleproxy-keenetic_1.0_armv7sf-k3.2.ipk` |
| `x86-64` | `teleproxy-keenetic_1.0_x86-64.ipk` |

Автоматически (подставит нужный файл):

```sh
VER=1.0
ARCH=$(opkg print-architecture | awk '{print $2}' \
       | grep -E '^(mipsel|mips|aarch64|armv7|x86-64)' | head -1)
PKG="teleproxy-keenetic_${VER}_${ARCH}.ipk"
cd /opt/tmp
wget "https://github.com/R17a/Teleproxy.Keenetic/releases/download/v${VER}/${PKG}"
opkg install "./${PKG}"
```

Или бинарником, без пакета:

| Файл | Куда | Права |
|---|---|---|
| `teleproxy.<arch>` | `/opt/sbin/teleproxy` | `chmod +x` |
| `packaging/config.toml.example` | `/opt/etc/teleproxy/config.toml` | `chown root:teleproxy`, `chmod 640` |
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
user = "teleproxy"                 # отдельный uid: по нему Susanin.Keenetic метит трафик
workers = 0
max_connections = 32               # special-соединения; общий лимит задаёт S99teleproxy
mss_clamp = false                  # фрагментация ClientHello: на PPPoE мешает
domain = "cloudflare.com"          # домен-прикрытие для fake-TLS (EE)

[[secret]]
key = "…32 hex…"
label = "myphone"
```

- **Порт.** Не занимайте `443`, если на роутере работает OpenConnect-сервер или
  веб-конфигуратор Keenetic: перехват 443 ломает OC+ (проверено).
- **Выход в туннель — один из двух** (см. раздел «Выход в интернет»):
  `user = "teleproxy"` + `proxy_uid`/`proxy_egress` в Susanin.Keenetic (трафик
  уходит в `nwg0`), либо `socks5 = "socks5://127.0.0.1:1080"` (трафик уходит в
  Xray из Susanin.Keenetic). Вместе их не включают.
- **Лимиты соединений** на Keenetic задаёт init-скрипт, и он перекрывает TOML:
  `--connections 128 --max-special-connections 32 --msg-buffers-size 10485760`.
  Ключ `max_connections` в TOML — потолок только «special» (секретных)
  соединений, а не всей таблицы. Чанк буферов — 2 МБ, поэтому 10 МБ = 5 чанков.
  Проверено на Viva (124 МБ): 4 МБ (2 чанка) исчерпывались сразу, 8 МБ (4)
  упирались в потолок под видео, 16 МБ (8) приводили к kswapd/OOM; 10 МБ —
  рабочий вариант с запасом (~20 МБ available).
- **`direct = true`** — это «соединяться с DC Telegram напрямую, без ME-relay»,
  а не «мимо туннеля»: маршрут всё равно определяется ядром/Susanin.Keenetic.
- **Всё перечисленное — «из коробки».** `S99teleproxy` в пакете уже запускает
  прокси с `--msg-buffers-size 10485760 --connections 128
  --max-special-connections 32`, а `postinst` при установке и обновлении
  дописывает в `config.toml` `mss_clamp = false` и `max_connections = 32`
  (существующий конфиг не затирается, добавляются только недостающие ключи).
  Править руками после `opkg install` ничего не нужно.
- **Если пул всё-таки кончился** (`cannot allocate tcp receive buffer … got 0
  of 128`, клиент висит на «Соединение», хотя процесс жив) — `S98teleproxy-fw`
  ловит это по `allocated_buffer_bytes` и `tcp_readv_bytes` и перезапускает
  прокси **только когда трафик встал**: пул ≥95% и за цикл не прочитано ни
  байта два цикла подряд, либо пул ≥85% и простой три цикла. Высокий пул при
  живом трафике рестарта не вызывает — иначе сторож рвал бы рабочие соединения
  (именно так «замирало» видео). Отдельный зависший сокет снаружи не закрыть
  (чужой fd без ptrace не отдать), поэтому лечим процессом. Факт пишется в
  `/opt/var/log/teleproxy-fw.log`.
- **Кого именно выкидывать при переполнении пула** (1.0.6): teleproxy сам
  закрывает соединения, когда пул занят больше чем на 3/4. Раньше он выбирал
  самые старые по созданию — то есть долгоживущие соединения к DC, через
  которые идёт видео. Теперь жертвой становится то соединение, которое дольше
  всех молчит (`update_conn_activity` в `cron`, сравнение занятых буферов раз
  в секунду), а видео не рвётся. В логе причина видна только при `-v 2`
  (`closing connection 12 (idle 41.3s)`), по умолчанию `verbosity=0`.
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

## Домен-прикрытие и fake-TLS (сертификатов нет)

`domain = "cloudflare.com"` — это **не** сертификат и не домен вашего сервера.
Сертификатов, ключей и ACME здесь нет вообще, настраивать нечего. Механика:

- клиент Telegram и прокси изображают TLS 1.3. Клиент в `ClientHello`
  отправляет SNI выбранного домена, прокси отвечает записями, которые выглядят
  как настоящий `ServerHello` этого домена;
- домен зашит в ссылку: `secret = ee + <32-hex ключ> + hex(<домен>)`, поэтому
  клиент и сервер обязаны использовать **один и тот же** домен. Поменяли домен —
  поменялись все ссылки;
- при старте teleproxy сам подключается к `<домен>:443` и запоминает параметры
  ответа: в логе это строка
  `Successfully checked domain cloudflare.com in 0.113 seconds:
  is_reversed_extension_order = 0, server_hello_encrypted_size = 1997`.
  Отсюда прокси знает, какого размера и в каком порядке слать записи.

Что требуется от домена:

- доступен с роутера по TLS 1.3 (прокси проверяет это при старте; если проверка
  не прошла — клиенты будут зависать на «Соединение»);
- его SNI не режется ТСПУ, иначе «TLS» до него выглядит подозрительно;
- поведение стабильно: если сервер начнёт отдавать другой `ServerHello`,
  размер перестанет совпадать и имитация станет заметной. Лечится перезапуском
  прокси — он перепроверит домен.

Менять домен:

```sh
sed -i 's|^domain = .*|domain = "example.com"|' /opt/etc/teleproxy/config.toml
/opt/etc/init.d/S99teleproxy restart
tail -3 /opt/var/log/teleproxy.log        # ждём «Successfully checked domain …»
```

После смены домена **все ссылки для клиентов пересобрать** (`tools/make-link.sh`)
и раздать заново: старые с другим `hex(domain)` работать не будут.

Если ТСПУ начал душить выбранный SNI — берут другой популярный домен и повторяют
процедуру. Ключи (`[[secret]]`) при этом можно оставить прежними: меняется только
хвост секрета.

Отдельно: `mss_clamp` в конфиге — про другое, это автоматическая фрагментация
`ClientHello` (низкий MSS), к сертификатам отношения не имеет.

## Выход в интернет: `nwg` или SOCKS5

Сам прокси маршрут не выбирает: он либо отдаёт исходящие соединения ядру
(тогда их уводит Susanin.Keenetic по uid процесса), либо ходит в локальный SOCKS5
(тогда маршрут задаёт Xray из Susanin.Keenetic). Способы взаимоисключающие — нужен один.

| | **A. Через `nwg`** («Другое подключение») | **B. Через SOCKS5 Xray** |
|---|---|---|
| `config.toml` | `direct = true`, `user = "teleproxy"` | `direct = true`, `socks5 = "socks5://127.0.0.1:1080"` |
| `susanin.conf` | `proxy_uid` + `proxy_egress=nwg0` | P5 не нужен |
| Что должно быть | WireGuard/AmneziaWG в «Других подключениях» Keenetic | Xray из поставки Susanin.Keenetic с SOCKS-входом |
| Схема шифрования | MTProto + WireGuard | MTProto + Xray/VLESS |

### A. Через `nwg` («Другое подключение» Keenetic)

1. В веб-конфигураторе Keenetic: **Интернет → Другие подключения → WireGuard /
   AmneziaWG** (или возьмите уже существующее). Интерфейс получит имя `nwg0`,
   `nwg1`, … — по порядку создания подключений.
2. Узнать фактическое имя на роутере:
   ```sh
   ip link show | grep -E 'nwg|wg|amnezia'
   ip -4 addr show dev nwg0
   ```
   (`ip -o`/`ip route get … uid` в busybox-версии `ip` на Keenetic нет.)
3. Проверить, что через этот интерфейс доступны серверы Telegram — иначе
   трафик уйдёт в туннель, но DC будут недоступны:
   ```sh
   curl -s --interface nwg0 --max-time 8 https://api.telegram.org | head -c 200
   ```
4. Пользователь и конфиг:
   ```sh
   adduser -S -D -H -s /sbin/nologin teleproxy    # busybox; postinst пакета делает это сам
   chown root:teleproxy /opt/etc/teleproxy/config.toml
   chmod 640 /opt/etc/teleproxy/config.toml
   ```
   В `config.toml`: `user = "teleproxy"` (можно числовой uid — на Keenetic
   `setuid(N)` работает и без записи в `/etc/passwd`), `direct = true`,
   строку `socks5` убрать. `user` заставляет процесс сбросить права уже после
   бинда порта, поэтому `8443` по-прежнему слушается от root.
5. В `/opt/susanin/etc/susanin.conf`:
   ```ini
   proxy_uid=teleproxy
   proxy_egress=nwg0
   proxy_table=110
   proxy_mark=0x01000000
   ```
   `susanin restart`, затем проверить:
   ```sh
   susanin check | grep proxy_egress      # mark_rules=1 ip_rule=1 default_route=1
   iptables -t mangle -S OUTPUT | grep uid-owner
   ip route show table 110                # default dev nwg0
   ```
6. Перезапустить прокси: `/opt/etc/init.d/S99teleproxy restart`.

LAN-клиенты при этом продолжают ходить своим путём (Xray/tproxy) — правила
Susanin.Keenetic для uid прокси с ними не пересекаются.

Если в `susanin check` вышло `default_route=0` или `proxy_egress: off` —
интерфейс `nwg0` лежит либо переименован: Keenetic перенумеровывает `nwg*`
при пересоздании подключения. Сверьтесь с шагом 2 и поправьте `proxy_egress`;
правила P5 переставляются при каждом `susanin restart`, но имя интерфейса
Susanin.Keenetic не угадывает.

### B. Через SOCKS5 Xray (Xray тоже из Susanin.Keenetic)

```toml
direct = true
socks5 = "socks5://127.0.0.1:1080"
```

`user`, `proxy_uid`, `proxy_egress` не нужны: прокси сам открывает TCP к
`127.0.0.1:1080`. Xray здесь — не отдельная установка, а часть
[Susanin.Keenetic](https://github.com/R17a/Susanin.Keenetic): его init-скрипт
`S93xray-tproxy` поднимает Xray с конфигом `/opt/susanin/etc/xray-tproxy.json`,
а `bootstrap.sh --with-xray` скачивает Xray-core. SOCKS-вход `:1080` объявлен
в этом же конфиге, поэтому достаточно установленного Susanin.Keenetic — свой
Xray ставить и настраивать не надо.

В этой схеме `nwg` вообще не участвует. Так работал роутер до 2026-11-09: телефон
→ `vpn.example.com:8443` → teleproxy → SOCKS `127.0.0.1:1080` → Xray
(Susanin.Keenetic) → `<IP-VDS>:8443`.

### C. Через SSH-SOCKS (быстрее Xray на слабом CPU)

Xray на MT7621 упирается в ~12 Мбит/с: REALITY шифруется в userspace, без
аппаратного AES. SSH на том же железе даёт ~28 Мбит/с (замеры 2026-11-09:
1,44–1,54 МБ/с через Xray против 3,5 МБ/с через SSH).

```toml
socks5 = "socks5://127.0.0.1:1081"
```

Туннель поднимает `autossh -D 127.0.0.1:1081` до VDS (ключ в `/opt/etc/ssh/`,
потому что `/root` на Keenetic — read-only squashfs; `ssh-keygen` нужен пакет
`openssh-keygen`, иначе подставляется dropbear и OpenSSH не читает ключ).
Init-скрипт — `S97ssh-tunnel` из комплекта поставки: он стартует раньше
`S98`/`S99`, чтобы туннель был готов к моменту запуска прокси.

**Конечный хост в скрипте не зашит** — адрес сервера в поставку не попадает.
Обязательно укажите его в `/opt/etc/teleproxy/ssh-tunnel.conf`:

```sh
SSH_HOST=vds.example.com      # адрес или IP вашего VDS — обязателен
SSH_KEY=/opt/etc/ssh/vds3     # путь к ключу (значение по умолчанию)
SSH_PORT=1081                 # локальный SOCKS-порт (значение по умолчанию)
```

Те же значения можно передать переменными окружения (`SSH_HOST`, `SSH_KEY`,
`SSH_PORT`) — они приоритетнее файла. Без `SSH_HOST` туннель не поднимается:
причина пишется в `/opt/var/log/ssh-tunnel.log`, а `S97ssh-tunnel status`
показывает «не задан SSH_HOST».

Тот же приём можно применить и к LAN-трафику: в `xray-tproxy.json` добавляется
outbound `ssh-socks` (protocol `socks` → `127.0.0.1:1081`) и первое правило
routing `TCP → ssh-socks`; UDP остаётся на VLESS. Тогда Xray работает релеем без
шифрования, и скорость LAN поднимается с 1,43 до 3,4 МБ/с.

## Проброс порта

Внешний **8443 → `192.168.1.1:8443`** (не 443):

```sh
WAN=$(ip route show default | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
iptables -t nat -I PREROUTING 1 -i "$WAN" -p tcp --dport 8443 -j REDIRECT --to-ports 8443
iptables -I INPUT 1 -i "$WAN" -p tcp --dport 8443 -j ACCEPT
```

Правила живут до перезагрузки; для постоянства — отдельный init-скрипт (см.
`init/S99teleproxy` и историю Susanin.Keenetic).

## Риск бана IP — и как это проверить

Банят не софт, а адреса, и риск есть у **обеих** точек схемы — и у роутера, и у сервера:

| Что забанено | Как выглядит | Чем лечится |
|---|---|---|
| IP роутера (Keenetic) | снаружи не открывается **ни один** порт, телефон висит на «Соединение», по Wi-Fi (внутри сети) при этом всё работает | новый статический IP у провайдера, либо фронт на VDS |
| IP сервера (VDS) | роутер не может достучаться до сервера ни по одному порту, хотя из другой сети он жив | другой IP/хостинг; для HTTP и WebSocket — фронт через CDN |

Реальный случай (ноябрь 2026), оба риска сработали одновременно:

- VDS `<IP-VDS>` перестал отвечать **с домашней линии полностью** —
  `curl http://IP/` давал `000 connect=0.000000` при живом `https://ya.ru/` → `302`;
  при этом с сотовой связи тот же сервер отвечал `301/200`. Классический бан IP;
- провайдер закрыл **входящие** на домашний статический IP: до роутера не доходил ни
  один пакет, поэтому MTProxy был недоступен снаружи, хотя внутри сети работал.

### Как проверять (на этих граблях мы и стояли)

1. **Не проверяйте порт изнутри LAN.** Запрос на свой внешний адрес из домашней сети
   уходит по hairpin-NAT и попадает в локальное правило, а не снаружи. Такой тест
   всегда «успешен» и не доказывает ничего.
2. **Не делайте вывод по одному адресу.** Успешное соединение с одним IP не говорит
   о доступности остальных: в том же инциденте из пяти дата-центров Telegram напрямую
   отвечал только один, и вывод «дата-центры доступны» оказался неверным.
3. Проверяйте с **внешних узлов** (несколько стран сразу):

```sh
curl -s -H 'Accept: application/json' \
  'https://check-host.net/check-tcp?host=IP:8443&max_nodes=4'
# затем, через ~15 с:
curl -s -H 'Accept: application/json' \
  'https://check-host.net/check-result/<request_id>'
```

4. На роутере смотрите, **доходят ли пакеты вообще**. Счётчик в `mangle` стоит до NAT
   и до фильтра, поэтому отвечает на вопрос «дошло ли до устройства»:

```sh
iptables -t mangle -I PREROUTING 1 -p tcp --dport 8443
# попытка подключения снаружи
iptables -t mangle -L PREROUTING -n -v | head -3
iptables -t mangle -D PREROUTING -p tcp --dport 8443
```

`0` пакетов → до устройства не дошло ничего: это провайдер или маршрутизация, и
правила роутера тут не помогут. Счётчик растёт → пакеты есть, причина локальная
(правила, порт, сам прокси).

### Что снижает риск

- **Второй IP** у хостинга: при бане меняется одна A-запись, сервис не переезжает;
- **короткий TTL** у DNS-записи (например, 300 с) — иначе клиенты до суток ходят на
  мёртвый адрес;
- **прослойка на отдельном IP** перед выходным сервером: если забанен VDS, клиент
  продолжает подключаться к прослойке, а выходной сервер меняется незаметно;
- **мониторинг** внешнего порта с внешней точки (периодическое TLS-рукопожатие), а не
  «пинг с роутера».

## Требования

- роутер Keenetic с Entware (нужен `opkg`);
- **что-то одно из двух**:
  - туннель WireGuard/AmneziaWG («Другое подключение» Keenetic, интерфейс вида
    `nwg0`), через который доступны серверы Telegram, плюс
    [Susanin.Keenetic](https://github.com/R17a/Susanin.Keenetic) **0.4.5+** с
    `proxy_uid=teleproxy` и `proxy_egress=nwg0` — он уводит трафик прокси в
    туннель по uid; либо
  - Xray из поставки Susanin.Keenetic с SOCKS-входом (`127.0.0.1:1080`) — тогда
    `nwg` не нужен, маршрут задаёт Xray из того же Susanin.Keenetic;
- публичный IP и проброс внешнего порта на роутер.

Без выхода в туннель прокси тоже запустится, но пойдёт напрямую — из РФ серверы
Telegram при этом недоступны.

## Мониторинг

Три инструмента в `tools/`, cron не нужен:

| Скрипт | Что делает |
|---|---|
| `tp-health.sh` | снимок раз в минуту: load, MemAvailable, прирост `RetransSegs`, чанки пула, соединения, прочитано/записано байт, число процессов xray. Пишет `/opt/var/log/tp-health.log` |
| `tp-health-report.sh N` | сводка за последние N часов: минимум памяти, срезы с `STALL`/`POOL`/`LOWMEM`, прирост ретрансмиссий, хвосты логов перезапусков |
| `tp-mon.sh` | ручной режим под конкретным тестом: срез раз в 1–2 с, флаги `POOL-FULL`, `CONN-LIMIT`, `NO-DATA`, `LRU+N`, `MEM-LOW` |

Флаги в `tp-health.log`: `STALL` — соединения есть, но за минуту не передано ни
байта (видео «встало»); `POOL` — пул буферов занят целиком; `LOWMEM` — меньше
10 МБ свободно; `RETRH` — прирост ретрансмиссий больше 100 за минуту; `XRAY2+` —
процессов Xray больше одного.

```sh
tp-health-report.sh 3     # что было за последние 3 часа
tp-health-report.sh 24    # за сутки
```

На роутере снимки запускает сторож `S95xray-guard` (см. Susanin.Keenetic), так
что отдельный планировщик не требуется.

## Релизы и их описания

В корне лежат `release-notes-v<версия>.md` — это текст, который CI подставляет
в GitHub Release (`body_path: release-notes-${{ github.ref_name }}.md`
в `.github/workflows/release.yml`). Поэтому имя файла обязано совпадать с тегом:
тег `v1.0.6` → `release-notes-v1.0.6.md`.

`CHANGELOG.md` здесь апстримовый (версии 4.x) и наши 1.0.x в него не пишем,
чтобы не ловить конфликты при мерже с upstream.

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

Откат версии — через тот же установщик, с указанием версии релиза с GitHub:

```sh
VERSION=1.0.5 sh install-keenetic.sh      # вернуться на 1.0.5
VERSION=1.0.6 sh install-keenetic.sh      # поставить 1.0.6
```

Скрипт скачивает `.ipk` из `releases/download/v<версия>/` и при повторной
установке той же версии делает `--force-reinstall`, поэтому init-скрипты и
пример конфига обновляются, а существующий `config.toml` не затирается.

Полное снятие службы (если прокси больше не нужен):

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