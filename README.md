# Spotify Connect for Squeezebox Touch

> **Proof of concept** — Running modern Spotify Connect (librespot 0.8.0) on a 
> Logitech Squeezebox Touch with Linux kernel 2.6.26 and ARMv6 processor.

<img src="https://www.cnet.com/a/img/resize/ee13774f789b424a6af810a36b8bc4ab5174ef2e/hub/2012/06/14/4a66de03-bb76-11e2-8a8e-0291187978f3/10_Logitech_squeezebox_touch_33770453.JPG?width=768" alt="Logitech Squeezebox Touch" width="768">

## What this does

Turns your Squeezebox Touch into a fully working **Spotify Connect** receiver — visible in 
the Spotify app just like a Chromecast or smart speaker. Audio plays at S24 quality 
through the built-in AKM4420 DAC at 320 kbps.

A Squeezeplay Lua applet is included to start/stop Spotify Connect directly from the 
device's touchscreen menu.

---

## Hardware Specifications

| Property | Value |
|---|---|
| Device | Logitech Squeezebox Touch |
| SoC | Freescale i.MX35 |
| CPU | ARM1136JF-S (ARMv6), VFP2 hardfloat, ~532 MHz |
| RAM | 128 MB |
| Kernel | Linux 2.6.26.8-rt16 |
| libc | glibc 2.11 |
| Storage | 17 MB flash (cramfs ro + ubifs rw) + SD card |
| DAC | AKM4420 (S24_LE, 44100 Hz) |
| Audio formats | MP3, FLAC, WAV, AIFF, Ogg Vorbis, AAC/HE-AACv2, Apple Lossless |

---

## Why this is hard

### 1. Missing kernel syscalls

Kernel 2.6.26 predates many syscalls that modern Rust/Tokio requires:

| Syscall | Added in kernel | Our fix |
|---|---|---|
| `epoll_create1` | 2.6.27 | → `epoll_create(1024)` + `fcntl(FD_CLOEXEC)` |
| `eventfd2` | 2.6.27 | → pipe-based waker (replaced mio's eventfd.rs) |
| `epoll_pwait` | 2.6.27 | → `epoll_wait` |
| `pipe2` | 2.6.27 | → `pipe` |
| `dup3` | 2.6.27 | → `dup3` with empty flags |
| `accept4` | 2.6.28 | → `accept` |
| `getrandom` | 3.17 | → `/dev/urandom` via extern C |
| `inotify_init1` | 2.6.27 | → `inotify_init1(0)` |
| `memfd_create` | 3.17 | → `openat` tmpfile |
| `SO_REUSEPORT` | 3.9 | → removed from libmdns |

### 2. No IPv6

Kernel 2.6.26 does not support IPv6. All sockets must be forced to IPv4:
- libmdns: patched to skip IPv6 socket creation
- librespot discovery server: patched from `Ipv6Addr::UNSPECIFIED` to `Ipv4Addr::UNSPECIFIED`

### 3. CPU performance

| Build type | CPU during 320kbps playback |
|---|---|
| softfloat (`gnueabi`) | ~75% |
| hardfloat (`gnueabihf`) | ~38% |
| hardfloat + f32 decoder | ~16% |

The key optimisations:
- **Hardfloat musl toolchain** (`arm-linux-musleabihf`) — uses the VFP2 FPU instead of software float
- **`target-cpu=arm1136jf-s`** — enables CPU-specific instruction selection  
- **`target-feature=+vfp2,+v6`** — enables VFP2 floating point instructions
- **f32 sample buffer** — changed Symphonia's internal `SampleBuffer<f64>` to `SampleBuffer<f32>`, halving FPU work

### 4. Clock reset

The system clock resets to 1970 on every reboot. TLS certificate validation fails 
unless `rdate` is called before connecting to Spotify's servers.

### 5. ALSA config path

The musl static binary is built on a Mac and hardcodes the ALSA config path to 
`/work/musl-hf-sysroot/share/alsa/alsa.conf`. A symlink must be created on the 
device at boot.

---

## Patches Applied

### mio 1.1.0
| File | Change |
|---|---|
| `src/sys/unix/waker/eventfd.rs` | Replaced entirely with pipe-based waker |
| `src/sys/unix/selector/epoll.rs` | `epoll_create1` → `epoll_create(1024)` + fcntl |

### rustix 1.1.2
| File | Change |
|---|---|
| `src/backend/linux_raw/event/syscalls.rs` | `eventfd2` → `eventfd`, `epoll_pwait` → `epoll_wait` |
| `src/backend/linux_raw/io/syscalls.rs` | `dup3` with empty flags, `dup2` via syscall |
| `src/backend/linux_raw/pipe/syscalls.rs` | `pipe2` → `pipe` |
| `src/backend/linux_raw/net/syscalls.rs` | `accept4` → `accept` |
| `src/backend/linux_raw/rand/syscalls.rs` | `getrandom` → `/dev/urandom` |
| `src/backend/linux_raw/fs/syscalls.rs` | `inotify_init1(0)`, `memfd_create` → `openat` |
| `src/backend/libc/event/syscalls.rs` | `eventfd2` → `eventfd` (libc backend) |

### libmdns 0.10.1
| File | Change |
|---|---|
| `src/address_family.rs` | Removed `SO_REUSEPORT` (not available until kernel 3.9) |

### librespot (source, not a crate patch)
| File | Change |
|---|---|
| `discovery/src/server.rs` | IPv6 dual-stack → IPv4 `Ipv4Addr::UNSPECIFIED` |
| `playback/src/decoder/symphonia_decoder.rs` | `SampleBuffer<f64>` → `SampleBuffer<f32>` for ~2x FPU speedup |

---

## Build Requirements

- **Mac or Linux** build machine
- **Docker** (for cross-compilation)
- **Squeezebox Touch** with SD card (≥ 1 GB)
- **Spotify Premium** account

---

## Build Instructions

### 1. Clone this repository

```bash
git clone https://github.com/YOUR_USERNAME/spotify-squeezebox
cd spotify-squeezebox
mkdir -p castbridge/sources
```

### 2. Download librespot 0.8.0

```bash
curl -L -o castbridge/librespot-0.8.0.tar.gz \
    https://github.com/librespot-org/librespot/archive/refs/tags/v0.8.0.tar.gz
tar xf castbridge/librespot-0.8.0.tar.gz -C castbridge/
```

### 3. Download crates to patch

```bash
# mio 1.1.0
curl -L -o /tmp/mio-1.1.0.crate \
    "https://crates.io/api/v1/crates/mio/1.1.0/download"
tar xf /tmp/mio-1.1.0.crate -C castbridge/librespot-0.8.0/patches/
mv castbridge/librespot-0.8.0/patches/mio-1.1.0 castbridge/librespot-0.8.0/patches/mio

# rustix 1.1.2
curl -L -o /tmp/rustix-1.1.2.crate \
    "https://crates.io/api/v1/crates/rustix/1.1.2/download"
tar xf /tmp/rustix-1.1.2.crate -C castbridge/librespot-0.8.0/patches/
mv castbridge/librespot-0.8.0/patches/rustix-1.1.2 castbridge/librespot-0.8.0/patches/rustix112

# libmdns 0.10.1
curl -L -o /tmp/libmdns-0.10.1.crate \
    "https://crates.io/api/v1/crates/libmdns/0.10.1/download"
tar xf /tmp/libmdns-0.10.1.crate -C castbridge/librespot-0.8.0/patches/
mv castbridge/librespot-0.8.0/patches/libmdns-0.10.1 castbridge/librespot-0.8.0/patches/libmdns
```

### 4. Apply all patches

```bash
chmod +x scripts/apply_patches.sh
./scripts/apply_patches.sh
```

### 5. Build Docker images

```bash
docker build -t armbuilder  -f docker/Dockerfile.base    .
docker build -t armbuilder2 -f docker/Dockerfile.build   .
docker build -t armbuilder3 -f docker/Dockerfile.rust    .
docker build -t armbuilder4 -f docker/Dockerfile.musl    .
docker build -t armbuilder5 -f docker/Dockerfile.hf      .
```

### 6. Build musl hardfloat sysroot

```bash
# Download musl hardfloat toolchain
curl -L -o /tmp/arm-linux-musleabihf-cross.tgz \
    "https://musl.cc/arm-linux-musleabihf-cross.tgz"
cp /tmp/arm-linux-musleabihf-cross.tgz castbridge/

# Download ALSA source
curl -L -o castbridge/sources/alsa-lib-1.2.9.tar.bz2 \
    https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.9.tar.bz2

# Build
chmod +x scripts/build_sysroot.sh
./scripts/build_sysroot.sh
```

### 7. Build librespot

```bash
chmod +x scripts/build_librespot.sh
./scripts/build_librespot.sh
```

The binary will be at:
```
castbridge/librespot-0.8.0/target/arm-unknown-linux-musleabihf/release/librespot
```
Size: ~8 MB (statically linked musl)

---

## Installation on Squeezebox Touch

### 1. Prepare SD card

Insert SD card into Squeezebox Touch. SSH in and verify it's mounted:
```bash
ssh root@SQUEEZEBOX_IP "ls /media/mmcblk0p1"
```

### 2. Copy binary and scripts

```bash
SB=root@SQUEEZEBOX_IP

# Binary
cat castbridge/librespot-0.8.0/target/arm-unknown-linux-musleabihf/release/librespot | \
    ssh $SB "cat > /media/mmcblk0p1/librespot && chmod +x /media/mmcblk0p1/librespot"

# Scripts
scp scripts/device/spotify_start.sh $SB:/media/mmcblk0p1/
scp scripts/device/spotify_stop.sh  $SB:/media/mmcblk0p1/
scp scripts/device/spotify_init.sh  $SB:/media/mmcblk0p1/
ssh $SB "chmod +x /media/mmcblk0p1/spotify_*.sh"

# ALSA config
scp config/asound.conf $SB:/etc/asound.conf

# Lua applet
ssh $SB "mkdir -p /usr/share/jive/applets/Spotify /mnt/storage/usr/share/jive/applets/Spotify"
for f in lua/SpotifyApplet.lua lua/SpotifyMeta.lua lua/strings.txt lua/install.xml; do
    scp $f $SB:/usr/share/jive/applets/Spotify/$(basename $f)
    scp $f $SB:/mnt/storage/usr/share/jive/applets/Spotify/$(basename $f)
done
```

### 3. Add auto-start to Squeezeplay

```bash
ssh $SB "grep -q spotify_init /etc/init.d/squeezeplay || \
    echo '/media/mmcblk0p1/spotify_init.sh &' >> /etc/init.d/squeezeplay"
```

### 4. Reboot and test

```bash
ssh $SB "reboot"
```

After reboot, **"Squeezebox"** appears in the Spotify app under Devices (cast icon).

---

## Device Operation

### From Spotify app
Open Spotify → tap the cast/device icon → select **"Squeezebox"**

### From Squeezeplay menu
Navigate to **Home → Spotify Connect** on the touchscreen.

### Startup sequence (automatic)
1. Squeezeplay boots
2. `spotify_init.sh` runs in background
3. Waits 5 seconds for network
4. Syncs time via `rdate -s time.cloudflare.com`
5. Creates ALSA config symlink
6. Starts librespot with `chrt -f 50` (realtime priority)

---

## Performance

| Metric | Value |
|---|---|
| CPU at idle | 0% |
| CPU during 320kbps playback | ~16% |
| Audio format | S24_LE, 44100 Hz |
| Bitrate | 320 kbps Ogg Vorbis |
| Latency | ~2 seconds (Spotify Connect standard) |
| Discovery | mDNS via libmdns (IPv4 only) |

---

## Known Limitations

- **No Spotify Lossless** — Spotify's FLAC stream is not available via Connect protocol to third-party devices (as of 2025)

- **Clock resets to 1970** on every reboot — handled automatically by startup script

- **IPv6 not supported** — kernel limitation

---

## Project Structure

```
spotify-squeezebox/
├── README.md
├── .gitignore
├── docker/
│   ├── Dockerfile.base       # Ubuntu base + ARM cross-compiler
│   ├── Dockerfile.build      # Build tools
│   ├── Dockerfile.rust       # Rust toolchain
│   ├── Dockerfile.musl       # musl softfloat toolchain
│   └── Dockerfile.hf         # musl hardfloat toolchain (VFP2)
├── patches/                  # Applied via scripts/apply_patches.sh
│   ├── mio/                  # mio 1.1.0 — pipe waker + epoll_create
│   ├── rustix112/            # rustix 1.1.2 — 8 syscall patches
│   └── libmdns/              # libmdns 0.10.1 — no SO_REUSEPORT
├── lua/
│   ├── SpotifyApplet.lua     # Squeezeplay applet (On/Off, status)
│   ├── SpotifyMeta.lua       # Applet registration
│   ├── strings.txt           # EN/SV localization
│   └── install.xml           # Applet manifest
├── config/
│   └── asound.conf           # ALSA plug device for hw:1
└── scripts/
    ├── apply_patches.sh      # Apply all kernel compat patches
    ├── build_sysroot.sh      # Build OpenSSL + ALSA for musl hardfloat
    ├── build_librespot.sh    # Cross-compile librespot
    └── device/
        ├── spotify_init.sh   # Auto-start at boot
        ├── spotify_start.sh  # Start librespot
        └── spotify_stop.sh   # Stop librespot
```

---

## Technical Deep Dive

### Why musl instead of glibc?

The Squeezebox Touch uses glibc 2.11, which is far too old for modern Rust binaries. 
By using musl, we create a fully static binary with no runtime dependencies on the 
device's libc. The binary carries everything it needs.

### Why hardfloat?

The ARM1136JF-S has a VFP2 floating-point unit. Without hardfloat, all floating-point 
operations (which are central to Ogg Vorbis decoding) are emulated in software — giving 
~75% CPU load. With hardfloat and VFP2 instructions, this drops to ~38%. With the 
additional f32 optimization in the Symphonia decoder, it drops further to ~16%.

### Why f32 instead of f64?

Symphonia's internal sample buffer defaults to `f64` (64-bit double precision). The 
ARM1136JF-S VFP2 coprocessor natively supports both f32 and f64, but f32 operations 
are significantly faster — the VFP2 can execute two f32 operations per cycle in some 
cases. Since audio samples at 16/24-bit depth don't benefit from 64-bit precision 
internally, switching to f32 halves the FPU workload with no audible quality impact.

### What is NQPTP? (future work)

For a potential AirPlay 2 implementation via shairport-sync, NQPTP ("Not Quite PTP") 
is a small C daemon that monitors PTP timing packets on UDP ports 319/320. It uses 
only basic socket operations and `clock_gettime()`, both available in kernel 2.6.26. 
This makes AirPlay 2 via shairport-sync a realistic future project for this platform.

---

## Credits

- [librespot](https://github.com/librespot-org/librespot) — Open source Spotify Connect library
- [Lyrion Music Server](https://lyrion.org) — SqueezePlay applet documentation  
- [musl.cc](https://musl.cc) — musl cross-compilation toolchains
-  My Brother Martin Hammarbrink who donated the Squeezebox
And my wonderful wife who knows that i can get obsessed when i'm working on a new project 
- 

---

## License

MIT
