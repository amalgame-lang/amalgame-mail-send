# amalgame-mail-send

**Outbound SMTP delivery** (the send path) for the native Amalgame mail
server (Phase 6). `Sender.Send` delivers a message to a destination SMTP
host over plaintext with **opportunistic STARTTLS**, optionally
**DKIM-signed** ([`amalgame-mail-dkim`](https://github.com/amalgame-lang/amalgame-mail-dkim)).

Complements [`amalgame-net-smtp`](https://github.com/amalgame-lang/amalgame-net-smtp)
(the v0.2.4 client — implicit-TLS `:465` submission to a provider): this
`Sender` speaks plaintext + STARTTLS, which is what MX `:25` / submission
`:587` / a smarthost expect. See
[`native-mail-server.md`](https://github.com/amalgame-lang/Amalgame/blob/main/docs/proposals/native-mail-server.md).

## Usage

```amalgame
import Amalgame.Mail.Send
import Amalgame.Crypto

let key: JwsKey = JwsKey.FromPemPrivate(pem)        // the DKIM key
let s: Sender = new Sender()
let s2: Sender = s.WithStartTls(true)
let s3: Sender = s2.WithDkim(key, "family.neitsab.fr", "sel1")

let ok: bool = s3.Send("smarthost.example", 587,
                       "alice@family.neitsab.fr", "bob@example.com", rawMessage)
if (!ok) { Console.WriteLine(s3.LastErr) }
```

`Send` connects, runs `EHLO` → (opportunistic `STARTTLS` if offered and
enabled) → `MAIL FROM` → `RCPT TO` → `DATA` (dot-stuffed message) →
`QUIT`, DKIM-signing the message first when a key is configured. Returns
true on a 2xx final reply.

Point it at a **smarthost** (a provider's submission server) or — once MX
lookup lands — directly at a recipient's MX. Direct MX delivery on `:25`
needs the IONOS IP's outbound `:25` to be open + PTR/SPF/DKIM/DMARC
published (see the deliverability runbook in `amalgame-mail-dkim`); until
then a smarthost is the pragmatic path.

## Tests

```sh
# siblings amalgame-mail-dkim, amalgame-crypto, amalgame-tls alongside
bash tests/smoke_test.sh /path/to/amc
```

The smoke test runs a minimal SMTP sink, builds + runs the `Sender`
fixture (DKIM-sign + deliver), and asserts the delivered message carries
a `DKIM-Signature` header + the body — exercising the full send path.

## Out of scope (v0.1.0)

- MX DNS lookup (caller passes host:port); implicit TLS `:465` (use
  `amalgame-net-smtp`); a retry queue / bounce handling; SMTP AUTH on
  submit (add when relaying through an authenticated smarthost);
  PIPELINING.

## Dependencies

- [`amalgame-mail-dkim`](https://github.com/amalgame-lang/amalgame-mail-dkim) `>=0.1.0`
- [`amalgame-crypto`](https://github.com/amalgame-lang/amalgame-crypto) `>=0.8.0`
- [`amalgame-tls`](https://github.com/amalgame-lang/amalgame-tls) `>=0.3.5`

## License

Apache-2.0 — see `LICENSE` and `NOTICE.md`.
