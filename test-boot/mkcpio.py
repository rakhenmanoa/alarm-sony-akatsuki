#!/usr/bin/env python3
"""mkcpio.py <dossier> > archive.cpio — archive cpio « newc » pour l'initramfs de test.

Contenu : les fichiers et dossiers de <dossier> (propriétaire root, /init exécutable),
plus /dev/console (périphérique caractère 5:1), /proc et /sys, ajoutés sans avoir
besoin des droits root.
"""
import os
import sys


def entry(out, name, mode, data=b"", rdev=(0, 0), ino=[1]):
    nb = name.encode() + b"\0"
    hdr = "070701" + "".join("%08X" % v for v in (
        ino[0], mode, 0, 0, 2 if mode & 0o040000 else 1, 0, len(data),
        0, 0, rdev[0], rdev[1], len(nb), 0))
    ino[0] += 1
    out.write(hdr.encode() + nb)
    out.write(b"\0" * ((4 - (110 + len(nb)) % 4) % 4))
    out.write(data)
    out.write(b"\0" * ((4 - len(data) % 4) % 4))


def main():
    root = sys.argv[1]
    out = sys.stdout.buffer
    entry(out, "dev", 0o040755)
    entry(out, "dev/console", 0o020600, rdev=(5, 1))
    entry(out, "proc", 0o040755)
    entry(out, "sys", 0o040755)
    for d, dirs, files in os.walk(root):
        dirs.sort()
        rel = os.path.relpath(d, root)
        if rel != ".":
            entry(out, rel, 0o040755)
        for f in sorted(files):
            p = os.path.join(d, f)
            name = os.path.normpath(os.path.join(rel, f))
            mode = 0o100755 if name == "init" else 0o100644
            with open(p, "rb") as fh:
                entry(out, name, mode, fh.read())
    entry(out, "TRAILER!!!", 0)


if __name__ == "__main__":
    main()
