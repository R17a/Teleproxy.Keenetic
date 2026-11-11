#!/bin/sh
# tp-mon.sh — мониторинг Teleproxy.Keenetic под нагрузкой.
#
# Пишет срез статистики раз в INTERVAL секунд, помечает аномалии и в конце
# печатает сводку. Нужен, чтобы поймать момент, когда видео «задумывается»,
# и понять причину: пул буферов, канал, лимит соединений или DC.
#
#   sh tp-mon.sh                     # до Ctrl-C
#   INTERVAL=1 DUR=600 sh tp-mon.sh  # 10 минут, срез раз в секунду
#   STATS=/tmp/stats.txt sh tp-mon.sh   # разбор сохранённого среза (для теста)
#
# Лог: /opt/var/log/tp-mon.log (CSV + пометки).

STATS=${STATS:-http://127.0.0.1:8899/stats}
INTERVAL=${INTERVAL:-2}
DUR=${DUR:-0}
LOG=${LOG:-/opt/var/log/tp-mon.log}
MAXSPEC=${MAXSPEC:-32}
CHUNK=2097088

command -v awk >/dev/null 2>&1 || { echo "нужен awk" >&2; exit 1; }

get_stats() {
    case "$STATS" in
        /*) cat "$STATS" 2>/dev/null ;;
        *)  curl -s -m 3 "$STATS" 2>/dev/null ;;
    esac
}

now() { date '+%H:%M:%S'; }

mkdir -p "${LOG%/*}" 2>/dev/null || true
printf '# %s start interval=%ss stats=%s\n' "$(date '+%F %T')" "$INTERVAL" "$STATS" | tee -a "$LOG"
printf '# %-8s %5s %5s %5s %6s %5s %8s %8s %4s %4s  %s\n' time alloc% chunks conns spec lru readB/s writeB/s stall memM flags | tee -a "$LOG"

prev_r=0; prev_w=0; have_prev=0
stall=0; n=0; max_alloc=0; max_conns=0; max_spec=0; min_mem=0; lru_total=0; fulls=0; stalls=0; end=$(( $(date +%s) + DUR ))

while :; do
    st=$(get_stats)
    if [ -z "$st" ]; then
        echo "$(now)  статистика недоступна ($STATS)"
        sleep "$INTERVAL"
        continue
    fi

    vals=$(printf '%s\n' "$st" | awk '
        /^allocated_buffer_bytes[[:space:]]/   { a = $2 }
        /^allocated_buffer_chunks[[:space:]]/  { ac = $2 }
        /^max_buffer_chunks[[:space:]]/        { mc = $2 }
        /^active_connections[[:space:]]/       { c = $2 }
        /^active_special_connections[[:space:]]/ { sp = $2 }
        /^max_special_connections[[:space:]]/  { msp = $2 }
        /^connections_failed_lru[[:space:]]/   { l = $2 }
        /^connections_failed_flood[[:space:]]/ { f = $2 }
        /^tcp_readv_bytes[[:space:]]/          { r = $2 }
        /^tcp_writev_bytes[[:space:]]/         { w = $2 }
        /^socks5_connects_failed[[:space:]]/   { sf = $2 }
        END {
            if (a == "") { exit 1 }
            printf "%d %d %d %d %d %d %d %d %d %d %d\n", a, ac, mc, c, sp+0, msp+0, l, f, r, w, sf
        }')
    [ -n "$vals" ] || { echo "$(now)  не разобрал статистику"; sleep "$INTERVAL"; continue; }

    set -- $vals
    alloc=$1; achunks=$2; mchunks=$3; conns=$4; spec=$5; mspec=$6; lru=$7; flood=$8; rd=$9; wr=${10}; sfail=${11}

    # проценты заполнения пула по байтам (чанк = 2 МБ)
    if [ "$mchunks" -gt 0 ] 2>/dev/null; then
        pct=$(( alloc * 100 / (mchunks * CHUNK) ))
    else
        pct=0
    fi

    if [ "$have_prev" = 1 ]; then
        dr=$(( rd - prev_r )); dw=$(( wr - prev_w ))
    else
        dr=0; dw=0; have_prev=1
    fi
    prev_r=$rd; prev_w=$wr

    memavail=$(awk '/^MemAvailable:/ { printf "%d", $2 / 1024 }' /proc/meminfo 2>/dev/null)
    [ -n "$memavail" ] || memavail=0

    flags=""
    [ "$achunks" -ge "$mchunks" ] && [ "$mchunks" -gt 0 ] && { flags="$flags POOL-FULL"; fulls=$((fulls + 1)); }
    [ "$mspec" -gt 0 ] && [ "$spec" -ge "$mspec" ] && flags="$flags CONN-LIMIT"
    [ "$memavail" -gt 0 ] && [ "$memavail" -lt "${MEMLOW:-6}" ] && flags="$flags MEM-LOW"
    if [ "$dr" -le 0 ] && [ "$dw" -le 0 ] && [ "$conns" -gt 0 ]; then
        stall=$((stall + 1))
        [ "$stall" -ge 3 ] && { flags="$flags NO-DATA"; }
    else
        stall=0
    fi
    [ "$stall" -eq 3 ] && stalls=$((stalls + 1))
    [ "$lru" -gt "$lru_total" ] && flags="$flags LRU+$((lru - lru_total))"
    lru_total=$lru
    [ "$flood" -gt 0 ] && flags="$flags FLOOD+"

    [ "$alloc" -gt "$max_alloc" ] && max_alloc=$alloc
    [ "$conns" -gt "$max_conns" ] && max_conns=$conns
    [ "$spec" -gt "$max_spec" ] && max_spec=$spec
    [ "$memavail" -gt 0 ] && { [ "$min_mem" -eq 0 ] || [ "$memavail" -lt "$min_mem" ]; } && min_mem=$memavail

    printf '%-10s %5s %5s %5s %5s %5s %8s %8s %4s %4s  %s\n' \
        "$(now)" "$pct" "$achunks/$mchunks" "$conns" "$spec/$mspec" "$lru" "$dr" "$dw" "$stall" "$memavail" "$flags" | tee -a "$LOG"

    n=$((n + 1))
    if [ "$DUR" -gt 0 ] && [ "$(date +%s)" -ge "$end" ]; then
        break
    fi
    sleep "$INTERVAL"
done

echo
echo "== сводка за $n срезов =="
echo "пул: пик $max_alloc байт ($(( max_alloc * 100 / (mchunks * CHUNK) ))% от $(( mchunks * CHUNK )))"
echo "соединений: пик $max_conns (клиентских $max_spec из $mspec)"
echo "память: минимум $min_mem МБ available"
echo "эвикций LRU: $lru_total, flood: $flood"
echo "срезов с полным пулом: $fulls, с простоем трафика: $stalls"
echo
echo "Если много POOL-FULL и LRU+ — пул мал; если NO-DATA без POOL-FULL —"
echo "смотрите канал/Xray в тот же момент:"
echo "  curl -s -o /dev/null -w 'socks %{speed_download} B/s ttfb=%{time_starttransfer}\\n' \\"
echo "    -x socks5h://127.0.0.1:1080 --max-time 20 https://speed.cloudflare.com/__down?bytes=5000000"
echo "Если CONN-LIMIT — упёрлись в клиентский лимит (поднимать max_connections)."
echo "Если MEM-LOW — памяти мало, пул поднимать нельзя, резать connections."
