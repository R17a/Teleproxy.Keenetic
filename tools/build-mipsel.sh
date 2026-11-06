#!/bin/bash
# build-mipsel.sh — кросс-сборка teleproxy под mipsel (Keenetic) статически.
# Запуск в WSL:  bash tools/build-mipsel.sh
# Артефакт:      dist/teleproxy.mipsel
#
# Требуется: mipsel-linux-gnu-gcc, make, curl, perl.
# OpenSSL и zlib собираются один раз в ~/tp-build/out и переиспользуются.
#
# Лимиты под 124 МБ RAM роутера (можно переопределить переменными окружения):
#   MAXCONN=2048             — таблица соединений (дефолт upstream 65536 -> BSS ~114 МБ)
#   MAXEVENTS=8192           — epoll-события (дефолт 1<<19 -> ~40 МБ)
#   EXT_CONN_TABLE_SIZE=16384 — таблица внешних соединений (дефолт 1<<22 -> 64 МБ)
set -e

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
B=$HOME/tp-build
OUT=$B/out
DIST=$REPO/dist
LOG=$B/build.log

mkdir -p "$B" "$DIST"
exec > >(tee -a "$LOG") 2>&1

CC=mipsel-linux-gnu-gcc
AR=mipsel-linux-gnu-ar
RANLIB=mipsel-linux-gnu-ranlib

echo "===== $(date -u) start ====="
echo "repo: $REPO"
$CC --version | head -1

# ---------- zlib ----------
if [ ! -f "$OUT/lib/libz.a" ]; then
  cd "$B"
  [ -f zlib.tgz ] || curl -fsSL -o zlib.tgz https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
  rm -rf zlib-1.3.1 && tar xzf zlib.tgz
  cd zlib-1.3.1
  CC=$CC AR=$AR RANLIB=$RANLIB CFLAGS="-O2 -fPIC" ./configure --static --prefix="$OUT"
  make -j"$(nproc)"
  make install
  echo "===== zlib ok ====="
fi

# ---------- openssl ----------
if [ ! -f "$OUT/lib/libcrypto.a" ]; then
  cd "$B"
  [ -f openssl.tgz ] || curl -fsSL -o openssl.tgz https://www.openssl.org/source/openssl-3.0.15.tar.gz
  rm -rf openssl-3.0.15 && tar xzf openssl.tgz
  cd openssl-3.0.15
  export CC AR RANLIB LDFLAGS="-latomic"
  # linux-mipsel в 3.0.x нет -> generic32 + little-endian
  if ! ./Configure linux-mipsel no-asm no-shared no-module no-tests \
        --prefix="$OUT" --openssldir="$OUT/ssl" >/tmp/ossl-conf.log 2>&1; then
    echo "linux-mipsel unavailable, using linux-generic32 -DL_ENDIAN"
    ./Configure linux-generic32 no-asm no-shared no-module no-tests -DL_ENDIAN \
        --prefix="$OUT" --openssldir="$OUT/ssl"
  fi
  make -j"$(nproc)" build_libs
  make install_dev
  echo "===== openssl ok ====="
fi

# ---------- teleproxy (этот репозиторий) ----------
MAXCONN=${MAXCONN:-2048}
MAXEVENTS=${MAXEVENTS:-8192}
EXTCONN=${EXT_CONN_TABLE_SIZE:-16384}
echo "limits: MAX_CONNECTIONS=$MAXCONN MAX_EVENTS=$MAXEVENTS EXT_CONN_TABLE_SIZE=$EXTCONN"

cd "$REPO"
make clean >/dev/null 2>&1 || true
make CC=$CC \
  CFLAGS="-O2 -std=gnu11 -Wall -fno-strict-aliasing -fno-strict-overflow -fwrapv -fno-common \
          -DAES=1 -D_GNU_SOURCE=1 -D_FILE_OFFSET_BITS=64 \
          -DMAX_CONNECTIONS=$MAXCONN -DMAX_EVENTS=$MAXEVENTS -DEXT_CONN_TABLE_SIZE=$EXTCONN \
          -I$OUT/include" \
  LDFLAGS="-static -L$OUT/lib -lm -lrt -lcrypto -lz -lpthread -latomic" \
  -j"$(nproc)"

cp -f objs/bin/teleproxy "$DIST/teleproxy.mipsel"
echo "===== teleproxy built ====="
file "$DIST/teleproxy.mipsel"
mipsel-linux-gnu-readelf -S "$DIST/teleproxy.mipsel" | grep -E '\.bss|\.data ' || true
ls -l "$DIST/teleproxy.mipsel"
echo "===== $(date -u) done ====="
