"""Retained current Lua contracts, migrated from fixed external Lua paths."""
from pathlib import Path
import pytest
from lupa.lua51 import LuaRuntime
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

@pytest.mark.parametrize('name,argument', [
    ('test-canonical.lua', ROOT),
    ('test-direct.lua', ROOT/'homepublish/files/usr/share/homepublish'),
    ('test-certificate-model.lua', ROOT),
    ('test-certificate-san.lua', ROOT),
    ('test-config.lua', ROOT/'homepublish/files/usr/share/homepublish'),
    ('test-core.lua', ROOT/'homepublish/files/usr/share/homepublish'),
    ('test-publication-config.lua', ROOT/'homepublish/files/usr/share/homepublish'),
])
def test_current_lua_contract(name, argument):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().arg = lua.table_from({1: argument.as_posix()})
    lua.execute((HERE/name).read_text(encoding='utf-8-sig'))
