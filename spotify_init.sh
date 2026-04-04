#!/bin/sh
# spotify_init.sh — Auto-start Spotify Connect on Squeezebox Touch
# Add to /etc/init.d/squeezeplay:
#   /media/mmcblk0p1/spotify_init.sh &

# Wait for network
sleep 5

# Sync time — required for TLS certificate validation
# Clock resets to 1970 on every reboot
rdate -s time.cloudflare.com 2>/dev/null || \
rdate -s time.nist.gov 2>/dev/null || \
rdate -s pool.ntp.org 2>/dev/null

# ALSA config symlink
# The musl binary was built on a Mac and looks for alsa.conf
# in the build machine's sysroot path. We symlink the device's
# real alsa.conf to that path.
mkdir -p /work/musl-hf-sysroot/share/alsa
ln -sf /usr/share/alsa/alsa.conf \
    /work/musl-hf-sysroot/share/alsa/alsa.conf 2>/dev/null

# Start librespot with realtime priority
# chrt -f 50 gives SCHED_FIFO priority 50, preventing audio underruns
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
    >> /tmp/librespot.log 2>&1 &

sleep 1
ps | grep '/media/mmcblk0p1/librespot' | grep -v grep | \
    awk '{print $1}' > /tmp/librespot.pid
