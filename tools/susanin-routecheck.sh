#!/bin/sh
# susanin-routecheck.sh — куда пойдёт домен: напрямую или в туннель.
#
#   susanin-routecheck.sh vkvideo.ru instagram.com
#
# Для каждого домена резолвит адреса и проверяет их во всех наборах Susanin:
#   susanin_never, susanin_direct  -> напрямую (исключения)
#   susanin_ok_tcp, susanin_ok_udp, susanin_ok_net -> через туннель
#   ни в одном -> попадёт под правило по умолчанию (обычно напрямую)
#
# Ничего не меняет, только читает ipset и DNS.

SETS_DIRECT="susanin_never susanin_direct"
SETS_VPN="susanin_ok_tcp susanin_ok_udp susanin_ok_net"

say() { echo "$*"; }

test_set() { ipset test "$1" "$2" >/dev/null 2>&1; }

total=0
direct_n=0
vpn_n=0
none_n=0

for d in "$@"; do
    say "== $d"
    # берём адреса только из блока ответа (после "Name:"), иначе в выборку
    # попадает "Address 1: 127.0.0.1" из блока Server:
    ips=$(nslookup "$d" 2>/dev/null | awk '
        /^Name:/ { inans = 1; next }
        inans && /^Address [0-9]+:/ { print $3 }')
    if [ -z "$ips" ]; then
        say "   не разрешился (DNS?)"
        continue
    fi
    for ip in $ips; do
        total=$((total + 1))
        case "$ip" in
            *:*) fam=inet6 ;;
            *)   fam=inet4 ;;
        esac
        in_direct=""
        in_vpn=""
        for s in $SETS_DIRECT; do test_set "$s" "$ip" && in_direct="$in_direct $s"; done
        for s in $SETS_VPN;    do test_set "$s" "$ip" && in_vpn="$in_vpn $s"; done

        if [ -n "$in_direct" ]; then
            direct_n=$((direct_n + 1))
            say "   $ip [$fam] -> НАПРЯМУЮ ($in_direct )"
        elif [ -n "$in_vpn" ]; then
            vpn_n=$((vpn_n + 1))
            say "   $ip [$fam] -> ЧЕРЕЗ VPN ($in_vpn )"
        else
            none_n=$((none_n + 1))
            say "   $ip [$fam] -> нет в наборах (правило по умолчанию)"
        fi
    done
done

say ""
say "итого адресов: $total, напрямую: $direct_n, через VPN: $vpn_n, без совпадений: $none_n"
