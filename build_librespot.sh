#!/bin/bash
# Build librespot for Squeezebox Touch
# Target: ARMv6 hardfloat musl (arm-unknown-linux-musleabihf)
# Optimized for ARM1136JF-S with VFP2 + f32 sample decoder
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LIBRESPOT="$BASE/castbridge/librespot-0.8.0"
SYSROOT="$BASE/castbridge/musl-hf-sysroot"
TARGET="arm-unknown-linux-musleabihf"

echo "=== Building librespot for Squeezebox Touch ==="
echo "Target:    $TARGET"
echo "CPU:       ARM1136JF-S @ 532MHz, VFP2 hardfloat"
echo "Sysroot:   $SYSROOT"
echo ""

# Write optimized .cargo/config.toml
mkdir -p "$LIBRESPOT/.cargo"
cat > "$LIBRESPOT/.cargo/config.toml" << EOF
[target.arm-unknown-linux-musleabihf]
linker = "arm-linux-musleabihf-gcc"
rustflags = [
    "-L/musl-sysroot/lib",
    "-C", "link-arg=-Wl,--gc-sections",
    "-C", "target-cpu=arm1136jf-s",
    "-C", "target-feature=+vfp2,+v6"
]

[profile.release]
opt-level = 3
lto = true
codegen-units = 1
panic = "abort"
strip = true
EOF

echo "Building (this takes ~2 minutes)..."

docker run --rm \
    -v "$LIBRESPOT:/work" \
    -v "$SYSROOT:/musl-sysroot" \
    armbuilder5 \
    bash -c "
        source /root/.cargo/env &&
        rustup target add $TARGET &&
        cd /work &&
        PKG_CONFIG_ALLOW_CROSS=1 \
        PKG_CONFIG_PATH=/musl-sysroot/lib/pkgconfig \
        OPENSSL_DIR=/musl-sysroot \
        OPENSSL_STATIC=1 \
        ALSA_INCLUDE_DIR=/musl-sysroot/include \
        ALSA_LIB_DIR=/musl-sysroot/lib \
        CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-linux-musleabihf-gcc \
        cargo build --release --target $TARGET \
            --no-default-features \
            --features 'alsa-backend rustls-tls-webpki-roots with-libmdns'
    "

BINARY="$LIBRESPOT/target/$TARGET/release/librespot"
SIZE=$(du -sh "$BINARY" | cut -f1)

echo ""
echo "=== Build complete! ==="
echo "Binary: $BINARY"
echo "Size:   $SIZE"
echo ""
echo "Performance on Squeezebox Touch (ARM1136JF-S @ 532MHz):"
echo "  CPU at idle:          0%"
echo "  CPU at 320kbps:      ~16%"
echo "  Audio format:         S24_LE 44100Hz"
echo ""
echo "Deploy:"
echo "  cat $BINARY | ssh root@SQUEEZEBOX_IP 'cat > /media/mmcblk0p1/librespot && chmod +x /media/mmcblk0p1/librespot'"
