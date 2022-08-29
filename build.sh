#!/bin/bash
#  build.sh - script to build a custom NDK toolchain
#
#  Copyright 2022 Chongyun Lee <uchkks@protonmail.com>
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

set -e -u -o pipefail

_SCRIPTDIR=$(cd "$(realpath "$(dirname "$0")")"; pwd)
source $_SCRIPTDIR/common-files/setup_toolchain_ndk_r17c.sh
source $_SCRIPTDIR/common-files/termux_download.sh

: ${TOOLCHAIN_ARCH:=aarch64}
: ${_CACHE_DIR:=$_SCRIPTDIR/cache}
: ${_TMP_DIR:=$_SCRIPTDIR/tmp}
: ${_API_LEVEL:=21}
: ${_MAKE_PROCESSES:=$(nproc)}
: ${GCC_VERSION:=12.1.0}
: ${GCC_SHA256:=e88a004a14697bbbaba311f38a938c716d9a652fd151aaaa4cf1b5b99b90e2de}

export TOOLCHAIN_ARCH

TERMUX_PKG_TMPDIR=$_TMP_DIR
mkdir -p $_CACHE_DIR
rm -rf $_TMP_DIR
mkdir -p $_TMP_DIR

_HOST_PLATFORM="${TOOLCHAIN_ARCH}-linux-android"

_EXTRA_HOST_BUILD=""
if [ "$TOOLCHAIN_ARCH" = "arm" ]; then
	_HOST_PLATFORM="${_HOST_PLATFORM}eabi"
	_EXTRA_HOST_BUILD="--with-arch=armv7-a --with-float=soft --with-fpu=vfp"
elif [ "$TOOLCHAIN_ARCH" = "aarch64" ]; then
	_EXTRA_HOST_BUILD="--enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419"
elif [ "$TOOLCHAIN_ARCH" = "i686" ]; then
	_EXTRA_HOST_BUILD="--with-arch=i686 --with-fpmath=sse "
elif [ "$TOOLCHAIN_ARCH" = "x86_64" ]; then
	_EXTRA_HOST_BUILD="--with-arch=x86-64 --with-fpmath=sse"
fi

# Install dependencies
sudo apt update
sudo apt install -y build-essential curl
sudo apt install -y libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev libisl-dev libtinfo5 libncurses5

pushd $_TMP_DIR

# Download source
SRC_URL=https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz
SRC_FILE=$_CACHE_DIR/gcc-${GCC_VERSION}.tar.gz
SRC_DIR=$_TMP_DIR/gcc-${GCC_VERSION}
termux_download $SRC_URL $SRC_FILE $GCC_SHA256

# Setup a standalone toolchain
_setup_standalone_toolchain_ndk_r17c $_TMP_DIR/standalone-toolchain
cp -R $_TMP_DIR/standalone-toolchain/sysroot/usr/include/$_HOST_PLATFORM/* $_TMP_DIR/standalone-toolchain/sysroot/usr/include/

PATH="$_TMP_DIR/standalone-toolchain/bin:$PATH"

# Extract source
tar -xf $SRC_FILE -C $_TMP_DIR/
pushd $_TMP_DIR
PATCHES="$(find "$_SCRIPTDIR/patches/" -maxdepth 1 -type f -name *.patch | sort)"
for f in $PATCHES; do
	echo "Applying patch: $(basename $f)"
	patch -d "$SRC_DIR/" -p1 < "$f";
done
popd

# Build a custom toolchain
mkdir -p $_TMP_DIR/newer-toolchain
cp -R $_TMP_DIR/standalone-toolchain/sysroot $_TMP_DIR/newer-toolchain/

mkdir -p newer-toolchain-build
pushd newer-toolchain-build

export CFLAGS="-D__ANDROID_API__=$_API_LEVEL"
export CPPFLAGS="-D__ANDROID_API__=$_API_LEVEL"
export CXXFLAGS="-D__ANDROID_API__=$_API_LEVEL"

$SRC_DIR/configure \
        --host=x86_64-linux-gnu  \
        --build=x86_64-linux-gnu \
        --target=$_HOST_PLATFORM \
        --disable-shared \
        --disable-nls \
        --enable-default-pie \
        --with-host-libstdcxx='-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm' \
        --with-gnu-as --with-gnu-ld \
        --disable-libstdc__-v3 \
        --disable-tls \
        --disable-bootstrap \
        --enable-initfini-array \
        --enable-libatomic-ifuncs=no \
        --prefix=$_TMP_DIR/newer-toolchain \
        --with-gmp --with-mpfr --with-mpc --with-system-zlib \
        --enable-languages=c,c++,fortran \
        --enable-plugins --enable-libgomp \
        --enable-gnu-indirect-function \
        --disable-libcilkrts --disable-libsanitizer \
        --enable-gold --enable-threads \
        --enable-eh-frame-hdr-for-static \
        --enable-graphite=yes --with-isl \
        --disable-multilib \
        $_EXTRA_HOST_BUILD \
        --with-sysroot=$_TMP_DIR/newer-toolchain/sysroot \
        --with-gxx-include-dir=$_TMP_DIR/newer-toolchain/include/c++/$GCC_VERSION

make -j $_MAKE_PROCESSES
make -j $_MAKE_PROCESSES install

popd # newer-toolchain-build

# Make the archive
mv newer-toolchain gcc-$GCC_VERSION-$TOOLCHAIN_ARCH
tar -cjvf gcc-$GCC_VERSION-$TOOLCHAIN_ARCH.tar.bz2 gcc-$GCC_VERSION-$TOOLCHAIN_ARCH

popd # $_TMP_DIR

# Copy the archive
mkdir -p build
cp $_TMP_DIR/gcc-$GCC_VERSION-$TOOLCHAIN_ARCH.tar.bz2 ./build
