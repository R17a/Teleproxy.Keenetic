#!/bin/sh
# install-keenetic.sh — установка Teleproxy.Keenetic на роутер из релиза GitHub (.ipk).
#
#   wget -qO- https://raw.githubusercontent.com/R17a/Teleproxy.Keenetic/main/install-keenetic.sh | sh
#   VERSION=1.0.1 sh install-keenetic.sh       # конкретная версия
#   sh install-keenetic.sh --no-install      # только скачать пакет
#
# Не путать с upstream install.sh — тот ставит systemd-службу на x86/aarch64 VPS.
set -eu

VER=${VERSION:-1.0.4}
REPO=${REPO:-https://github.com/R17a/Teleproxy.Keenetic}
DO_INSTALL=1
[ "${1:-}" = "--no-install" ] && DO_INSTALL=0

say() { echo "[teleproxy] $*"; }
die() { echo "[teleproxy] ERROR: $*" >&2; exit 1; }

# --- архитектура по данным opkg (точнее, чем uname -m) ----------------------
detect_arch() {
    if command -v opkg >/dev/null 2>&1; then
        opkg print-architecture 2>/dev/null | awk '{print $2}' | while read -r a; do
            case "$a" in
                mipsel-*)  echo mipsel;  break ;;
                mips-*)    echo mips;    break ;;
                aarch64-*) echo aarch64; break ;;
                armv7*)    echo armv7;   break ;;
                x86-64)    echo x86_64;  break ;;
            esac
        done | head -1
        return 0
    fi
    case "$(uname -m)" in
        mipsel|mips) echo mipsel ;;
        mips64*)     echo mips ;;
        armv7l|armv6l) echo armv7 ;;
        aarch64|arm64) echo aarch64 ;;
        x86_64|amd64) echo x86_64 ;;
        *) echo "" ;;
    esac
}

ARCH=$(detect_arch)
[ -n "$ARCH" ] || die "не удалось определить архитектуру (opkg print-architecture / uname -m)"
[ -x /opt/bin/opkg ] || command -v opkg >/dev/null 2>&1 || die "не найден opkg — это не Entware/Keenetic?"

OPKG_ARCH=$(case "$ARCH" in
    mipsel)  echo mipsel-3.4 ;;
    mips)    echo mips-3.4 ;;
    aarch64) echo aarch64-3.10 ;;
    armv7)   echo armv7sf-k3.2 ;;
    x86_64)  echo x86-64 ;;
esac)
PKG="teleproxy-keenetic_${VER}_${OPKG_ARCH}.ipk"
URL="$REPO/releases/download/v$VER/$PKG"

say "arch=$ARCH, пакет: $PKG"

TMP=${TMPDIR:-/opt/tmp}
mkdir -p "$TMP" 2>/dev/null || TMP=/tmp

if command -v curl >/dev/null 2>&1; then
    curl -fL -o "$TMP/$PKG" "$URL" || die "не скачался $URL"
else
    wget -O "$TMP/$PKG" "$URL" || die "не скачался $URL"
fi
say "скачано: $TMP/$PKG"

[ "$DO_INSTALL" = 1 ] || { say "--no-install: остановился"; exit 0; }

say "ставлю пакет"
opkg install "$TMP/$PKG" || die "opkg install не удался"

# Всё остальное делает postinst пакета: идентификатор (имя или числовой uid),
# права на конфиг, ключи P5 в Susanin, проброс 8443 и запуск службы.
say "итог установки:"
[ -f /opt/etc/teleproxy/config.toml ] && \
    say "  config: $(grep -m1 '^user' /opt/etc/teleproxy/config.toml 2>/dev/null)"
[ -f /opt/susanin/etc/susanin.conf ] && \
    say "  susanin: $(grep -m1 '^proxy_uid' /opt/susanin/etc/susanin.conf 2>/dev/null)"
say "  статус: /opt/etc/init.d/S99teleproxy status"
