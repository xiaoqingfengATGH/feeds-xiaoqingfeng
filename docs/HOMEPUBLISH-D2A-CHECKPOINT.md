# D2a implementation checkpoint

Scope: local-only renderer/backend slice; Start/Apply remain unsupported. No guardian, firewall, router, mapping or production activation.

Discovery: baseline ab57f163de613cc8601d156b8f6af16afe678bbb clean. WSL has no system nginx; cached SDK nginx 1.26.1 runs using cached musl loader/library path. Lua5.1 available under local-tools. No installation/network needed.

Plan: vertical TDD (1) static backend selection, (2) literal-listener direct renderer, (3) isolated real TLS four-family matrix + rejection and POST no replay. Trusted providers are injected only by internal Lua caller, never client wire; their fixture assertions do not prove DNS, ownership, role, certificate readiness. Keep product activation blocked. All runtime binds loopback and temporary certificates/processes cleaned and read back.
