#!/bin/bash
# amalgame-mail-send — loopback send smoke test.
# Runs a minimal Python SMTP sink on :2530, builds + runs the Sender
# fixture (DKIM-sign + deliver), and asserts the captured message carries
# a DKIM-Signature header + the body. Exercises the full send path.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -ge 1 ]; then AMC="$1"; elif [ -n "${AMC:-}" ]; then :
elif command -v amc >/dev/null 2>&1; then AMC="$(command -v amc)"
else echo "ERROR: amc not found." >&2; exit 2; fi
AMC_DIR="$(cd "$(dirname "$AMC")" && pwd)"
[ -n "${AMC_RUNTIME:-}" ] && [ -d "$AMC_RUNTIME" ] || AMC_RUNTIME="$AMC_DIR/runtime"

sib() { local v="${!1:-}"; if [ -n "$v" ] && [ -d "$v" ]; then echo "$v"; return; fi
        if [ -d "$PKG_DIR/../$2" ]; then (cd "$PKG_DIR/../$2" && pwd); return; fi; echo ""; }
DKIM_DIR="$(sib AMALGAME_MAIL_DKIM amalgame-mail-dkim)"
CRYPTO_DIR="$(sib AMALGAME_CRYPTO amalgame-crypto)"
TLS_DIR="$(sib AMALGAME_TLS amalgame-tls)"
for v in DKIM_DIR:mail-dkim CRYPTO_DIR:crypto TLS_DIR:tls; do
  d="${v%%:*}"; [ -n "${!d}" ] || { echo "ERROR: ${v##*:} not found"; exit 2; }
done
command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 2; }

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
echo "  amc:  $AMC ($("$AMC" --version 2>&1 | head -1))"
BUILD_DIR="$(mktemp -d -t ams-smoke-XXXXXX)"
INC="-I$AMC_RUNTIME -I$TLS_DIR/runtime"
CAP="$BUILD_DIR/captured.eml"

FAKE_CACHE="$BUILD_DIR/cache"
mkdir -p "$FAKE_CACHE/github.com/amalgame-lang/amalgame-tls"
ln -s "$TLS_DIR" "$FAKE_CACHE/github.com/amalgame-lang/amalgame-tls/v0.3.5_deadbeef"
export AMALGAME_PACKAGES_DIR="$FAKE_CACHE"
LOCK_BAK=""; [ -f "$PKG_DIR/amalgame.lock" ] && { LOCK_BAK="$BUILD_DIR/lock.bak"; cp "$PKG_DIR/amalgame.lock" "$LOCK_BAK"; }
SINK_PID=""
cleanup() { [ -n "$SINK_PID" ] && kill "$SINK_PID" 2>/dev/null; rm -f "$PKG_DIR/_smoke.am"; rm -rf "$BUILD_DIR"
  if [ -n "$LOCK_BAK" ] && [ -f "$LOCK_BAK" ]; then mv "$LOCK_BAK" "$PKG_DIR/amalgame.lock"; else rm -f "$PKG_DIR/amalgame.lock"; fi; }
trap cleanup EXIT
cat > "$PKG_DIR/amalgame.lock" <<EOF
[[package]]
name = "amalgame-tls"
git = "github.com/amalgame-lang/amalgame-tls"
tag = "v0.3.5"
rev = "deadbeefcafebabe0000000000000000000000ab"
EOF
EXT="--external $DKIM_DIR/facade.am --external $CRYPTO_DIR/facade.am"

echo "── build ──"
bo() { "$AMC" --lib -o "$BUILD_DIR/$1" "$2/facade.am" $3 >/dev/null 2>&1
       gcc -O2 $INC -Wno-incompatible-pointer-types -c "$BUILD_DIR/$1.c" -o "$BUILD_DIR/$1.o" 2>"$BUILD_DIR/g.log" \
         || { echo -e "${RED}$1 failed${NC}"; cat "$BUILD_DIR/g.log"; exit 1; }; }
bo crypto "$CRYPTO_DIR" ""
bo dkim "$DKIM_DIR" "--external $CRYPTO_DIR/facade.am"
( cd "$PKG_DIR" && "$AMC" --lib -o "$BUILD_DIR/facade" facade.am $EXT ) 2>&1 | tail -12
gcc -O2 $INC -Wno-incompatible-pointer-types -c "$BUILD_DIR/facade.c" -o "$BUILD_DIR/facade.o" 2>"$BUILD_DIR/g.log" \
    || { echo -e "${RED}facade build failed${NC}"; cat "$BUILD_DIR/g.log"; exit 1; }
cp "$SCRIPT_DIR/send_fixture.am" "$PKG_DIR/_smoke.am"
( cd "$PKG_DIR" && "$AMC" -o "$BUILD_DIR/smoke" _smoke.am $EXT --external facade.am ) 2>&1 | tail -12
gcc -O2 $INC -Wno-incompatible-pointer-types "$BUILD_DIR/smoke.c" \
    "$BUILD_DIR/facade.o" "$BUILD_DIR/dkim.o" "$BUILD_DIR/crypto.o" \
    -lgc -lm -lssl -lcrypto -lresolv -lpthread -o "$BUILD_DIR/smoke" 2>"$BUILD_DIR/g.log" \
    || { echo -e "${RED}smoke link failed${NC}"; cat "$BUILD_DIR/g.log"; exit 1; }

echo "── start SMTP sink ──"
CAP="$CAP" python3 - "$CAP" > "$BUILD_DIR/sink.out" 2>&1 <<'PY' &
import socket, sys
cap = sys.argv[1]
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 2530)); s.listen(1)
print("SINK-READY", flush=True)
c, _ = s.accept()
def send(t): c.sendall(t.encode())
send("220 sink ready\r\n")
buf=b""; data_mode=False; data=b""
while True:
    chunk = c.recv(4096)
    if not chunk: break
    if data_mode:
        data += chunk
        if b"\r\n.\r\n" in data:
            body = data.split(b"\r\n.\r\n")[0]
            open(cap,"wb").write(body)
            send("250 OK queued\r\n"); data_mode=False; data=b""
        continue
    buf += chunk
    while b"\r\n" in buf:
        line, buf = buf.split(b"\r\n", 1)
        u = line.upper()
        if u.startswith(b"EHLO") or u.startswith(b"HELO"): send("250 sink\r\n")
        elif u.startswith(b"MAIL"): send("250 OK\r\n")
        elif u.startswith(b"RCPT"): send("250 OK\r\n")
        elif u.startswith(b"DATA"): send("354 go\r\n"); data_mode=True
        elif u.startswith(b"QUIT"): send("221 bye\r\n")
        else: send("250 OK\r\n")
c.close()
PY
SINK_PID=$!
for i in $(seq 1 50); do
  grep -q "SINK-READY" "$BUILD_DIR/sink.out" 2>/dev/null && break
  sleep 0.2
done
sleep 0.3

echo "── run sender ──"
OUT="$("$BUILD_DIR/smoke" 2>&1)"; echo "  $OUT"
sleep 0.3

echo "── assert delivered message ──"
PASS=0; FAIL=0
echo "$OUT" | grep -q "SENT-OK" && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo -e "  ${RED}sender failed${NC}"; }
if [ -f "$CAP" ] && grep -q "DKIM-Signature:" "$CAP" && grep -q "hello send smoke body" "$CAP"; then
    PASS=$((PASS+1)); echo -e "  ${GREEN}DKIM-signed message delivered${NC}"
else
    FAIL=$((FAIL+1)); echo -e "  ${RED}captured message missing/incomplete${NC}"; [ -f "$CAP" ] && head -5 "$CAP" | sed 's/^/    /'
fi
echo "────────────────────────────────────────────"
echo -e "  ${GREEN}PASS: $PASS${NC} | ${RED}FAIL: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
