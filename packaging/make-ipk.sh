#!/bin/sh
# make-ipk.sh — упаковать teleproxy в .ipk для Entware (Keenetic).
#
#   sh packaging/make-ipk.sh --bin dist --out dist --version 1.0
#   sh packaging/make-ipk.sh --one mipsel dist/teleproxy.mipsel
#
# Формат как у пакетов Entware: gzip(tar) с ./debian-binary, ./data.tar.gz,
# ./control.tar.gz. Без --one собирает все архитектуры, для которых есть
# <bin>/teleproxy.<arch>.
set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINDIR="$SRC/dist"
OUT="$SRC/dist"
VER="1.0"
ONE=""
ONE_BIN=""
ARCHS=""

die() { echo "make-ipk: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --bin) BINDIR="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --version) VER="$2"; shift 2 ;;
        --one) ONE="$2"; ONE_BIN="${3:-}"; shift 2; [ -n "$ONE_BIN" ] && shift ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "неизвестный параметр: $1" ;;
        *) ARCHS="$ARCHS $1"; shift ;;
    esac
done

command -v tar >/dev/null 2>&1 || die "нет tar"
command -v gzip >/dev/null 2>&1 || die "нет gzip"

opkg_arch() {
    case "$1" in
        mipsel)  echo mipsel-3.4 ;;
        mips)    echo mips-3.4 ;;
        aarch64) echo aarch64-3.10 ;;
        armv7)   echo armv7sf-k3.2 ;;
        x86_64)  echo x86-64 ;;
        *)       echo "$1" ;;
    esac
}

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

build_one() { # build_one <arch> <binary>
    _t="$1"; _bin="$2"
    _oa=$(opkg_arch "$_t")
    [ -f "$_bin" ] || die "нет бинарника: $_bin"
    _sz=$(wc -c < "$_bin" | tr -d ' ')

    _w=$(mktemp -d 2>/dev/null || echo "/tmp/tpkipk.$$")
    _d="$_w/data"; _c="$_w/control"
    mkdir -p "$_d/opt/sbin" "$_d/opt/etc/init.d" "$_d/opt/share/teleproxy" "$_c"

    cp "$_bin" "$_d/opt/sbin/teleproxy"
    chmod 755 "$_d/opt/sbin/teleproxy"
    cp "$SRC/init/S99teleproxy" "$_d/opt/etc/init.d/S99teleproxy"
    cp "$SRC/init/S98teleproxy-fw" "$_d/opt/etc/init.d/S98teleproxy-fw"
    chmod 755 "$_d/opt/etc/init.d/S99teleproxy" "$_d/opt/etc/init.d/S98teleproxy-fw"
    cp "$SRC/packaging/config.toml.example" "$_d/opt/share/teleproxy/config.toml.example"
    chmod 644 "$_d/opt/share/teleproxy/config.toml.example"

    _size=$(du -sk "$_d" | awk '{print $1}')
    sed -e "s|{{VER}}|$VER|g" -e "s|{{ARCH}}|$_oa|g" \
        -e "s|{{SIZE}}|$_size|g" -e "s|{{BINSIZE}}|$_sz|g" \
        "$SRC/packaging/control.template" > "$_c/control"
    cp "$SRC/packaging/postinst" "$_c/postinst"
    cp "$SRC/packaging/prerm" "$_c/prerm"
    chmod 755 "$_c/postinst" "$_c/prerm" 2>/dev/null || true

    printf '2.0\n' > "$_w/debian-binary"
    ( cd "$_c" && tar -czf "$_w/control.tar.gz" ./control ./postinst ./prerm 2>/dev/null \
        || tar -czf "$_w/control.tar.gz" ./control )
    ( cd "$_d" && tar -czf "$_w/data.tar.gz" ./opt )
    _out="$OUT/teleproxy-keenetic_${VER}_${_oa}.ipk"
    ( cd "$_w" && tar -czf "$_out" ./debian-binary ./data.tar.gz ./control.tar.gz )
    echo "make-ipk: $_out ($(du -h "$_out" | awk '{print $1}'))"
    rm -rf "$_w"
}

if [ -n "$ONE" ]; then
    [ -n "$ONE_BIN" ] || die "--one требует путь к бинарнику"
    build_one "$ONE" "$ONE_BIN"
else
    [ -n "$ARCHS" ] || ARCHS="mipsel mips aarch64 armv7 x86_64"
    _n=0
    for a in $ARCHS; do
        b="$BINDIR/teleproxy.$a"
        if [ ! -f "$b" ]; then
            echo "make-ipk: пропускаю $a (нет $b)" >&2
            continue
        fi
        build_one "$a" "$b"
        _n=$((_n + 1))
    done
    [ "$_n" -gt 0 ] || die "не собрано ни одного пакета"
fi

( cd "$OUT" && sha256sum ./*.ipk > SHA256SUMS 2>/dev/null ) || true
( cd "$OUT" && sha256sum ./teleproxy.* >> SHA256SUMS 2>/dev/null ) || true
echo "make-ipk: готово, пакеты в $OUT (+SHA256SUMS)"
