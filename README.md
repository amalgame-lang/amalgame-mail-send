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
let s2: Sender = s.WithStartTls(true).WithHelo("mail.amalgame.me")  // FQDN = PTR (anti-spam)
let s3: Sender = s2.WithDkim(key, "family.neitsab.fr", "sel1")

let ok: bool = s3.Send("smarthost.example", 587,
                       "alice@family.neitsab.fr", "bob@example.com", rawMessage)
if (!ok) { Console.WriteLine(s3.LastErr) }
```

### Relaying through a smarthost (v0.3.0)

When your sending IP has poor reputation (e.g. collateral DNSBL listing of
a hosting provider's range), relay through a reputable submission server:

```amalgame
let s: Sender = new Sender()
    .WithStartTls(true)
    .WithAuth("relay-user", "relay-pass")        // SMTP AUTH PLAIN (over TLS)
    .WithDkim(key, "amalgame.me", "sel1")
    .WithHelo("mail.amalgame.me")
let ok: bool = s.Send("smtp.relay.example", 587, "you@amalgame.me", "bob@yahoo.com", msg)
```

The mail is DKIM-signed by you and leaves from the relay's (clean) IP. Add
the relay to your SPF (`v=spf1 mx include:<relay-spf> -all`).

`Send` connects, runs `EHLO` → (opportunistic `STARTTLS` if offered and
enabled) → `MAIL FROM` → `RCPT TO` → `DATA` (dot-stuffed message) →
`QUIT`, DKIM-signing the message first when a key is configured. Returns
true on a 2xx final reply.

### Direct MX delivery (v0.2.0)

`Sender.Deliver(from, to, message)` resolves the recipient domain's MX
records and delivers to the best one on `:25` (trying each in preference
order, falling back to the domain's A record when there is no MX):

```amalgame
let ok: bool = s3.Deliver("alice@amalgame.me", "bob@gmail.com", rawMessage)
```

MX lookup is also exposed directly — `Mx.Lookup("gmail.com")` returns the
exchangers best-preference first, via the system resolver (`res_query`),
so consumers **link `-lresolv`**.

Point `Send` at a **smarthost** (a provider's submission server) or use
`Deliver` for direct MX. Direct delivery on `:25` needs this host's
outbound `:25` open + PTR/SPF/DKIM/DMARC published (see the deliverability
runbook in `amalgame-mail-dkim`); when `:25` egress is blocked, a
smarthost is the pragmatic path.

### Direct-first, relay-on-failure (v0.4.0)

`Sender.DeliverOrRelay(from, to, msg)` tries **direct MX** first and falls
back to the configured relay only on a **hard failure** (5xx / unreachable
MX):

```amalgame
let s: Sender = new Sender()
    .WithStartTls(true)
    .WithDkim(key, "amalgame.me", "sel1")
    .WithHelo("mail.amalgame.me")
    .WithRelay("ssl0.ovh.net", 587, "relay@domain", "pass")   // fallback only
let ok: bool = s.DeliverOrRelay("you@amalgame.me", to, msg)   // s.LastVia = "direct"|"relay"
```

⚠️ This only reacts to *rejections*. A message **accepted then
spam-foldered** returns success (the receiver said 250 — no failure
signal), so the relay is NOT used. While your domain's reputation is
young, **relay everything** (`Send(relay, …)`) lands in the inbox more
reliably; switch to `DeliverOrRelay` once reputation is established (to
spare the relay's quota).

## Tests

```sh
# siblings amalgame-mail-dkim, amalgame-crypto, amalgame-tls alongside
bash tests/run_tests.sh  /path/to/amc     # MX lookup (3/3, needs network/DNS)
bash tests/smoke_test.sh /path/to/amc     # send path vs a local SMTP sink
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
