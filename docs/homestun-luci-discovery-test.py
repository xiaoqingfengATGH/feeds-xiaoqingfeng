#!/usr/bin/env python3
"""Regression for SDK lexical scan before Makefile evaluation."""
import pathlib, re
repo=pathlib.Path(__file__).resolve().parents[1]
recipe=(repo/'luci-app-homestun/Makefile').read_text()
assert re.search(r'call (Build/DefaultTargets|BuildPackage|KernelPackage)',recipe), 'SDK scan.mk excludes recipe: missing OpenWrt buildroot signature'
print('PASS SDK lexical discovery signature')
