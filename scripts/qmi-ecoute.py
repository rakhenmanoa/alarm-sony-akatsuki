#!/usr/bin/env python3
"""qmi-ecoute.py — Annonce des services QMI sur le bus QRTR et journalise ce que le
modem leur demande. Outil de diagnostic pour le Xperia XZ3 sous Linux.

Sous LineageOS, des services Sony tournent côté Linux/Android et le modem s'en sert
(relevé du 11/10/2026, /sys/kernel/debug/msm_ipc_router/dump_servers) :

    227 (0xe3) ta_qmi_service   « TA QMI service »      (partition TA)
    228 (0xe4) ta_qmi_service   « MiscTA QMI service »
    229 (0xe5) sct_service
    230 (0xe6) mlog_qmi_service (journal du modem)

Sous Linux mainline, aucun ne répond. Ce script les annonce et affiche chaque
requête reçue (en-tête QMI + champs TLV en hexadécimal) ; il répond « échec / non
pris en charge » (QMI_RESULT_FAILURE, QMI_ERR_NOT_SUPPORTED) ou, avec --muet, ne
répond pas. But : savoir si le modem les interroge et avec quels messages.
Les messages du journal du modem (service 230, mlog) sont affichés en clair
(« [modem] fichier.c:ligne message ») et acquittés par un « succès ».

Usage (root, sous Arch, AVANT de démarrer le modem) :
    python3 qmi-ecoute.py                  # services Sony 227 à 230
    python3 qmi-ecoute.py 227 228 52:1:1   # service[:version[:instance]]
    python3 qmi-ecoute.py --muet           # ne répond jamais
"""
import select
import socket
import struct
import sys
import time

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


def parse_spec(s):
    p = [int(x, 0) for x in s.split(":")]
    return p[0], (p[1] if len(p) > 1 else 1), (p[2] if len(p) > 2 else 0)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    muet = "--muet" in sys.argv
    if "-h" in sys.argv or "--help" in sys.argv:
        print(__doc__)
        return
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
