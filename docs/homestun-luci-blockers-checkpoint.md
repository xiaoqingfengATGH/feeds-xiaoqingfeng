# LuCI blocker correction checkpoint

Scope: feature/homestun; no commit/push/install or production configuration writes.

Confirmed schema returns a plain object rejected by the real LuCI loader. Default Save only stages UCI changes, while status reads committed configuration. Work in progress: test-first class export, scoped commit/status refresh, validation and disabled recovery, isolated actual target assets + rpcd/UCI fixture. Prior LuCI IPK is buggy and must not be treated as release evidence. Core IPK remains unchanged.

SSH uses existing known-host entry root@127.0.0.1:222 (`-F /dev/null`), not localhost. rpcd has no `-h` usage flag; do not probe it again (it attempts registration on default bus). All further daemon execution must be inside a /tmp fixture chroot with its own bus and config.
