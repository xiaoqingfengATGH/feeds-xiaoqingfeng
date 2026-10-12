# Scoped save and validation checkpoint

Implemented scoped form save -> uci commit(homestun) RPC -> committed status refresh. Actual target uci.js has no commit() method, so use rpc.declare(config, reject:true), not an invented uci.commit API. No apply/reload/start call.

TDD: save RED 2 failing -> GREEN 2; validation RED 2 -> GREEN 2. Final Node regression: 8/8 pass. Numeric integer TTL/ports, numeric port inequality (leading-zero equivalence), exposure approval, 1–16 unique hostnames and private upstream validation; disabled fields inactive and retained for damaged-disable recovery.

Isolated target rpcd/UCI: genuine nonzero session, homestun staged enabled/approval leaves committed status disabled; scoped commit changes status to configured and committed CLI plan to 60/18444/18443. Other package remains committed before and session-staged staged-other. Evidence: homestun-luci-persistence-evidence.json. No service activation invoked.

Interrupted fixture recovered: session create returned empty because synthetic /dev/urandom node was denied; scoped bind mount of actual urandom allowed create. Mount removed during cleanup. Chroot-owned processes only killed, fixture directory and 18992 listener absent; production default session bus and management listener still available. Evidence: homestun-luci-cleanup-final.txt.

Limits: real headless Chrome target schema loader PASS. Full browser settings persistence harness remains blocked by Invalid URL in target request batching; persistence evidence is genuine rpcd/UCI plus unit view contract, NOT successful end-to-end browser Save. persistence.cjs is an unfinished diagnostic, overrides section.formvalue, not a UI acceptance test. Damaged-disable actual browser form path and full validation UI boundaries unverified. Prior LuCI IPK remains buggy, not rebuilt; no install, production UCI edits, firewall changes, merge, push or PR. Parent independent review required.
