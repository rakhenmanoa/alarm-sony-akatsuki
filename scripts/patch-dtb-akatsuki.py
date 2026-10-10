#!/usr/bin/env python3
"""patch-dtb-akatsuki.py — Ajoute l'écran (simple-framebuffer) et la charge
au DTB du Sony Xperia XZ3 (akatsuki), sans dtc ni recompilation du noyau.

Usage :
    python3 scripts/patch-dtb-akatsuki.py ENTREE.dtb SORTIE.dtb
    python3 scripts/patch-dtb-akatsuki.py --decompile FICHIER.dtb   # DTB -> texte

Modifications (par chemin de nœud, indépendantes des numéros de phandle) :

1. Écran — simple-framebuffer dans /chosen, sur la zone cont_splash_mem
   (0x9d400000) que le bootloader Sony laisse allumée : 1440 x 2880,
   a8r8g8b8, stride 1440*4. Méthode reprise de la série « Add framebuffer on
   Xiaomi Poco F1 » (D. Heidelberg, P. Hodina, mars 2026, même SoC et même zone).
   Le framebuffer garde allumées les alimentations de l'écran et du DSI
   (L14A, ts_vddio, L26A, L1A) pour que Linux ne les coupe pas.
   MDSS et dispcc sont désactivés pour que le pilote d'affichage ne reprenne
   pas la main sur l'écran (comme le patch Poco F1 « tianma »).

2. Charge — chargeur PMI8998 activé (pilote qcom_smbx) avec la batterie décrite
   par Petr Hodina (2023) : 3325 mAh, 3,40 V min, 4,38 V max.

Garde-fou : le script REFUSE d'écrire la sortie si le contrôleur UFS ou son PHY
n'est pas en status = "disabled" (brick définitif sur Tama sinon).
"""
import struct
import sys

FDT_MAGIC = 0xD00DFEED
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


# --------------------------------------------------------------------------
# Lecture / écriture FDT (format v17)
# --------------------------------------------------------------------------
class Node:
    def __init__(self, name):
        self.name = name
        self.props = []      # liste ordonnée de [nom, valeur(bytes)]
        self.children = []

    def child(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def get(self, name):
        for k, v in self.props:
            if k == name:
                return v
        return None

    def set(self, name, value):
        for p in self.props:
            if p[0] == name:
                p[1] = value
                return
        self.props.append([name, value])


def parse(data):
    (magic, _total, off_struct, off_strings, off_rsv, version, _last,
     boot_cpu, size_strings, _size_struct) = struct.unpack(">10I", data[:40])
    if magic != FDT_MAGIC:
        sys.exit("Erreur : ce n'est pas un DTB (magie 0x%08x)." % magic)
    if version < 16:
        sys.exit("Erreur : version FDT %d non gérée." % version)
    strings = data[off_strings:off_strings + size_strings]

    rsv = []
    p = off_rsv
    while True:
        addr, size = struct.unpack(">QQ", data[p:p + 16])
        p += 16
        if addr == 0 and size == 0:
            break
        rsv.append((addr, size))

    root = None
    stack = []
    p = off_struct
    while True:
        (tok,) = struct.unpack(">I", data[p:p + 4])
        p += 4
        if tok == BEGIN_NODE:
            end = data.index(b"\0", p)
            node = Node(data[p:end].decode())
            p = (end + 4) & ~3
            if stack:
                stack[-1].children.append(node)
            else:
                root = node
            stack.append(node)
        elif tok == END_NODE:
            stack.pop()
        elif tok == PROP:
            ln, nameoff = struct.unpack(">II", data[p:p + 8])
            p += 8
            name = strings[nameoff:strings.index(b"\0", nameoff)].decode()
            stack[-1].props.append([name, data[p:p + ln]])
            p = (p + ln + 3) & ~3
        elif tok == NOP:
            continue
        elif tok == END:
            break
        else:
            sys.exit("Erreur : jeton FDT inconnu %d." % tok)
    return root, rsv, boot_cpu


def serialize(root, rsv, boot_cpu):
    strtab = bytearray()
    stroff = {}

    def name_off(n):
        if n not in stroff:
            stroff[n] = len(strtab)
            strtab.extend(n.encode() + b"\0")
        return stroff[n]

    st = bytearray()

    def pad4():
        while len(st) % 4:
            st.append(0)

    def emit(node):
        st.extend(struct.pack(">I", BEGIN_NODE))
        st.extend(node.name.encode() + b"\0")
        pad4()
        for k, v in node.props:
            st.extend(struct.pack(">III", PROP, len(v), name_off(k)))
            st.extend(v)
            pad4()
        for c in node.children:
            emit(c)
        st.extend(struct.pack(">I", END_NODE))

    emit(root)
    st.extend(struct.pack(">I", END))

    rsvblk = b"".join(struct.pack(">QQ", a, s) for a, s in rsv) + b"\0" * 16
    off_rsv = 40
    off_struct = off_rsv + len(rsvblk)
    off_strings = off_struct + len(st)
    total = off_strings + len(strtab)
    hdr = struct.pack(">10I", FDT_MAGIC, total, off_struct, off_strings, off_rsv,
                      17, 16, boot_cpu, len(strtab), len(st))
    return hdr + rsvblk + bytes(st) + bytes(strtab)


# --------------------------------------------------------------------------
# Aides
# --------------------------------------------------------------------------
def u32(*vals):
    return struct.pack(">%dI" % len(vals), *vals)


def string(s):
    return s.encode() + b"\0"


def find(root, path):
    node = root
    for part in [x for x in path.split("/") if x]:
        node = node.child(part)
        if node is None:
            sys.exit("Erreur : nœud introuvable dans le DTB : %s" % path)
    return node


def all_nodes(node):
    yield node
    for c in node.children:
        yield from all_nodes(c)


def ensure_phandle(root, node):
    v = node.get("phandle")
    if v is not None:
        return struct.unpack(">I", v)[0]
    used = [struct.unpack(">I", n.get("phandle"))[0]
            for n in all_nodes(root) if n.get("phandle") is not None]
    ph = max(used + [0]) + 1
    node.set("phandle", u32(ph))
    return ph


def ufs_status(root):
    out = {}
    soc = root.child("soc@0")
    for name in ("ufshc@1d84000", "phy@1d87000"):
        n = soc.child(name) if soc else None
        if n is None:
            out[name] = "absent"
        else:
            s = n.get("status")
            out[name] = s.rstrip(b"\0").decode() if s else "(aucun -> actif)"
    return out


def check_ufs(root, label):
    st = ufs_status(root)
    ok = all(v == "disabled" for v in st.values())
    for k, v in st.items():
        print("  %s %s : %s" % ("OK" if v == "disabled" else "!!", k, v))
    if not ok:
        sys.exit("DANGER (%s) : l'UFS n'est pas désactivé. Aucun fichier écrit." % label)


# --------------------------------------------------------------------------
# Modifications
# --------------------------------------------------------------------------
WIDTH, HEIGHT = 1440, 2880

def patch(root):
    # --- 1. Écran : simple-framebuffer ------------------------------------
    splash = find(root, "/reserved-memory/memory@9d400000")
    splash_ph = ensure_phandle(root, splash)

    supplies = {
        # nom de la propriété     : chemin du régulateur
        "vddio-supply": "/soc@0/rsc@179c0000/regulators-0/ldo14",  # E/S panneau 1,8 V
        "vci-supply":   "/ts-vddio-regulator",                     # DCDC de l'OLED
        "vdda-supply":  "/soc@0/rsc@179c0000/regulators-0/ldo26",  # DSI 1,2 V
        "vdds-supply":  "/soc@0/rsc@179c0000/regulators-0/ldo1",   # PHY DSI 0,9 V
    }

    chosen = root.child("chosen")
    if chosen is None:
        chosen = Node("chosen")
        root.children.append(chosen)
    if chosen.child("framebuffer") is not None:
        sys.exit("Erreur : /chosen/framebuffer existe déjà (DTB déjà modifié ?).")
    chosen.set("#address-cells", u32(2))
    chosen.set("#size-cells", u32(2))
    chosen.set("ranges", b"")

    fb = Node("framebuffer")
    fb.set("compatible", string("simple-framebuffer"))
    fb.set("memory-region", u32(splash_ph))
    fb.set("format", string("a8r8g8b8"))
    fb.set("stride", u32(WIDTH * 4))
    fb.set("height", u32(HEIGHT))
    fb.set("width", u32(WIDTH))
    for prop, path in supplies.items():
        fb.set(prop, u32(ensure_phandle(root, find(root, path))))
    chosen.children.append(fb)

    # Le pilote d'affichage ne doit pas reprendre la main sur l'écran
    find(root, "/soc@0/display-subsystem@ae00000").set("status", string("disabled"))
    find(root, "/soc@0/clock-controller@af00000").set("status", string("disabled"))

    # --- 2. Charge ----------------------------------------------------------
    if root.child("battery") is not None:
        sys.exit("Erreur : /battery existe déjà (DTB déjà modifié ?).")
    bat = Node("battery")
    bat.set("compatible", string("simple-battery"))
    bat.set("charge-full-design-microamp-hours", u32(3325000))
    bat.set("voltage-min-design-microvolt", u32(3400000))
    bat.set("voltage-max-design-microvolt", u32(4380000))
    root.children.append(bat)
    bat_ph = ensure_phandle(root, bat)

    chg = find(root, "/soc@0/spmi@c440000/pmic@2/charger@1000")
    chg.set("monitored-battery", u32(bat_ph))
    chg.set("status", string("okay"))


# --------------------------------------------------------------------------
# Décompilation texte (pour vérifier le résultat)
# --------------------------------------------------------------------------
def fmt_value(b):
    if not b:
        return None
    if b[-1] == 0 and all(p and all(0x20 <= c <= 0x7E for c in p) for p in b[:-1].split(b"\0")):
        return ", ".join('"%s"' % p.decode() for p in b[:-1].split(b"\0"))
    if len(b) % 4 == 0:
        return "<" + " ".join("0x%x" % c for c in struct.unpack(">%dI" % (len(b) // 4), b)) + ">"
    return "[" + " ".join("%02x" % c for c in b) + "]"


def decompile(root, rsv):
    out = ["/dts-v1/;"]
    out += ["/memreserve/ 0x%x 0x%x;" % r for r in rsv]

    def walk(n, d):
        out.append("\t" * d + (n.name or "/") + " {")
        for k, v in n.props:
            fv = fmt_value(v)
            out.append("\t" * (d + 1) + (k + ";" if fv is None else "%s = %s;" % (k, fv)))
        for c in n.children:
            walk(c, d + 1)
        out.append("\t" * d + "};")

    walk(root, 0)
    return "\n".join(out)


def main(argv):
    if len(argv) == 3 and argv[1] == "--decompile":
        root, rsv, _ = parse(open(argv[2], "rb").read())
        print(decompile(root, rsv))
        return
    if len(argv) != 3:
        sys.exit(__doc__)
    src, dst = argv[1], argv[2]
    root, rsv, boot_cpu = parse(open(src, "rb").read())

    model = root.get("model")
    if model is None or b"Xperia XZ3" not in model:
        sys.exit("Erreur : ce DTB n'est pas celui du Xperia XZ3 (model = %r)." % model)

    print("Garde-fou UFS sur l'entrée :")
    check_ufs(root, "entrée")
    patch(root)
    print("Garde-fou UFS sur la sortie :")
    check_ufs(root, "sortie")

    data = serialize(root, rsv, boot_cpu)
    # Relecture de contrôle : le fichier produit doit se relire à l'identique.
    root2, rsv2, _ = parse(data)
    if decompile(root2, rsv2) != decompile(root, rsv):
        sys.exit("Erreur interne : le DTB produit ne se relit pas à l'identique.")
    check_ufs(root2, "relecture")

    with open(dst, "wb") as f:
        f.write(data)
    print("DTB écrit : %s (%d octets)" % (dst, len(data)))


if __name__ == "__main__":
    main(sys.argv)
