local M = {}

-- Player-facing text is UTF-8 so a localization can ship as source text. The
-- font, material and atlas come from the active locale's native body face, so
-- any script that face covers is drawable. Keep rejecting the semicolon the
-- forecast markup reserves and control codes the native text pipeline cannot
-- draw, plus malformed, overlong, surrogate and out-of-range UTF-8.
function M.display(text)
    assert(type(text) == 'string' and not text:find(';', 1, true),
        'Display text must be a string without semicolons')
    local index,length = 1,#text
    while index<=length do
        local byte = text:byte(index)
        local size,code
        if byte<0x80 then size,code = 1,byte
        elseif byte>=0xC2 and byte<=0xDF then size,code = 2,byte-0xC0
        elseif byte>=0xE0 and byte<=0xEF then size,code = 3,byte-0xE0
        elseif byte>=0xF0 and byte<=0xF4 then size,code = 4,byte-0xF0
        else size,code = 0,0 end
        assert(size>0 and index+size-1<=length, 'Display text must be valid UTF-8')
        for offset=1,size-1 do
            local follow = text:byte(index+offset)
            assert(follow and follow>=0x80 and follow<=0xBF, 'Display text must be valid UTF-8')
            code = code*64+follow-0x80
        end
        assert(not (size==1 and (byte<0x20 or byte==0x7F)) and not (code>=0x80 and code<=0x9F),
            'Display text must not contain control codes')
        assert(not (size==2 and code<0x80) and not (size==3 and code<0x800)
            and not (size==4 and code<0x10000), 'Display text must not use overlong UTF-8')
        assert(not (code>=0xD800 and code<=0xDFFF) and code<=0x10FFFF,
            'Display text must be a Unicode code point')
        index = index+size
    end
    return text
end

function M.make(snapshot, catalogue)
    local cards = {}
    for _, tag in ipairs(snapshot.tags) do
        local entry = catalogue[tag]
        if entry then
            cards[#cards + 1] = {title=M.display(entry[1]), detail=M.display(entry[2])}
        end
    end
    -- Player-facing text is Simplified Chinese. Unit and faction names follow
    -- the game's own zh-CN resources; the rest is this localization's wording.
    if #cards == 0 then
        if snapshot.complete and #snapshot.tags==0 then
            cards[1] = {title='常规部队', detail='未选中特殊敌军编组'}
        else
            cards[1] = {title='暂无编组情报', detail='无法确定此任务的敌军编组'}
        end
    end
    if snapshot.heavies and #snapshot.heavies > 0 then
        cards[#cards+1] = {title='重型敌人',
            detail=M.display(table.concat(snapshot.heavies,', '))}
    end
    local footer = '可能遭遇的敌人，不保证实际出现。'
    if not snapshot.complete then footer = '基础预测：特殊敌人情报尚不完整。' end
    if snapshot.difficulty < 6 then
        footer = snapshot.complete and '编组特征：兵种随难度变化。' or footer
    end
    local parts = {}
    for _,card in ipairs(cards) do
        parts[#parts+1] = '['..card.title..'] '..card.detail
    end
    return {key=snapshot.key, screen=snapshot.screen,
        marquee=M.display(table.concat(parts,'    //    ')..'    /// END REPORT ///'),
        footer=footer, label='敌情预测 // 情报与侦察', complete=snapshot.complete}
end

return M
