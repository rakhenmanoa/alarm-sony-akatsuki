#!/usr/bin/env python3
"""imx400-sequences.py — Construit le fichier de séquences du pilote imx400
(modules/imx400) à partir d'une capture faite sous LineageOS :

    scripts/capturer-camera-adb.sh arriere      → capture-camera/…registres.txt
    scripts/imx400-sequences.py capture-camera/…registres.txt imx400-akatsuki.bin

Les séquences (initialisation du capteur, réglages de chaque mode) sont celles que
le pilote de Sony écrit sur VOTRE téléphone : elles ne sont pas publiées dans le
dépôt. Le fichier va dans /usr/lib/firmware/sony/imx400-akatsuki.bin.

Découpage de la capture (écritures vers l'esclave 0x20 = 0x10 en 7 bits) :
  - init : de la 1re écriture de 0x0136 (fréquence d'horloge) jusqu'à la 2e ;
  - mode : de chaque 0x0136 suivant jusqu'à la mise en flux (0x0100 = 01) ;
    un mode par taille de sortie (0x034c/0x034e), le premier rencontré.

Format (petit-boutiste) : « IMX400SQ », u32 version (1), u32 nombre de blocs ;
puis par bloc : nom[16], u16 largeur, hauteur, llp, fll, x0, y0, x1, y1,
u32 pixel_rate, u32 link_freq, u32 longueur ; puis les entrées
[u16 registre (gros-boutiste)][u8 n][n octets]. Bloc init : géométrie à 0.
"""
import struct
import sys

ESCLAVE = 0x20
XCLK_SONY = 8_000_000      # horloge MCLK0 utilisée par Sony (0x0136 = 0x0800)
PIX_PAR_HORLOGE = 4        # vérifié sur la capture : 5744 × 15475 / 2,6667 GHz = 33,33 ms (30 i/s mesurés)


def lire(fichier):
    ecr = []
    for l in open(fichier, errors="replace"):
        c = l.split()
        if len(c) < 4 or c[1] == "#" or l.startswith("#"):
            continue
        try:
            t, esc, adr = float(c[0]), int(c[1], 16), int(c[2], 16)
            octets = bytes(int(x, 16) for x in c[3:])
        except ValueError:
            continue
        if esc == ESCLAVE:
            ecr.append((t, adr, octets))
    return ecr


def etat(ecritures):
    r = {}
    for _, adr, o in ecritures:
        for i, v in enumerate(o):
            r[adr + i] = v
    return r


def r16(r, a):
    return (r.get(a, 0) << 8) | r.get(a + 1, 0)


def premier16(ecritures, a):
    for _, adr, o in ecritures:
        if adr <= a and a + 1 < adr + len(o):
            return (o[a - adr] << 8) | o[a - adr + 1]
    return 0


def entrees(ecritures):
    b = bytearray()
    for _, adr, o in ecritures:
        for i in range(0, len(o), 255):
            m = o[i:i + 255]
            b += struct.pack(">HB", adr + i, len(m)) + m
    return bytes(b)


def bloc(nom, ecr, geo=None):
    g = geo or (0,) * 10
    corps = entrees(ecr)
    return struct.pack("<16s8HIII", nom.encode()[:15], *g, len(corps)) + corps


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ecr = lire(sys.argv[1])
    debuts = [i for i, (_, a, _) in enumerate(ecr) if a == 0x0136]
    if len(debuts) < 2:
        sys.exit("capture incomplète : moins de deux écritures de 0x0136 (ouvrir l'appareil photo arrière)")
    blocs = [bloc("init", ecr[debuts[0]:debuts[1]])]
    print("init : %d écritures, %d octets" % (debuts[1] - debuts[0], sum(len(o) for _, _, o in ecr[debuts[0]:debuts[1]])))
    vus = set()
    for d in debuts[1:]:
        fin = next((j for j in range(d, len(ecr)) if ecr[j][1] == 0x0100 and ecr[j][2][:1] == b"\x01"), None)
        if fin is None:
            continue
        seg = ecr[d:fin]
        r = etat(seg)
        w, h = r16(r, 0x034c), r16(r, 0x034e)
        if (w, h) in vus or not w or not h:
            continue
        vus.add((w, h))
        llp, fll = r16(r, 0x0342), premier16(seg, 0x0340)
        x0, y0, x1, y1 = (r16(r, a) for a in (0x0344, 0x0346, 0x0348, 0x034a))
        pre, mult, vtpix = r16(r, 0x0304), r16(r, 0x0306), r16(r, 0x0300)
        oppre, opmult, opsys = r16(r, 0x030c), r16(r, 0x030e), r16(r, 0x030a)
        if r16(r, 0x0136) != 0x0800 or not (pre and vtpix and oppre and opsys):
            sys.exit("mode %dx%d : réglages d'horloge inattendus" % (w, h))
        pixel_rate = XCLK_SONY // pre * mult * PIX_PAR_HORLOGE // vtpix
        link_freq = XCLK_SONY // oppre * opmult // opsys // 2
        nom = "%dx%d" % (w, h)
        blocs.append(bloc(nom, seg, (w, h, llp, fll, x0, y0, x1, y1, pixel_rate, link_freq)))
        print("mode %-10s llp %d fll %d  recadrage (%d,%d)-(%d,%d)  binning %02x%02x  "
              "pixel_rate %d  link_freq %d  ~%.1f i/s  %d écritures" % (
                  nom, llp, fll, x0, y0, x1, y1, r.get(0x0900, 0), r.get(0x0901, 0),
                  pixel_rate, link_freq, pixel_rate / (llp * fll), len(seg)))
    with open(sys.argv[2], "wb") as f:
        f.write(b"IMX400SQ" + struct.pack("<II", 1, len(blocs)) + b"".join(blocs))
    print("→ %s (%d blocs)" % (sys.argv[2], len(blocs)))


if __name__ == "__main__":
    main()
