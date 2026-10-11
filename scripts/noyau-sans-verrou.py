#!/usr/bin/env python3
"""noyau-sans-verrou.py <vmlinuz|Image> <sortie-vmlinuz>

Retire le verrouillage (« lockdown ») forcé à la compilation du noyau pmOS
linux-postmarketos-qcom-sdm845 (CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y), pour
pouvoir charger un module corrigé par nos soins (ath10k_core sans « quiet mode »,
voir ath10k-sans-quiet.py) : ce verrouillage refuse tout module non signé par la
clé de postmarketOS, et ne peut être levé ni par la ligne de commande ni à chaud.

Dans lockdown_lsm_init() (security/lockdown/lockdown.c), le noyau compilé fait :

    ldr  w9, [x8, #…]        ; niveau actuel (kernel_locked_down)
    cmp  w9, #0x14
    b.ls verrouiller         ; → mov w9, #0x15 (LOCKDOWN_INTEGRITY_MAX), printk…
    …                        ; enregistrement normal du module de sécurité

Le « b.ls » devient « nop » : le niveau reste « aucun verrouillage », le reste de la
fonction (enregistrement des points d'accroche) est inchangé. Le noyau charge alors
les modules non signés en le signalant (« module verification failed … tainting »).

Contrepartie : root peut charger n'importe quel module et lire la mémoire du noyau,
comme sur la plupart des distributions sans démarrage sécurisé.

Le motif est cherché dans l'image décompressée ; s'il n'est pas trouvé exactement
une fois, ou si la cible du saut n'est pas « mov w9, #0x15 », rien n'est modifié.
"""
import gzip
import struct
import sys

CMP_W9_20 = 0x7100513F
B_LS_30 = 0x54000189      # b.ls +0x30
MOV_W9_21 = 0x528002A9
NOP = 0xD503201F


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    brut = open(sys.argv[1], "rb").read()
    img = bytearray(gzip.decompress(brut) if brut[:2] == b"\x1f\x8b" else brut)
    if img[0x38:0x3C] != b"ARM\x64":
        raise SystemExit("pas une image de noyau arm64")
    motif = struct.pack("<II", CMP_W9_20, B_LS_30)
    n = img.count(motif)
    if n != 1:
        deja = img.count(struct.pack("<II", CMP_W9_20, NOP))
        raise SystemExit("déjà corrigé" if deja == 1 and n == 0 else
                         "motif trouvé %d fois : autre version du noyau, rien modifié" % n)
    i = img.find(motif)
    cible = struct.unpack_from("<I", img, i + 4 + 0x30)[0]
    if cible != MOV_W9_21:
        raise SystemExit("cible du saut inattendue (%08x) : rien modifié" % cible)
    struct.pack_into("<I", img, i + 4, NOP)
    with open(sys.argv[2], "wb") as f:
        f.write(gzip.compress(bytes(img), compresslevel=9, mtime=0))
    print("%s : verrouillage retiré (décalage 0x%x de l'image)" % (sys.argv[2], i + 4))


if __name__ == "__main__":
    main()
