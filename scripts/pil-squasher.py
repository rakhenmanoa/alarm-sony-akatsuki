#!/usr/bin/env python3
"""pil-squasher.py <sortie.mbn> <entrée.mdt>

Recolle un firmware Qualcomm découpé à la manière d'Android (« split ») en un seul
fichier ELF, comme l'outil pil-squasher de Linaro :

  entrée.mdt          en-tête ELF + table des segments (+ segment de hachage)
  entrée.b00, .b01…   contenu de chaque segment n, à placer à son p_offset

Le noyau mainline (qcom_mdt_loader) charge directement le fichier .mbn obtenu.
ELF 32 et 64 bits, petit boutiste. Les segments sans fichier .bNN sont repris du
.mdt s'ils y sont entièrement contenus ; sinon c'est une erreur.
"""
import os
import struct
import sys


def phdrs(mdt):
    if mdt[:4] != b"\x7fELF":
        raise SystemExit("pas un fichier ELF : en-tête .mdt invalide")
    cls = mdt[4]
    if mdt[5] != 1:
        raise SystemExit("ELF gros-boutiste non pris en charge")
    if cls == 1:  # ELF32
        e_phoff, = struct.unpack_from("<I", mdt, 0x1C)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x2A)
        fmt = "<IIIIIIII"  # type offset vaddr paddr filesz memsz flags align
        get = lambda t: (t[1], t[4])
    elif cls == 2:  # ELF64
        e_phoff, = struct.unpack_from("<Q", mdt, 0x20)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x36)
        fmt = "<IIQQQQQQ"  # type flags offset vaddr paddr filesz memsz align
        get = lambda t: (t[2], t[5])
    else:
        raise SystemExit("classe ELF inconnue")
    out = []
    for i in range(e_phnum):
        t = struct.unpack_from(fmt, mdt, e_phoff + i * e_phentsize)
        out.append(get(t))  # (p_offset, p_filesz)
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    dst, src = sys.argv[1], sys.argv[2]
    if not src.endswith(".mdt"):
        raise SystemExit("l'entrée doit être un fichier .mdt")
    base = src[:-4]
    mdt = open(src, "rb").read()
    segs = phdrs(mdt)
    size = max([len(mdt)] + [o + s for o, s in segs if s])
    img = bytearray(size)
    img[:len(mdt)] = mdt
    for i, (off, sz) in enumerate(segs):
        if not sz:
            continue
        part = "%s.b%02d" % (base, i)
        if os.path.exists(part):
            data = open(part, "rb").read()
            if len(data) != sz:
                raise SystemExit("%s : %d octets, %d attendus" % (part, len(data), sz))
        elif off + sz <= len(mdt):
            data = mdt[off:off + sz]
        else:
            raise SystemExit("segment %d manquant (%s absent)" % (i, part))
        img[off:off + sz] = data
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(img)
    os.replace(tmp, dst)


if __name__ == "__main__":
    main()
