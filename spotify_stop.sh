#!/bin/sh
# spotify_stop.sh — Stop Spotify Connect
kill $(cat /tmp/librespot.pid 2>/dev/null) 2>/dev/null
rm -f /tmp/librespot.pid
