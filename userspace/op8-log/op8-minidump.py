#!/usr/bin/env python3
# op8-log (armdeck): a minimal Breakpad minidump reader for ARM64, with no dependencies.
# Shows the signal, the address, module + offset for the PC and LR of the crashed thread, and the
# likely return addresses found by scanning the stack (module + offset).
# Usage: python3 op8-minidump.py /tmp/dumps/crash_XXXX.dmp
import struct
import sys

SIGNALS = {4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE", 11: "SIGSEGV"}


def main(path):
    d = open(path, "rb").read()
    sig, ver, nstreams, dir_rva = struct.unpack_from("<IIII", d, 0)
    if sig != 0x504D444D:
        sys.exit("not a minidump")
    streams = {}
    for i in range(nstreams):
        stype, size, rva = struct.unpack_from("<III", d, dir_rva + 12 * i)
        streams[stype] = (size, rva)

    def mdstring(rva):
        n = struct.unpack_from("<I", d, rva)[0]
        return d[rva + 4:rva + 4 + n].decode("utf-16-le", "replace")

    # modules: (base, size, name)
    mods = []
    if 4 in streams:
        _, rva = streams[4]
        n = struct.unpack_from("<I", d, rva)[0]
        for i in range(n):
            o = rva + 4 + 108 * i
            base, size = struct.unpack_from("<QI", d, o)
            name_rva = struct.unpack_from("<I", d, o + 20)[0]
            mods.append((base, size, mdstring(name_rva)))

    def where(addr):
        for base, size, name in mods:
            if base <= addr < base + size:
                return "%s+0x%x" % (name.rsplit("/", 1)[-1], addr - base)
        return "?"

    if 6 not in streams:
        sys.exit("no exception in the dump")
    _, rva = streams[6]
    tid = struct.unpack_from("<I", d, rva)[0]
    code, flags, rec, addr = struct.unpack_from("<IIQQ", d, rva + 8)
    ctx_size, ctx_rva = struct.unpack_from("<II", d, rva + 8 + 152)
    print("thread %d: signal %s (%d), code/flags 0x%x, address 0x%x" % (
        tid, SIGNALS.get(code, "?"), code, flags, addr))

    # Breakpad ARM64 context: flags(4) cpsr(4) x0..x30 sp pc
    regs = struct.unpack_from("<II31QQQ", d, ctx_rva)
    x = regs[2:33]
    sp, pc = regs[33], regs[34]
    print("PC  0x%x  %s" % (pc, where(pc)))
    print("LR  0x%x  %s" % (x[30], where(x[30])))
    print("SP  0x%x" % sp)

    # the stack of the crashed thread (thread list, stream 3)
    if 3 in streams:
        _, rva = streams[3]
        n = struct.unpack_from("<I", d, rva)[0]
        for i in range(n):
            o = rva + 4 + 48 * i
            t = struct.unpack_from("<I", d, o)[0]
            if t != tid:
                continue
            start, msize, mrva = struct.unpack_from("<QII", d, o + 24)
            print("stack: 0x%x, %d bytes; likely return addresses (scan):" % (start, msize))
            shown = 0
            for off in range(max(0, sp - start), msize - 7, 8):
                v = struct.unpack_from("<Q", d, mrva + off)[0]
                w = where(v)
                if w != "?" and ".so" in w or w.startswith(("steam", "streaming_client")):
                    print("  [sp+0x%x] 0x%x  %s" % (start + off - sp, v, w))
                    shown += 1
                    if shown >= 25:
                        break

    print("modules loaded: %d" % len(mods))


if __name__ == "__main__":
    main(sys.argv[1])
