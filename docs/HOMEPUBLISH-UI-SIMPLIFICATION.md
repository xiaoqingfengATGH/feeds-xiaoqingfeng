# HomePublish UI simplification acceptance

## User-approved interaction
- HomePublish has one master Enable control. It represents desired state, not a claim of successful operation.
- Primary form action is 保存并应用. When enabled, save then apply/start the saved configuration. When disabled, persist without starting.
- Individual service enabled flags determine participation while the master is enabled.
- Ordinary status vocabulary: 运行中、已停止、启动中、停止中、启动失败、应用失败. Do not label service operation as public publication success/failure.
- Remove standing 公网未验证、本机就绪不代表公网可达 reminders and public-verification columns. External reachability is outside application status.
- Hide saved/active/intent revision numbers from normal summary. Retain in expandable diagnostic information and internal concurrency checks.

## Reliability retained
- Do not change backend journal/state-machine contract or weaken validation, certificate checks, stale revision protection, ownership checks or policy deadlines.
- Enabled but failed remains enabled; expose actual error rather than pretending stopped or running.
- Save failure must not dispatch lifecycle operations. Save success followed by apply failure must retain the saved configuration and report application failure.
- Re-read state after saving and use checked revision; do not blindly retry stale writes or overwrite a concurrent user's settings.
- Master state and runtime state must be shown separately where needed, without requiring users to understand revisions.

## Verification scope
Run focused tests for disabled save-only, enabled save/apply, enabled stopped start, validation/conflict errors, apply failure and UI summary rendering. Follow with integrated static and real-browser verification when changes are available. Existing ordinary-page and P2 harness tests must be updated only for intended interaction differences, not weakened to conceal regressions.

No automatic commit, push, merge, configuration overwrite or IPK installation. Source changes and tests are the current deliverable; live deployment, if undertaken, must preserve journal and be explicitly identified in evidence.
