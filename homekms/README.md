# HomeKMS backend

See [integration and verification notes](../docs/HOMEKMS.md).

Local checks (Python executable is `python` on the Windows authoring host):

```
HOMEKMS_ARCHIVE=/path/to/source.tar.gz python homekms/tests/test_packaging.py -v
bash homekms/tests/test_lifecycle.sh
bash homekms/tests/test_discovery.sh
python homekms/tests/test_protocol.py --server-dir /path/to/py-kms --client /path/to/vlmcs
```

The protocol test requires an independently built Wind4/vlmcsd client and runs a disposable loopback server. It does not change Windows or Office license state.

## Service identity

`USERID:=homekms:homekms` requests dynamic UID/GID allocation. Do not pin 453:
the HomeLede build tree reserves that ID for dnsmasq. The VM's
`package/base-files/files/lib/functions.sh` parses missing numeric IDs and uses
`group_add_next` / `user_add` to select unused IDs starting at 32768, retaining
existing named accounts. procd resolves the `homekms` user/group by name.
The packaging regression checks this declaration; image/package installation
and target account resolution remain build/deployment acceptance checks.
