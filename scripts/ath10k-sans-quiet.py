#!/usr/bin/env python3
"""ath10k-sans-quiet.py <ath10k_core.ko> <sortie.ko>

⚠️ INUTILISABLE avec le noyau pmOS 7.1-rc1 : son verrouillage (lockdown « integrity »,
forcé à la compilation) refuse tout module non signé, et ath10k_core ne se charge
plus. Utile seulement avec un noyau sans ce verrouillage ou qu'on signe soi-même.

Corrige le module ath10k_core du noyau pmOS pour que le Wi-Fi du Xperia XZ3 ne
plante plus : la fonction ath10k_thermal_set_throttling() rend la main tout de
suite, sans envoyer la commande WMI « quiet mode ».

Pourquoi : le firmware Wi-Fi de Sony (WLAN.HL.2.0.c12) annonce le service
THERM_THROT ; ath10k lui envoie alors « quiet mode » juste avant de créer
l'interface, et le firmware plante (« WLAN RT … PC=b001ba04 »), entraînant le
modem avec lui (constaté le 11/10/2026). Même bug et même correctif que le patch
« ath10k: skip quiet mode for WCN3990 to prevent firmware crash » (Malte
Schababerle, liste ath10k, 22/03/2026), pas encore dans le noyau pmOS 7.1-rc1.

Effet : la première instruction utile de la fonction (après « bti c » et les deux
« nop » réservés au traçage) devient « ret ». La fonction ne renvoie rien : rendre
la main tôt revient exactement à ne pas envoyer la commande. La signature du module
est retirée (elle ne serait plus valide) : le noyau le charge quand même
(CONFIG_MODULE_SIG_FORCE n'est pas activé), en le signalant comme non signé.

Le script vérifie les octets attendus avant de modifier quoi que ce soit, et
refuse sinon (module d'une autre version).
"""
import struct
import sys

SYMBOLE = b"ath10k_thermal_set_throttling"
BTI_C, NOP, RET = 0xD503245F, 0xD503201F, 0xD65F03C0
MARQUE = b"~Module signature appended~\n"


def sections(elf):
    shoff, = struct.unpack_from("<Q", elf, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", elf, 0x3A)
    out = []
    for i in range(shnum):
        o = shoff + i * shentsize
        name, typ, flags, addr, off, size, link, info, align, entsize = struct.unpack_from("<IIQQQQIIQQ", elf, o)
        out.append(dict(type=typ, off=off, size=size, link=link, entsize=entsize))
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    elf = bytearray(open(sys.argv[1], "rb").read())
    if elf[:4] != b"\x7fELF" or elf[4] != 2 or struct.unpack_from("<H", elf, 0x12)[0] != 183:
        raise SystemExit("pas un module ELF64 aarch64")

    # Signature ajoutée en fin de fichier : on la retire
    if elf.endswith(MARQUE):
        siglen, = struct.unpack_from(">I", elf, len(elf) - len(MARQUE) - 4)
        elf = elf[:len(elf) - len(MARQUE) - 12 - siglen]

    secs = sections(elf)
    symtab = next(s for s in secs if s["type"] == 2)  # SHT_SYMTAB
    strtab = secs[symtab["link"]]
    cible = None
    for i in range(symtab["size"] // 24):
        nom, info, other, shndx, val, taille = struct.unpack_from("<IBBHQQ", elf, symtab["off"] + i * 24)
        debut = strtab["off"] + nom
        if elf[debut:debut + len(SYMBOLE) + 1] == SYMBOLE + b"\0":
            cible = (shndx, val)
            break
    if not cible:
        raise SystemExit("symbole %s introuvable" % SYMBOLE.decode())
    off = secs[cible[0]]["off"] + cible[1]
    mots = struct.unpack_from("<4I", elf, off)
    if mots[3] == RET:
        raise SystemExit("module déjà corrigé")
    # attendu : bti c ; nop ; nop ; ldr x8, [x0, #…]
    if mots[0] != BTI_C or mots[1] != NOP or mots[2] != NOP or (mots[3] & 0xFFC003FF) != 0xF9400008:
        raise SystemExit("début de fonction inattendu (%s) : autre version du module, rien modifié"
                         % " ".join("%08x" % m for m in mots))
    struct.pack_into("<I", elf, off + 12, RET)
    open(sys.argv[2], "wb").write(elf)
    print("%s : ath10k_thermal_set_throttling() neutralisée (décalage 0x%x)" % (sys.argv[2], off + 12))


if __name__ == "__main__":
    main()
