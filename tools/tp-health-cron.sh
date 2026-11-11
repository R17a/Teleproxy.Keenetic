#!/bin/sh
# tp-health-cron.sh — поставить снимок tp-health.sh в cron (раз в 2 минуты).
#
# Сам определяет, как устроен cron в Entware: спул /opt/etc/crontabs или
# общий /opt/etc/crontab. Идемпотентен: повторный запуск не дублирует строку.
#
#   sh tp-health-cron.sh          поставить
#   sh tp-health-cron.sh --off    убрать
#
# Проверка: pidof crond; tail -3 /opt/var/log/tp-health.log через пару минут.

BIN=/opt/sbin/tp-health.sh
MARK="tp-health.sh"

say() { echo "[tp-health] $*"; }

[ -x "$BIN" ] || { say "нет $BIN — сначала положите скрипт"; exit 1; }

remove_lines() { # remove_lines <file>
    [ -f "$1" ] || return 0
    grep -v "$MARK" "$1" > "$1.tmp" 2>/dev/null && mv -f "$1.tmp" "$1"
}

if [ "${1:-}" = "--off" ]; then
    remove_lines /opt/etc/crontabs/root
    remove_lines /opt/etc/crontab
    [ -x /opt/etc/init.d/S10cron ] && /opt/etc/init.d/S10cron restart >/dev/null 2>&1
    say "запись удалена"
    exit 0
fi

if [ -d /opt/etc/crontabs ]; then
    FILE=/opt/etc/crontabs/root
    LINE="*/2 * * * * $BIN >/dev/null 2>&1"
    touch "$FILE" 2>/dev/null || { say "нет прав на $FILE"; exit 1; }
    remove_lines "$FILE"
    echo "$LINE" >> "$FILE"
    say "cron: $FILE"
elif [ -f /opt/etc/crontab ]; then
    FILE=/opt/etc/crontab
    LINE="*/2 * * * * root $BIN >/dev/null 2>&1"
    remove_lines "$FILE"
    echo "$LINE" >> "$FILE"
    say "cron: $FILE"
else
    say "не нашёл ни /opt/etc/crontabs, ни /opt/etc/crontab"
    say "проверьте, установлен ли cron: opkg install cron"
    exit 1
fi

if [ -x /opt/etc/init.d/S10cron ]; then
    /opt/etc/init.d/S10cron restart >/dev/null 2>&1 || /opt/etc/init.d/S10cron start >/dev/null 2>&1
elif command -v crond >/dev/null 2>&1; then
    pidof crond >/dev/null 2>&1 || (crond >/dev/null 2>&1 &)
fi

sleep 1
if pidof crond >/dev/null 2>&1; then
    say "crond запущен (pid $(pidof crond))"
else
    say "ВНИМАНИЕ: crond не запущен — установите пакет cron: opkg install cron"
fi

say "готово. Через 2–3 минуты: tail -5 /opt/var/log/tp-health.log"
