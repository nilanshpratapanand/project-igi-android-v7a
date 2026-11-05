#!/usr/bin/env python3
"""Patch upstream's jni_bridge.cpp (in a local clone) for the .NET 11 32-bit ARM CoreCLR.

Why: this CoreCLR looks for System.Private.CoreLib.dll in the SAME directory as libcoreclr.so
(not only in the trusted-platform-assembly list). On Android, libcoreclr.so lives in the APK's
read-only native library directory, so CoreLib can never sit next to it and
coreclr_initialize fails with HRESULT 0x80070002 (file not found). The patch copies
libcoreclr.so, libclrjit.so and System.Private.CoreLib.dll into <filesDir>/coreclr and loads
libcoreclr.so from there.

Usage: patch_jni_bridge.py path/to/jni_bridge.cpp
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

if "v7a_sync_file" in src:
    print("already patched")
    sys.exit(0)

HELPER = r'''
// ---- armeabi-v7a patch: keep CoreLib next to libcoreclr.so -------------------------------
#include <sys/stat.h>
#include <unistd.h>
#include <cstdio>

static bool v7a_sync_file(const std::string& from, const std::string& to) {
    struct stat a {}, b {};
    if (stat(from.c_str(), &a) != 0) return false;
    if (stat(to.c_str(), &b) == 0 && b.st_size == a.st_size && b.st_mtime >= a.st_mtime) return true;
    FILE* in = fopen(from.c_str(), "rb");
    if (!in) return false;
    std::string tmp = to + ".tmp";
    FILE* out = fopen(tmp.c_str(), "wb");
    if (!out) { fclose(in); return false; }
    static char buf[1 << 16];
    size_t n;
    bool ok = true;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0) {
        if (fwrite(buf, 1, n, out) != n) { ok = false; break; }
    }
    fclose(in);
    ok = (fclose(out) == 0) && ok;
    if (!ok) { unlink(tmp.c_str()); return false; }
    return rename(tmp.c_str(), to.c_str()) == 0;
}
// -----------------------------------------------------------------------------------------
'''

ANCHOR_FN = "static bool initialize_coreclr("
assert ANCHOR_FN in src, "initialize_coreclr not found; upstream layout changed"
src = src.replace(ANCHOR_FN, HELPER + "\n" + ANCHOR_FN, 1)

OLD = '    std::string coreclrPath = nativeLibDir + "/libcoreclr.so";'
NEW = '''    std::string rtDir = filesDir + "/coreclr";
    mkdir(rtDir.c_str(), 0700);
    bool rtOk = v7a_sync_file(nativeLibDir + "/libcoreclr.so", rtDir + "/libcoreclr.so") &&
                v7a_sync_file(nativeLibDir + "/libclrjit.so", rtDir + "/libclrjit.so") &&
                v7a_sync_file(managedDir + "/System.Private.CoreLib.dll", rtDir + "/System.Private.CoreLib.dll");
    LOGI("v7a: coreclr dir=%s ok=%d", rtDir.c_str(), rtOk ? 1 : 0);
    std::string coreclrPath = (rtOk ? rtDir : nativeLibDir) + "/libcoreclr.so";'''
assert OLD in src, "coreclrPath line not found; upstream layout changed"
src = src.replace(OLD, NEW, 1)

open(path, "w", encoding="utf-8").write(src)
print("patched", path)
