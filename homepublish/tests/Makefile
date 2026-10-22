LUA_TEST ?= /home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1
.PHONY: browser rpc controller controller-multi direct product guardian guardian-nginx owned-runtime startup-owned trusted-provider openssl-engine audit-regressions
# WSL root + Windows node.exe/Chrome/Playwright; see RPC checkpoint prerequisites.
# HP_PLAYWRIGHT is optional when Windows Node can resolve 'playwright'.
browser:
	python3 test-browser-lifecycle.py
rpc:
	python3 test-rpc.py
controller:
	python3 test-controller.py
	python3 test-controller-multi.py
controller-multi:
	python3 test-controller-multi.py
controller-recovery:
	python3 test-controller-recovery.py
audit-regressions:
	python3 test-audit-regressions.py maps
	python3 test-audit-regressions.py compiler
	python3 test-audit-regressions.py trace-error
	python3 test-audit-regressions.py trace-timeout
	@for stage in maps metadata observation all; do for cut in live bind; do python3 test-audit-regressions.py write-$$stage-$$cut || exit $$?; done; done
trusted-provider:
	python3 test-trusted-provider.py
startup-owned:
	python3 test-startup-owned.py
owned-runtime:
	HP_OWNED_DIAG_TEST=1 python3 test-owned-runtime.py
	python3 test-owned-runtime.py
openssl-engine:
	python3 test-openssl-engine.py
# Local test-only private-pair profile; production activation remains disabled.
guardian-nginx:
	$(CC) -std=c11 -Wall -Wextra -Werror -DHP_GUARD_TEST -I../src ../src/renewable-guard.c private-pair-probe.c -o $(TMPDIR)/hp-private-pair-probe
	$(TMPDIR)/hp-private-pair-probe
	$(TMPDIR)/hp-private-pair-probe abstract
	python3 test-guardian-nginx.py
guardian:
	python3 test-renewable-guard.py
# Run from homepublish/tests in WSL; uses cached tools, never installs.
direct:
	python3 test-direct.py
	python3 test-direct-boundary.py
	$(LUA_TEST) test-req013.lua ../..
shared-runtime:
	$(LUA_TEST) test-shared-provider.lua ../files/usr/share/homepublish
	$(LUA_TEST) test-business-provider.lua ../files/usr/share/homepublish
	python3 test-shared-runtime.py
product:
	$(LUA_TEST) test-certificate-model.lua ../..
	$(LUA_TEST) test-certificate-san.lua ../..
	$(LUA_TEST) test-certificate-inventory.lua ../..
	python3 test-certificate-metadata.py
	python3 test-product-lifecycle.py
	python3 test-product-review.py
	python3 test-product.py
	python3 test-recipe.py
	python3 test-package.py
