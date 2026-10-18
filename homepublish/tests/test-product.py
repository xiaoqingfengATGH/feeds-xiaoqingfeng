#!/usr/bin/env python3
"""Device-only Lua/nixio regression transport; no local native build."""
import pathlib, runpy, sys
m=runpy.run_path(str(pathlib.Path(__file__).with_name('run-device-tcp-p1-lua.py')))
sys.exit(m['run'](['product']))
