#!/usr/bin/env python3
"""Current conventional target adapter contract; old C fixtures remain historical."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('test-simple-device.py')))
