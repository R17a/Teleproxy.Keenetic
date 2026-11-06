# Teleproxy.Keenetic v1.0.1

Исправление установки: пользователь `teleproxy` не создавался, из-за чего пакет
ставился, но служба сразу падала.

## Что исправлено

- **`postinst`: пользователь `teleproxy` создаётся надёжно.** Раньше вызов
  `adduser` на Keenetic завершался ошибкой, а `|| true` это скрывал: пользователя
  не появлялось, `chown root:teleproxy` тоже молча не срабатывал, и прокси падал с
  `change_user_group: can't find the user teleproxy`. Теперь postinst пробует три
  варианта (`adduser -S -D -H`, вариант с `-h /opt/var/empty`, `useradd -r -M`),
  проверяет `id -u teleproxy` и только потом выставляет права `root:teleproxy 640`.
  Если пользователя создать не удалось — пакет **не молчит**, а пишет
  предупреждение и ставит `chmod 644`, чтобы прокси мог прочитать конфиг.

- **`install-keenetic.sh` проверяет результат установки**: после `opkg install`
  убеждается, что пользователь есть (иначе создаёт), выставляет права на конфиг и
  печатает `teleproxy: uid=…`.

- **`init/S99teleproxy`: добавлена команда `restart`** (раньше в usage её не было,
  приходилось делать `stop` + `start`).

- **Документация**: как определить архитектуру (`opkg print-architecture`) и
  самоподставляющийся сниппет для ручной установки; конфиг-пример берётся из
  `packaging/config.toml.example`.

## Установка / обновление

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
```

Или пакетом:

```sh
opkg install --force-reinstall /opt/tmp/teleproxy-keenetic_1.0.1_mipsel-3.4.ipk
```

Проверка после установки:

```sh
id teleproxy
ls -l /opt/etc/teleproxy/config.toml      # ожидаем root:teleproxy, -rw-r-----
/opt/etc/init.d/S99teleproxy restart
/opt/etc/init.d/S99teleproxy status
```

## Если пользователь всё же не создался

```sh
adduser -S -D -H -s /sbin/nologin teleproxy
chown root:teleproxy /opt/etc/teleproxy/config.toml
chmod 640 /opt/etc/teleproxy/config.toml
```

Либо поставьте в `/opt/etc/teleproxy/config.toml` `user = "root"`.

## Совместимость

Без изменений: Keenetic + Entware, Susanin.Keenetic 0.4.5 (`proxy_uid` /
`proxy_egress=nwg0`) для выхода в туннель.
