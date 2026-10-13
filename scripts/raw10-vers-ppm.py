#!/usr/bin/env python3
"""raw10-vers-ppm.py — Aperçu d'une image brute RAW10 compactée (MIPI, « pRAA »),
sans dépendance : dématriçage grossier par blocs 2×2, image ÷ 4, gain auto.

  python3 raw10-vers-ppm.py imx400-2528x1896.raw 2528 1896 [images] [ordre] > apercu.ppm

images : nombre d'images dans le fichier (défaut 4, la dernière est convertie) ;
ordre  : RGGB (défaut), GRBG, GBRG ou BGGR.
"""
import sys

f, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
n = int(sys.argv[4]) if len(sys.argv) > 4 else 4
ordre = (sys.argv[5] if len(sys.argv) > 5 else "RGGB").upper()
d = open(f, "rb").read()
taille = len(d) // n
pas = taille // H                      # octets par ligne (avec bourrage)
img = d[taille * (n - 1): taille * n]


def px(x, y):                          # 8 bits de poids fort
    return img[y * pas + (x // 4) * 5 + (x % 4)]


pos = {c: [] for c in "RGB"}
for i, c in enumerate(ordre):
    pos[c].append((i % 2, i // 2))
R = 2                                  # réduction (image ÷ 4)
w, h = W // (2 * R), H // (2 * R)
pix = []
for by in range(h):
    for bx in range(w):
        x0, y0 = bx * 2 * R, by * 2 * R
        v = []
        for c in "RGB":
            v.append(sum(px(x0 + dx, y0 + dy) for dx, dy in pos[c]) / len(pos[c]))
        pix.append(v)
m = [sum(p[i] for p in pix) / len(pix) for i in range(3)]
g = [128 / max(x, 1) for x in m]       # balance des blancs « monde gris » + exposition
sys.stderr.write("moyennes R G B : %.1f %.1f %.1f ; pas %d octets/ligne\n" % (*m, pas))
out = bytearray(b"P6\n%d %d\n255\n" % (w, h))
for p in pix:
    for i in range(3):
        out.append(min(255, int((p[i] * g[i] / 255) ** (1 / 2.2) * 255)))
sys.stdout.buffer.write(out)
