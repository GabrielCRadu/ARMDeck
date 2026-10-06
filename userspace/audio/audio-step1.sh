#!/bin/sh
# armdeck, sound step 1: the missing PipeWire packages and the UCM link.
# Our profile is in ucm2/OnePlus/, but ALSA looks it up by driver and card name
# (conf.d/sm8250/OnePlus8.conf); without the link, PipeWire creates no output at all.
# pipewire-spa-bluez: Bluetooth headphones (A2DP). Without it the headphones pair but never
# connect ("a2dp-sink profile connect failed: Protocol not available").
# pipewire-filter-graph-ladspa + lsp-plugins-ladspa: the average-power limiter (LSP Compressor
# Mono) in the speaker filter, 50-op8-speakers.conf; without them that filter does not load.
# Plays no sound. Run: sudo sh audio-step1.sh
set -eu
apk add pipewire-pulse pipewire-filter-graph pipewire-filter-graph-builtin pipewire-spa-bluez pipewire-filter-graph-ladspa lsp-plugins-ladspa
ln -sfn ../../OnePlus/OnePlus8.conf /usr/share/alsa/ucm2/conf.d/sm8250/OnePlus8.conf
sync
echo "== check"
ls -l /usr/share/alsa/ucm2/conf.d/sm8250/
ls /usr/lib/spa-0.2/filter-graph/
echo "== DONE sound step 1"
