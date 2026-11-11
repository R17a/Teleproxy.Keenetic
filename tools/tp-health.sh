#!/bin/sh
# tp-health.sh — снимок здоровья роутера и teleproxy.
#
#   tp-health.sh               одна строка и выход (вызывается сторожем)
#   tp-health.sh -n 60 -i 30   цикл: 60 срезов раз в 30 с (ручной режим)
#
# Пишет в /opt/var/log/tp-health.log. Строка:
#   время load=[..] avail=<МБ> retr=<всего>(+<прирост>) chunks=<зан>/<всего>
#   conns=<активных> rd=<байт/с> wr=<байт/с> xray=<процессов> [флаги]
#
# Флаги:
#   STALL   — соединения есть, но за интервал не прочитано и не записано ни байта
#             (это и есть «видео подвисло»);
#   POOL    — пул буферов занят целиком (chunks == max);
#   LOWMEM  — MemAvailable ниже 10 МБ;
#   RETRH   — прирост RetransSegs больше 100 за интервал (потери в канале);
#   XRAY2+  — процессов xray больше одного.
#
# Состояние для дельт — /opt/var/run/tp-health.state.

N=1
I=60
LOG=${LOG:-/opt/var/log/tp-health.log}
STATE=${STATE:-/opt/var/run/tp-health.state}

while [ $# -gt 0 ]; do
    case "$1" in
        -n) N=$2; shift 2 ;;
        -i) I=$2; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) shift ;;
    esac
done

snapshot() {
    _l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    _a=$(awk '/MemAvailable/ { printf "%d", $2 / 1024 }' /proc/meminfo 2>/dev/null)
    _r=$(awk '/^Tcp:/ { n++; if (n == 2) { print $12; exit } }' /proc/net/snmp 2>/dev/null)
    _x=$(pidof xray 2>/dev/null | wc -w)

    _s=$(curl -s -m 2 http://127.0.0.1:8899/stats 2>/dev/null)
    _ch=$(printf '%s\n' "$_s" | awk '/^allocated_buffer_chunks/ { print $2; exit }')
    _mc=$(printf '%s\n' "$_s" | awk '/^max_buffer_chunks/ { print $2; exit }')
    _ac=$(printf '%s\n' "$_s" | awk '/^active_connections/ { print $2; exit }')
    _rd=$(printf '%s\n' "$_s" | awk '/^tcp_readv_bytes/ { print $2; exit }')
    _wr=$(printf '%s\n' "$_s" | awk '/^tcp_writev_bytes/ { print $2; exit }')

    # предыдущее состояние
    _pr=; _pw=; _pt=
    if [ -f "$STATE" ]; then
        read _pr _pw _pt < "$STATE" 2>/dev/null || true
    fi

    # дельты (если состояние есть и счётчики не уменьшились)
    _dr=0; _dw=0; _dt=0
    if [ -n "${_rd:-}" ] && [ -n "${_pr:-}" ] && [ "$_rd" -ge "$_pr" ] 2>/dev/null; then
        _dr=$((_rd - _pr))
    fi
    if [ -n "${_wr:-}" ] && [ -n "${_pw:-}" ] && [ "$_wr" -ge "$_pw" ] 2>/dev/null; then
        _dw=$((_wr - _pw))
    fi
    if [ -n "${_r:-}" ] && [ -n "${_pt:-}" ] && [ "$_r" -ge "$_pt" ] 2>/dev/null; then
        _dt=$((_r - _pt))
    fi

    _flags=""
    [ -n "${_ch:-}" ] && [ -n "${_mc:-}" ] && [ "$_mc" -gt 0 ] && [ "$_ch" -ge "$_mc" ] && _flags="$_flags POOL"
    [ -n "${_a:-}" ] && [ "$_a" -lt 10 ] && _flags="$_flags LOWMEM"
    [ -n "${_ac:-}" ] && [ "$_ac" -gt 0 ] && [ "$_dr" -eq 0 ] && [ "$_dw" -eq 0 ] && _flags="$_flags STALL"
    [ "$_dt" -gt 100 ] && _flags="$_flags RETRH"
    [ "${_x:-0}" -gt 1 ] && _flags="$_flags XRAY${_x}"

    printf '%s load=[%s] avail=%sM retr=%s(+%s) chunks=%s/%s conns=%s rd=%s wr=%s xray=%s%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${_l:-?}" "${_a:-0}" "${_r:-0}" "$_dt" \
        "${_ch:-?}" "${_mc:-?}" "${_ac:-?}" "$_dr" "$_dw" "${_x:-0}" "$_flags"

    mkdir -p "${STATE%/*}" 2>/dev/null || true
    printf '%s %s %s\n' "${_rd:-0}" "${_wr:-0}" "${_r:-0}" > "$STATE" 2>/dev/null || true
}

i=0
while [ "$i" -lt "$N" ]; do
    line=$(snapshot)
    echo "$line"
    if [ -n "$LOG" ]; then
        echo "$line" >> "$LOG" 2>/dev/null || true
    fi
    i=$((i + 1))
    [ "$i" -lt "$N" ] && sleep "$I"
done

# ротация: держим до 5 суток при срезе раз в минуту
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 10000 ]; then
    tail -n 5000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

exit 0
