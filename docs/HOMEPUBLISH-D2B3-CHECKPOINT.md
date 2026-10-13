# D2b3 private socketpair checkpoint

Baseline e85f3f91332a7d57691e725075e7b0041b1de8d7, exclusive feature/homepublish-product; local WSL non-root only.

RED before implementation: real make guardian-nginx exit2; nine records, nine channel EPERM, remaining_owned empty. Evidence in profile scratch/d2b2-pair-red. New private-pair-probe compiled with -Wall -Wextra -Werror and old generic profile failed exit134 because provider could not report successful internal SCM_RIGHTS receipt (global recvmsg deny). Generic protection is not being removed.

Feasibility prototype: Linux connected SOCK_STREAM and SOCK_SEQPACKET socketpair endpoints can bind pathname addresses, but listen returns EINVAL before/after shutdown, external connect ECONNREFUSED, /proc/self/fd socket reopen ENXIO. SOCK_DGRAM pair can bind too and is not safe to permit. Candidate therefore permits AF_UNIX SOCK_STREAM protocol0 socketpair only, denies all socket(AF_UNIX) and other domains except IPv4/IPv6. No numeric FD allowlist. Further real attacks and final regressions pending.

Contract: trusted fixed non-root provider, not hostile filesystem sandbox. External same-UID process interference, mutable executable/library/config authority and native TLS cleanup remain separate unresolved production gates. Production CLI activation remains unavailable.
