#!/bin/sh
# preparer-arbre-noyau.sh — Prépare (sur un PC x86_64) un arbre de sources Linux
# capable de compiler des modules chargeables par le noyau pmOS du XZ3
# (linux-postmarketos-qcom-sdm845 7.1_rc1-r4), sans recompiler le noyau.
#
# Usage : scripts/preparer-arbre-noyau.sh <config-du-noyau> [dossier]   (défaut : ./noyau-7.1-rc1)
#   <config-du-noyau> : /proc/config.gz du téléphone décompressé
#                       (ssh … 'zcat /proc/config.gz' > config-akatsuki)
# Puis, pour un module :
#   "$dossier/construire-module.sh" <dossier-du-module>        (Kbuild/Makefile « obj-m := … »)
#
# Comment l'ABI est reproduite (vérifié le 11/10/2026 en recompilant des modules que
# pmOS fournit déjà — panel-simple, panel-himax-hx83112a — : désassemblage identique,
# struct module de même taille, 0x500 octets) :
#   - sources officielles v7.1-rc1 (GitHub torvalds/linux) ;
#   - même compilateur que pmOS : clang/LLD 22.1.8 (version officielle LLVM) ;
#   - même configuration ; release forcée à « 7.1.0-rc1-sdm845 » ;
#   - arch/arm64/Kconfig : HAVE_DYNAMIC_FTRACE_WITH_DIRECT_CALLS sans exiger
#     CALL_OPS, comme dans la branche sdm845 de pmOS (sinon l'option disparaît) ;
#   - « pahole » factice annonçant la v1.31 : garde CONFIG_DEBUG_INFO_BTF_MODULES,
#     qui ajoute 24 octets à struct module (la génération BTF des modules est
#     ensuite sautée faute de vmlinux, sans conséquence).
# Le noyau pmOS doit être démarré SANS verrouillage (boot.img SANS_VERROU=1) pour
# accepter ces modules non signés.

set -eu
die() { echo "Erreur : $*" >&2; exit 1; }
[ "$#" -ge 1 ] || die "usage : $0 <config-du-noyau> [dossier]"
cfg="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
dst="${2:-noyau-7.1-rc1}"
LLVM_VER=22.1.8
REL=7.1.0-rc1-sdm845

for c in git curl tar make bison bc; do command -v "$c" >/dev/null 2>&1 || die "$c manquant."; done
mkdir -p "$dst"; dst="$(cd "$dst" && pwd)"
outils="$dst/outils"; mkdir -p "$outils/bin"

if [ ! -x "$outils/llvm/bin/clang" ]; then
	echo "== LLVM $LLVM_VER (officiel)"
	curl -fL# -o "$outils/llvm.tar.xz" \
		"https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VER/LLVM-$LLVM_VER-Linux-X64.tar.xz"
	mkdir -p "$outils/llvm" && tar -xJf "$outils/llvm.tar.xz" -C "$outils/llvm" --strip-components=1
	rm "$outils/llvm.tar.xz"
fi
if ! command -v flex >/dev/null 2>&1 && [ ! -x "$outils/bin/flex" ]; then
	echo "== flex"
	curl -fsSL https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz | tar -xz -C "$outils"
	(cd "$outils/flex-2.6.4" && ./configure -q --prefix="$outils" >/dev/null && make -s -j"$(nproc)" >/dev/null && make -s install >/dev/null)
fi
cat > "$outils/bin/pahole" <<'EOF'
#!/bin/sh
# pahole factice : seulement pour que Kconfig garde CONFIG_DEBUG_INFO_BTF*
[ "$1" = --version ] && echo v1.31 && exit 0
[ "$1" = --supported_btf_features ] && echo "encode_force,var,float,decl_tag,type_tag,enum64,optimized_func,consistent_func,decl_tag_kfuncs,reproducible_build,distilled_base,global_var,attributes" && exit 0
exit 1
EOF
chmod +x "$outils/bin/pahole"
export PATH="$outils/bin:$outils/llvm/bin:$PATH"

src="$dst/linux"
if [ ! -d "$src" ]; then
	echo "== Sources v7.1-rc1"
	git clone -q --depth 1 --branch v7.1-rc1 https://github.com/torvalds/linux.git "$src"
fi
sed -i 's/if DYNAMIC_FTRACE_WITH_ARGS && DYNAMIC_FTRACE_WITH_CALL_OPS$/if DYNAMIC_FTRACE_WITH_ARGS/' "$src/arch/arm64/Kconfig"

echo "== Configuration et préparation"
cp "$cfg" "$src/.config"
"$src/scripts/config" --file "$src/.config" --disable LOCALVERSION_AUTO
K="make -C $src ARCH=arm64 LLVM=1 KERNELRELEASE=$REL"
$K olddefconfig >/dev/null
$K -j"$(nproc)" modules_prepare >/dev/null
[ "$(cat "$src/include/config/kernel.release")" = "$REL" ] || die "release inattendue."

cat > "$dst/construire-module.sh" <<EOF
#!/bin/sh
# Compile un module externe pour le noyau pmOS du XZ3 : \$0 <dossier-du-module>
set -eu
export PATH="$outils/bin:$outils/llvm/bin:\$PATH"
make -C "$src" ARCH=arm64 LLVM=1 KERNELRELEASE=$REL KBUILD_MODPOST_WARN=1 M="\$(cd "\$1" && pwd)" modules
EOF
chmod +x "$dst/construire-module.sh"
echo "Prêt : $dst/construire-module.sh <dossier-du-module>"
