# Project IGI Android Port: armeabi-v7a (32-bit ARM) build scripts

Build scripts that produce a 32-bit ARM (`armeabi-v7a`) APK of
[rayishere0/Project-IGI-Android-Port](https://github.com/rayishere0/Project-IGI-Android-Port),
whose releases ship `arm64-v8a` only.

**This repository contains no upstream code, assets, binaries or APK.** The upstream project is
published under an all-rights-reserved `LICENSE`, so nothing of theirs is redistributed here. The
script clones upstream on your machine at a pinned commit and builds locally. You also need your
own copy of the original PC game; the app has a folder picker for it.

## Status: experimental

Tested on a Redmi 9 Activ (MediaTek MT6765, PowerVR GE8320, 32-bit-only Android 10, 3.8 GB RAM):

- Builds and installs; the launcher shows and accepts a game folder.
- After PLAY the .NET 11 RC runtime starts on 32-bit ARM, Vulkan 1.1 initializes on the GE8320 using
  upstream's render-pass fallback, the game loop starts, and the game's main menu renders.
- **Not verified:** actual gameplay, frame rate, stability over time, audio quality, or other devices.
  Expect it to be slow: it is a JIT-compiled engine on a low-end 32-bit phone.

## Why it needs more than a repack

- Upstream targets .NET 10, but Microsoft publishes no 32-bit ARM Android CoreCLR runtime for
  .NET 8, 9 or 10. The newest is the .NET 11 release candidate (`11.0.0-rc.3`), which the script
  uses in place of the arm64 runtime; the game's CPU-neutral IL assemblies run on top of it.
- The native pieces (`libprojectigi.so` JNI bridge, OpenAL Soft 1.23.1) are rebuilt for armv7 with the NDK.
- Many 32-bit devices, including the one above, lack `VK_KHR_dynamic_rendering`. The v1.0.0 release
  predates upstream's render-pass fallback, so the script builds from upstream source instead.
- Upstream commit `0b12709` does not compile as-is (missing `using ProjectIGI.Game.Player;` in
  `SettingsScreen.cs`); the script adds that line in its local clone.
- The .NET 11 32-bit CoreCLR looks for `System.Private.CoreLib.dll` next to `libcoreclr.so`, which on
  Android is a read-only directory inside the APK, so `coreclr_initialize` fails with `0x80070002`.
  `scripts/patch_jni_bridge.py` makes the bridge copy `libcoreclr.so`, `libclrjit.so` and CoreLib into
  `<filesDir>/coreclr` and load the runtime from there.
- Upstream's `VulkanInstance` refuses any loader below Vulkan 1.3 even though the rest of the renderer
  adapts to the adapter. `scripts/patch_vulkan_instance.py` accepts a 1.1+ loader.

## Build

Prerequisites (not installed by the script): Android SDK with NDK `27.2.12479018`, CMake `3.31.6`
and build-tools; **JDK 17**; .NET SDK 10.x; git, curl, unzip, python. Works from Git Bash on
Windows, and should on Linux/macOS.

```bash
export ANDROID_HOME=/path/to/Android/Sdk
export JAVA_HOME=/path/to/jdk-17
./scripts/build-v7a.sh ./work
```

The result is `work/src/app/android/app/build/outputs/apk/release/app-release.apk`, signed with the
Gradle debug key. Install with `adb install -r`. On Xiaomi/MIUI, accept the "Install via USB" prompt
on the phone within about 10 seconds.

## License

The scripts and this README are MIT licensed (see `LICENSE`). That covers only this repository's own
files, not upstream's code or the game.
