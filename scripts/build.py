"""Build the local-only Know Your Constellation release without deploying it."""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True
from archive import GAME, LUA, EXE_SHA, GAME_DLL_SHA, ARCHIVE, sha, make_archive, resource_hash
from module import MODULE, REVISION, ROWS_REVISION, TESTED_RESOURCE_SHA, TESTED_ROWS_RESOURCE_SHA, wrapper
from package import package_release

ROOT = Path(__file__).resolve().parents[1]
GUID = '9a9c8423-8f3e-4b7b-9a16-7d0b78ff1a18'
ROWS_GUID = '3b68356c-b11c-431a-aa5a-d7b1ca50b189'
SUMMARY = 'Reveals mission constellations and enemy forecasts on the war table and briefing screen so you can choose your loadout before deployment.'
# Manager-facing text for the Simplified Chinese localization. The provenance
# name, slug and release filename stay ASCII so the package keeps its identity.
LOCALIZED_NAME = '敌情预测'
LOCALIZED_ROWS_NAME = '敌情预测·分行显示'
LOCALIZED_SUMMARY = '在银河战争地图及任务简报中显示敌军编组与可能遭遇的敌人，方便选择武装配置。'
LOCALIZED_ROWS_SUMMARY = '采用静态分行显示，支持中文换行。'
LOCALIZED_TAIL = '仅在本机显示。需要另行安装 Bingus Shared Loader v12 或更新版本。'
LOCALIZED_LAST = '仅启用一种敌情预测版本；不保证预测敌人实际出现。'


def run(arguments):
    env = dict(os.environ, LUA_PATH=str(LUA.parent / '?.lua') + ';;')
    # LuaJIT reports failing source lines verbatim, which may be localized text.
    # Decode as UTF-8 rather than the console code page so diagnostics stay readable.
    process = subprocess.run(list(map(str, arguments)), capture_output=True,
                             encoding='utf-8', errors='replace', env=env)
    if process.returncode:
        raise RuntimeError(process.stdout + process.stderr)
    return process.stdout


def gc64():
    """Report whether the host LuaJIT uses 64-bit GC64 pointers.

    The shipped chunk is dumped non-GC64 for the game's loader, and a GC64 host
    VM refuses to load it. The local package test then runs an equivalent GC64
    dump of the identical wrapper source; the shipped bytes never change.
    """
    return run([LUA, '-e', "io.write(tostring(require('ffi').abi('gc64')))"]) == 'true'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rows', action='store_true', help='Build the alternate static rows package')
    parser.add_argument('--allow-untested', action='store_true', help='Build a local test package when the runtime differs from the in-game verified payload')
    args = parser.parse_args()
    build = ROOT / ('build/rows' if args.rows else 'build')
    build.mkdir(parents=True, exist_ok=True)
    for filename, expected in [('bin/helldivers2.exe', EXE_SHA), ('data/game/game.dll', GAME_DLL_SHA)]:
        assert sha((GAME / filename).read_bytes()) == expected, 'Unsupported game build'
    source = build / 'mod.wrapper.lua'
    source.write_text(wrapper(ROOT, GAME_DLL_SHA, EXE_SHA, rows=args.rows), encoding='utf-8', newline='\n')
    tests = ''
    suites = ('resolve', 'panel', 'install', 'mission', 'heavy', 'presentation')
    for name in suites + (('rows',) if args.rows else ()):
        tests += run([LUA, ROOT / ('tests/test_' + name + '.lua'), ROOT / 'src'])
    compiled = build / 'mod.ljbc'
    run([LUA, '-bsdW', source, compiled])
    code = compiled.read_bytes()
    assert code[:5] == b'\x1bLJ\x02\x02'
    resource = struct.pack('<II', len(code), 2) + code
    runtime_verified = sha(resource) == (TESTED_ROWS_RESOURCE_SHA if args.rows else TESTED_RESOURCE_SHA)
    assert runtime_verified or args.allow_untested, 'Runtime differs from the in-game verified payload; use --allow-untested for a local test build'
    if args.rows:
        # Keep verification of the scrolling alternative separate from rows.
        baseline_source, baseline_code = build / 'scrolling.wrapper.lua', build / 'scrolling.ljbc'
        baseline_source.write_text(wrapper(ROOT, GAME_DLL_SHA, EXE_SHA), encoding='utf-8', newline='\n')
        run([LUA, '-bsdW', baseline_source, baseline_code])
        baseline = baseline_code.read_bytes()
        scrolling_verified = sha(struct.pack('<II', len(baseline), 2) + baseline) == TESTED_RESOURCE_SHA
        assert scrolling_verified or args.allow_untested, 'Scrolling runtime differs from the in-game verified payload'
    revision = ROWS_REVISION if args.rows else REVISION
    # The game's loader is non-GC64, so the shipped chunk stays a -W dump. A
    # GC64 host cannot load that chunk, so the package test runs the same
    # wrapper dumped for the host. The verified resource hash is unaffected.
    tested = compiled
    if gc64():
        tested = build / 'mod.host.ljbc'
        run([LUA, '-bsdX', source, tested])
    tests += run([LUA, ROOT / 'tests/test_package.lua', tested, revision])
    (build / 'mod.lua.main').write_bytes(resource)
    for suffix, data in [('',make_archive({resource_hash(MODULE):resource})),('.stream',b''),('.gpu_resources',b'')]:
        (build / (ARCHIVE + suffix)).write_bytes(data)
    files = {f'data/{ARCHIVE}{s}':(build / (ARCHIVE+s)).relative_to(ROOT).as_posix()
             for s in ('','.stream','.gpu_resources')}
    name = 'Know Your Constellation Rows' if args.rows else 'Know Your Constellation'
    guid = ROWS_GUID if args.rows else GUID
    summary = SUMMARY + (' Displays the complete forecast in static rows. Enable only one forecast variant.' if args.rows else '')
    localized_name = LOCALIZED_ROWS_NAME if args.rows else LOCALIZED_NAME
    localized_summary = LOCALIZED_SUMMARY + (LOCALIZED_ROWS_SUMMARY if args.rows else '')
    report = {'name':name,'slug':name.replace(' ',''),'revision':revision,'guid':guid,
        'description':summary + ' Client-side only. Requires Bingus Shared Loader v12 or newer. Spawns are not guaranteed.',
        'localized_name':localized_name + ' - ' + REVISION + ' 简体中文',
        'localized_description':localized_summary + LOCALIZED_TAIL + LOCALIZED_LAST,
        'localization':{'language':'zh-CN','source_revision':revision,
            'in_game_verified':runtime_verified,'utf8_wrap':True},
        'module':MODULE,'game_exe_sha256':EXE_SHA,'game_dll_sha256':GAME_DLL_SHA,
        'runtime_verified':runtime_verified,'client_only':True,'network_calls':False,'gameplay_memory_writes':False,
        'requires':[{'name':'Bingus Shared Loader','revision':'loader-v12','api':1}],
        'deployment_files':files,'files':{p:sha((ROOT/p).read_bytes()) for p in files.values()},
        'resource_sha256':sha(resource),'offline_tests':tests.strip()}
    report['install_instructions'] = 'INSTALL-zh-CN.txt'
    if args.rows:
        report.update(version=REVISION.removeprefix('v'))
    release = package_release(ROOT,build,report)
    with zipfile.ZipFile(release) as package:
        manifest = json.loads(package.read('manifest.json'))
        assert manifest['Name']==report['localized_name'] and manifest['Guid']==guid
        assert manifest['IconPath']==manifest['Options'][0]['Image']=='thumbnail.png'
        archive = package.read('data/'+ARCHIVE)
        entry = struct.unpack_from('<7Q6I',archive,104)
        assert struct.unpack_from('<III',archive)==(0xF0000011,1,1)
        assert entry[0]==resource_hash(MODULE) and archive[entry[2]:entry[2]+entry[7]]==resource
    report['release_sha256']=sha(release.read_bytes())
    (build/'build-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    (build/'offline-tests.txt').write_text(tests,encoding='utf-8')
    print(tests.strip())
    print('PASS: runtime matches the in-game verified payload' if runtime_verified else 'In-game verification pending for this test build')
    print('Built '+str(release))


if __name__ == '__main__':
    main()
