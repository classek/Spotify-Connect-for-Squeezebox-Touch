#!/bin/sh
# spotify_start.sh — Start Spotify Connect
# Called from Squeezeplay Lua applet

rdate -s time.cloudflare.com 2>/dev/null &

mkdir -p /work/musl-hf-sysroot/share/alsa
ln -sf /usr/share/alsa/alsa.conf \
    /work/musl-hf-sysroot/share/alsa/alsa.conf 2>/dev/null

chrt -f 50 /media/mmcblk0p1/librespot \
    --name "Squeezebox" \
    --backend alsa \
    --device librespot \
    --format S24 \
    --bitrate 320 \
    --dither none \
    --disable-audio-cache \
    --disable-gapless \
    --initial-volume 80 \
    > /tmp/librespot.log 2>&1 &

sleep 1
ps | grep '/media/mmcblk0p1/librespot' | grep -v grep | \
    awk '{print $1}' > /tmp/librespot.pid
