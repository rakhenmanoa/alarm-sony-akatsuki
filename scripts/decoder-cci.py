#!/usr/bin/env python3
"""decoder-cci.py — Reconstitue les écritures I2C (registre, valeur) d'un capteur
caméra à partir du journal du noyau de LineageOS, capturé avec le débogage CCI :

    echo 0x4000 > /sys/module/cam_debug_util/parameters/debug_mdl   (CAM_CCI)

Le pilote CCI de Qualcomm (cam_cci_core.c, cam_cci_data_queue) journalise alors,
pour chaque paquet envoyé au contrôleur :
    cmd_size N addr 0xAAAA data 0xVV                  (1er registre du paquet)
    LOAD_DATA_ADDR 0xWWWWWWWW, q: Q, len:L, cnt: C    (mots du paquet, petit-boutiste)
    CCI_I2C_M0_Q0_LOAD_DATA_ADDR:val 0xOFF:0xVAL      (SET_PARAM : adresse esclave)
    CCI_I2C_M0_Q0_LOAD_DATA_ADDR 0xVAL                (attente entre deux paquets)

Paquet = octet 0 : (nombre d'octets suivants << 4) | 9 (WRITE) — 0xF9 = 11 octets et
le paquet suivant continue sans adresse (écriture séquentielle) —, puis l'adresse du
registre (2 octets, sauf continuation), puis les données (1 octet par registre).

Usage : decoder-cci.py imx400-cci.txt [--esclave 0x34] [--brut]
Sortie : « temps  esclave  registre  valeur(s) », un bloc par écriture contiguë.
"""
import argparse
import re
import sys

RE_TEMPS = re.compile(r"^\s*(?:<\d+>)?\[\s*([0-9.]+)\]")
RE_ANCRE = re.compile(r"cam_cci_data_queue: \d+: cmd_size (\d+) addr 0x([0-9a-fA-F]+) data 0x([0-9a-fA-F]+)")
RE_MOT = re.compile(r"cam_cci_data_queue: \d+: LOAD_DATA_ADDR 0x([0-9a-fA-F]+), q: (\d+), len:(\d+)")
RE_PARAM = re.compile(r"LOAD_DATA_ADDR:val 0x([0-9a-fA-F]+):0x([0-9a-fA-F]+)")
RE_ATTENTE = re.compile(r"cam_cci_data_queue: \d+: CCI_I2C_M0_Q0_LOAD_DATA_ADDR 0x([0-9a-fA-F]+)\s*$")
RE_SONY = re.compile(r"sony_camera_\w+: (sensor power (?:up|down) \d+|sensor I2C read id=\d+|sensor eeprom get id=\d+)")

CCI_I2C_WRITE_CMD = 9
CCI_I2C_SET_PARAM_CMD = 1
CCI_I2C_M0_Q0_LOAD_DATA_ADDR = 0x110  # cam_cci_hwreg.h (seul le décalage master/queue sert)


class Decodeur:
    def __init__(self):
        self.ecritures = []          # (temps, esclave, registre, valeur)
        self.evenements = []         # (temps, texte)
        self.esclave = {}            # file (master*2+queue) -> adresse 8 bits
        self.file_courante = None
        self.paquet = None           # [temps, adresse d'ancrage, mots, mots attendus]
        self.suite = {}              # file -> le paquet précédent annonçait une continuation
        self.anomalies = 0

    def fin_paquet(self):
        p = self.paquet
        self.paquet = None
        if p is None:
            return
        temps, ancre, mots, file_ = p
        octets = b"".join(m.to_bytes(4, "little") for m in mots)
        if not octets or octets[0] & 0x0F != CCI_I2C_WRITE_CMD:
            self.anomalies += 1
            return
        n = octets[0] >> 4
        continuation = n == 0xF
        if continuation:
            n = 11
        corps = octets[1:1 + n]
        if len(corps) < n:
            self.anomalies += 1
            return
        if not self.suite.get(file_, False):
            adr = (corps[0] << 8) | corps[1]
            if adr != ancre:
                self.anomalies += 1
            corps = corps[2:]
        esc = self.esclave.get(file_)
        for i, v in enumerate(corps):
            self.ecritures.append((temps, esc, ancre + i, v))
        self.suite[file_] = continuation

    def ligne(self, l):
        m = RE_TEMPS.match(l)
        temps = float(m.group(1)) if m else 0.0
        m = RE_SONY.search(l)
        if m:
            self.fin_paquet()
            self.evenements.append((temps, m.group(1)))
            self.suite.clear()
            return
        m = RE_PARAM.search(l)
        if m:
            off, val = int(m.group(1), 16), int(m.group(2), 16)
            if val & 0x0F == CCI_I2C_SET_PARAM_CMD:
                self.fin_paquet()
                file_ = (off - CCI_I2C_M0_Q0_LOAD_DATA_ADDR) // 0x100
                self.esclave[file_] = ((val >> 4) & 0x7F) << 1
                self.file_courante = file_
                self.suite[file_] = False
            return
        m = RE_ANCRE.search(l)
        if m:
            self.fin_paquet()
            self.paquet = [temps, int(m.group(2), 16), [], self.file_courante]
            return
        m = RE_MOT.search(l)
        if m:
            if self.paquet is None:
                self.anomalies += 1
                return
            self.paquet[2].append(int(m.group(1), 16))
            return
        m = RE_ATTENTE.search(l)
        if m:
            self.fin_paquet()
            self.evenements.append((temps, "attente (cmd 0x%s)" % m.group(1)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("journal")
    ap.add_argument("--esclave", type=lambda s: int(s, 0), help="adresse I2C 8 bits à garder (ex. 0x34)")
    ap.add_argument("--brut", action="store_true", help="une ligne par registre")
    a = ap.parse_args()

    d = Decodeur()
    with open(a.journal, errors="replace") as f:
        for l in f:
            d.ligne(l.rstrip("\n"))
    d.fin_paquet()

    ecr = [e for e in d.ecritures if a.esclave is None or e[1] == a.esclave]
    evts = sorted(d.evenements)
    sortie = sys.stdout
    esclaves = sorted({e[1] for e in d.ecritures if e[1] is not None})
    print("# esclaves vus : %s ; écritures : %d ; anomalies : %d" % (
        " ".join("0x%02x" % e for e in esclaves), len(ecr), d.anomalies), file=sortie)

    ie = 0
    bloc = None

    def vider():
        if bloc:
            t, esc, adr, vals = bloc
            print("%12.6f  %s  0x%04x  %s" % (t, "0x%02x" % esc if esc is not None else "  ? ", adr,
                                              " ".join("%02x" % v for v in vals)), file=sortie)

    for t, esc, adr, v in ecr:
        while ie < len(evts) and evts[ie][0] <= t:
            vider(); bloc = None
            if not evts[ie][1].startswith("attente") or a.brut:
                print("%12.6f  # %s" % evts[ie], file=sortie)
            ie += 1
        if a.brut:
            print("%12.6f  %s  0x%04x  %02x" % (t, "0x%02x" % esc if esc is not None else "  ? ", adr, v), file=sortie)
            continue
        if bloc and bloc[1] == esc and bloc[2] + len(bloc[3]) == adr and t - bloc[0] < 0.05 and len(bloc[3]) < 16:
            bloc[3].append(v)
        else:
            vider()
            bloc = [t, esc, adr, [v]]
    vider()
    for e in evts[ie:]:
        if not e[1].startswith("attente"):
            print("%12.6f  # %s" % e, file=sortie)


if __name__ == "__main__":
    main()
