#!/usr/bin/env python3
"""Relax upstream's hard "Vulkan 1.3 loader or nothing" instance check (in a local clone).

VulkanInstance.CreateInstance refuses any loader below Vulkan 1.3, while the rest of the renderer
(capability probe, render-pass fallback) already adapts to what the adapter reports. Devices such as
the PowerVR GE8320 only offer Vulkan 1.1, so the instance check is the first thing that stops them.
This patch accepts a 1.1+ loader and requests min(supported, 1.3).

Usage: patch_vulkan_instance.py path/to/VulkanInstance.cs
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

OLD = '''        if (Vk.EnumerateInstanceVersion(&supported) != Result.Success || supported < Vk.Version13)
        {
            throw new GraphicsDeviceException("Vulkan 1.3 is required but the loader does not offer it.");
        }
        uint apiVersion = Vk.Version13;'''
NEW = '''        if (Vk.EnumerateInstanceVersion(&supported) != Result.Success || supported < Vk.Version11)
        {
            throw new GraphicsDeviceException("Vulkan 1.1 is required but the loader does not offer it.");
        }
        uint apiVersion = supported < Vk.Version13 ? supported : Vk.Version13;'''

if NEW in src:
    print("already patched")
    sys.exit(0)
assert OLD in src, "instance version check not found; upstream layout changed"
open(path, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
print("patched", path)
