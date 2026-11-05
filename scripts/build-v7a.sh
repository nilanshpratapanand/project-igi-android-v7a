#!/usr/bin/env bash
# Build an armeabi-v7a (32-bit ARM) APK of rayishere0/Project-IGI-Android-Port.
#
# This script contains none of the upstream code or assets. It clones upstream into $WORK,
# applies two small edits in that clone, cross-compiles the native pieces for armv7, swaps in
# the .NET 11 RC 32-bit ARM CoreCLR runtime, and runs the upstream Gradle project.
#
# Requirements (not installed by this script):
#   - Android SDK with NDK r27 (27.2.12479018), CMake 3.31.6 and build-tools; set ANDROID_HOME
#   - JDK 17 (Gradle 8.9 / AGP 8.5.2 do not run on newer JDKs); set JAVA_HOME
#   - .NET SDK 10.x, git, curl, unzip, python
# Usage: ANDROID_HOME=... JAVA_HOME=... ./build-v7a.sh [workdir]
set -euo pipefail

UPSTREAM=https://github.com/rayishere0/Project-IGI-Android-Port.git
UPSTREAM_COMMIT=0b1270954f8de24c9e5bd50872afafb69a784120
OPENAL_VERSION=1.23.1
NDK_VERSION=27.2.12479018
CMAKE_VERSION=3.31.6
DOTNET_PACK_VERSION=11.0.0-rc.3.26522.148   # newest .NET with a 32-bit ARM Android CoreCLR pack

: "${ANDROID_HOME:?set ANDROID_HOME}"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17}"
WORK="$(mkdir -p "${1:-./work}" && cd "${1:-./work}" && pwd)"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) HOST_TAG=windows-x86_64 ;;
  Darwin*)              HOST_TAG=darwin-x86_64 ;;
  *)                    HOST_TAG=linux-x86_64 ;;
esac
NDK="$ANDROID_HOME/ndk/$NDK_VERSION"
LLVM="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CMAKE_BIN="$ANDROID_HOME/cmake/$CMAKE_VERSION/bin"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"

echo "== 1/7 clone upstream @ $UPSTREAM_COMMIT"
if [ ! -d "$WORK/src/.git" ]; then
  git clone "$UPSTREAM" "$WORK/src"
fi
git -C "$WORK/src" checkout -q "$UPSTREAM_COMMIT"
SRC="$WORK/src"
ANDROID_DIR="$SRC/app/android"

echo "== 2/7 fix missing using in SettingsScreen.cs (upstream HEAD does not compile without it)"
F="$SRC/src/Game/ProjectIGI.Frontend/Screens/SettingsScreen.cs"
grep -q '^using ProjectIGI.Game.Player;' "$F" || \
  sed -i 's/^using ProjectIGI.Core.Graphics;/using ProjectIGI.Core.Graphics;\nusing ProjectIGI.Game.Player;/' "$F"

echo "== 2b/7 patch the native bridge (CoreLib next to libcoreclr) and the Vulkan 1.3-only instance check"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python "$HERE/patch_jni_bridge.py" "$SRC/app/android/app/src/main/cpp/jni/jni_bridge.cpp"
python "$HERE/patch_vulkan_instance.py" "$SRC/src/Rendering/ProjectIGI.Rendering.Vulkan/VulkanInstance.cs"

echo "== 3/7 build OpenAL Soft $OPENAL_VERSION for armeabi-v7a"
mkdir -p "$WORK/openal"
[ -d "$WORK/openal/openal-soft-$OPENAL_VERSION" ] || {
  curl -sSL -o "$WORK/openal/oal.tgz" "https://github.com/kcat/openal-soft/archive/refs/tags/$OPENAL_VERSION.tar.gz"
  tar xzf "$WORK/openal/oal.tgz" -C "$WORK/openal"
}
"$CMAKE_BIN/cmake" -S "$WORK/openal/openal-soft-$OPENAL_VERSION" -B "$WORK/build-oal" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$CMAKE_BIN/ninja" -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release -DLIBTYPE=SHARED -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF \
  -DALSOFT_INSTALL=OFF -DALSOFT_BACKEND_OPENSL=ON -DALSOFT_BACKEND_OBOE=OFF -DALSOFT_REQUIRE_OPENSL=ON
"$CMAKE_BIN/cmake" --build "$WORK/build-oal" -j 8

echo "== 4/7 build the JNI bridge (libprojectigi.so) with upstream's CMakeLists"
CPP="$ANDROID_DIR/app/src/main/cpp"
mkdir -p "$ANDROID_DIR/app/src/main/jniLibs/armeabi-v7a"
cp "$WORK/build-oal/libopenal.so" "$ANDROID_DIR/app/src/main/jniLibs/armeabi-v7a/libopenal.so"
"$CMAKE_BIN/cmake" -S "$CPP" -B "$WORK/build-jni" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$CMAKE_BIN/ninja" -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-frtti -fexceptions"
"$CMAKE_BIN/cmake" --build "$WORK/build-jni"

echo "== 5/7 fetch the .NET $DOTNET_PACK_VERSION android-arm runtime pack from nuget.org"
mkdir -p "$WORK/pack"
[ -f "$WORK/pack/pack.nupkg" ] || curl -sSL -o "$WORK/pack/pack.nupkg" \
  "https://api.nuget.org/v3-flatcontainer/microsoft.netcore.app.runtime.android-arm/$DOTNET_PACK_VERSION/microsoft.netcore.app.runtime.android-arm.$DOTNET_PACK_VERSION.nupkg"
unzip -q -o "$WORK/pack/pack.nupkg" -d "$WORK/pack/x"
PACK="$WORK/pack/x/runtimes/android-arm"

echo "== 6/7 publish the managed (CPU-neutral) game assemblies"
# No RID: .NET 10 has no android-arm runtime pack. nuget.org is passed explicitly because a
# default NuGet config may have no sources.
dotnet publish "$SRC/apps/ProjectIGI.Android/ProjectIGI.Android.csproj" -c Release \
  -p:UseAppHost=false -p:RestoreSources=https://api.nuget.org/v3/index.json -o "$WORK/managed"

echo "== 7/7 assemble native libs + assets, patch build.gradle, run Gradle"
JNI="$WORK/jni/armeabi-v7a"; ASSETS="$WORK/assets"
mkdir -p "$JNI" "$ASSETS/managed"
for f in libcoreclr libclrjit libSystem.Native libSystem.IO.Compression.Native \
         libSystem.Globalization.Native libSystem.Security.Cryptography.Native.Android; do
  cp "$PACK/native/$f.so" "$JNI/"
done
cp "$WORK/build-oal/libopenal.so" "$WORK/build-jni/libprojectigi.so" "$JNI/"
cp "$NDK/toolchains/llvm/prebuilt/$HOST_TAG/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so" "$JNI/"
for f in "$JNI"/*.so; do "$LLVM/llvm-strip" --strip-unneeded "$f"; done

A="$ANDROID_DIR/app/src/main/assets"
cp "$A"/*.png "$A/capacitor.config.json" "$ASSETS/"
cp -r "$A/public" "$ASSETS/"
cp -r "$A/managed/Assets" "$ASSETS/managed/"
cp "$PACK"/lib/net11.0/*.dll "$ASSETS/managed/"     # framework from the .NET 11 RC pack
cp "$WORK/managed"/*.dll "$ASSETS/managed/"         # game + NuGet assemblies

python - "$ANDROID_DIR/app/build.gradle" "$WORK/jni" "$WORK/assets" <<'PY'
import sys
p, jni, assets = sys.argv[1], sys.argv[2].replace('\\', '/'), sys.argv[3].replace('\\', '/')
s = open(p).read()
s = s.replace("""        externalNativeBuild {
            cmake {
                cppFlags "-std=c++17 -frtti -fexceptions"
                arguments "-DANDROID_STL=c++_shared"
            }
        }
""", "")
s = s.replace("""    externalNativeBuild {
        cmake {
            path file('src/main/cpp/CMakeLists.txt')
        }
    }
""", "")
s = s.replace("abiFilters 'arm64-v8a'", "abiFilters 'armeabi-v7a'")
s = s.replace("jniLibs.srcDirs = ['src/main/jniLibs']",
              "jniLibs.srcDirs = ['%s']\n            assets.srcDirs = ['%s']" % (jni, assets))
s = s.replace('versionName "1.0.2"', 'versionName "1.0.2-v7a"')
open(p, 'w').write(s)
PY

echo "sdk.dir=$ANDROID_HOME" > "$ANDROID_DIR/local.properties"
( cd "$ANDROID_DIR" && ./gradlew --no-daemon :app:assembleRelease )
APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
echo
echo "Built: $APK  (debug-signed)"
