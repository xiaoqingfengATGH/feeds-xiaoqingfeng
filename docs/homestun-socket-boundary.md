# HomeSTUN NATMap socket boundary evidence

This evidence index repairs the README link. It does not add a new test run or a production approval.

## Source and existing execution evidence

- [NATMap security resume checkpoint](homestun-resume-natmap.md): pinned upstream revision `f8d7996710677c9885c148dda80a42d626f0a17b`, vulnerability location, RED/GREEN and negative-control execution, exact namespace commands and limitations.
- Executable regression: `homestun/tests/test-socket-boundary.py`; implementation `homestun/src/lease-supervisor.c`.
- Checkpoint's final execution: four boundary tests pass, including busy foreign socket, preflight/startup race, inherited `pidfd_getfd=EPERM` after exec, and filter-install fail-closed (neither engine starts). Both temporary no-boundary negative controls mutate foreign `SO_REUSEPORT` and fail the preservation tests as expected. Those results are attributed to the original security agent's saved checkpoint, not newly executed by this cleanup task.
- Resume parent reports an independent latest isolated boundary4/lifecycle1/recipe1/package1/source-cleanup15/Worker6 pass. Parent owns that run's evidence.

## What the boundary proves

Native helper applies raw seccomp-BPF with no_new_privs in the NATMap child before exec, rejects foreign `pidfd_getfd` descriptor import, checks syscall ABI and rejects x32 on x86-64. Private pipe readiness acknowledgement prevents nginx starting if boundary installation fails. Tests compile the inspected upstream dangerous routine rather than substitute a fake socket mutation API. Tests run only inside root-owned isolated network namespace with loopback.

## What remains unproven

Not a general malicious-root sandbox, exclusive port allocator, full NATMap networking/reachability test or supported-ABI SDK certification. A deliberately reusable foreign socket is outside this narrow guarantee. Actual target kernel filter acceptance, SDK/ipk and real enabled service need independent approval. The resumed cleanup fixture passed with the current native helper, but uses dummy no-network engines and does not replace those gates. Target firmware's missing stat prerequisite is explicitly recorded in [cleanup resume](homestun-resume-cleanup.md).

No NAT/firewall/Cloudflare/business changes, installation, commit, merge, push or PR were performed to repair this documentation link.
