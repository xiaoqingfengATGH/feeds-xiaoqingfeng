"""Real LuCI prepare/install macros, no SDK; preserve migrated resource bytes."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PACKAGE = Path(__file__).resolve().parents[1]
ASSETS = 'htdocs/luci-static/resources/view/homestatus'

class ResourcePackaging(unittest.TestCase):
    def test_global_minifiers_cannot_change_migrated_resources(self):
        with tempfile.TemporaryDirectory(prefix='homestatus-minify-') as directory:
            root = Path(directory)
            package = root / PACKAGE.name
            for relative in ['Makefile', ASSETS + '/overview.js', ASSETS + '/overview.css']:
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(PACKAGE / relative, target)
            (root / 'feeds/luci').mkdir(parents=True)
            (root / 'include').mkdir()
            (root / 'rules.mk').write_text('')
            (root / 'include/package.mk').write_text('')
            shutil.copyfile(PACKAGE / 'tests/fixtures/luci-24.10.mk', root / 'feeds/luci/luci.mk')
            binary = root / 'bin'
            binary.mkdir()
            for tool in ['jsmin', 'csstidy']:
                path = binary / tool
                path.write_text('#!/bin/sh\nprintf minifier-invoked >> "' + str(root / 'minified') + '"\nexit 1\n')
                path.chmod(0o755)
            harness = root / 'fixture.mk'
            harness.write_text(f'include {package / "Makefile"}\n' +
                'define Run\nall:\n\t$(Build/Prepare)\n' +
                '\t$(call Package/$(PKG_NAME)/install,' + str(root / 'image') + ')\nendef\n$(eval $(Run))\n')
            result = subprocess.run(['make', '-f', str(harness), f'TOPDIR={root}',
                f'INCLUDE_DIR={root}/include', f'BUILD_DIR={root}/build', 'DUMP=1',
                'CP=cp -fpR', 'INSTALL_DIR=mkdir -p', 'FIND=find', 'MESSAGE=:',
                'CONFIG_LUCI_JSMIN=y', 'CONFIG_LUCI_CSSTIDY=y',
                'SHELL=/bin/sh', 'PATH=' + str(binary) + ':/usr/bin:/bin'],
                cwd=package, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((root / 'minified').exists(), 'LuCI default minifiers ran on migrated assets')
            for name in ['overview.js', 'overview.css']:
                installed = root / 'image/www/luci-static/resources/view/homestatus' / name
                self.assertEqual(installed.read_bytes(), (PACKAGE / ASSETS / name).read_bytes())

if __name__ == '__main__':
    unittest.main()
