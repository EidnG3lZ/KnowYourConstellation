local M = {}

function M.layout(width,height,anchor)
    assert(anchor and width>=640 and height>=480, 'Native panel unavailable')
    local s = anchor.scale
    local h = 82*s
    -- Share the native frame's bottom stroke instead of doubling its thickness.
    local y = anchor.y-h+3*s
    local box = {x=anchor.x,y=y,w=anchor.w,h=h,scale=s,
        title_size=18*s,detail_size=20*s,small_size=13*s,padding=30*s,border=3*s,inset=7*s}
    assert(box.x>=0 and box.y>=0 and box.x+box.w<=width+1 and box.y+box.h<=height+1
        and anchor.y+anchor.h<=height+1,
        'Native panel outside viewport')
    return box
end

-- A continuation byte cannot open a UTF-8 character, so it marks a cut that
-- would split one.
local function continuation(byte)
    return byte~=nil and byte>=0x80 and byte<=0xBF
end

-- Index just past the UTF-8 character opening at index. Carets and cuts are
-- always taken on character boundaries: hand the native text pipeline a
-- partial sequence and it cannot lay the string out, which locks the game up.
local function character(text,index)
    local byte=text:byte(index)
    local size
    if byte<0x80 then size=1
    elseif byte<0xE0 then size=2
    elseif byte<0xF0 then size=3
    else size=4 end
    if index+size-1>#text then size=1 end
    return index+size
end

-- Remove fully offscreen glyphs. Opaque padding clips partial edge glyphs,
-- letting the text move in pixels without drawing outside our own strip.
function M.window(metrics,distance,width)
    -- Negative distance is the initial entry from offscreen right. Do not
    -- wrap it into the repeated text, which would skip the opening words.
    local offset = distance<0 and distance or distance % metrics.period
    local first = 1
    while metrics.edges[first+1]<=offset do first=first+1 end
    local last = first
    while metrics.edges[last]<offset+width do last=last+1 end
    -- The caret table advances on character boundaries, so the opening cut is
    -- already whole. The closing cut can still land inside a character: widen
    -- it, and let the opaque strip clip the partial trailing glyph, so the
    -- native renderer only ever receives complete sequences.
    local text = metrics.text
    while first>1 and continuation(text:byte(first)) do first=first-1 end
    while last<=#text and continuation(text:byte(last)) do last=last+1 end
    return text:sub(first,last-1),metrics.edges[first]-offset
end

function M.new(engine,trace)
    trace = trace or function() end
    local self = {cache={},cache_order={}}
    local App,World,Gui = engine.Application,engine.World,engine.Gui
    local function exists(list,wanted)
        for _,world in ipairs(list or {}) do if world==wanted then return true end end
        return false
    end
    local function worlds()
        local list = App.worlds()
        assert(type(list)=='table', 'UI worlds unavailable')
        return list
    end
    local function destroy()
        if self.gui and exists(worlds(),self.world) then World.destroy_gui(self.world,self.gui) end
        self.gui,self.world,self.text_id = nil,nil,nil
        self.layout_signature,self.font_signature,self.caption_signature = nil,nil,nil
        self.rect_ids,self.label_id,self.footer_id = nil,nil,nil
    end
    function self:clear()
        destroy()
        self.distance,self.metrics,self.mission = nil,nil,nil
        self.label,self.footer = nil,nil
        self.cache,self.cache_order = {},{}
    end
    local function colour(a,r,g,b) return engine.Color(a,r,g,b) end
    local function vector(x,y,z) return engine.Vector3(x,y,z or 0) end
    -- Player-facing text is UTF-8 so a localization can ship as source text.
    -- Keep rejecting the semicolon the forecast markup reserves and control
    -- codes the native text pipeline cannot draw, plus malformed, overlong,
    -- surrogate and out-of-range UTF-8.
    local function display(text)
        assert(type(text)=='string' and not text:find(';',1,true),
            'Display text must be a string without semicolons')
        local index,length=1,#text
        while index<=length do
            local byte=text:byte(index)
            local size,code
            if byte<0x80 then size,code=1,byte
            elseif byte>=0xC2 and byte<=0xDF then size,code=2,byte-0xC0
            elseif byte>=0xE0 and byte<=0xEF then size,code=3,byte-0xE0
            elseif byte>=0xF0 and byte<=0xF4 then size,code=4,byte-0xF0
            else size,code=0,0 end
            assert(size>0 and index+size-1<=length, 'Display text must be valid UTF-8')
            for offset=1,size-1 do
                local follow=text:byte(index+offset)
                assert(follow and follow>=0x80 and follow<=0xBF, 'Display text must be valid UTF-8')
                code=code*64+follow-0x80
            end
            assert(not (size==1 and (byte<0x20 or byte==0x7F)) and not (code>=0x80 and code<=0x9F),
                'Display text must not contain control codes')
            assert(not (size==2 and code<0x80) and not (size==3 and code<0x800)
                and not (size==4 and code<0x10000), 'Display text must not use overlong UTF-8')
            assert(not (code>=0xD800 and code<=0xDFFF) and code<=0x10FFFF,
                'Display text must be a Unicode code point')
            index=index+size
        end
        return text
    end
    -- The active face is the only source of glyphs, and a character it cannot
    -- draw is replaced by the notdef mark, which is what the game shows as a
    -- question mark. Private-use code points are never in a game font, so their
    -- ink is the notdef ink: any character with that same ink is undrawable.
    -- Each character is probed once and reported, so a localization can see
    -- exactly which characters this face may use.
    local glyphs,missing={},{}
    local function probe_glyphs(value,font,size)
        local function ink(one)
            local lo,hi=Gui.text_extents(self.gui,one,font,size)
            assert(lo and hi, 'Font metrics unavailable')
            return engine.Vector2.x(hi)-engine.Vector2.x(lo)
        end
        local notdef
        local at=1
        while at<=#value do
            local next_at=character(value,at)
            local one=value:sub(at,next_at-1)
            if glyphs[one]==nil then
                if one:find('[^\32-\126]') then
                    if not notdef then notdef=ink('\238\128\128') end
                    glyphs[one]=math.abs(ink(one)-notdef)<.01
                    if glyphs[one] then missing[#missing+1]=one end
                else
                    glyphs[one]=false
                end
            end
            at=next_at
        end
        return missing
    end
    local function metrics_for(text,font,box,font_name)
        local available=box.w-2*box.padding
        local key=table.concat({text,font_name,box.detail_size,available},'|')
        if self.cache[key] then return self.cache[key] end
        local cycle=text..'      '
        assert(#cycle<=4096, 'Forecast exceeds marquee bounds')
        -- Cold path: the only place that measures localized text. Trace the
        -- stage first, so a frame that blocks here still names the stage.
        trace('panel measuring '..#cycle..'B font='..tostring(font_name))
        local function advance(value)
            local _,_,caret=Gui.text_extents(self.gui,value,font,box.detail_size)
            assert(caret, 'Font caret unavailable')
            return engine.Vector2.x(caret)
        end
        local edges={0}
        -- Measure one cycle. Trailing spaces isolate successive cycles from
        -- kerning, so repeated copies normally reuse the same caret positions.
        -- Only whole-character prefixes are measured, so the native pipeline
        -- never receives a partial UTF-8 sequence. Every byte of a character
        -- repeats that character's closing caret, which keeps the table
        -- byte-addressable for M.window without measuring a partial sequence.
        local function extend(source,from,to)
            local at=from
            while at<=to do
                local next_at=character(source,at)
                local caret=advance(source:sub(1,next_at-1))
                local step=caret-edges[at]
                assert(step>=0 and step<box.padding-box.inset, 'Invalid caret advance')
                for index=at,next_at-1 do edges[index+1]=caret end
                at=next_at
            end
        end
        extend(cycle,1,#cycle)
        local period=edges[#cycle+1]
        assert(period>0, 'Empty marquee')
        local copies=math.ceil(available/period)+2
        local repeated=cycle:rep(copies)
        local additive=math.abs(advance(cycle..cycle)-2*period)<.001
        if additive then
            for i=#cycle+1,#repeated do
                local cycles=math.floor(i/#cycle)
                edges[i+1]=cycles*period+edges[i%#cycle+1]
            end
        else
            -- Keep exact shaping if this font does not have additive cycle
            -- advances, instead of assuming fixed-width glyphs.
            extend(repeated,#cycle+1,#repeated)
        end
        local result={text=repeated,edges=edges,period=period,width=available,scale=box.scale}
        self.cache[key]=result
        self.cache_order[#self.cache_order+1]=key
        if #self.cache_order>8 then self.cache[table.remove(self.cache_order,1)]=nil end
        return result
    end
    function self:show(model,dt,anchor)
        local main,target = App.main_world(),nil
        for _,world in ipairs(worlds()) do if world~=main then target=world break end end
        if not target then self:clear() return false end
        if self.world and self.world~=target then self:clear() end
        local width,height = Gui.resolution()
        local box = M.layout(width,height,anchor)
        -- Engine IDs are temporary. Only Lua strings and numeric metrics are
        -- cached across frames, never font/material/vector userdata.
        local font = engine.IdString64.from_hex(anchor.font)
        local material = engine.IdString64.from_hex(anchor.material)
        local font_signature=table.concat({anchor.font,anchor.material,anchor.atlas},'|')
        if not self.gui or self.font_signature~=font_signature then
            destroy()
            self.gui = World.create_screen_gui(target,'scale',1,1)
            assert(self.gui, 'Could not create forecast strip')
            self.world = target
            -- Mirror native normal-font setup on our own GUI material.
            local ink = assert(Gui.material(self.gui,material), 'Font material unavailable')
            local function slot(hash) return engine.IdString64.from_hex(hash..'00000000') end
            for _,hash in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'}) do
                engine.Material.set_scalar(ink,slot(hash),0)
            end
            engine.Material.set_vector2(ink,slot('e13777ce'),engine.Vector2(1,-1))
            engine.Material.set_vector4(ink,slot('7701209e'),colour(0,0,0,0))
            engine.Material.set_texture(ink,slot('88bac99b'),engine.IdString64.from_hex(anchor.atlas))
            self.font_signature=font_signature
            self.rect_ids={}
        end
        local metrics,remeasured=false,false
        if model.marquee then
            metrics=metrics_for(display(model.marquee),font,box,anchor.font)
            local mission=model.screen..'|'..model.key
            if metrics~=self.metrics or mission~=self.mission then
                remeasured=true
                local previous=self.metrics
                if not previous then
                    self.distance=-metrics.width
                elseif self.distance<0 then
                    self.distance=self.distance/previous.width*metrics.width
                elseif mission~=self.mission then
                    self.distance=(self.distance%previous.period)/previous.period*metrics.period
                else
                    -- Metadata can add/remove sections after a mission is first
                    -- highlighted. Do not remap that mission's cursor by length.
                    self.distance=self.distance*metrics.scale/previous.scale
                end
                self.metrics,self.mission=metrics,mission
            end
        end
        local gui=self.gui
        local x,y,w,h,s,b,p,i=box.x,box.y,box.w,box.h,box.scale,box.border,box.padding,box.inset
        local layout_signature=table.concat({width,height,x,y,w,s},'|')
        local moved=layout_signature~=self.layout_signature
        -- Native menu palette and geometry captured from the supported build.
        -- The body sits 4 UI units inside the 3-unit gold outline. Keep the
        -- clipping masks inside that opaque body so the inset stays translucent.
        local yellow,border,background=colour(255,255,213,0),colour(255,255,185,0),colour(255,15,20,30)
        self.baseline=y+h-49*s
        if moved then
            local function rect(index,rx,ry,rw,rh,z,ink)
                local pos,size=vector(rx,ry,z),engine.Vector2(rw,rh)
                if self.rect_ids[index] then
                    Gui.update_rect(gui,self.rect_ids[index],pos,size,ink)
                else
                    self.rect_ids[index]=assert(Gui.rect(gui,pos,size,ink), 'Retained rectangle unavailable')
                end
            end
            rect(1,x+i,y+i,w-2*i,h-2*i,901,background)
            rect(2,x,y+h-b,w,b,904,border)
            rect(3,x,y,w,b,904,border)
            rect(4,x,y,b,h,904,border)
            rect(5,x+w-b,y,b,h,904,border)
            rect(6,x+i,self.baseline-5*s,p-i,29*s,903,background)
            rect(7,x+w-p,self.baseline-5*s,p-i,29*s,903,background)
            rect(8,x+b,y+b,w-2*b,h-2*b,900,colour(204,0,0,0))
        end
        local caption_signature=table.concat({display(model.label),display(model.footer),w,s},'|')
        local captions_changed=caption_signature~=self.caption_signature
        if captions_changed then
            local function fit(text,size)
                local lo,hi=Gui.text_extents(gui,text,font,size)
                assert(lo and hi, 'Font metrics unavailable')
                local measured=engine.Vector2.x(hi)-engine.Vector2.x(lo)
                if measured>w-2*p then size=size*(w-2*p)/measured end
                assert(size>=10*s, 'Forecast text exceeds panel width')
                return size
            end
            self.label_size=fit(model.label,box.title_size)
            self.footer_size=fit(model.footer,box.small_size)
        end
        if moved or captions_changed then
            local function line(id,text,size,top,ink)
                local pos=vector(x+p,y+h-top*s,902)
                if id then Gui.update_text(gui,id,text,font,size,material,pos,ink) return id end
                return Gui.text(gui,text,font,size,material,pos,ink)
            end
            self.label_id=line(self.label_id,model.label,self.label_size,24,yellow)
            self.footer_id=line(self.footer_id,model.footer,self.footer_size,68,colour(255,179,198,205))
        end
        self.layout_signature,self.caption_signature=layout_signature,caption_signature
        self.label,self.footer=model.label,model.footer
        if not self.text_id then
            self.text_id=assert(Gui.text(gui,' ',font,box.detail_size,material,
                vector(x+p,self.baseline,902),colour(255,240,243,245)), 'Retained text unavailable')
        end
        local text,offset = '',0
        if metrics then text,offset=M.window(metrics,self.distance,metrics.width) end
        if remeasured then
            trace('panel drawing '..#text..'B font='..tostring(anchor.font))
            -- Never let a diagnostic break the frame: report what the face can
            -- draw, and stay silent if the engine refuses the probe.
            pcall(function()
                local absent=probe_glyphs((model.marquee or '')..(model.label or '')..(model.footer or ''),
                    font,box.detail_size)
                trace('font missing '..#absent..' '..table.concat(absent)..' font='..tostring(anchor.font))
            end)
        end
        Gui.update_text(gui,self.text_id,text,font,box.detail_size,material,
            vector(x+p+offset,self.baseline,902),colour(255,240,243,245))
        if metrics then
            self.distance=self.distance+math.max(0,math.min(dt or 0,0.1))*64*s
            if self.distance>=0 then self.distance=self.distance%metrics.period end
        end
        return true
    end
    function self:suspend(anchor)
        -- Keep the existing frame and captions while the next report resolves.
        -- Clear only enemy text and leave scroll state and measurements intact.
        if not self.gui then return false end
        return self:show({label=self.label,footer=self.footer},0,anchor)
    end
    return self
end

return M
