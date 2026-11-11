#!/bin/sh
# tp-health-report.sh — сводка по логу здоровья за последние N часов.
#
#   tp-health-report.sh          за 2 часа
#   tp-health-report.sh 8        за 8 часов
#   tp-health-report.sh 2 /path/to/tp-health.log
#
# Читает /opt/var/log/tp-health.log (срез раз в минуту) и печатает:
#   * минимум MemAvailable и когда это было;
#   * сколько раз пул был занят целиком (POOL);
#   * сколько срезов с простоем трафика (STALL) и время первых из них;
#   * суммарный прирост ретрансмиссий за окно;
#   * срезы, где процессов xray было больше одного.
# Плюс хвосты событийных логов: перезапуски teleproxy и убийства лишних Xray.

HOURS=${1:-2}
LOG=${2:-/opt/var/log/tp-health.log}

[ -f "$LOG" ] || { echo "нет $LOG"; exit 1; }

LINES=$((HOURS * 60))
echo "=== tp-health-report: последние ${HOURS} ч (до $LINES срезов) из $LOG ==="
echo

tail -n "$LINES" "$LOG" | awk '
/avail=/ {
    n++
    ts = $1 " " $2
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^avail=/)  { a = $i; sub("avail=", "", a); sub("M", "", a) }
        if ($i ~ /^chunks=/) { c = $i; sub("chunks=", "", c) }
        if ($i ~ /^conns=/)  { k = $i; sub("conns=", "", k); if (k + 0 > maxconn + 0) maxconn = k }
        if ($i ~ /^rd=/)     { r = $i; sub("rd=", "", r); rdsum += r; rdn++ }
        if ($i ~ /^wr=/)     { w = $i; sub("wr=", "", w); wrsum += w }
        if ($i ~ /^rdpc=/)   { }
    }
    if (minavail == "" || a + 0 < minavail + 0) { minavail = a; minwhen = ts }
    if (maxchunks == "" || (c + 0) > (maxchunks + 0)) { maxchunks = c }
    if ($0 ~ /POOL/)   pool++
    if ($0 ~ /STALL/)  { stall++; if (stall <= 12) stalls = stalls "    " ts "\n" }
    if ($0 ~ /LOWMEM/) lowmem++
    if ($0 ~ /XRAY[2-9]/) x2++
}
END {
    printf "срезов:                  %d\n", n
    printf "MemAvailable минимум:    %s МБ (%s)\n", minavail, minwhen
    printf "максимум чанков пула:    %s\n", maxchunks
    printf "пик соединений teleproxy: %s\n", maxconn
    if (rdn > 0) {
        # rd/wr в логе — байты за интервал 60 с
        printf "средняя скорость:        %.1f КБ/с (%.2f Мбит/с) принято, %.1f КБ/с (%.2f Мбит/с) отдано\n", \
            rdsum/rdn/60/1024, rdsum/rdn*8/60/1000000, wrsum/rdn/60/1024, wrsum/rdn*8/60/1000000
    }
    printf "срезов с POOL:           %d\n", pool
    printf "срезов с STALL:          %d\n", stall
    if (stalls != "") printf "%s", stalls
    printf "срезов с памятью <10 МБ: %d\n", lowmem
    printf "срезов с xray > 1:       %d\n", x2
}
'

echo
echo "--- ретрансмиссии за окно ---"
tail -n "$LINES" "$LOG" | awk '
/retr=/ {
    for (i = 1; i <= NF; i++) if ($i ~ /^retr=/) { v = $i; sub("retr=", "", v); sub(/\(.*/, "", v) }
    if (first == "") { first = v; prev = v; next }
    # счётчик обнуляется при перезагрузке — отрицательный шаг пропускаем
    if (v >= prev) { sum += v - prev }
    prev = v
    last = v
}
END {
    if (first != "") printf "RetransSegs: %s -> %s, суммарный прирост за окно %d\n", first, last, sum
}
'

echo
echo "--- перезапуски teleproxy ---"
if [ -f /opt/var/log/teleproxy-fw.log ]; then
    tail -n 20 /opt/var/log/teleproxy-fw.log | grep -E 'залип|перезапуск|восстановлены' || echo "нет событий"
else
    echo "нет лога"
fi

echo
echo "--- лишние Xray ---"
if [ -f /opt/var/log/xray-guard.log ]; then
    tail -n 20 /opt/var/log/xray-guard.log
else
    echo "нет лога"
fi

echo
echo "--- Susanin: Xray/tproxy ---"
if [ -f /opt/susanin/var/susanin.log ]; then
    grep -E 'Xray|tproxy' /opt/susanin/var/susanin.log | tail -n 15
else
    echo "нет лога"
fi

exit 0
