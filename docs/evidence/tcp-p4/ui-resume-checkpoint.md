# P4 lifecycle resume checkpoint

- Read-only device check: controller-fixture, controller-runtime and root private SSH auth all absent; prior finally did clean. No owned high-port listeners remain.
- Current RED evidence: ui-lifecycle-red.log and ui-lifecycle-attempt1.log. Native service modal Save actually succeeded (saved_revision2, active_revision1, A response retained); failure is disabled overview Apply, not Save.
- Confirmed contract mismatch: installed running generation reports runtime.cleanup=unknown (owned running resources); product.js actionGates common rejects every cleanup != confirmed, including verified running Apply. API contract explicitly permits controlled Apply of owned active group; stopped/failed unknown must remain blocked.
- Next bounded work: allow cleanup=unknown only for verified running Apply, keep Start cleanup strict, execute full private-RPC browser chain then overview regression. Busy reason in first page render may be transient polling; diagnose separately if failure persists.
- No fw/routes/DNS/auth changes, no commit/push/merge/P5. Fixed SSH private transport is not public rpcd ACL acceptance.
