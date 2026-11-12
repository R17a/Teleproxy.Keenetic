#!/bin/sh
# make-link.sh — собрать ссылку подключения к MTProxy (fake-TLS, режим EE).
#
#   sh tools/make-link.sh <32-hex-secret> <host> <port> [camouflage-domain]
#
# Пример (ключ = hex("cloudflare.com") — демонстрационный):
#   sh tools/make-link.sh 636c6f7564666c6172652e636f6d 203.0.113.10 8443
#   -> tg://proxy?server=203.0.113.10&port=8443&secret=ee636c...6d
#
# Ссылка собирается по формуле Telegram: "ee" + secret + hex(domain).
set -eu

SECRET=${1:-}
HOST=${2:-}
PORT=${3:-}
DOMAIN=${4:-cloudflare.com}

[ -n "$SECRET" ] && [ -n "$HOST" ] && [ -n "$PORT" ] || {
    echo "usage: $0 <32-hex-secret> <host> <port> [domain]" >&2
    exit 2
}

case "$SECRET" in
    *[!0-9a-fA-F]*) echo "secret должен быть hex" >&2; exit 2 ;;
esac
[ "${#SECRET}" -eq 32 ] || { echo "secret должен быть 32 hex-символа (16 байт)" >&2; exit 2; }

# hex(domain) без префиксов и пробелов
DHEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')
EEE="ee${SECRET}${DHEX}"

echo "tg://proxy?server=${HOST}&port=${PORT}&secret=${EEE}"
echo "https://t.me/proxy?server=${HOST}&port=${PORT}&secret=${EEE}"
