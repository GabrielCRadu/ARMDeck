#!/bin/sh
# steamed-noodle, sunet pasul 1: pachetele PipeWire lipsa si legatura UCM.
# Profilul nostru e in ucm2/OnePlus/, dar ALSA il cauta dupa driver si nume de placa
# (conf.d/sm8250/OnePlus8.conf); fara legatura, PipeWire nu creeaza nicio iesire.
# Nu porneste niciun sunet. Rulare: sudo sh /tmp/op8-log/audio-step1.sh
set -eu
apk add pipewire-pulse pipewire-filter-graph pipewire-filter-graph-builtin
ln -sfn ../../OnePlus/OnePlus8.conf /usr/share/alsa/ucm2/conf.d/sm8250/OnePlus8.conf
sync
echo "== verificare"
ls -l /usr/share/alsa/ucm2/conf.d/sm8250/
ls /usr/lib/spa-0.2/filter-graph/
echo "== GATA sunet pasul 1"
