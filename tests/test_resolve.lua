local source = assert(arg[1])
local resolve = assert(loadfile(source..'/resolve.lua'))()
local catalogue = assert(loadfile(source..'/catalogue.lua'))()
local model = assert(loadfile(source..'/model.lua'))()
local function settings(weights)
    local ids = {1,2,3,5,7,6}
    local rows = {}
    for i,id in ipairs(ids) do rows[i] = {id=id,weight=weights[i],only_when_empty=false} end
    return {draws=1,candidates=rows,blockers={},fallback=0}
end
local low = settings({1,0.5,1,0.7,0.7,1})
local high = settings({1,0.8,1,0.2,0.5,1})
-- Settings are replaced below by recorded values generated from each native
-- capture. The comparisons exercise unsigned RNG output and float32 rounding.
local fixture = assert(loadfile(source..'/../tests/fixtures/seeds.lua'))()
for _, row in ipairs(fixture) do
    local got = resolve.base(row.seed,row.settings,row.initial)
    assert(table.concat(got,',') == table.concat(row.expected,','), 'Recorded seed mismatch: '..row.seed)
end
local fallback = {draws=1,candidates={},blockers={26,27,28,29,0},fallback=27}
assert(resolve.base(3,fallback,{})[1] == 27)
assert(table.concat(resolve.base(3,fallback,{26}),',') == '26')
local filtered = resolve.filter({1,11,9},1,{[9]=true})
assert(#filtered == 1 and filtered[1] == 11)
assert(not pcall(resolve.base,1,{draws=17,candidates={},blockers={},fallback=0},{}))
for id, entry in pairs(catalogue) do
    assert(id >= 1 and id <= 31)
    model.display(entry[1])
    model.display(entry[2])
end
-- The supported build's face has no glyph for these, and the engine draws the
-- notdef mark instead, which players see as a question mark. The list comes
-- from the in-game glyph report (EnemyIntelligenceFont.log); shipped wording
-- must avoid every entry.
local unavailable={'汁'}
for id, entry in pairs(catalogue) do
    for _, value in ipairs({entry[1], entry[2]}) do
        for _, glyph in ipairs(unavailable) do
            assert(not value:find(glyph,1,true),
                'Catalogue entry '..id..' uses a glyph the game cannot draw: '..glyph)
        end
    end
end
local captions=model.make({key='glyphs',screen='map',difficulty=10,tags={},complete=true},catalogue)
for _, value in ipairs({captions.label, captions.footer}) do
    for _, glyph in ipairs(unavailable) do
        assert(not value:find(glyph,1,true),
            'Panel caption uses a glyph the game cannot draw: '..glyph)
    end
end
-- Everything drawn is Chinese. Latin letters may only survive in the literal
-- markup the renderer splits on, so a merge that restores upstream English
-- fails here instead of shipping a half-translated panel.
local function localized(value) return not value:find('[A-Za-z]') end
local function drawn(marquee) return localized(marquee:gsub('/// END REPORT ///',''):gsub('//','')) end
-- Entry 31 is upstream's HORDE FORCES card for a mission mode this build does
-- not reach. Its wording is still undecided, so it stays English as the one
-- documented exception; every other entry must be Chinese.
local pending={[31]=true}
for id, entry in pairs(catalogue) do
    if not pending[id] then
        assert(localized(entry[1]) and localized(entry[2]), 'Catalogue entry '..id..' is not localized')
    end
end
assert(not localized(catalogue[31][1]), 'Entry 31 is no longer the pending English card')
for _, case in ipairs({
    {tags={1,11},complete=true,difficulty=10},
    {tags={},complete=true,difficulty=10},
    {tags={},complete=false,difficulty=10},
    {tags={},complete=true,difficulty=5},
    {tags={1},complete=true,difficulty=10,heavies={'重型敌人占位'}}}) do
    local made=model.make({key='localized',screen='map',tags=case.tags,difficulty=case.difficulty,
        complete=case.complete,heavies=case.heavies},catalogue)
    assert(drawn(made.marquee), 'Panel text is not localized: '..made.marquee:gsub('[^\32-\126]','.'))
    assert(localized(made.label) and localized(made.footer), 'Panel captions are not localized')
end
local m = model.make({key='mission',screen='map',difficulty=10,tags={1,11},complete=false},catalogue)
assert(m.footer:find('尚不完整',1,true))
-- The section separators and terminator stay literal; the text between them
-- comes from the catalogue so a localization does not have to restate it.
assert(m.marquee=='['..catalogue[1][1]..'] '..catalogue[1][2]..'    //    '..
    '['..catalogue[11][1]..'] '..catalogue[11][2]..'    /// END REPORT ///')
-- Localized text is expected. Malformed UTF-8, control codes and the reserved
-- semicolon stay rejected.
assert(model.display('bad'..string.char(226,128,148)))
assert(model.display('本地化'))
assert(not pcall(model.display,'bad'..string.char(226,128)))
assert(not pcall(model.display,'bad'..string.char(128)))
assert(not pcall(model.display,'bad'..string.char(192,175)))
assert(not pcall(model.display,'bad'..string.char(237,160,128)))
assert(not pcall(model.display,'bad'..string.char(244,144,128,128)))
assert(not pcall(model.display,'bad'..string.char(0)))
assert(not pcall(model.display,'bad'..string.char(127)))
assert(not pcall(model.display,'bad'..string.char(59)))
local standard=model.make({key='standard',screen='map',difficulty=1,tags={},complete=true},catalogue)
assert(standard.marquee=='[常规部队] 未选中特殊敌军编组    /// END REPORT ///')
local unavailable=model.make({key='pending',screen='map',difficulty=1,tags={},complete=false},catalogue)
assert(unavailable.marquee:find('暂无编组情报',1,true),
    'Unresolved data must not be presented as a standard composition')
print('PASS: recorded seed predictions, fallback, exclusions, modifier display and UTF-8 display text')
assert(resolve.from_native(0)==0 and resolve.from_native(1)==31)
for id=2,31 do assert(resolve.from_native(id)==id-1) end
assert(not pcall(resolve.from_native,32))
assert(table.concat(resolve.filter({1,11,9},{[1]=true,[11]=true},{}),',')=='9')
