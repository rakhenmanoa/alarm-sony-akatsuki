#!/usr/bin/env python3
"""voix-hostless.py — Ouvre et démarre le PCM VoiceMMode1 sans y écrire de données.

Ce PCM est « sans hôte » (hostless) : la voix circule directement entre le modem et
le SLIMbus dans l'ADSP, aucune donnée ne passe par Linux. aplay/arecord échouent
(« Argument invalide » à la première écriture) ; il suffit d'ouvrir, régler,
préparer puis démarrer le flux (snd_pcm_start) et de le garder ouvert.

Usage (root) : voix-hostless.py hw:0,6 [débit=8000]   — Ctrl+C ou kill pour arrêter.
"""
import ctypes
import signal
import sys
import time

lib = ctypes.CDLL("libasound.so.2")
lib.snd_strerror.restype = ctypes.c_char_p
SND_PCM_STREAM_PLAYBACK, SND_PCM_STREAM_CAPTURE = 0, 1
SND_PCM_FORMAT_S16_LE = 2
SND_PCM_ACCESS_RW_INTERLEAVED = 3


def ouvrir(dev, flux, debit):
    h = ctypes.c_void_p()
    r = lib.snd_pcm_open(ctypes.byref(h), dev.encode(), flux, 0)
    if r < 0:
        sys.exit("ouverture %s : %s" % (dev, lib.snd_strerror(r).decode()))
    r = lib.snd_pcm_set_params(h, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                               1, debit, 0, 500000)
    if r < 0:
        sys.exit("réglage %s : %s" % (dev, lib.snd_strerror(r).decode()))
    r = lib.snd_pcm_prepare(h)
    if r < 0:
        sys.exit("préparation %s : %s" % (dev, lib.snd_strerror(r).decode()))
    r = lib.snd_pcm_start(h)
    if r < 0:
        sys.exit("démarrage %s : %s" % (dev, lib.snd_strerror(r).decode()))
    return h


def main():
    dev = sys.argv[1] if len(sys.argv) > 1 else "hw:0,6"
    debit = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    lecture = ouvrir(dev, SND_PCM_STREAM_PLAYBACK, debit)
    capture = ouvrir(dev, SND_PCM_STREAM_CAPTURE, debit)
    print("Session voix démarrée sur %s (%d Hz)." % (dev, debit), flush=True)
    fin = []
    signal.signal(signal.SIGTERM, lambda *a: fin.append(1))
    try:
        while not fin:
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    for h in (capture, lecture):
        lib.snd_pcm_drop(h)
        lib.snd_pcm_close(h)
    print("Session voix arrêtée.")


if __name__ == "__main__":
    main()
