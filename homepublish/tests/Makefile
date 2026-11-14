# Supported current-version suite; obsolete implementation targets removed.
.PHONY: current current-target
current:
	uv run --no-project --python 3.13 --with lupa --with pytest python run-current-suite.py
current-target:
	uv run --no-project --python 3.13 --with lupa --with pytest python run-current-suite.py --target
