.PHONY: direct product guardian guardian-nginx
# D2b2 acceptance gate: intentionally RED while internal-channel safety is unresolved.
guardian-nginx:
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
