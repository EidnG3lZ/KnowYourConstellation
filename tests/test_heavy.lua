local source=assert(arg[1])
local heavy=assert(loadfile(source..'/heavy.lua'))()
local data=assert(loadfile(source..'/heavy_data.lua'))()
local function got(tags,difficulty,complete)
    return table.concat(heavy.possible({faction=2,tags=tags,difficulty=difficulty,complete=complete},data),',')
end
assert(got({1},10,true)=='吐酸泰坦')
assert(got({6},9,true)=='吐酸泰坦')
assert(got({1,11},10,true)=='蟑龙')
assert(got({1},10,false)=='')
assert(got({1},1,true)=='')
assert(got({1,9},10,true)=='阴霾吐酸泰坦')
-- Heavy labels are drawn, so they must avoid the same unavailable glyphs and
-- must not stay English after an upstream regeneration of this table.
for _, label in pairs(data.labels) do
    assert(not label:find('汁',1,true), 'Heavy label uses a glyph the game cannot draw')
    assert(not label:find('[A-Za-z]'), 'Heavy label is not localized: '..label)
end
print('PASS: difficulty gates, Titan versus Dragon replacement, Gloom replacement, localized labels and incomplete-data suppression')
