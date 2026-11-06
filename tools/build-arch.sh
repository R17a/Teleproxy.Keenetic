#!/bin/bash
# build-arch.sh — кросс-сборка teleproxy под архитектуры Keenetic (Entware).
#
#   bash tools/build-arch.sh mipsel     # одна архитектура
#   bash tools/build-arch.sh all        # mipsel mips aarch64 armv7 x86_64
#
# Результат: dist/teleproxy.<arch> (статический бинарник).
# OpenSSL и zlib собираются один раз в ~/tp-build/out/<arch> и переиспользуются.
# Требуется: соответствующий GCC (gcc-<arch>-linux-gnu*), make, curl, perl.
set -e

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
B=$HOME/tp-build
DIST=$REPO/dist

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

pick_cc() { # pick_cc <arch> -> CC
    case "$1" in
        mipsel)  echo mipsel-linux-gnu-gcc ;;
        mips)    echo mips-linux-gnu-gcc ;;
        aarch64) echo aarch64-linux-gnu-gcc ;;
        armv7)   echo arm-linux-gnueabihf-gcc ;;
        x86_64)  echo gcc ;;
        *) return 1 ;;
    esac
}

pick_ossl_target() { # pick_ossl_target <arch> -> "target [extra flags]"
    case "$1" in
        # OpenSSL 3.0 без linux-mipsel: generic32 + явная little-endian
        mipsel)  echo "linux-generic32 -DL_ENDIAN" ;;
        mips)    echo "linux-generic32" ;;
        aarch64) echo "linux-aarch64" ;;
        armv7)   echo "linux-armv4" ;;
        x86_64)  echo "linux-x86_64" ;;
        *) return 1 ;;
    esac
}

build_one() { # build_one <arch>
    local ARCH=$1
    local CC; CC=$(pick_cc "$ARCH") || { echo "unknown arch: $ARCH" >&2; return 1; }
    if ! command -v "$CC" >/dev/null 2>&1; then
        echo "ОШИБКА: нет компилятора $CC для $ARCH (пакет gcc-${ARCH}-linux-gnu*)" >&2
        return 1
    fi
    echo "[$ARCH] CC=$(command -v "$CC")"

    local OUT=$B/out/$ARCH
    local AR=${CC%gcc}ar
    local RANLIB=${CC%gcc}ranlib
    command -v "$AR" >/dev/null 2>&1 || AR=ar
    command -v "$RANLIB" >/dev/null 2>&1 || RANLIB=ranlib
    local LOG=$B/build-$ARCH.log
    mkdir -p "$B" "$OUT" "$DIST"

    exec 3>&1
    exec > >(tee -a "$LOG") 2>&1
    echo "===== $ARCH start $(date -u) ====="
    echo "CC=$CC AR=$AR RANLIB=$RANLIB OUT=$OUT"

    # ---------- zlib ----------
    if [ ! -f "$OUT/lib/libz.a" ]; then
        cd "$B"
        [ -f zlib.tgz ] || curl -fsSL -o zlib.tgz https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
        rm -rf "zlib-$ARCH" && mkdir "zlib-$ARCH" && tar xzf zlib.tgz -C "zlib-$ARCH" --strip-components=1
        cd "zlib-$ARCH"
        CC=$CC AR=$AR RANLIB=$RANLIB CFLAGS="-O2 -fPIC" ./configure --static --prefix="$OUT"
        make -j"$(nproc)"
        make install
        echo "===== $ARCH zlib ok ====="
    fi

    # ---------- openssl ----------
    if [ ! -f "$OUT/lib/libcrypto.a" ]; then
        cd "$B"
        [ -f openssl.tgz ] || curl -fsSL -o openssl.tgz https://www.openssl.org/source/openssl-3.0.15.tar.gz
        rm -rf "openssl-$ARCH" && mkdir "openssl-$ARCH" && tar xzf openssl.tgz -C "openssl-$ARCH" --strip-components=1
        cd "openssl-$ARCH"
        export CC AR RANLIB LDFLAGS="-latomic"
        # shellcheck disable=SC2086
        ./Configure $(pick_ossl_target "$ARCH") no-asm no-shared no-module no-tests \
            --prefix="$OUT" --openssldir="$OUT/ssl" --libdir=lib >/dev/null
        make -j"$(nproc)" build_libs
        make install_dev
        echo "===== $ARCH openssl ok ====="
    fi

    # ---------- teleproxy ----------
    # У x86_64 crc32c.c использует интринсики PCLMUL/SSSE3: CFLAGS переопределяются
    # целиком, поэтому нужные -m флаги задаём явно.
    ARCHCFLAGS=""
    case "$ARCH" in
        x86_64) ARCHCFLAGS="-mpclmul -mssse3 -march=core2 -mfpmath=sse" ;;
    esac
    MAXCONN=${MAXCONN:-2048}
    MAXEVENTS=${MAXEVENTS:-8192}
    EXTCONN=${EXT_CONN_TABLE_SIZE:-16384}
    cd "$REPO"
    rm -f objs/bin/teleproxy        # чтобы не скопировать бинарник прошлой арх
    make clean >/dev/null 2>&1 || true
    make CC="$CC" \
      CFLAGS="-O2 -std=gnu11 -Wall -fno-strict-aliasing -fno-strict-overflow -fwrapv -fno-common \
              $ARCHCFLAGS \
              -DAES=1 -D_GNU_SOURCE=1 -D_FILE_OFFSET_BITS=64 \
              -DMAX_CONNECTIONS=$MAXCONN -DMAX_EVENTS=$MAXEVENTS -DEXT_CONN_TABLE_SIZE=$EXTCONN \
              -I$OUT/include" \
      LDFLAGS="-static -L$OUT/lib -lm -lrt -lcrypto -lz -lpthread -latomic" \
      -j"$(nproc)"

    if [ ! -f objs/bin/teleproxy ]; then
        echo "===== $ARCH FAILED: бинарник не собран =====" >&2
        exec >&3
        return 1
    fi
    cp -f objs/bin/teleproxy "$DIST/teleproxy.$ARCH"
    echo "===== $ARCH built ====="
    file "$DIST/teleproxy.$ARCH"
    ls -l "$DIST/teleproxy.$ARCH"
    echo "===== $ARCH done $(date -u) ====="
    exec >&3
}

[ $# -gt 0 ] || usage 2

case "$1" in
    -h|--help) usage 0 ;;
    all) ARCHS="mipsel mips aarch64 armv7 x86_64" ;;
    *)   ARCHS="$@" ;;
esac

rc=0
for a in $ARCHS; do
    build_one "$a" || rc=1
done
exit $rc
