# Teleproxy.Keenetic 1.0.7

Дата: 2026-11-12

## Что в релизе

Релиз документации и поставляемого примера конфига. Код прокси относительно
1.0.6 не менялся — бинарники и поведение те же, пакет пересобран, чтобы новый
пример конфига попал в `.ipk`.

- Из репозитория и примеров убраны реальные адреса и домены: адрес VDS, входы
  `px1`/`px2` и WAN-адрес заменены на `vds.example.com`, `px1.example.com`,
  `px2.example.com` и документационный `203.0.113.10`.
- Во всех конфигах-примерах оставлен один демонстрационный секрет:
  `key = "636c6f7564666c6172652e636f6d"` (это `hex("cloudflare.com")`),
  `label = "default"`. Живые ключи и метки пользователей в поставку не входят.
- Добавлена документация `deploy/vds/` — развёртывание мультипользовательского
  варианта на VDS (systemd-unit и README).
- `tools/make-link.sh`: пример вызова обновлён под тот же демо-ключ.

## Установка

```sh
wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
# или конкретная версия:
VERSION=1.0.7 sh install-keenetic.sh
```

## Проверка

```sh
/opt/etc/init.d/S99teleproxy status
opkg list-installed | grep teleproxy
```

## Важно про секрет

На чистой установке `postinst` копирует пример конфига как есть, поэтому в
`/opt/etc/teleproxy/config.toml` окажется демонстрационный ключ. Замените его на
случайный (32 hex-символа) и перезапустите службу:

```sh
KEY=$(/opt/sbin/teleproxy generate-secret)
sed -i "s|^key = .*|key = \"$KEY\"|" /opt/etc/teleproxy/config.toml
/opt/etc/init.d/S99teleproxy restart
```

При обновлении поверх существующей установки конфиг не затирается — ключи
остаются прежними.

## Откат

```sh
VERSION=1.0.6 sh install-keenetic.sh
```
