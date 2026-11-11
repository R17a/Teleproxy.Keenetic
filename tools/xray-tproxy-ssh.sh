#!/bin/sh
# xray-tproxy-ssh.sh — перевести TCP-трафик Xray в SSH-SOCKS (127.0.0.1:1081).
#
# Зачем: VLESS/REALITY на MT7621 упирается в ~12 Мбит/с (шифрование в
# userspace). SSH-туннель на том же железе даёт ~28 Мбит/с (замер 2026-11-09).
# После этой правки Xray перестаёт шифровать: он принимает tproxy-трафик и
# релеит TCP в локальный SSH-SOCKS. UDP остаётся на прежнем outbound
# (VLESS 8443), потому что SOCKS5 через SSH умеет только TCP.
#
#   xray-tproxy-ssh.sh apply    применить (с бэкапом)
#   xray-tproxy-ssh.sh revert   вернуть бэкап
#   xray-tproxy-ssh.sh status   показать, что сейчас в конфиге
#
# Идемпотентно: повторный apply не добавляет вторую копию правила.
# Бэкап: /opt/susanin/etc/xray-tproxy.json.bak-pre-ssh

CFG=${XRAY_CFG:-/opt/susanin/etc/xray-tproxy.json}
BAK=${CFG}.bak-pre-ssh
TAG=ssh-socks
PORT=1081
INIT=/opt/etc/init.d/S94susanin

say() { echo "[xray-ssh] $*"; }

restart_xray() {
    # Важно: S94 перезапускает агента, но уже живой Xray не трогает —
    # конфиг остаётся старым. Поэтому гасим процесс и поднимаем заново.
    _p=$(pidof xray 2>/dev/null)
    if [ -n "$_p" ]; then
        kill "$_p" 2>/dev/null
        sleep 2
    fi
    if [ -x "$INIT" ]; then
        "$INIT" restart >/dev/null 2>&1 || true
    fi
    /opt/etc/init.d/S93xray-tproxy start >/dev/null 2>&1 || true
    sleep 3
    if netstat -ltn 2>/dev/null | grep -q ':12345'; then
        say "Xray перезапущен и слушает 12345 (pid $(pidof xray 2>/dev/null))"
    else
        say "ВНИМАНИЕ: 12345 не слушается — смотрите /opt/susanin/var/susanin.log"
    fi
}

apply() {
    [ -f "$CFG" ] || { say "нет $CFG"; exit 1; }
    command -v jq >/dev/null 2>&1 || { say "нужен jq: opkg install jq"; exit 1; }

    [ -f "$BAK" ] || cp -a "$CFG" "$BAK"

    # 1. outbound ssh-socks (если ещё нет)
    if jq -e --arg t "$TAG" '.outbounds[] | select(.tag == $t)' "$CFG" >/dev/null 2>&1; then
        say "outbound $TAG уже есть"
    else
        jq --arg t "$TAG" --argjson p "$PORT" \
           '.outbounds += [{"tag": $t, "protocol": "socks",
             "settings": {"servers": [{"address": "127.0.0.1", "port": $p}]}}]' \
           "$CFG" > "$CFG.new" && mv -f "$CFG.new" "$CFG" || { say "jq: не добавил outbound"; exit 1; }
        say "добавлен outbound $TAG -> 127.0.0.1:$PORT"
    fi

    # 2. первое правило: весь TCP в ssh-socks; старое такое же правило убираем
    jq --arg t "$TAG" '
        .routing.rules = ([{"type": "field", "network": "tcp", "outboundTag": $t}]
                          + ((.routing.rules // []) | map(select((.outboundTag // "") != $t))))
    ' "$CFG" > "$CFG.new" && mv -f "$CFG.new" "$CFG" || { say "jq: не поправил routing"; exit 1; }

    jq empty "$CFG" 2>/dev/null || { say "JSON битый — откатываю"; cp -a "$BAK" "$CFG"; exit 1; }
    say "routing: первый rule = TCP -> $TAG (UDP идёт прежним путём)"
    restart_xray
}

revert() {
    if [ -f "$BAK" ]; then
        cp -a "$BAK" "$CFG"
        say "восстановлен $BAK"
        restart_xray
    else
        say "бэкапа нет — нечего откатывать"
    fi
}

status() {
    echo "outbound'ы:"
    jq -r '.outbounds[] | "  " + (.tag // "?") + "  (" + (.protocol // "?") + ")"' "$CFG" 2>/dev/null
    echo "правила routing:"
    jq -r '.routing.rules[]? | "  " + ((.network // "tcp+udp")) + " -> " + (.outboundTag // "?")' "$CFG" 2>/dev/null
    echo -n "туннель 1081: "
    netstat -ltn 2>/dev/null | grep -q '127.0.0.1:1081' && echo LISTEN || echo "НЕ слушает"
}

case "${1:-status}" in
    apply) apply ;;
    revert) revert ;;
    status) status ;;
    *) echo "usage: $0 {apply|revert|status}" >&2; exit 1 ;;
esac
