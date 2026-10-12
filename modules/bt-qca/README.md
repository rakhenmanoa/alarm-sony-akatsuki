# Modules btqca / hci_uart sans veille IBS (Bluetooth du Xperia XZ3)

Le WCN3990 démarre, reçoit son firmware (`crbtfw21.tlv`) et la NVM de Sony
(`Sony/tama/crnv21.bin`), puis ne répond plus : le pilote mainline active dans la
NVM la veille « IBS » (octets 0xFD/0xFC/0xFE sur l'UART) et la veille profonde, et
la puce ne répond jamais à l'octet de réveil (relevé du 12/10/2026 :
`ibs_sent_wakes: 584`, `ibs_recv_wake_acks: 0`, puis `command 0xfc14 tx timeout`).

[`0001-qca-akatsuki-sans-veille.patch`](0001-qca-akatsuki-sans-veille.patch)
(sur Linux v7.1-rc1) ajoute des options, toutes désactivées par défaut :

| Module | Option | Effet |
|---|---|---|
| `btqca` | `nvm_no_ibs=1` | ne pas activer la veille IBS dans la NVM |
| `btqca` | `nvm_no_deep_sleep=1` | ne pas activer la veille profonde dans la NVM |
| `hci_uart` | `qca_no_ibs=1` | ne jamais activer l'IBS côté hôte (et ne pas bloquer la mise en veille du téléphone) |
| `hci_uart` | `qca_broken_le_tx_power=1` | ne pas envoyer `LE Read Transmit Power` (0x204b), annoncé mais refusé par le firmware |

Il journalise aussi les champs d'origine de la NVM. Sur le XZ3 :
`QCA NVM HCI tag (origine): 82 01 11 08 04 14 28 02 15` (IBS déjà activée, 0x80,
débit 0x11 = 3 200 000) et `deep sleep tag (origine): 01` (déjà activée). Les
options de `btqca` ne changent donc rien ici : c'est `qca_no_ibs` (l'hôte n'envoie
plus d'octet de réveil) qui débloque la puce. Ensuite, l'initialisation s'arrêtait
sur `unexpected cc 0x204b length: 1 < 3` / `Opcode 0x204b failed: -38`, d'où
`qca_broken_le_tx_power`.

## Construction

```sh
S=~/noyau-7.1-rc1            # arbre Linux configuré comme le noyau pmOS
mkdir -p /tmp/bt && cp $S/drivers/bluetooth/*.[ch] /tmp/bt/ && cp Kbuild /tmp/bt/
(cd /tmp/bt && patch -p3 < $PWD/0001-qca-akatsuki-sans-veille.patch)
make -C $S ARCH=arm64 LLVM=1 KERNELRELEASE=7.1.0-rc1-sdm845 KBUILD_MODPOST_WARN=1 M=/tmp/bt modules
```

`Kbuild` reprend la composition de `hci_uart.ko` du noyau pmOS (H4, LL, BCM, QCA,
Marvell).

## Installation (téléphone, en root)

```sh
d=/usr/lib/modules/$(uname -r)/updates; mkdir -p $d
install -m 644 btqca.ko hci_uart.ko $d/ && depmod -a
modinfo -n hci_uart        # doit afficher …/updates/hci_uart.ko
cat > /etc/modprobe.d/akatsuki-bluetooth.conf <<'E'
options hci_uart qca_no_ibs=1 qca_broken_le_tx_power=1
E
reboot
```

Retour arrière : `rm $d/btqca.ko $d/hci_uart.ko /etc/modprobe.d/akatsuki-bluetooth.conf && depmod -a`.
