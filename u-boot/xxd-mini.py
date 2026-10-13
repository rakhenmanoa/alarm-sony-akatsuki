#!/usr/bin/env python3
# mini xxd : seulement « xxd -i » (lecture sur l'entrée standard), pour U-Boot
import sys
d = sys.stdin.buffer.read()
out = []
for i in range(0, len(d), 12):
    out.append("  " + ", ".join("0x%02x" % b for b in d[i:i+12]))
sys.stdout.write(",\n".join(out) + ("\n" if d else ""))
