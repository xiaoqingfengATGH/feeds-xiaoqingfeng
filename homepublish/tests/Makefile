.PHONY: direct product guardian guardian-nginx owned-runtime startup-owned trusted-provider
trusted-provider:
	python3 test-trusted-provider.py
startup-owned:
	python3 test-startup-owned.py
owned-runtime:
	python3 test-owned-runtime.py
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
product:
	python3 test-product-review.py
	python3 test-product.py
	python3 test-recipe.py
	python3 test-package.py
