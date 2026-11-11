#!/bin/sh
# tp-flash-check.sh — проверка носителя /opt (ext4 на USB-флешке).
#
# Запускается раз в сутки в 03:00 из S95xray-guard, вручную — в любой момент:
#   tp-flash-check.sh
#
# Что проверяет:
#   1) запись реально работает (touch/rm в /opt);
#   2) появились ли новые ошибки ввода-вывода в dmesg с прошлого запуска
#      (EXT4-fs error, critical target error, Remounting filesystem read-only,
#      I/O error);
#   3) состояние суперблока ext4 (Filesystem state, FS Error count) — только чтение;
#   4) свободное место.
#
# Пишет /opt/var/log/flash-health.log. При проблеме — строку ALERT и файл
# /opt/var/run/flash-alert (его наличие = носитель требует внимания).

LOG=/opt/var/log/flash-health.log
STATE=/opt/var/run/flash-check.state
ALERT=/opt/var/run/flash-alert

mkdir -p "${LOG%/*}" "${STATE%/*}" 2>/dev/null || true

say() {
    _line="$(date '+%F %T') $*"
    echo "$_line"
    echo "$_line" >> "$LOG" 2>/dev/null || true
}

alert=0

# 1. запись
if touch /opt/.fsprobe 2>/dev/null; then
    rm -f /opt/.fsprobe
    rw=rw
else
    rw=RO
    alert=1
fi

# 2. новые ошибки ядра с прошлого запуска
cur=$(dmesg 2>/dev/null | grep -c -E 'EXT4-fs error|critical target error|Remounting filesystem read-only|I/O error')
prev=$(cat "$STATE" 2>/dev/null || echo 0)
[ -n "$prev" ] || prev=0
# после перезагрузки dmesg обнуляется — счётчик может уменьшиться
[ "$cur" -lt "$prev" ] && prev=0
new=$((cur - prev))
[ "$new" -gt 0 ] && alert=1

# 3. состояние ФС: сначала пробуем суперблок (e2fsprogs), если их нет —
#    счётчик ошибок из ядра (есть на современных ядрах Keenetic).
sup=$(dumpe2fs -h /dev/sda1 2>/dev/null | grep -E 'Filesystem state|FS Error count' | tr '\n' ' ')
if [ -z "$sup" ]; then
    sup=$(tune2fs -l /dev/sda1 2>/dev/null | grep -E 'Filesystem state|FS Error count' | tr '\n' ' ')
fi
if [ -z "$sup" ] && [ -r /sys/fs/ext4/sda1/errors_count ]; then
    _ec=$(cat /sys/fs/ext4/sda1/errors_count 2>/dev/null)
    sup="fs_errors_count=${_ec:-?}"
    [ -n "$_ec" ] && [ "$_ec" -gt 0 ] 2>/dev/null && alert=1
fi
[ -n "$sup" ] || sup="superblock: n/a"

# 4. место
use=$(df -h /opt 2>/dev/null | awk 'NR==2 { print $5 " занято, " $4 " свободно" }')

say "rw=$rw new_io_err=$new total_io_err=$cur space=${use:-n/a} ${sup}"

if [ "$alert" = 1 ]; then
    say "ALERT: носитель требует внимания (rw=$rw, новых ошибок: $new). Остановите службы и прогнать e2fsck -f -y /dev/sda1"
    echo "$(date '+%F %T') ALERT rw=$rw new=$new" >> "$ALERT" 2>/dev/null || true
    # не даём файлу расти бесконечно
    if [ -f "$ALERT" ] && [ "$(wc -l < "$ALERT" 2>/dev/null || echo 0)" -gt 200 ]; then
        tail -n 100 "$ALERT" > "$ALERT.tmp" 2>/dev/null && mv -f "$ALERT.tmp" "$ALERT"
    fi
fi

echo "$cur" > "$STATE" 2>/dev/null || true
exit 0
