#!/bin/sh
# tp-postmortem.sh — разбор зависания по логам после перезагрузки.
#
#   tp-postmortem.sh        последние 90 срезов до последнего «разрыва» в логе
#   tp-postmortem.sh 200    больше истории
#
# Что делает:
#   1) находит в /opt/var/log/tp-health.log последний разрыв (пауза > 3 минут —
#      это и есть момент зависания/перезагрузки) и печатает срезы ПЕРЕД ним;
#   2) считает по этому окну: сколько было STALL, POOL, LOWMEM, RETRH;
#   3) показывает хвосты событийных логов: перезапуски teleproxy, лишние Xray,
#      SSH-туннель, Susanin, проверка носителя;
#   4) печатает текущее состояние (uptime, память, процессы, порты).
#
# Ничего не меняет, только читает.

HEALTH=${HEALTH:-/opt/var/log/tp-health.log}
N=${1:-90}

echo "=== tp-postmortem: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo

if [ -f "$HEALTH" ]; then
    echo "--- срезы перед последним разрывом ---"
    awk -v n="$N" '
    function sec(t){ split(t,a,":"); return a[1]*3600 + a[2]*60 + a[3] }
    /avail=/ {
        c++
        line[c] = $0
        t = sec($2)
        if (prev > 0 && t - prev > 180) { gap = c }   # пауза > 3 мин
        prev = t
    }
    END {
        if (c == 0) { print "нет данных"; exit }
        if (gap) printf "# разрыв в логе после строки выше (около %s)\n", line[gap-1]
        start = gap ? gap : (c > n ? c - n : 1)
        for (i = start; i <= c; i++) print line[i]
    }' "$HEALTH"

    echo
    echo "--- итоги по последним ${N} срезам ---"
    tail -n "$N" "$HEALTH" | awk '
    /avail=/ {
        n++
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^avail=/)   { a = $i; sub("avail=", "", a); sub("M", "", a) }
            if ($i ~ /^chunks=/)  { ch = $i; sub("chunks=", "", ch) }
        }
        if (minmem == "" || a + 0 < minmem + 0) { minmem = a; minwhen = $1 " " $2 }
        if ($0 ~ /STALL/)  stall++
        if ($0 ~ /POOL/)   pool++
        if ($0 ~ /LOWMEM/) lowmem++
        if ($0 ~ /RETRH/)  retrh++
        if ($0 ~ /XRAY[2-9]/) x2++
    }
    END {
        printf "срезов: %d, минимум памяти: %s МБ (%s)\n", n, minmem, minwhen
        printf "STALL: %d, POOL: %d, LOWMEM: %d, RETRH: %d, xray>1: %d\n", stall, pool, lowmem, retrh, x2
    }'
else
    echo "нет $HEALTH"
fi

echo
echo "--- перезапуски teleproxy (последние 10) ---"
[ -f /opt/var/log/teleproxy-fw.log ] && tail -n 20 /opt/var/log/teleproxy-fw.log || echo "нет лога"

echo
echo "--- лишние Xray (последние 5) ---"
[ -f /opt/var/log/xray-guard.log ] && tail -n 5 /opt/var/log/xray-guard.log || echo "нет лога"

echo
echo "--- SSH-туннель (последние 10) ---"
[ -f /opt/var/log/ssh-tunnel.log ] && tail -n 10 /opt/var/log/ssh-tunnel.log || echo "нет лога"

echo
echo "--- Susanin: Xray/tproxy (последние 10) ---"
[ -f /opt/susanin/var/susanin.log ] && grep -E 'Xray|tproxy|error|ERR' /opt/susanin/var/susanin.log | tail -n 10 || echo "нет лога"

echo
echo "--- проверка носителя ---"
if [ -f /opt/var/log/flash-health.log ]; then
    tail -n 3 /opt/var/log/flash-health.log
    [ -f /opt/var/run/flash-alert ] && echo "!!! ЕСТЬ ALERT: $(tail -n 2 /opt/var/run/flash-alert)"
else
    echo "нет лога (tp-flash-check.sh ещё не запускался)"
fi

echo
echo "--- сейчас ---"
echo "uptime: $(uptime)"
echo "память: $(awk '/MemAvailable/ {printf "%d МБ доступно", $2/1024}' /proc/meminfo)"
echo "load:   $(cut -d' ' -f1-3 /proc/loadavg)"
echo "xray:   $(pidof xray 2>/dev/null | wc -w) процесс(ов)"
echo "teleproxy: $(pidof teleproxy 2>/dev/null || echo нет)"
if netstat -ltn 2>/dev/null | grep -q '127.0.0.1:1081'; then
    echo "ssh-туннель: LISTEN 1081"
else
    echo "ssh-туннель: НЕ слушает"
fi
echo "порты: $(netstat -ltn 2>/dev/null | grep -cE ':(8443|12345|1081)')"
echo "сокетов к 1081: $(netstat -tan 2>/dev/null | grep -c '127.0.0.1:1081')"
