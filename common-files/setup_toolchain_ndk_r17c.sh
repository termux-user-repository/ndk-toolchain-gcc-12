_download_ndk_r17c() {
	if [ ! -f $_CACHE_DIR/.placeholder-android-ndk-r17c ]; then
		echo "Start downloading Android NDK toolchain (version r17c)..."
		mkdir -p $_CACHE_DIR/
		local _NDKARCHIVE_FILE=$_CACHE_DIR/android-ndk-r17c-linux-x86_64.zip
		local _NDK_URL=https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip
		local _NDK_SHA256=3f541adbd0330a9205ba12697f6d04ec90752c53d6b622101a2a8a856e816589
		termux_download $_NDK_URL $_NDKARCHIVE_FILE $_NDK_SHA256
		unzip -d $_CACHE_DIR/ $_NDKARCHIVE_FILE > /dev/null 2>&1
		touch $_CACHE_DIR/.placeholder-android-ndk-r17c
		echo "Downloading completed."
	fi
}

_setup_standalone_toolchain_ndk_r17c() {
	_download_ndk_r17c

	local TOOLCHAIN_DIR="$1"
	rm -rf $TOOLCHAIN_DIR

	local _NDKARCH
	if [ "$TOOLCHAIN_ARCH" == "aarch64" ]; then
		_NDKARCH="arm64"
	elif [ "$TOOLCHAIN_ARCH" == "arm" ]; then
		_NDKARCH="arm"
	elif [ "$TOOLCHAIN_ARCH" == "x86_64" ]; then
		_NDKARCH="x86_64"
	elif [ "$TOOLCHAIN_ARCH" == "i686" ]; then
		_NDKARCH="x86"
	fi

	# Setup a standalone toolchain
	python $_CACHE_DIR/android-ndk-r17c/build/tools/make_standalone_toolchain.py \
				--arch $_NDKARCH --api $_API_LEVEL --install-dir $TOOLCHAIN_DIR

	# Modify sysroot
	pushd $TOOLCHAIN_DIR

	# See https://github.com/android/ndk/issues/215#issuecomment-524293090
	sed -i "s/include_next <stddef.h>/include <stddef.h>/" include/c++/4.9.x/cstddef

	sed -i "s/define __ANDROID_API__ __ANDROID_API_FUTURE__/define __ANDROID_API__ $_API_LEVEL/" \
		sysroot/usr/include/android/api-level.h
	popd
}
