# Discord bridge

Relays the Discord RPC named pipe inside a bottle to the Discord client running
on the host, so a Windows game's own rich presence reaches Discord on macOS.

`make install` builds `WhiskyDiscordBridge.exe` and drops it into
`WhiskyKit/Sources/WhiskyKit/Discord/Resources/`, where it ships as a bundle
resource. The built binary is committed: Xcode builds do not run `make`, and CI
has no MinGW. Rebuild and commit both together whenever `bridge.c` changes.

```
brew install mingw-w64   # provides x86_64-w64-mingw32-gcc
make install
```

## How it works

Both ends of the Discord RPC transport use the same framing, a little-endian
opcode and length then JSON, so the relay never parses a message. It serves
`\\.\pipe\discord-ipc-0` inside the prefix and pumps bytes to whichever of
`discord-ipc-0` … `discord-ipc-9` exists in the socket directory it is given.

Three things are worth knowing before changing it:

- **It reaches the socket through raw xnu syscalls.** PE code shares an address
  space with the unix side of Wine, so a `syscall` instruction lands in the
  kernel directly. A PE module cannot link libSystem, and the supported
  alternative, a PE plus a unixlib half, would have to be built against a
  specific Wine rather than plain MinGW. `sockaddr_un` here is xnu's layout (a
  length byte, then a family byte), not Linux's 16-bit family.
- **The socket directory is passed in with `--dir`.** A PE process sees Wine's
  Windows environment, where the host's `TMPDIR` may not have survived, and the
  sockets are named relative to it.
- **It becomes a Wine system process after a grace window.** System processes do
  not keep a prefix alive, so the relay stops holding a bottle open once the
  game exits, and exits with the prefix rather than outliving it. The window
  exists because Whisky starts the relay just before the game, and a prefix with
  no ordinary process in it starts shutting down.

## Testing it by hand

Serve a socket somewhere short enough to fit `sun_path`, point the relay at it,
and connect from inside the prefix:

```
mkdir -p /tmp/whiskyipc
python3 - /tmp/whiskyipc/discord-ipc-0 <<'EOF'
import socket, struct, sys
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1]); server.listen(1)
conn, _ = server.accept()
header = conn.recv(8)
print(struct.unpack("<II", header), conn.recv(4096))
EOF

WINEPREFIX=... wine64 WhiskyDiscordBridge.exe --dir /tmp/whiskyipc --grace 600000
```

`--grace` is milliseconds; a long one keeps the relay from standing down while
you poke at it.
