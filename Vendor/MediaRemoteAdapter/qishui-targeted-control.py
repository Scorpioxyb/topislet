#!/usr/bin/python3

import ctypes
import sys
import time


MEDIA_REMOTE_PATH = (
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
)
CORE_FOUNDATION_PATH = (
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
)
DISPATCH_PATH = "/usr/lib/system/libdispatch.dylib"
ALLOWED_COMMANDS = {2, 4, 5}
QISHUI_BUNDLE_IDENTIFIER = "com.soda.music"


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: qishui-targeted-control.py FRAMEWORK BUNDLE COMMAND", file=sys.stderr)
        return 64

    framework_path, bundle_identifier, raw_command = sys.argv[1:]
    if bundle_identifier != QISHUI_BUNDLE_IDENTIFIER:
        print("unsupported bundle identifier", file=sys.stderr)
        return 64
    try:
        command = int(raw_command)
    except ValueError:
        print("invalid command", file=sys.stderr)
        return 64
    if command not in ALLOWED_COMMANDS:
        print("unsupported command", file=sys.stderr)
        return 64

    adapter = ctypes.CDLL(framework_path)
    media_remote = ctypes.CDLL(MEDIA_REMOTE_PATH)
    core_foundation = ctypes.CDLL(CORE_FOUNDATION_PATH)
    dispatch = ctypes.CDLL(DISPATCH_PATH)

    core_foundation.CFStringCreateWithCString.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_uint32,
    ]
    core_foundation.CFStringCreateWithCString.restype = ctypes.c_void_p
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    adapter.findNowPlayingClient.argtypes = [ctypes.c_void_p]
    adapter.findNowPlayingClient.restype = ctypes.c_void_p
    media_remote.MRMediaRemoteGetLocalOrigin.argtypes = []
    media_remote.MRMediaRemoteGetLocalOrigin.restype = ctypes.c_void_p
    media_remote.MRMediaRemoteSendCommandToClient.argtypes = [
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    media_remote.MRMediaRemoteSendCommandToClient.restype = None
    dispatch.dispatch_get_global_queue.argtypes = [ctypes.c_long, ctypes.c_ulong]
    dispatch.dispatch_get_global_queue.restype = ctypes.c_void_p

    bundle = core_foundation.CFStringCreateWithCString(
        None,
        bundle_identifier.encode("utf-8"),
        0x08000100,
    )
    if not bundle:
        print("targetedControlSent=false reason=bundle", file=sys.stderr)
        return 2

    try:
        client = adapter.findNowPlayingClient(bundle)
        origin = media_remote.MRMediaRemoteGetLocalOrigin()
        queue = dispatch.dispatch_get_global_queue(0, 0)
        if not client or not origin or not queue:
            print("targetedControlSent=false reason=client", file=sys.stderr)
            return 2

        media_remote.MRMediaRemoteSendCommandToClient(
            command,
            None,
            origin,
            client,
            queue,
            None,
        )
        time.sleep(0.02)
        print("targetedControlSent=true")
        return 0
    finally:
        core_foundation.CFRelease(bundle)


if __name__ == "__main__":
    raise SystemExit(main())
