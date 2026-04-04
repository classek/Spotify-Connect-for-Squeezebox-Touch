#!/bin/bash
# Apply all kernel 2.6.26 compatibility patches + ARMv6 optimizations
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LIBRESPOT="$BASE/castbridge/librespot-0.8.0"
PATCHES="$LIBRESPOT/patches"

echo "=== Applying patches for kernel 2.6.26 + ARMv6 optimization ==="

# ----------------------------------------------------------------
# mio: Replace eventfd waker with pipe waker (no eventfd2 needed)
# ----------------------------------------------------------------
echo "[1/9] mio: Replace eventfd waker with pipe..."
cp "$PATCHES/mio/src/sys/unix/waker/pipe.rs" \
   "$PATCHES/mio/src/sys/unix/waker/eventfd.rs"

echo "[2/9] mio: epoll_create1 -> epoll_create..."
sed -i '' 's|let ep = unsafe { OwnedFd::from_raw_fd(syscall!(epoll_create1(libc::EPOLL_CLOEXEC))?) };|let ep = unsafe { OwnedFd::from_raw_fd(syscall!(epoll_create(1024))?) }; unsafe { libc::fcntl(ep.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) };|' \
    "$PATCHES/mio/src/sys/unix/selector/epoll.rs"

# ----------------------------------------------------------------
# rustix 1.1.2
# ----------------------------------------------------------------
echo "[3/9] rustix 1.1.2: eventfd2 -> eventfd..."
python3 << PYEOF
path = '$PATCHES/rustix112/src/backend/libc/event/syscalls.rs'
with open(path) as f: c = f.read()
old = """            fn eventfd2(
                initval: c::c_uint,
                flags: c::c_int
            ) via SYS_eventfd2 -> c::c_int
        }
        ret_owned_fd(eventfd2(initval, bitflags_bits!(flags)))"""
new = """            fn eventfd_old(
                initval: c::c_uint
            ) via SYS_eventfd -> c::c_int
        }
        ret_owned_fd(eventfd_old(initval))"""
assert old in c, "eventfd2 pattern not found"
with open(path, 'w') as f: f.write(c.replace(old, new))
print("  OK")
PYEOF

sed -i '' 's|ret_owned_fd(syscall_readonly!(__NR_eventfd2, c_uint(initval), flags))|ret_owned_fd(syscall_readonly!(__NR_eventfd, c_uint(initval)))|' \
    "$PATCHES/rustix112/src/backend/linux_raw/event/syscalls.rs"

echo "[4/9] rustix 1.1.2: epoll_pwait -> epoll_wait..."
python3 << PYEOF
path = '$PATCHES/rustix112/src/backend/linux_raw/event/syscalls.rs'
with open(path) as f: c = f.read()
old = """        if let Some(old_timeout) = old_timeout {
            // Call \`epoll_pwait\`.
            return ret_usize(syscall!(
                __NR_epoll_pwait,
                epfd,
                events.0,
                pass_usize(events.1),
                c_int(old_timeout),
                zero()
            ));
        }
    }

    // Call \`epoll_pwait2\`.
    //
    // We either have Linux 5.1 or the timeout didn't fit in an \`i32\`, so
    // \`__NR_epoll_pwait2\` will either succeed or fail due to our having no
    // other options.
    ret_usize(syscall!(
        __NR_epoll_pwait2,
        epfd,
        events.0,
        pass_usize(events.1),
        opt_ref(timeout),
        zero()
    ))"""
new = """        if let Some(old_timeout) = old_timeout {
            // Use epoll_wait for kernel 2.6.26 compatibility
            return ret_usize(syscall!(
                __NR_epoll_wait,
                epfd,
                events.0,
                pass_usize(events.1),
                c_int(old_timeout)
            ));
        }
    }

    // Fallback with -1 timeout
    ret_usize(syscall!(
        __NR_epoll_wait,
        epfd,
        events.0,
        pass_usize(events.1),
        c_int(-1_i32)
    ))"""
assert old in c, "epoll_pwait pattern not found"
with open(path, 'w') as f: f.write(c.replace(old, new))
print("  OK")
PYEOF

echo "[5/9] rustix 1.1.2: pipe2, dup3, accept4, getrandom, memfd..."
python3 << PYEOF
import os
base = '$PATCHES/rustix112/src/backend/linux_raw'

# pipe2 -> pipe
path = f'{base}/pipe/syscalls.rs'
with open(path) as f: c = f.read()
c = c.replace('ret(syscall!(__NR_pipe2, &mut result, flags))?;', 'ret(syscall!(__NR_pipe, &mut result))?;')
with open(path, 'w') as f: f.write(c)
print("  OK: pipe2 -> pipe")

# dup3 with empty flags
path = f'{base}/io/syscalls.rs'
with open(path) as f: c = f.read()
old = """    unsafe {
        ret_discarded_fd(syscall_readonly!(__NR_dup2, fd, new.as_fd()))
    }
}"""
new = """    unsafe { ret_discarded_fd(syscall_readonly!(__NR_dup3, fd, new.as_fd(), DupFlags::empty())) }
}"""
c = c.replace(old, new)
with open(path, 'w') as f: f.write(c)
print("  OK: dup3")

# accept4 -> accept
path = f'{base}/net/syscalls.rs'
with open(path) as f: c = f.read()
c = c.replace(
    'let fd = ret_owned_fd(syscall_readonly!(__NR_accept4, fd, zero(), zero(), flags))?;',
    'let fd = ret_owned_fd(syscall_readonly!(__NR_accept, fd, zero(), zero()))?;'
)
with open(path, 'w') as f: f.write(c)
print("  OK: accept4 -> accept")

# getrandom -> /dev/urandom
path = f'{base}/rand/syscalls.rs'
with open(path, 'w') as f:
    f.write("""use crate::backend::conv::ret_usize;
use crate::io;
use crate::rand::GetRandomFlags;

#[inline]
pub(crate) unsafe fn getrandom(buf: (*mut u8, usize), flags: GetRandomFlags) -> io::Result<usize> {
    extern "C" {
        fn open(path: *const u8, flags: i32) -> i32;
        fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
        fn close(fd: i32) -> i32;
    }
    let path = b"/dev/urandom\\0";
    let fd = open(path.as_ptr(), 0);
    if fd < 0 { return Err(io::Errno::IO); }
    let n = read(fd, buf.0, buf.1);
    close(fd);
    if n < 0 { return Err(io::Errno::IO); }
    Ok(n as usize)
}
""")
print("  OK: getrandom -> /dev/urandom")

# memfd_create + inotify_init1
path = f'{base}/fs/syscalls.rs'
with open(path) as f: c = f.read()
c = c.replace(
    'unsafe { ret_owned_fd(syscall_readonly!(__NR_memfd_create, name, flags)) }',
    'unsafe { ret_owned_fd(syscall_readonly!(__NR_openat, crate::backend::conv::c_int(-100_i32), crate::cstr!("/tmp/.rustix-memfd"), crate::backend::conv::c_int(0o102), crate::backend::conv::c_int(0o600))) }'
)
c = c.replace(
    'unsafe { ret_owned_fd(syscall_readonly!(__NR_inotify_init1, flags)) }',
    'unsafe { ret_owned_fd(syscall_readonly!(__NR_inotify_init1, crate::backend::conv::c_int(0_i32))) }'
)
with open(path, 'w') as f: f.write(c)
print("  OK: memfd_create + inotify_init1")
PYEOF

# ----------------------------------------------------------------
# libmdns: Remove SO_REUSEPORT (added in kernel 3.9)
# ----------------------------------------------------------------
echo "[6/9] libmdns: Remove SO_REUSEPORT..."
python3 << PYEOF
path = '$PATCHES/libmdns/src/address_family.rs'
with open(path) as f: c = f.read()
old = """        #[cfg(all(unix, not(any(target_os = "solaris", target_os = "illumos"))))]
        socket.set_reuse_port(true)?;"""
new = """        // SO_REUSEPORT not available on kernel < 3.9"""
assert old in c, "SO_REUSEPORT not found"
with open(path, 'w') as f: f.write(c.replace(old, new))
print("  OK")
PYEOF

# ----------------------------------------------------------------
# librespot discovery: IPv6 -> IPv4
# ----------------------------------------------------------------
echo "[7/9] discovery: Force IPv4..."
python3 << PYEOF
path = '$LIBRESPOT/discovery/src/server.rs'
with open(path) as f: c = f.read()
old = """        let address = if cfg!(windows) {
            SocketAddr::new(Ipv4Addr::UNSPECIFIED.into(), *port)
        } else {
            // this creates a dual stack socket on non-windows systems
            SocketAddr::new(Ipv6Addr::UNSPECIFIED.into(), *port)
        };"""
new = """        let address = {
            // Force IPv4 — kernel 2.6.26 has no IPv6 support
            SocketAddr::new(Ipv4Addr::UNSPECIFIED.into(), *port)
        };"""
assert old in c, "IPv6 socket not found"
with open(path, 'w') as f: f.write(c.replace(old, new))
print("  OK")
PYEOF

# ----------------------------------------------------------------
# Symphonia decoder: f64 -> f32 (2x FPU speedup on ARMv6 VFP2)
# ----------------------------------------------------------------
echo "[8/9] Symphonia: SampleBuffer<f64> -> SampleBuffer<f32>..."
python3 << PYEOF
path = '$LIBRESPOT/playback/src/decoder/symphonia_decoder.rs'
with open(path) as f: c = f.read()
c = c.replace(
    'sample_buffer: Option<SampleBuffer<f64>>',
    'sample_buffer: Option<SampleBuffer<f32>>'
)
c = c.replace(
    'self.sample_buffer.insert(SampleBuffer::new(duration, spec))',
    'self.sample_buffer.insert(SampleBuffer::<f32>::new(duration, spec))'
)
c = c.replace(
    'let samples = AudioPacket::Samples(sample_buffer.samples().to_vec());',
    'let samples = AudioPacket::Samples(sample_buffer.samples().iter().map(|&s| s as f64).collect());'
)
with open(path, 'w') as f: f.write(c)
print("  OK (CPU usage: ~38% -> ~16%)")
PYEOF

# ----------------------------------------------------------------
# Cargo.toml: Add patch section
# ----------------------------------------------------------------
echo "[9/9] Cargo.toml: Add patch section..."
python3 << PYEOF
path = '$LIBRESPOT/Cargo.toml'
with open(path) as f: c = f.read()
patch = """
[patch.crates-io]
mio = { path = "patches/mio" }
rustix = { path = "patches/rustix112", version = "1.1.2" }
libmdns = { path = "patches/libmdns" }
"""
if '[patch.crates-io]' not in c:
    with open(path, 'w') as f: f.write(c + patch)
    print("  OK: patch section added")
else:
    print("  OK: patch section already present")
PYEOF

echo ""
echo "=== All 9 patches applied! ==="
echo "Next: ./scripts/build_sysroot.sh"
