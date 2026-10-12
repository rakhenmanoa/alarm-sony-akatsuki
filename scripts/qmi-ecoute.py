#!/usr/bin/env python3
"""qmi-ecoute.py — Annonce des services QMI sur le bus QRTR et journalise ce que le
modem leur demande. Outil de diagnostic pour le Xperia XZ3 sous Linux.

Sous LineageOS, des services Sony tournent côté Linux/Android et le modem s'en sert
(relevé du 11/10/2026, /sys/kernel/debug/msm_ipc_router/dump_servers) :

    227 (0xe3) ta_qmi_service   « TA QMI service »      (partition TA)
    228 (0xe4) ta_qmi_service   « MiscTA QMI service »
    229 (0xe5) sct_service
    230 (0xe6) mlog_qmi_service (journal du modem)

Sous Linux mainline, aucun ne répond. Ce script les annonce et :
  - MiscTA (228) : vrai service, qui lit une COPIE de la partition TA du téléphone
    (--ta, défaut /var/lib/miscta/ta.img, prise par scripts/copier-ta-adb.sh). Les
    écritures du modem vont dans /var/lib/miscta/ecrits/<unité>.bin (la copie de la
    TA n'est jamais modifiée) et sont relues en priorité. Sans copie de la TA :
    « unité introuvable » pour chaque lecture.
  - journal du modem (230, mlog) : affiché en clair (« [modem] fichier.c:ligne
    message ») et acquitté par un « succès » ;
  - les autres (TA 227, SCT 229) : requête journalisée (TLV en hexadécimal), réponse
    « échec / non pris en charge » (QMI_RESULT_FAILURE, QMI_ERR_NOT_SUPPORTED).
Avec --muet, aucune réponse n'est envoyée.

Format des messages MiscTA (tables IDL de ta_qmi_service, LineageOS 17.1 Sony) :
    0x0001 taille    requête TLV1 u32 unité          réponse TLV1 u32 code, TLV 0x10 u32 taille
    0x0002 lecture   requête TLV1 u32 unité          réponse TLV1 u32 code, TLV 0x10 u16 n + données (≤ 4096)
    0x0003 écriture  requête TLV1 u32 unité, TLV2 u16 n + données   réponse TLV1 u32 code
    0x0004 écriture « critique » (même format)       réponse TLV1 u32 code
    0x0005 vidage (flush), requête vide              réponse TLV1 u32 code
Codes (libmiscta) : 0 succès, 2 unité introuvable, 3 erreur, 4 tampon trop petit.
Pas de TLV 0x02 « résultat QMI » standard dans ces réponses.

Usage (root, sous Arch, AVANT de démarrer le modem) :
    python3 qmi-ecoute.py                  # services Sony 227 à 230
    python3 qmi-ecoute.py 227 228 52:1:1   # service[:version[:instance]]
    python3 qmi-ecoute.py --muet           # ne répond jamais
    python3 qmi-ecoute.py --ta=/chemin/ta.img
    python3 qmi-ecoute.py --ta-lister [--ta=…]       # contenu de la copie de la TA
    python3 qmi-ecoute.py --ta-unite=0x7d3 [--ta=…]  # une unité MiscTA en hexadécimal
"""
import os
import select
import socket
import struct
import sys
import time
import zlib

AF_QIPCRTR = getattr(socket, "AF_QIPCRTR", 42)
QRTR_PORT_CTRL = 0xFFFFFFFE
QRTR_TYPE_NEW_SERVER = 4
QRTR_TYPE_DEL_SERVER = 5

NOMS = {227: "Sony TA", 228: "Sony MiscTA", 229: "Sony SCT", 230: "Sony mlog",
        28: "RFSA", 52: "memshare", 53: "periph. manager", 1053: "inconnu 1053"}
TYPES = {0: "requête", 2: "réponse", 4: "indication"}


def log(msg):
    print("%s %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def tlvs(data):
    out, i = [], 0
    while i + 3 <= len(data):
        t, n = data[i], struct.unpack_from("<H", data, i + 1)[0]
        v = data[i + 3:i + 3 + n]
        out.append("TLV 0x%02x (%d o) : %s" % (t, n, v.hex(" ") if n <= 64 else v[:64].hex(" ") + " …"))
        i += 3 + n
    if i != len(data):
        out.append("reste : " + data[i:].hex(" "))
    return out


def champs(data):
    """TLV → {type: valeur}"""
    d, i = {}, 0
    while i + 3 <= len(data):
        t, n = data[i], struct.unpack_from("<H", data, i + 1)[0]
        d[t] = data[i + 3:i + 3 + n]
        i += 3 + n
    return d


def chaine(v):
    """Chaîne QMI : longueur sur 2 octets puis texte."""
    if v and len(v) >= 2:
        n = struct.unpack_from("<H", v)[0]
        if n == len(v) - 2:
            return v[2:].decode("ascii", "replace")
    return v.hex(" ") if v else ""


# ---------------------------------------------------------------------------
# Partition TA (« Trim Area ») de Sony — format relevé dans tad (LineageOS) :
#   blocs de 128 Kio ; en-tête de bloc de 12 octets :
#     +0 u32 0x3BF8E9C1 (magique)   +4 u32 Adler-32 de [+8, fin utile[
#     +8 u8 type   +9 u8 n° du bloc   +0xa u8 partition (1 : clés, 2 : misc)
#     +0xb u8 pages de 2 Kio utilisées (fin utile = (n + 1) × 2 Kio ; 0xff : tout le bloc)
#   puis les unités : en-tête de 16 octets {u32 id, u32 taille, u32 0x3BF8E9C1,
#   u32 réservé}, données, bourrage jusqu'au multiple de 4 suivant.
# MiscTA = partition 2. Seule la lecture est faite ici : le fichier n'est jamais écrit.
# ---------------------------------------------------------------------------
TA_MAGIQUE = 0x3BF8E9C1
TA_BLOC = 0x20000
TA_PART_MISC = 2


class TA:
    def __init__(self, chemin):
        self.chemin = chemin
        self.blocs = []      # (décalage, type, n°, partition, fin utile, somme correcte)
        self.unites = {}     # partition → {id: données}
        with open(chemin, "rb") as f:
            img = f.read()
        if len(img) % TA_BLOC:
            raise ValueError("taille %d : pas un multiple de 128 Kio" % len(img))
        for off in range(0, len(img), TA_BLOC):
            b = img[off:off + TA_BLOC]
            magique, somme, typ, num, part, pages = struct.unpack_from("<IIBBBB", b)
            if magique != TA_MAGIQUE:
                continue
            fin = TA_BLOC if pages == 0xFF else min(TA_BLOC, (pages << 11) + 0x800)
            ok = zlib.adler32(b[8:fin]) == somme
            self.blocs.append((off, typ, num, part, fin, ok))
            if not ok:
                continue  # bloc abîmé ou en cours d'écriture : ignoré, comme tad
            u = self.unites.setdefault(part, {})
            p = 0xC
            while p + 0x10 <= fin:
                uid, n, m, _ = struct.unpack_from("<IIII", b, p)
                if m != TA_MAGIQUE or p + 0x10 + n > fin:
                    break
                u.setdefault(uid, b[p + 0x10:p + 0x10 + n])  # le premier trouvé gagne
                p += 0x10 + ((n + 3) & ~3)

    def misc(self):
        return self.unites.get(TA_PART_MISC, {})


MISCTA_OK, MISCTA_INTROUVABLE, MISCTA_ERREUR, MISCTA_TROP_GRAND = 0, 2, 3, 4
MISCTA_MAX = 4096


class MiscTA:
    """Service MiscTA (228) : lit la copie de la TA, écrit à côté."""

    def __init__(self, ta_chemin, ecrits):
        self.ecrits = ecrits
        self.ta = None
        self.ta_chemin = ta_chemin
        try:
            self.ta = TA(ta_chemin)
            log("MiscTA : %s — %d unités dans la partition 2"
                % (ta_chemin, len(self.ta.misc())))
        except FileNotFoundError:
            log("MiscTA : %s absent — chaque lecture répondra « unité introuvable »" % ta_chemin)
        except (OSError, ValueError) as e:
            log("MiscTA : %s illisible (%s)" % (ta_chemin, e))

    def _ecrit(self, unite):
        return os.path.join(self.ecrits, "%08x.bin" % unite)

    def lire(self, unite):
        try:
            with open(self._ecrit(unite), "rb") as f:
                return f.read()
        except OSError:
            pass
        return self.ta.misc().get(unite) if self.ta else None

    def ecrire(self, unite, donnees):
        try:
            os.makedirs(self.ecrits, mode=0o700, exist_ok=True)
            tmp = self._ecrit(unite) + ".tmp"
            with open(tmp, "wb") as f:
                f.write(donnees)
            os.replace(tmp, self._ecrit(unite))
            return MISCTA_OK
        except OSError as e:
            log("      écriture impossible : %s" % e)
            return MISCTA_ERREUR

    def repondre(self, msg, corps):
        """Corps (TLV) de la réponse au message msg, et une ligne de journal."""
        c = champs(corps)
        u = struct.unpack_from("<I", c[1])[0] if len(c.get(1, b"")) == 4 else None
        code = lambda v: struct.pack("<BHI", 0x01, 4, v)
        if msg in (1, 2) and u is None:
            return code(MISCTA_ERREUR), "requête sans unité"
        if msg == 1:   # taille ; une unité absente a la taille 0 (comme libmiscta)
            d = self.lire(u)
            n = len(d) if d is not None else 0
            return code(MISCTA_OK) + struct.pack("<BHI", 0x10, 4, n), "taille 0x%x → %d" % (u, n)
        if msg == 2:   # lecture
            d = self.lire(u)
            if d is None:
                return code(MISCTA_INTROUVABLE), "lecture 0x%x → introuvable" % u
            if len(d) > MISCTA_MAX:
                return code(MISCTA_TROP_GRAND), "lecture 0x%x → trop grand (%d)" % (u, len(d))
            return (code(MISCTA_OK) + struct.pack("<BHH", 0x10, 2 + len(d), len(d)) + d,
                    "lecture 0x%x → %d o : %s" % (u, len(d), apercu(d)))
        if msg in (3, 4):  # écriture (normale, « critique »)
            v = c.get(2, b"")
            if u is None or len(v) < 2 or struct.unpack_from("<H", v)[0] != len(v) - 2:
                return code(MISCTA_ERREUR), "écriture mal formée"
            d = v[2:]
            return code(self.ecrire(u, d)), "écriture 0x%x ← %d o : %s" % (u, len(d), apercu(d))
        if msg == 5:
            return code(MISCTA_OK), "vidage"
        return None, "message 0x%04x inconnu" % msg


def apercu(d):
    if d.rstrip(b"\0") and all(32 <= x < 127 for x in d.rstrip(b"\0")):
        t = d.rstrip(b"\0").decode("ascii")
        return repr(t[:60]) + (" …" if len(t) > 60 else "")
    return d[:32].hex(" ") + (" …" if len(d) > 32 else "")


def ta_lister(chemin, unite=None):
    ta = TA(chemin)
    if unite is not None:
        d = ta.misc().get(unite)
        if d is None:
            sys.exit("unité 0x%x absente de la partition 2" % unite)
        for i in range(0, len(d), 16):
            print("%04x  %s" % (i, d[i:i + 16].hex(" ")))
        return
    print("%s : %d blocs TA" % (chemin, len(ta.blocs)))
    for off, typ, num, part, fin, ok in ta.blocs:
        print("  bloc @0x%06x type %d n°%d partition %d, %d o utiles, somme %s"
              % (off, typ, num, part, fin, "correcte" if ok else "FAUSSE (ignoré)"))
    for part, u in sorted(ta.unites.items()):
        print("partition %d : %d unités" % (part, len(u)))
        if part == TA_PART_MISC:  # la partition 1 (clés) n'est jamais affichée
            for uid in sorted(u):
                print("  0x%05x %5d o  %s" % (uid, len(u[uid]), apercu(u[uid])))


def parse_spec(s):
    p = [int(x, 0) for x in s.split(":")]
    return p[0], (p[1] if len(p) > 1 else 1), (p[2] if len(p) > 2 else 0)


def option(nom, defaut=None):
    for a in sys.argv[1:]:
        if a.startswith(nom + "="):
            return a.split("=", 1)[1]
    return defaut


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    muet = "--muet" in sys.argv
    if "-h" in sys.argv or "--help" in sys.argv:
        print(__doc__)
        return
    ta_chemin = option("--ta", "/var/lib/miscta/ta.img")
    if "--ta-lister" in sys.argv or option("--ta-unite"):
        u = option("--ta-unite")
        ta_lister(ta_chemin, int(u, 0) if u else None)
        return
    miscta = MiscTA(ta_chemin, option("--ecrits", "/var/lib/miscta/ecrits"))
    specs = [parse_spec(a) for a in args] or [(227, 1, 0), (228, 1, 0), (229, 1, 0), (230, 1, 0)]

    socks = {}
    for svc, ver, inst in specs:
        s = socket.socket(AF_QIPCRTR, socket.SOCK_DGRAM)
        node, port = s.getsockname()
        pkt = struct.pack("<5I", QRTR_TYPE_NEW_SERVER, svc, (inst << 8) | ver, 0, 0)
        s.sendto(pkt, (node, QRTR_PORT_CTRL))
        socks[s.fileno()] = (s, svc, ver, inst)
        log("annoncé : service %d (%s) version %d instance %d — %d:%d"
            % (svc, NOMS.get(svc, "?"), ver, inst, node, port))
    log("en attente (Ctrl+C pour arrêter)%s" % (" — mode muet" if muet else ""))

    try:
        while True:
            r, _, _ = select.select(list(socks), [], [])
            for fd in r:
                s, svc, ver, inst = socks[fd]
                data, (snode, sport) = s.recvfrom(65536)
                if sport == QRTR_PORT_CTRL:
                    continue  # messages de contrôle du bus (bye, del_client…)
                if len(data) < 7:
                    log("[%d] %d:%d → paquet court : %s" % (svc, snode, sport, data.hex(" ")))
                    continue
                typ, txn, msg, ln = struct.unpack_from("<BHHH", data)
                corps = data[7:7 + ln]
                if svc == 230 and typ == 0 and msg == 1:
                    # Journal du modem (mlog) : une ligne lisible, réponse « succès »
                    c = champs(corps)
                    ligne = struct.unpack_from("<I", c[4])[0] if len(c.get(4, b"")) == 4 else "?"
                    log("[modem] %s:%s %s" % (chaine(c.get(3)), ligne, chaine(c.get(6))))
                    if not muet:
                        s.sendto(struct.pack("<BHHH", 2, txn, msg, 7) + struct.pack("<BHHH", 0x02, 4, 0, 0),
                                 (snode, sport))
                    continue
                if svc == 228 and typ == 0:
                    rep, ligne = miscta.repondre(msg, corps)
                    log("[MiscTA] %s" % ligne)
                    if rep is not None and not muet:
                        s.sendto(struct.pack("<BHHH", 2, txn, msg, len(rep)) + rep, (snode, sport))
                    if rep is not None:
                        continue
                log("[%d %s] %d:%d → %s txn=%d msg=0x%04x (%d o)"
                    % (svc, NOMS.get(svc, "?"), snode, sport, TYPES.get(typ, typ), txn, msg, ln))
                for line in tlvs(corps):
                    log("      " + line)
                if typ == 0 and not muet:
                    # QMI_RESULT_FAILURE (1), QMI_ERR_NOT_SUPPORTED (0x5e)
                    rep = struct.pack("<BHHH", 2, txn, msg, 7) + struct.pack("<BHHH", 0x02, 4, 1, 0x5E)
                    s.sendto(rep, (snode, sport))
                    log("      ← réponse : échec, non pris en charge")
    except KeyboardInterrupt:
        pass
    finally:
        for s, svc, ver, inst in socks.values():
            node, port = s.getsockname()
            try:
                s.sendto(struct.pack("<5I", QRTR_TYPE_DEL_SERVER, svc, (inst << 8) | ver, node, port),
                         (node, QRTR_PORT_CTRL))
            except OSError:
                pass
            s.close()


if __name__ == "__main__":
    main()
