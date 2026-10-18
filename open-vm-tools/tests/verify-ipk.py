#!/usr/bin/env python3
"""Validate runtime-loaded library and preserved config in the actual IPK."""
import io
import sys
import tarfile
with tarfile.open(sys.argv[1]) as ipk:
    def inner(suffix):
        member = next(m for m in ipk.getmembers() if m.name.endswith(suffix))
        return tarfile.open(fileobj=io.BytesIO(ipk.extractfile(member).read()))
    with inner("data.tar.gz") as data:
        names = {m.name.removeprefix("./") for m in data.getmembers()}
        assert "lib/libguestStoreClient.so.0" in names, "missing vmtoolsd runtime-loaded GuestStore library"
        assert "lib/libguestStoreClient.so.0.0.0" in names, "missing GuestStore library target"
    with inner("control.tar.gz") as control:
        member = next(m for m in control.getmembers() if m.name.removeprefix("./") == "conffiles")
        assert "/etc/vmware-tools/tools.conf" in control.extractfile(member).read().decode().splitlines()
print("PASS: runtime library and preserved tools.conf present")
