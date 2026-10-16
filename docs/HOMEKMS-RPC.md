# HomeKMS read-only RPC contract

Backend: rpcd exec plugin `/usr/libexec/rpcd/homekms` (Python runtime already used by HomeKMS). Object `homekms`; methods `status` and `logs`; both accept **only `{}`**, no paths, commands, PID, port, line count or regexp parameters. Unknown method/parameters fail without execution.

```javascript
'require rpc';
const getStatus = rpc.declare({ object: 'homekms', method: 'status', params: [] });
const getLogs = rpc.declare({ object: 'homekms', method: 'logs', params: [] });
```

## status

Example of observed read-only router execution (not deployed/registered):

```json
{"running":true,"pid":23119,"port":1688,"listening":true,"listeners":[{"family":"tcp","address":"00000000","port":1688}],"checked":true}
```

- `running`: exact procd `homekms.instances.main.running`, not a process-name search.
- `pid`: positive main PID or null.
- `port`: valid configured `homekms.main.port` (1024–65535), default 1688 when UCI option absent, null on invalid/unreadable status.
- `listening`: true only if a TCP LISTEN socket at the configured port has an inode held by that main PID. A different process on 1688, established connections and other ports do not count.
- `listeners`: matching unique sockets; family `tcp` or `tcp6`; `address` is the raw kernel hexadecimal address (not human-readable IPv6). Empty unless verified.
- `checked`: false means inspection unavailable; do not render as conclusively stopped/not listening. Stopped instance has checked=true/listening=false.
- Optional `error`: `invalid_port` or `status_unavailable`.

This is a non-atomic read snapshot: reload/exit and config edits can race. A running service on an old port after an unapplied config edit intentionally reports not listening on the configured port.

## logs

```json
{"text":"","truncated":false,"available":true}
```

- Fixed non-following `logread` snapshot restricted to `homekms:` / `homekms[digits]:` service tags (includes procd stdout/stderr).
- Newest at most 50 lines, at most 16384 UTF-8 bytes **in `text`**; JSON escaping/envelope bytes are not part of this payload bound.
- `truncated`: more than 50 matching returned records or byte-bound trimming. First retained line may be partial after byte trimming; UTF-8 remains valid.
- `available=false`: logread failed/timed out; empty text does not then mean no logs.
- Render text using textContent, never innerHTML. Log tags are not cryptographic provenance.

## ACL and packaging

Package installs independent `homekms-read` ACL granting only `homekms.status` and `homekms.logs`, no write/file/exec/UCI permissions. Existing frontend ACL and JS are intentionally unchanged: integration must grant this role to the session or add only these two ubus methods to the existing LuCI read ACL. No broad file-exec permission is needed by these methods.

Makefile explicitly sets helper mode 0755 and adds `rpcd` / `python3-json`; other Python modules use the existing runtime. No init changes. No deployment, rpcd restart, commit or push performed.

## Verification

Run `python -m unittest discover -s homekms/tests -v`. RPC tests cover method allowlist/parameter rejection, main PID/config port association, inode LISTEN filtering and UTF-8 byte/line limits. Read-only SSH execution streams source to `python3 -` without writing target files; observed live PID 23119 listening on 1688 and available empty service logs. This is not a full rpcd registration/ACL integration test or a package rebuild. Existing archive test requires `HOMEKMS_ARCHIVE` and skips when not supplied.
