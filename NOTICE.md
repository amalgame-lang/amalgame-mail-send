# NOTICE — amalgame-mail-send

## Authorship

Copyright 2026 Bastien Mouget. The Amalgame facade code in this
repository is original work — see `facade.am` and the `amalgame.toml`
manifest.

This package is part of the Amalgame ecosystem
([github.com/amalgame-lang/Amalgame](https://github.com/amalgame-lang/Amalgame)).

## License

Licensed under the Apache License, Version 2.0 — see `LICENSE`.

## Third-party content

None vendored. `Sender` drives the runtime's built-in TcpClient, signs
via `amalgame-mail-dkim`, and upgrades with `amalgame-tls` (STARTTLS).
