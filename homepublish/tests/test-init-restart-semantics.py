#!/usr/bin/env python3
"""Strict source contracts for init restart and private nginx bootstrap."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INIT = (ROOT / "files/etc/init.d/homepublish").read_text()
GROUP = (ROOT / "files/usr/share/homepublish/product-procd-group.lua").read_text()
RENDERER = (ROOT / "files/usr/share/homepublish/direct-renderer.lua").read_text()
MAKEFILE = (ROOT / "Makefile").read_text()


def test_restart_is_explicit_handoff_not_manual_stop():
    assert "restart_service()" in INIT
    restart = INIT.split("restart_service()", 1)[1].split("\n}", 1)[0]
    assert "product-device-cli.lua" not in restart
    assert "action='stop'" not in restart and 'action="stop"' not in restart
    assert "product-restart-cli.lua prepare" in restart
    assert "product-restart-cli.lua wait" in restart
    assert restart.index("prepare") < restart.index("procd_kill homepublish") < restart.index("lua wait") < restart.index("HANDOFF=1 start")
    assert 'restart_service "$@"' in INIT
    assert "procd_kill homepublish" in restart
    assert "boot_restore" in INIT


def test_nginx_bootstrap_prepares_private_logs_before_config_test():
    assert "mkdir -p" in GROUP and "logs" in GROUP
    assert GROUP.index("logs") < GROUP.index("-t -p")


def test_renderer_uses_capacity_for_concurrent_workers():
    assert "worker_connections 512;" in RENDERER
    assert "worker_connections 64;" not in RENDERER


def test_obsolete_nginx_entry_is_not_packaged():
    assert "./files/etc/init.d/homepublish $(1)/etc/init.d/homepublish" in MAKEFILE
    assert "homepublish*" not in MAKEFILE
    assert not (ROOT / "files/etc/init.d/homepublish-nginx").exists()


if __name__ == "__main__":
    for name, test in sorted(globals().items()):
        if name.startswith("test_"):
            test()
    print("PASS init restart/log/bootstrap contracts")
