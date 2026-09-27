"""Build the stable runtime wrapper shared by standalone and megapack builds."""
REVISION = 'v3.16'
ROWS_REVISION = REVISION + '-rows-v1'
MODULE = 'mods/cowboybingus/enemy_intelligence'
TESTED_RESOURCE_SHA = '8B0929FB67A59AD5D950D231D059650894DE0472F053FC1F86DF8DFD0F01A60E'
TESTED_ROWS_RESOURCE_SHA = 'A295CA7C367FF69D63D3D5346A610034A7B6A9BE1472434F061D322190D96689'


def module_source(root, name):
    """Read one shipped Lua module as UTF-8 source text.

    Display text may be localized, so the pipeline reads and writes UTF-8 end
    to end. LuaJIT compiles byte strings unchanged, which carries non-ASCII
    text into the dumped bytecode verbatim.
    """
    text = (root / 'src' / (name + '.lua')).read_text(encoding='utf-8')
    assert not text.startswith('\ufeff'), 'Lua sources must not open with a byte-order mark: ' + name
    return text


def wrapper(root, game_sha, exe_sha, rows=False):
    result = ''
    for variable, filename in [('create_api','read_api'), ('resolve','resolve'), ('mission','mission'),
                               ('catalogue','catalogue'), ('model','model'), ('panel','panel'), ('install','install'),
                               ('heavy','heavy'), ('heavy_data','heavy_data'), ('presentation','presentation')]:
        source = module_source(root, filename)
        for forbidden in ('WriteProcessMemory', 'VirtualProtect', 'VirtualAlloc', 'CreateRemoteThread',
                          'Network.', 'RPC.', "ffi.cast('void (*"):
            assert forbidden not in source, 'Unexpected side effect API: ' + forbidden
        result += 'local ' + variable + ' = (function()\n' + source + '\nend)()\n'
    revision = REVISION
    if rows:
        source = module_source(root, 'rows')
        result += 'panel = (function()\n' + source + '\nend)()(panel)\n'
        revision = ROWS_REVISION
    result += "install(create_api,mission,resolve,catalogue,model,panel,{revision='" + revision
    result += "',game_sha256='" + game_sha + "',exe_sha256='" + exe_sha + "'},heavy,heavy_data,presentation)\n"
    return result
