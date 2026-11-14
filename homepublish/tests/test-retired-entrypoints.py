"""Historical production writers must refuse execution before any side effect."""
import ast
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent

def guarded_paths():
    return sorted(p for p in HERE.glob('*.py') if p.name.startswith(('deploy-', 'finalize-', 'resume-')))

def test_historical_writers_fail_closed():
    paths = guarded_paths()
    assert paths
    for path in paths:
        tree = ast.parse(path.read_text(encoding='utf-8-sig'))
        first = tree.body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
            first = tree.body[1]
        assert isinstance(first, ast.Raise), path.name
        assert isinstance(first.exc, ast.Call) and isinstance(first.exc.func, ast.Name) and first.exc.func.id == 'SystemExit', path.name
        # AST gate verified before invocation, so this cannot reach SSH/import side effects.
        result = subprocess.run([sys.executable, str(path)], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0 and 'RETIRED_PRODUCTION_TOOL' in result.stderr, path.name

def test_retired_shell_fixture_stops_before_writes():
    text = (HERE/'router-r7-browser-setup.sh').read_text()
    assert text.splitlines()[2] == 'exit 2'
    result = subprocess.run(['bash'], input=text.encode('utf-8'), capture_output=True, timeout=10)
    assert result.returncode == 2 and b'RETIRED_PRODUCTION_TOOL' in result.stderr


def test_destructive_overview_drivers_removed():
    for name in ('run-r8-overview.py', 'run-r9-device.py'):
        assert not (HERE/name).exists(), name
