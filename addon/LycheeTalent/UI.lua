local _, A = ...
local L=A.L
local U={scene="mythic",results={},offset=0,rows={},shared=false}
A.UI=U
local C={bg={.055,.055,.063},hover={.09,.09,.09},selected={.085,.085,.085},
    red={.835,.235,.285},hot={.95,.35,.4},text={.94,.932,.91},muted={.71,.705,.69},
    dim={.59,.58,.59},field={.085,.085,.095},border={.19,.18,.19}}
local media="Interface\\AddOns\\LycheeTalent\\Media\\"
local ROW_HEIGHT,ROW_STEP,MENU_STEP=58,64,44
local function color(fs,c) fs:SetTextColor(c[1],c[2],c[3]) end
local function text(parent,size,c,value,x,y,w)
    x=x*280/340; if w then w=w*280/340 end
    local t=parent:CreateFontString(nil,"OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT,math.max(16,size+4),""); t:SetShadowOffset(0,0)
    t:SetPoint("TOPLEFT",x,y); if w then t:SetWidth(w) end
    t:SetJustifyH("LEFT"); color(t,c); t:SetText(value or "")
    return t
end
local function fill(parent,c)
    local t=parent:CreateTexture(nil,"BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(c[1],c[2],c[3],1); return t
end
local function rounded(parent,c,r)
    local parts={}; local mid=parent:CreateTexture(nil,"BACKGROUND"); mid:SetPoint("TOPLEFT",r,0); mid:SetPoint("BOTTOMRIGHT",-r,0)
    mid:SetColorTexture(c[1],c[2],c[3],1); parts[#parts+1]=mid
    for _,side in ipairs({"LEFT","RIGHT"}) do
        local strip=parent:CreateTexture(nil,"BACKGROUND"); strip:SetPoint("TOP"..side,0,-r); strip:SetPoint("BOTTOM"..side,0,r); strip:SetWidth(r)
        strip:SetColorTexture(c[1],c[2],c[3],1); parts[#parts+1]=strip
    end
    for _,v in ipairs({{"TOPLEFT",0,1,0,1},{"TOPRIGHT",1,0,0,1},{"BOTTOMLEFT",0,1,1,0},{"BOTTOMRIGHT",1,0,1,0}}) do
        local t=parent:CreateTexture(nil,"BACKGROUND"); t:SetSize(r,r); t:SetPoint(v[1]); t:SetTexture(media.."corner.tga")
        t:SetTexCoord(v[2],v[3],v[4],v[5]); t:SetVertexColor(c[1],c[2],c[3]); parts[#parts+1]=t
    end
    return parts
end
-- Match Lychee Components: 12px hit gutter, 3px accent thumb, no visible track.
local function scrollbar(parent)
    local bar=CreateFrame("Slider",nil,parent)
    bar:SetWidth(12);bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1);bar:SetObeyStepOnDrag(true)
    local thumb=bar:CreateTexture(nil,"ARTWORK");bar.thumb=thumb
    bar:SetThumbTexture(thumb);thumb:SetSize(3,24);thumb:SetColorTexture(unpack(C.red))
    function bar:SizeThumb(total,viewport)
        local height=math.max(0,self:GetHeight())
        local size=math.min(height,48,math.max(24,height*viewport/math.max(1,total)))
        if self.thumbHeight~=size then self.thumb:SetHeight(size);self.thumbHeight=size end
    end
    return bar
end
local function button(parent,label,x,y,w,callback,accent)
    x=x*280/340; w=(w or 110)*280/340
    local b=CreateFrame("Button",nil,parent); b:SetSize(w or 110,30); b:SetPoint("TOPLEFT",x,y)
    b.label=text(b,14,accent and C.hot or C.text,label,0,0)
    b.label:ClearAllPoints(); b.label:SetPoint("CENTER")
    b:SetScript("OnEnter",function(self) if self:IsEnabled() then color(self.label,C.hot) end end)
    b:SetScript("OnLeave",function(self) color(self.label,self:IsEnabled() and (accent and C.hot or C.text) or C.dim) end)
    b:SetScript("OnMouseDown",function(self) if self:IsEnabled() then self.label:SetAlpha(.7) end end)
    b:SetScript("OnMouseUp",function(self) self.label:SetAlpha(1) end)
    b:SetScript("OnHide",function(self) self.label:SetAlpha(1) end)
    b.action=callback
    b:SetScript("OnClick",function(self) if not U.closing then callback(self) end end)
    return b
end
-- Filled primary actions keep white text in every enabled pointer state.
local function primaryButton(b,radius)
    local parts=rounded(b,C.red,radius)
    function b:RefreshStyle()
        local enabled=self:IsEnabled()
        local tint=not enabled and C.border or self.pressed and {.70,.17,.22} or self.hovered and C.hot or C.red
        for i,t in ipairs(parts) do
            if i<=3 then t:SetColorTexture(tint[1],tint[2],tint[3],1)
            else t:SetVertexColor(tint[1],tint[2],tint[3]) end
        end
        color(self.label,enabled and {1,1,1} or C.dim)
        self.label:SetAlpha(1)
    end
    b:SetScript("OnEnter",function(self) self.hovered=true;self:RefreshStyle() end)
    b:SetScript("OnLeave",function(self) self.hovered=nil;self.pressed=nil;self:RefreshStyle() end)
    b:SetScript("OnMouseDown",function(self) self.pressed=self:IsEnabled();self:RefreshStyle() end)
    b:SetScript("OnMouseUp",function(self) self.pressed=nil;self:RefreshStyle() end)
    b:SetScript("OnHide",function(self) self.hovered=nil;self.pressed=nil;self:RefreshStyle() end)
    b:RefreshStyle()
end
local function field(parent,x,y,w,h,multiline)
    x=x*280/340; w=w*280/340
    local host=CreateFrame("Frame",nil,parent); host:SetSize(w,h); host:SetPoint("TOPLEFT",x,y)
    local border=rounded(host,C.border,10)
    local inset=CreateFrame("Frame",nil,host); inset:SetPoint("TOPLEFT",1,-1); inset:SetPoint("BOTTOMRIGHT",-1,1)
    rounded(inset,C.field,9)
    local function tint(c)
        for i,t in ipairs(border) do
            if i<=3 then t:SetColorTexture(c[1],c[2],c[3],1) else t:SetVertexColor(c[1],c[2],c[3]) end
        end
    end
    local scroll=CreateFrame("ScrollFrame",nil,host); scroll:SetPoint("TOPLEFT",10,-8); scroll:SetPoint("BOTTOMRIGHT",-10,8); scroll:SetFrameLevel(inset:GetFrameLevel()+1)
    local edit=CreateFrame("EditBox",nil,scroll); edit:SetWidth(w-20); edit:SetHeight(h-16)
    edit:SetFont(STANDARD_TEXT_FONT,18,""); edit:SetAutoFocus(false); edit:SetMultiLine(multiline==true)
    edit:SetMaxBytes(multiline and 16384 or 160); edit:SetTextColor(unpack(C.text)); scroll:SetScrollChild(edit)
    edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained",function() tint(C.red) end)
    edit:SetScript("OnEditFocusLost",function() tint(C.border) end)
    edit:SetScript("OnCursorChanged",function(_,_,cy,_,ch)
        local pos=-cy; local top=scroll:GetVerticalScroll(); local height=scroll:GetHeight()
        if pos<top then scroll:SetVerticalScroll(math.max(0,pos)) elseif pos+ch>top+height then scroll:SetVerticalScroll(pos+ch-height) end
    end)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel",function(_,delta) scroll:SetVerticalScroll(math.max(0,math.min(scroll:GetVerticalScrollRange(),scroll:GetVerticalScroll()-delta*30))) end)
    edit.host=host; return edit
end
function U:HideTooltip(owner)
    local tip=self.tooltip
    if not tip or (owner and tip.owner~=owner) then return end
    tip:Hide()
end
function U:ShowTooltip(owner,build,title)
    if InCombatLockdown() then return end
    if not self.tooltip then
        local tip=CreateFrame("Frame",nil,self.frame);self.tooltip=tip
        tip:SetFrameStrata("TOOLTIP");tip:SetClampedToScreen(true);tip:SetWidth(300);tip:EnableMouse(false)
        rounded(tip,{.065,.065,.075},8)
        tip.title=text(tip,14,C.text,"",0,0,270)
        tip.meta=text(tip,10,C.muted,"",0,0,270)
        tip.detail=text(tip,10,C.muted,"",17,-94,328)
        tip.hint=text(tip,10,C.dim,"",17,-120,328)
        tip.buildIcon=tip:CreateTexture(nil,"ARTWORK");tip.buildIcon:SetSize(34,34);tip.buildIcon:SetPoint("TOPLEFT",14,-14);tip.buildIcon:SetTexCoord(.08,.92,.08,.92)
        tip.bindingRows={}
        for i=1,9 do
            local row=CreateFrame("Frame",nil,tip);row:SetSize(272,34);row:SetPoint("TOPLEFT",14,-60-(i-1)*36)
            row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(26,26);row.icon:SetPoint("LEFT");row.icon:SetTexCoord(.08,.92,.08,.92)
            row.label=text(row,12,C.text,"",0,0,283);row.label:ClearAllPoints();row.label:SetPoint("LEFT",36,0);row.label:SetWidth(236);row.label:SetMaxLines(1)
            tip.bindingRows[i]=row
        end
        tip:SetScript("OnEvent",function()U:HideTooltip()end)
        tip:SetScript("OnHide",function()tip:UnregisterAllEvents();tip.owner=nil;tip.build=nil;tip.bindings=nil end)
        tip:Hide()
    end
    local tip=self.tooltip;tip.owner=owner;tip.build=build;tip.bindings=nil
    if build and build.source=="user" and type(build.contexts)=="table" then
        local entries={}
        for id,enabled in pairs(build.contexts)do local scene=A.Catalog.scenarios[id];if enabled and scene then entries[#entries+1]={name=scene.label or scene.name,icon=scene.icon}end end
        table.sort(entries,function(a,b)return a.name<b.name end)
        tip.bindingCount=#entries
        if #entries>0 then
            while #entries>8 do table.remove(entries)end
            if tip.bindingCount>8 then entries[#entries+1]={name=L.MORE_CONTEXTS:format(tip.bindingCount-8)}end
            tip.bindings=entries
        end
    end
    tip.title:SetText(build and A.Catalog:Title(build) or title or "")
    tip.title:ClearAllPoints();tip.title:SetPoint("TOPLEFT",build and 60 or 14,-14);tip.title:SetWidth(build and 224 or 272);tip.title:SetMaxLines(1)
    tip.buildIcon:SetShown(build~=nil);if build then tip.buildIcon:SetTexture(build.icon or 134400)end
    tip.meta:ClearAllPoints();tip.meta:SetPoint("TOPLEFT",60,-39)
    tip.meta:SetShown(build~=nil and not tip.bindings);tip.detail:Hide();tip.hint:SetShown(not tip.bindings)
    for i,row in ipairs(tip.bindingRows)do
        local entry=tip.bindings and tip.bindings[i];row:SetShown(entry~=nil)
        if entry then row.label:SetText(entry.name);row.icon:SetTexture(entry.icon or 134400);row.icon:SetShown(entry.icon~=nil)end
    end
    tip.hint:ClearAllPoints()
    if tip.bindings then
        tip.title:ClearAllPoints();tip.title:SetPoint("TOPLEFT",60,-22)
        tip:SetHeight(70+#tip.bindings*36)
    elseif build then
        local meta=""
        if build.source=="builtin" then
            if build.scene=="mythic" and tonumber(build.level) and build.level>0 then meta=L.WCL_LEVEL:format(build.level)
            elseif build.scene=="raid" then meta="WCL · "..(build.difficulty==5 and L.MYTHIC_RAID or L.HEROIC_RAID) end
        end
        tip.meta:SetText(meta)
        local dated=type(build.recordTime)=="number"
        tip.detail:SetShown(dated);tip.detail:ClearAllPoints();tip.detail:SetPoint("TOPLEFT",14,-70)
        if dated then tip.detail:SetText(L.WCL_RECORD:format(date("%Y-%m-%d",build.recordTime)))end
        tip.hint:SetText(L.DOUBLE_CLICK_HINT);tip.hint:SetPoint("TOPLEFT",14,dated and -100 or -68);tip:SetHeight(dated and 132 or 100)
    else tip.hint:SetText("");tip:SetHeight(50) end
    tip:ClearAllPoints()
    local scale=tip:GetEffectiveScale();local x,y=GetCursorPosition();x=x/scale+18;y=y/scale-18
    local screenWidth=UIParent:GetWidth()*UIParent:GetEffectiveScale()/scale
    if x+300>screenWidth-12 then x=x-336 end
    tip:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",math.max(12,x),y)
    tip:RegisterEvent("PLAYER_REGEN_DISABLED");tip:Show()
end
function U:Scale()
    A.Motion:Finish(self.frame)
    local native=PlayerSpellsFrame
    -- Match the native panel in physical pixels, including its inherited scale.
    self.frame:SetScale(native:GetEffectiveScale()/A.Dock.host:GetEffectiveScale())
    self.frame:SetHeight(native:GetHeight())
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT",A.Dock:Anchor(),"TOPRIGHT",8,0)

end
function U:ClearApplyFeedback(row)
    row.successRemaining=nil
    row.switchRemaining=nil
    row:SetScript("OnUpdate",nil)
    row.progress:SetText("")
    if row.more then row.more:Show() end
end
function U:ShowApplySuccess(buildID,startedAt)
    if not self.frame or not self.frame:IsShown() then return end
    for _,row in ipairs(self.rows) do
        self:ClearApplyFeedback(row)
        if row:IsShown() and row.build and row.build.id==buildID then
            row.switchRemaining=math.max(0,1.5-(GetTime()-(startedAt or GetTime())))
            row.successRemaining=1.5
            row.progress:SetText(row.switchRemaining>0 and L.APPLYING_SHORT or L.APPLIED_SHORT)
            color(row.progress,row.switchRemaining>0 and C.muted or C.red)
            row.title:SetWidth(122)
            row.link:Hide()
            row.more:Hide()
            row:SetScript("OnUpdate",function(r,elapsed)
                if not r.build or r.build.id~=buildID or A.Apply.op then
                    U:ClearApplyFeedback(r);return
                end
                if r.switchRemaining>0 then
                    local remaining=r.switchRemaining-elapsed
                    r.switchRemaining=math.max(0,remaining)
                    if remaining>0 then return end
                    elapsed=-remaining
                    r.progress:SetText(L.APPLIED_SHORT)
                    color(r.progress,C.red)
                end
                r.successRemaining=r.successRemaining-elapsed
                if r.successRemaining<=0 then
                    U:ClearApplyFeedback(r);U:Refresh();return
                end
            end)
        end
    end
end
function U:Refresh()
    if self.options then self.options:Hide() end
    if not self.frame or not self.frame:IsShown() then return end
    local spec=A:GetSpec()
    A.Catalog:Load()
    self.difficulty=self.difficulty or A.Store.character.raidDifficulty or 5
    A.Catalog:Query(spec,self.scene,self.scene=="mine" and "user" or "builtin","",nil,self.difficulty,self.results)
    for i=#self.results,1,-1 do
        if self.results[i].kind=="popular" then table.remove(self.results,i) end
    end
    self:LayoutRows()
    self.offset=math.min(self.offset,math.max(0,#self.results-self.visibleRows))
    local selected=false
    for _,b in ipairs(self.results) do if b.id==self.selected then selected=true; break end end
    if not selected then self.selected=self.results[1] and self.results[1].id or nil end
    for _,b in ipairs(self.nav) do
        local active=b.scene==self.scene
        b.mark:SetShown(active); color(b.label,active and C.text or C.muted)
    end
    self.count:SetText(tostring(#self.results))
    self.currentID=A.Apply:CurrentBuildID()
    local applying=A.Apply.op and A.Apply.op.buildID
    for i,row in ipairs(self.rows) do
        local b=i<=self.visibleRows and self.results[i+self.offset] or nil
        local id,revision=b and b.id,b and (b.code or b.version)
        local context=self.scene..":"..self.difficulty
        if row.boundID~=id or row.boundRevision~=revision or row.boundContext~=context then
            self:HideTooltip(row)
            self:ClearApplyFeedback(row)
            row.generation=row.generation+1; row.pressed=nil; row.lastClickID=nil; row.lastClickGeneration=nil
            row.boundID=id; row.boundRevision=revision; row.boundContext=context
        end
        row.build=b
        if b then
            row.title:SetText(A.Catalog:Title(b))
            if applying then self:ClearApplyFeedback(row) end
            row.progress:SetText((b.id==applying or (row.switchRemaining and row.switchRemaining>0)) and L.APPLYING_SHORT or row.successRemaining and L.APPLIED_SHORT or "")
            color(row.progress,(b.id==applying or (row.switchRemaining and row.switchRemaining>0)) and C.muted or row.successRemaining and C.red or C.muted)
            row.more:SetShown(b.id~=applying and not row.successRemaining)
            local linked=b.source=="user" and type(b.contexts)=="table" and next(b.contexts)~=nil
            row.link:SetShown(linked and not applying and not row.successRemaining)
            row.title:SetWidth((b.id==applying or row.successRemaining or linked) and 122 or 154)
            row:SetEnabled(not applying); row.more:SetEnabled(not applying)
            row.icon:SetTexture(b.icon or 134400)
            row.mark:SetShown(b.id==self.currentID); row.bg:SetShown(b.id==self.currentID or b.id==self.selected)
            row:Show()
        else row:Hide() end
    end
    local empty=#self.results==0
    self.empty:SetShown(empty)
    if empty then
        self.emptyTitle:SetText(self.scene~="mine" and L.EMPTY_RECOMMENDED or L.EMPTY)
        self.emptyHelp:SetText(self.scene~="mine" and L.EMPTY_RECOMMENDED_HELP or L.EMPTY_HELP)
    end
    self.up:SetEnabled(self.offset>0); self.down:SetEnabled(self.offset+self.visibleRows<#self.results)
    local modes=A.Store.character.modes or {}
    self.shared=self.selected and modes[tostring(self.selected)]==true or false
    local secondary=(self.dialog and self.dialog:IsShown()) or (self.contextSettings and self.contextSettings:IsShown()) or (self.settings and self.settings:IsShown())
    self.back:SetShown(secondary)
    if self.settingsButton then self.settingsButton:SetShown(not secondary) end
    for _,nav in ipairs(self.nav) do nav:SetShown(not secondary) end
    if secondary then
        for _,control in ipairs({self.buildList,self.footer,self.difficultyButton,self.up,self.down,self.count}) do control:Hide() end
    end
end
function U:SetShared(shared,id)
    id=id or self.selected
    if not id then return end
    local character=A.Store.character
    character.modes=character.modes or {}
    character.modes[tostring(id)]=shared==true
    if id==self.selected then self.shared=shared==true end
end
function U:BuildOptions(id,anchor)
    self:HideTooltip()
    if not id or not A.Catalog:Find(id) or A.Apply.op then return end
    if not self.options then
        local menu=CreateFrame("Frame",nil,self.frame); self.options=menu
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetFrameLevel(self.frame:GetFrameLevel()+25)
        menu:SetClampedToScreen(true); menu:EnableMouse(true); rounded(menu,{.065,.065,.075},8)
        local icon=menu:CreateTexture(nil,"ARTWORK"); icon:SetSize(16,16); icon:SetPoint("TOPLEFT",20,-17)
        icon:SetTexture(media.."game-menu.tga")
        menu.title=text(menu,14,C.text,L.ACTION_MENU,51,-16)
        local function item(label,callback)
            local b=button(menu,label,8,-36,144,callback)
            b:SetHeight(MENU_STEP)
            b.label:ClearAllPoints(); b.label:SetPoint("LEFT",12,0); b.label:SetPoint("RIGHT",-12,0)
            b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
            b:SetScript("OnMouseDown",function(self,mouse)
                self.pressed=(not mouse or mouse=="LeftButton") and menu.revision or nil
                self.label:SetAlpha(.7)
            end)
            b:SetScript("OnHide",function(self) self.pressed=nil; self.label:SetAlpha(1) end)
            b:SetScript("OnClick",function(self)
                if U.closing or not menu.owner or not menu.owner:IsShown() or self.pressed~=menu.revision then return end
                self.pressed=nil; self.action(self)
            end)
            return b
        end
        local option=item(L.INDEPENDENT,function()
            local modes=A.Store.character.modes or {}
            local shared=not (modes[tostring(menu.buildID)]==true)
            U:SetShared(shared,menu.buildID); menu.option:SetChecked(not shared)
        end)
        option.label:ClearAllPoints(); option.label:SetPoint("LEFT",12,0); option.label:SetPoint("RIGHT",-36,0)
        menu.mark=option:CreateTexture(nil,"OVERLAY"); menu.mark:SetSize(22,22); menu.mark:SetPoint("CENTER",option,"RIGHT",-22,0)
        menu.mark:SetTexture(media.."choice-checkbox.tga")
        -- Preserve the atlas' square geometry at inherited fractional UI scales.
        if menu.mark.SetSnapToPixelGrid then menu.mark:SetSnapToPixelGrid(false); menu.mark:SetTexelSnappingBias(0) end
        option.bg=fill(option,C.selected); option.bg:Hide()
        function option:Paint()
            local enabled=self:IsEnabled()
            local state=self.checked and (enabled and 2 or 3) or (enabled and self.hovered and 1 or 0)
            menu.mark:SetTexCoord(state/4,(state+1)/4,0,1)
            menu.mark:SetAlpha(not enabled and not self.checked and .45 or 1)
            color(self.label,enabled and C.text or C.dim)
            self.bg:SetShown(self.hovered==true or self.down==true)
            self.bg:SetColorTexture(unpack(self.down and {.175,.115,.125} or C.selected))
        end
        function option:SetChecked(checked) self.checked=checked==true; self:Paint() end
        option:SetScript("OnEnter",function(self) self.hovered=true; self:Paint() end)
        option:SetScript("OnLeave",function(self) self.hovered=nil; self.down=nil; self:Paint() end)
        option:HookScript("OnMouseDown",function(self) self.down=true; self:Paint() end)
        option:HookScript("OnMouseUp",function(self) self.down=nil; self:Paint() end)
        option:HookScript("OnHide",function(self) self.hovered=nil; self.down=nil; self:Paint() end)
        menu.option=option; menu.actions={}
        for _,key in ipairs({"export","edit","sourceLink","delete"}) do
            local actionKey=key
            local b=item("",function()
                local targetID=menu.buildID
                if not targetID or not A.Catalog:Find(targetID) then menu:Hide(); return end
                U.selected=targetID; menu:Hide(); U:Action(actionKey,targetID)
            end)
            b.key=key; menu.actions[#menu.actions+1]=b
        end
        menu:SetScript("OnShow",function() menu:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        menu:SetScript("OnEvent",function()
            if not menu:IsMouseOver() and not (menu.owner and menu.owner:IsMouseOver()) then menu:Hide() end
        end)
        menu:SetScript("OnHide",function()
            menu:UnregisterAllEvents()
            menu.buildID=nil; menu.owner=nil; menu.option.pressed=nil
            for _,b in ipairs(menu.actions) do b.pressed=nil end
        end)
        menu:Hide()
    end
    local menu=self.options
    if menu:IsShown() and menu.buildID==id then menu:Hide(); return end
    menu.revision=(menu.revision or 0)+1; menu.buildID=id; menu.owner=anchor
    self.selected=id; GameTooltip:Hide()
    local build=A.Catalog:Find(id)
    local labels={edit=build.source=="builtin" and L.FORK or L.EDIT,export=L.EXPORT,
        sourceLink=L.SOURCE_LINK,delete=L.DELETE}
    local width=math.max(196,menu.option.label:GetStringWidth()+60)
    local count=1
    menu.option:ClearAllPoints(); menu.option:SetPoint("TOPLEFT",8,-48)
    for _,b in ipairs(menu.actions) do
        local visible=(b.key~="delete" or build.source=="user") and (b.key~="sourceLink" or build.report~=nil)
        b:SetShown(visible); b.pressed=nil
        if visible then
            b.label:SetText(labels[b.key]); width=math.max(width,b.label:GetStringWidth()+24)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",8,-(48+count*MENU_STEP)); count=count+1
        end
    end
    width=math.min(280,math.ceil(width))
    menu.option:SetWidth(width); for _,b in ipairs(menu.actions) do b:SetWidth(width) end
    local height=56+count*MENU_STEP; menu:SetSize(width+16,height)
    menu:SetScale(math.min(1,(UIParent:GetHeight()*UIParent:GetEffectiveScale()-32)/(height*self.frame:GetEffectiveScale())))
    local modes=A.Store.character.modes or {}; menu.option:SetChecked(modes[tostring(id)]~=true)
    local x,y=GetCursorPosition(); local scale=menu:GetEffectiveScale()
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",math.floor(x+.5)/scale,math.floor(y+.5)/scale); menu:Show()
end
function U:Action(key,id)
    local build=A.Catalog:Find(id); if not build then return end
    if key=="delete" then
        if build.source=="user" and A.Store:Delete(id) then self:Refresh() end
        return
    end
    local title=A.Catalog:Title(build)
    if key=="export" or key=="edit" then
        local code,err=A.Talents:Code(build); if not code then A:Message(err); return end
        self:Dialog(key=="export",{name=title,code=code,scene=build.scene,target=A.Catalog:Target(build),
            icon=build.icon,scenarioID=build.scenarioID,contexts=build.contexts,remind=build.remind,editID=key=="edit" and build.source=="user" and id or nil})
        return
    end
    if key=="sourceLink" and A.Catalog:SourceURL(build) then
        local url=A.Catalog:SourceURL(build)
        self:Dialog(true,{name=title,code=url,scene=build.scene,target=A.Catalog:Target(build)})
        self.dialog.header:SetText(L.SOURCE_LINK); return
    end
end
function U:ConfirmPending(ticket,title)
    if not StaticPopupDialogs or not StaticPopup_Show then A:Message("PENDING");return end
    StaticPopupDialogs.LYCHEETALENT_PENDING={
        text=L.PENDING_CONFIRM,button1=L.PENDING_REPLACE,button2=L.CANCEL,
        timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function(_,data)
            if U.pendingPrompt==data then U.pendingPrompt=nil end
            local ok,err=A.Apply:ConfirmPending(data)
            if not ok then A:Message(err) end
        end,
        OnCancel=function(_,data)
            A.Apply:CancelPending(data)
            if U.pendingPrompt==data then U.pendingPrompt=nil end
        end,
    }
    if self.pendingPrompt then
        A.Apply:CancelPending(self.pendingPrompt)
        StaticPopup_Hide("LYCHEETALENT_PENDING")
    end
    self.pendingPrompt=ticket
    if not StaticPopup_Show("LYCHEETALENT_PENDING",title,nil,ticket) then
        self.pendingPrompt=nil;A.Apply:CancelPending(ticket);A:Message("PENDING")
    end
end
function U:LayoutRows()
    local top=148+(self.scene=="raid" and 48 or 0)
    local personal=self.scene=="mine"
    self.footer:SetShown(personal)

    local room=math.max(56,self.frame:GetHeight()-top-(personal and 104 or 32))
    -- A full-height sidebar gets breathing room; short windows remain scrollable.
    local step=math.max(56,math.min(68,math.floor(room/9/2)*2))
    self.visibleRows=math.max(1,math.min(18,math.floor(room/step)))
    for i,row in ipairs(self.rows) do
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*step); row:SetHeight(step-6); row.more:SetHeight(step-6)
    end
    self.buildList:ClearAllPoints(); self.buildList:SetPoint("TOPLEFT",15,-top); self.buildList:SetHeight(room)
    self.buildList:Show()
    self.up:SetShown(#self.results>self.visibleRows); self.down:SetShown(#self.results>self.visibleRows)
    self.count:SetShown(#self.results>self.visibleRows)
    local pageY=personal and 72 or 20
    self.up:ClearAllPoints(); self.up:SetPoint("BOTTOMLEFT",self.frame,"BOTTOMLEFT",158,pageY)
    self.down:ClearAllPoints(); self.down:SetPoint("BOTTOMLEFT",self.frame,"BOTTOMLEFT",194,pageY)
    self.count:ClearAllPoints(); self.count:SetPoint("BOTTOMRIGHT",self.frame,"BOTTOMRIGHT",-15,pageY+10)
    self.difficultyButton:SetShown(self.scene=="raid")
    self.difficultyButton:ClearAllPoints(); self.difficultyButton:SetPoint("TOPRIGHT",-15,-142)
    for _,b in ipairs(self.difficultyChoices) do
        local active=b.difficulty==self.difficulty
        b.selected:SetShown(active); color(b.label,active and C.red or C.muted)
    end
end
function U:ScrollDialog(delta)
    local p=self.iconPicker
    local cursorX,cursorY=GetCursorPosition()
    local function contains(frame)
        local scale=frame:GetEffectiveScale()
        local x,y=cursorX/scale,cursorY/scale
        local left,right,top,bottom=frame:GetLeft(),frame:GetRight(),frame:GetTop(),frame:GetBottom()
        return left and right and top and bottom and x>=left and x<=right and y>=bottom and y<=top
    end
    -- Nested ScrollFrames can deliver the wheel to the outer viewport. Route by
    -- the visible hit area, regardless of which frame received that event.
    if p and p.expanded and p:IsShown() and contains(self.dialogScroll) and contains(p.clip)
        and (contains(p.grid) or contains(p.scroll)) then
        p:ScrollTo(p.offset-delta*44)
        return
    end
    local room=math.max(1,self.frame:GetHeight()-98)
    local limit=math.max(0,self.dialog:GetHeight()-room)
    self.dialogScroll:SetVerticalScroll(math.max(0,math.min(limit,self.dialogScroll:GetVerticalScroll()-delta*44)))
    self:LayoutDialog()
end
function U:LayoutDialog(expansion)
    local d=self.dialog;if not d or not d.save then return end
    d.expansion=expansion or d.expansion or 0
    local gap=d.exportOnly and 0 or d.expansion
    local function place(region,y)
        region:ClearAllPoints();region:SetPoint("TOPLEFT",15,y-gap)
    end
    place(d.nameLabel,-76);place(d.name.host,-104)
    place(d.codeLabel,-172);place(d.code.host,d.exportOnly and -58 or -200)
    place(d.associationsLabel,-366);place(d.associations,-394)
    place(d.save,-470);place(d.error,-522)
    d:SetHeight((d.exportOnly and 246 or 566)+gap)
    local room=math.max(1,self.frame:GetHeight()-98)
    local limit=math.max(0,d:GetHeight()-room)
    local scroll=math.min(limit,self.dialogScroll:GetVerticalScroll())
    self.dialogScroll:SetVerticalScroll(scroll)
    self.dialogScrollBar.syncing=true
    self.dialogScrollBar:SetHeight(math.max(24,room-20))
    self.dialogScrollBar:SizeThumb(d:GetHeight(),room)
    self.dialogScrollBar:SetMinMaxValues(0,limit);self.dialogScrollBar:SetValue(scroll)
    self.dialogScrollBar:SetShown(limit>0);self.dialogScrollBar.syncing=nil
end
function U:ExpandIcons(shown,instant)
    local p=self.iconPicker;if not p then return end
    local clip=p.clip;local start=self.dialog.expansion or 0
    local target=shown and 336 or 0
    p.expanded=shown
    clip:SetScript("OnUpdate",nil)
    local function apply(value)
        clip:SetHeight(math.max(1,value-16));U:LayoutDialog(value)
    end
    local function finish()
        clip:SetScript("OnUpdate",nil);apply(target)
        if not shown then p:Hide() end
    end
    if instant or A.Store.db.reducedMotion or InCombatLockdown() or start==target then finish();return end
    local elapsed=0;local duration=shown and .24 or .16
    clip:SetScript("OnUpdate",function(_,dt)
        if not p:IsShown() then clip:SetScript("OnUpdate",nil);return end
        if InCombatLockdown() or A.Store.db.reducedMotion then finish();return end
        elapsed=math.min(duration,elapsed+dt)
        local q=elapsed/duration;apply(start+(target-start)*(1-(1-q)^3))
        if q==1 then finish() end
    end)
end
function U:Dialog(exportOnly,preset)
    self:HideTooltip()
    if self.options then self.options:Hide() end
    if not self.dialog then self:CreateDialog() end
    local d=self.dialog
    d.associationDraft={contexts={},remind=not preset or preset.remind~=false}
    for id,enabled in pairs(preset and preset.contexts or {})do if enabled then d.associationDraft.contexts[id]=true end end
    if self.iconPicker then self.iconPicker:Hide() end
    local _,_,_,specIcon=A:GetSpec()
    d.iconValue=preset and preset.icon or specIcon or 134400; d.iconButton.icon:SetTexture(d.iconValue); d.iconButton:SetShown(not exportOnly)
    d.header:SetWidth(exportOnly and 250 or 194)
    d.exportOnly=exportOnly; d.specID=A:GetSpec(); d.editID=preset and preset.editID; d.targetID=preset and preset.scenarioID
    d.header:SetText(exportOnly and L.EXPORT or d.editID and L.EDIT or preset and preset.code and L.SAVE or L.IMPORT_TITLE)
    d.help:SetText(exportOnly and L.EXPORT_HELP or "")
    d.name:SetText(preset and preset.name or ""); d.code:SetText(preset and preset.code or "")
    local scenario=d.targetID and A.Catalog.scenarios[d.targetID]
    d.targetText=preset and preset.target or (scenario and scenario.label or "")
    d.scene=preset and preset.scene or "mythic"
    d.name:EnableMouse(not exportOnly); d.name:SetEnabled(not exportOnly)
    d.save:SetShown(not exportOnly); d.error:SetText("")
    d.originalCode=exportOnly and (preset and preset.code or "") or nil
    d:ClearAllPoints(); d:SetPoint("TOPLEFT",0,0)
    d:SetSize(280,exportOnly and 246 or 566)
    d:SetScale(1)
    d.nameLabel:SetText(d.editID and L.NAME or L.NAME_OPTIONAL)
    d.nameLabel:SetShown(not exportOnly); d.name.host:SetShown(not exportOnly)
    d.codeLabel:SetShown(not exportOnly); d.code.host:Show()
    d.help:SetShown(exportOnly)
    d.help:ClearAllPoints(); d.help:SetPoint("TOPLEFT",15,-202)
    d.nameLabel:ClearAllPoints(); d.nameLabel:SetPoint("TOPLEFT",15,-76)
    d.name.host:ClearAllPoints(); d.name.host:SetPoint("TOPLEFT",15,-104); d.name.host:SetSize(250,44); d.name:SetWidth(230); d.name:SetHeight(28)
    d.codeLabel:ClearAllPoints(); d.codeLabel:SetPoint("TOPLEFT",15,-172)
    d.code.host:ClearAllPoints(); d.code.host:SetPoint("TOPLEFT",15,exportOnly and -58 or -200)
    d.code.host:SetHeight(exportOnly and 128 or 142); d.code:SetHeight(exportOnly and 112 or 126)
    d.iconButton:ClearAllPoints(); d.iconButton:SetPoint("TOPLEFT",221,-8)
    d.save.label:SetText((d.editID or preset and preset.code) and L.SAVE or L.IMPORT_ACTION)
    d.associationsLabel:SetShown(not exportOnly);d.associations:SetShown(not exportOnly);d:RefreshAssociations()
    d.save:ClearAllPoints(); d.save:SetPoint("TOPLEFT",15,-470)
    d.error:ClearAllPoints(); d.error:SetPoint("TOPLEFT",15,-522)
    self.dialogScroll:SetVerticalScroll(0);self:LayoutDialog(0)
    self.dialogCover:Show(); d:Show(); self:Refresh()
    A.Motion:Slide(d,1)
    if exportOnly then d.code:SetFocus(); d.code:HighlightText()
    else d.code:SetFocus() end
end
function U:ChooseIcon()
    self:HideTooltip()
    local d=self.dialog
    if not d or not d:IsShown() or d.exportOnly then return end
    d.code:ClearFocus(); d.name:ClearFocus()
    if not self.iconPicker then
        -- Keep the grid; discard catalog references when the picker closes.
        local clip=CreateFrame("ScrollFrame",nil,d)
        clip:SetSize(280,1);clip:SetPoint("TOPLEFT",0,-64);clip:Hide()
        local p=CreateFrame("Frame",nil,clip); self.iconPicker=p;p.clip=clip
        p:SetSize(280,320);clip:SetScrollChild(p)
        p:SetPoint("TOPLEFT");p:SetFrameLevel(clip:GetFrameLevel()+1)
        p:EnableMouse(true); fill(p,C.bg)
        p.offset=0;p.filter=false;p.cells={};p.tabs={}
        local grid=CreateFrame("ScrollFrame",nil,p);p.grid=grid
        grid:SetSize(238,264);grid:SetPoint("TOPLEFT",15,-40)
        local canvas=CreateFrame("Frame",nil,grid);p.canvas=canvas
        -- Seven recycled rows cover six visible rows plus a partially scrolled row.
        canvas:SetSize(238,308);grid:SetScrollChild(canvas)
        function p:Refresh()
            local count=self.provider:GetNumIcons()
            self.contentHeight=math.ceil(count/5)*44
            self.maximum=math.max(0,self.contentHeight-264)
            self.offset=math.max(0,math.min(self.maximum,self.offset))
            local firstRow=math.floor(self.offset/44)
            self.grid:SetVerticalScroll(self.offset-firstRow*44)
            self.revision=(self.revision or 0)+1
            for i,b in ipairs(self.cells) do
                local index=firstRow*5+i
                local value=index<=count and self.provider:GetIconByIndex(index) or nil
                if b.value~=value then b.icon:SetTexture(value) end
                b.value=value;b.index=index
                b.pressed=nil; b:SetShown(b.value~=nil)
                if b.value then b.mark:SetShown(b.value==d.iconValue) end
            end
            self.syncing=true;self.scroll:SetMinMaxValues(0,self.maximum);self.scroll:SetValue(self.offset);self.syncing=nil
            self.scroll:SizeThumb(self.contentHeight,264);self.scroll:SetShown(self.maximum>0)
            for _,b in ipairs(self.tabs) do color(b.label,b.filter==self.filter and C.hot or C.muted) end
        end
        function p:ScrollTo(offset)self.offset=offset;self:Refresh()end
        local function wheel(_,delta)U:ScrollDialog(delta)end
        grid:EnableMouseWheel(true);grid:SetScript("OnMouseWheel",wheel)
        for i,v in ipairs({{L.ICON_ALL,false},{L.ICON_SPELL,IconDataProviderIconType.Spell},{L.ICON_ITEM,IconDataProviderIconType.Item}}) do
            local b=button(p,v[1],15+(i-1)*82,0,78,function(btn)
                p.filter=btn.filter; p.provider:SetIconTypes(btn.filter and {btn.filter} or nil)
                p.offset=0;p:Refresh()
            end)
            b:ClearAllPoints();b:SetPoint("TOPLEFT",15+(i-1)*82,0);b:SetWidth(78)
            b.filter=v[2]; p.tabs[i]=b
        end
        for i=1,35 do
            local b=CreateFrame("Button",nil,canvas);p.cells[i]=b
            b:SetSize(42,40);b:SetPoint("TOPLEFT",((i-1)%5)*49,-math.floor((i-1)/5)*44)
            b:EnableMouseWheel(true);b:SetScript("OnMouseWheel",wheel)
            rounded(b,C.field,7)
            b.mark=fill(b,C.red); b.mark:Hide()
            b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(38,38); b.icon:SetPoint("CENTER"); b.icon:SetTexCoord(.08,.92,.08,.92)
            b:SetScript("OnEnter",function() b.icon:SetAlpha(.75) end)
            b:SetScript("OnLeave",function() b.icon:SetAlpha(1) end)
            b:SetScript("OnMouseDown",function(_,mouse) b.pressed=mouse=="LeftButton" and p.revision or nil end)
            b:SetScript("OnHide",function() b.pressed=nil; b.icon:SetAlpha(1) end)
            b:SetScript("OnClick",function(_,mouse)
                if mouse~="LeftButton" or not p:IsShown() or not p.expanded or b.pressed~=p.revision or not b.value then return end
                d.iconValue=b.value; d.iconButton.icon:SetTexture(b.value);U:ExpandIcons(false)
            end)
        end
        p.scroll=scrollbar(p);p.scroll:SetHeight(264);p.scroll:SetPoint("TOPRIGHT",-14,-40)
        p.scroll:SetScript("OnValueChanged",function(_,value)
            if not p.syncing then p:ScrollTo(value) end
        end)
        p.scroll:EnableMouseWheel(true);p.scroll:SetScript("OnMouseWheel",wheel)
        p:SetScript("OnHide",function()
            clip:SetScript("OnUpdate",nil);clip:Hide();p.expanded=false
            U:LayoutDialog(0)
            for _,b in ipairs(p.cells) do b.pressed=nil;b.value=nil;b.icon:SetTexture(nil) end
            local provider=p.provider;p.provider=nil
            if provider then provider:Release() end
        end)
    end
    local p=self.iconPicker
    if p:IsShown() and p.expanded then self:ExpandIcons(false);return end
    if not p.provider then
        p.provider=A.Icons:Create()
        if p.filter then p.provider:SetIconTypes({p.filter}) end
    end
    A.Motion:Finish(d)
    self.dialogScroll:SetVerticalScroll(0)
    p:Refresh();p.clip:Show();p:Show();self:ExpandIcons(true)
end
function U:CreateDialog()
    local cover=CreateFrame("Frame",nil,self.frame); self.dialogCover=cover
    cover:SetPoint("TOPLEFT",0,-88); cover:SetPoint("BOTTOMRIGHT",0,10)
    cover:SetFrameLevel(self.frame:GetFrameLevel()+29); cover:EnableMouse(true); fill(cover,C.bg)
    local viewport=CreateFrame("ScrollFrame",nil,cover);self.dialogScroll=viewport
    viewport:SetAllPoints(cover)
    local d=CreateFrame("Frame",nil,viewport); self.dialog=d
    d:SetSize(280,450); d:SetFrameLevel(self.frame:GetFrameLevel()+30); d:EnableMouse(true)
    viewport:SetScrollChild(d)
    local scroll=scrollbar(cover);self.dialogScrollBar=scroll
    scroll:SetHeight(400);scroll:SetPoint("TOPRIGHT",0,-10);scroll:SetFrameLevel(d:GetFrameLevel()+15)
    scroll:SetScript("OnValueChanged",function(_,value)if not scroll.syncing then viewport:SetVerticalScroll(value) end end)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel",function(_,delta)U:ScrollDialog(delta)end)
    cover:SetScript("OnSizeChanged",function()U:LayoutDialog()end)
    fill(d,C.bg)
    d.header=text(d,18,C.text,"",18,-18,300)
    d.header:SetFont(STANDARD_TEXT_FONT,24,"")
    d.help=text(d,10,C.muted,"",18,-202,300)
    d.nameLabel=text(d,12,C.muted,L.NAME_OPTIONAL,18,-262)
    d.name=field(d,18,-288,304,38,false)
    d.iconButton=button(d,L.CHOOSE_ICON,18,-348,304,function() U:ChooseIcon() end)
    d.iconButton:SetSize(44,44); rounded(d.iconButton,C.field,10)
    d.iconButton.icon=d.iconButton:CreateTexture(nil,"ARTWORK"); d.iconButton.icon:SetSize(36,36); d.iconButton.icon:SetPoint("CENTER"); d.iconButton.icon:SetTexCoord(.08,.92,.08,.92)
    d.iconButton.label:Hide()
    d.iconButton:SetScript("OnEnter",function(b) b.icon:SetAlpha(.7); U:ShowTooltip(b,nil,L.CHOOSE_ICON) end)
    d.iconButton:SetScript("OnLeave",function(b) b.icon:SetAlpha(1); U:HideTooltip(b) end)
    d.iconButton:SetScript("OnHide",function(b) b.icon:SetAlpha(1); U:HideTooltip(b) end)
    d.codeLabel=text(d,12,C.muted,L.CODE,18,-66)
    d.code=field(d,18,-92,304,142,true)
    d.code:SetScript("OnTextChanged",function(edit,user)
        if d.exportOnly and user and d.originalCode and edit:GetText()~=d.originalCode then edit:SetText(d.originalCode); edit:HighlightText() end
        if d.save then
            local ready=edit:GetText():find("%S")~=nil
            d.save:SetEnabled(ready); d.save:RefreshStyle()
        end
    end)
    d.associationsLabel=text(d,12,C.muted,"",18,-366,304)
    d.associations=button(d,"",18,-394,304,function()
        d.associationDraft.name=d.name:GetText()~="" and d.name:GetText() or L.NEW_BUILD
        d.code:ClearFocus();d.name:ClearFocus()
        U:ContextSettings(nil,d.associationDraft)
    end)
    d.associations:SetHeight(52);rounded(d.associations,C.field,8)
    d.associations.label:ClearAllPoints();d.associations.label:SetPoint("LEFT",52,0);d.associations.label:SetFont(STANDARD_TEXT_FONT,16,"")
    d.associations.label:SetWidth(167);d.associations.label:SetMaxLines(1)
    d.associations.icon=d.associations:CreateTexture(nil,"ARTWORK");d.associations.icon:SetSize(28,28);d.associations.icon:SetPoint("LEFT",12,0);d.associations.icon:SetTexCoord(.08,.92,.08,.92)
    d.associations.plus=text(d.associations,18,C.muted,"+",0,0);d.associations.plus:ClearAllPoints();d.associations.plus:SetPoint("LEFT",17,0)
    local arrow=text(d.associations,12,C.muted,">",0,0);arrow:ClearAllPoints();arrow:SetPoint("RIGHT",-10,0)
    function d:RefreshAssociations()
        local scenes={}
        for id,enabled in pairs(self.associationDraft and self.associationDraft.contexts or {})do
            local scene=A.Catalog.scenarios[id];if enabled and scene then scenes[#scenes+1]=scene end
        end
        table.sort(scenes,function(a,b)return (a.label or a.name)<(b.label or b.name)end)
        local first=scenes[1]
        self.associationsLabel:SetText(first and L.SELECTED_CONTEXTS:format(#scenes) or L.CHOOSE_CONTEXTS)
        self.associations.icon:SetShown(first~=nil);self.associations.plus:SetShown(first==nil)
        if first then self.associations.icon:SetTexture(first.icon)end
        self.associations.label:SetText(first and (first.label or first.name) or L.CONTEXTS_EMPTY_HELP)
    end
    d.error=text(d,12,C.hot,"",18,-404,304)
    d.save=button(d,L.IMPORT_ACTION,18,-350,304,function()
        if d.specID~=A:GetSpec() then d.error:SetText(L.WRONG_SPEC); return end
        local code,spec=A.Talents:Validate(d.code:GetText())
        if not code then d.error:SetText(L[spec]); return end
        local name=d.name:GetText():match("^%s*(.-)%s*$")
        if name=="" and not d.editID then
            local _,specName=A:GetSpec()
            name=L.DEFAULT_NAME:format(specName or L.TITLE,(A.Store.db.nextID or 0)+1)
        end
        local b,err
        if d.editID then b,err=A.Store:Update(d.editID,name,code,d.scene,d.targetText,spec)
        else b,err=A.Store:Save(name,code,d.scene,d.targetText,spec) end
        if not b then d.error:SetText(L[err]); return end
        b.icon=d.iconValue
        A.Store:SetContexts(b.id,d.associationDraft.contexts,d.associationDraft.remind)
        local scene=d.targetID and A.Catalog.scenarios[d.targetID]
        b.scenarioID=scene and scene.scene==d.scene and d.targetText==scene.label and scene.id or nil
        U.scene="mine"; U.selected=b.id; U.offset=0
        A.Motion:Finish(d);d:Hide(); U:Refresh();A.Motion:Slide(U.buildList,-1)
    end,true)
    d.save:SetSize(250,42); primaryButton(d.save,10)
    for _,edit in ipairs({d.code,d.name}) do edit:SetScript("OnEscapePressed",function()U:Back()end) end
    d:SetScript("OnHide",function()
        if A.Motion.frame==d then A.Motion:Finish(d)end
        if U.iconPicker then U.iconPicker:Hide() end
        if d.suspended then cover:Hide();return end
        d.code:ClearFocus(); d.name:ClearFocus(); d.originalCode=nil; cover:Hide(); U.back:Hide()
        if U.frame:IsShown() and not U.closing then U:Refresh() end
    end)
    d:Hide()
end
function U:Create()
    local f=CreateFrame("Frame","LycheeTalentFrame",A.Dock.host); self.frame=f
    f:SetSize(280,700); f:SetPoint("TOPLEFT",PlayerSpellsFrame,"TOPRIGHT",8,0); f:SetFrameLevel(A.Dock.host:GetFrameLevel()+10); f:SetClampedToScreen(false)
    f:EnableMouse(true); rounded(f,C.bg,10); f:Hide()
    local escape=CreateFrame("Frame","LycheeTalentEscape",f); escape:SetSize(1,1)
    table.insert(UISpecialFrames,"LycheeTalentEscape")
    escape:SetScript("OnHide",function()
        if not f:IsShown() or U.closing then return end
        if U.tooltip and U.tooltip:IsShown() then U:HideTooltip(); escape:Show()
        elseif U.options and U.options:IsShown() then U.options:Hide(); escape:Show()
        elseif U:ContentPage()~=U.buildList then U:Back();escape:Show()
        else U:Close() end
    end)
    self.escape=escape
    -- The 128px artwork has a 75x82px visible mark. Preserve its full silhouette
    -- while sizing the visible fruit to ~32x35, rather than a tiny padded icon.
    local logoHolder=CreateFrame("Frame",nil,f);logoHolder:SetSize(54,54);logoHolder:SetPoint("TOPLEFT",8,-14);logoHolder:EnableMouse(true)
    local logo=logoHolder:CreateTexture(nil,"ARTWORK");self.logo=logo;logo:SetSize(54,54);logo:SetPoint("CENTER",logoHolder,"CENTER",0,0);logo:SetTexture(media.."logo.tga")
    logoHolder:SetScript("OnEnter",function()A.Motion:Brand(logo,54)end)
    logoHolder:SetScript("OnHide",function()A.Motion:StopBrand(logo)end)
    local brand=text(f,20,C.text,L.TITLE,0,0)
    self.brand=brand
    brand:ClearAllPoints(); brand:SetPoint("LEFT",logoHolder,"RIGHT",2,0); brand:SetWidth(158); brand:SetWordWrap(false)
    local function headerAction(texture,onClick)
        local b=CreateFrame("Button",nil,f)
        b:SetSize(48,48);b:SetPoint("TOPRIGHT",-10,-17)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(24,24)
        b.icon:SetPoint("CENTER");b.icon:SetTexture(media..texture)
        local function paint(hover,pressed)
            b.icon:SetVertexColor(unpack(hover and C.hot or C.text));b.icon:SetAlpha(pressed and .7 or 1)
        end
        paint(false)
        b:SetScript("OnEnter",function()b.hovered=true;paint(true)end)
        b:SetScript("OnLeave",function()b.hovered=nil;paint(false)end)
        b:SetScript("OnMouseDown",function()paint(true,true)end)
        b:SetScript("OnMouseUp",function()paint(b.hovered)end)
        b:SetScript("OnHide",function()b.hovered=nil;paint(false)end)
        b:SetScript("OnClick",onClick)
        return b
    end
    self.settingsButton=headerAction("settings.tga",function()U:HideTooltip();U:Settings()end)
    self.back=headerAction("back-search.tga",function()U:Back()end);self.back:Hide()
    self.nav={}
    for i,item in ipairs({{"mythic",L.MYTHIC},{"raid",L.RAID},{"mine",L.MINE}}) do
        local b=button(f,item[2],18+(i-1)*102,-88,98,function(btn)
            if U.scene==btn.scene then return end
            local order={mythic=1,raid=2,mine=3};local direction=order[btn.scene]>order[U.scene] and 1 or -1
            A.Motion:Finish(U.buildList);U:HideTooltip();U.scene=btn.scene; U.offset=0; U:Refresh();A.Motion:Slide(U.buildList,direction)
        end)
        b.label:SetFont(STANDARD_TEXT_FONT,16,"")
        b.scene=item[1]; b:SetHeight(38)
        b.mark=b:CreateTexture(nil,"ARTWORK"); b.mark:SetSize(22,2); b.mark:SetPoint("BOTTOM",0,-1); b.mark:SetColorTexture(unpack(C.red))
        self.nav[i]=b
    end
    local difficulty=CreateFrame("Frame",nil,f); self.difficultyButton=difficulty
    difficulty:SetSize(250,36); rounded(difficulty,C.field,6)
    self.difficultyChoices={}
    for i,v in ipairs({{4,L.HEROIC_RAID},{5,L.MYTHIC_RAID}}) do
        local choice=button(difficulty,v[2],0,-3,145,function(btn)
            if U.difficulty==btn.difficulty then return end
            U.difficulty=btn.difficulty; A.Store.character.raidDifficulty=U.difficulty; U.offset=0; U:Refresh()
        end)
        choice.difficulty=v[1]; choice:SetSize(121,30); choice:ClearAllPoints(); choice:SetPoint("TOPLEFT",4+(i-1)*121,-3)
        choice.selected=CreateFrame("Frame",nil,choice); choice.selected:SetAllPoints(); choice.selected:SetFrameLevel(math.max(0,choice:GetFrameLevel()-1))
        rounded(choice.selected,{.175,.115,.125},4)
        choice.label:SetDrawLayer("OVERLAY")
        choice:SetScript("OnLeave",function(btn) color(btn.label,btn.difficulty==U.difficulty and C.red or C.muted) end)
        self.difficultyChoices[i]=choice
    end
    self.count=text(f,11,C.dim,"0",290,-596,30)
    local footer=CreateFrame("Frame",nil,f); self.footer=footer
    footer:SetPoint("BOTTOMLEFT",0,16); footer:SetSize(280,36)
    button(footer,L.IMPORT,18,0,140,function() U:Dialog(false) end,true)
    button(footer,L.SAVE_CURRENT,178,0,144,function()
        local code,err=A.Talents:Export()
        if not code then A:Message(err); return end
        local _,spec=A:GetSpec(); U:Dialog(false,{name=(spec or "").." · "..L.CURRENT,code=code,scene=U.scene=="raid" and "raid" or "mythic",target=""})
    end)
    local list=CreateFrame("Frame",nil,f); list:SetPoint("TOPLEFT",15,-220); list:SetSize(250,344); self.buildList=list; list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel",function(_,delta) U.offset=math.max(0,math.min(math.max(0,#U.results-U.visibleRows),U.offset-delta*3)); U:Refresh() end)
    for i=1,18 do
        local row=CreateFrame("Button",nil,list); row:SetPoint("TOPLEFT",0,-(i-1)*ROW_STEP); row:SetSize(250,ROW_HEIGHT); row.generation=0
        row.bg=fill(row,C.selected); row.mark=row:CreateTexture(nil,"ARTWORK"); row.mark:SetPoint("LEFT",0,0); row.mark:SetSize(4,28); row.mark:SetColorTexture(unpack(C.red))
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetTexCoord(.08,.92,.08,.92); row.icon:SetSize(32,32); row.icon:SetPoint("LEFT",10,0)
        row.title=text(row,15,C.text,"",0,0); row.title:ClearAllPoints(); row.title:SetPoint("LEFT",54,0); row.title:SetWordWrap(false)
        row.progress=text(row,10,C.muted,"",0,0,66); row.progress:ClearAllPoints(); row.progress:SetPoint("RIGHT",-8,0);row.progress:SetJustifyH("RIGHT")
        row:SetScript("OnEnter",function(r)
            if not r.build then return end
            r.bg:Show(); U:ShowTooltip(r,r.build)
        end)
        row:SetScript("OnLeave",function(r) r.bg:SetShown(r.build and (r.build.id==U.currentID or r.build.id==U.selected)); U:HideTooltip(r) end)
        row:SetScript("OnMouseDown",function(r,mouse) r.pressed=(not mouse or mouse=="LeftButton") and r.generation or nil end)
        row:SetScript("OnClick",function(r,mouse)
            if mouse and mouse~="LeftButton" then return end
            if U.closing or A.Apply.op or not r.build or r.pressed~=r.generation then return end
            U.selected=r.build.id; r.lastClickID=r.build.id; r.lastClickGeneration=r.generation
            U:HideTooltip()
            if U.options then U.options:Hide() end
            for _,other in ipairs(U.rows) do
                other.bg:SetShown(other.build and (other.build.id==U.selected or other.build.id==U.currentID))
            end
        end)
        row:SetScript("OnDoubleClick",function(r,mouse)
            if mouse and mouse~="LeftButton" then return end
            if U.closing or A.Apply.op or not r.build or r.pressed~=r.generation
                or r.lastClickID~=r.build.id or r.lastClickGeneration~=r.generation then return end
            local build=r.build; r.lastClickID=nil; r.lastClickGeneration=nil
            U.selected=build.id
            local modes=A.Store.character.modes or {}
            local ok,err,ticket=A.Apply:Start(build,modes[tostring(build.id)]==true)
            if not ok then
                if err=="PENDING" and ticket then U:ConfirmPending(ticket,A.Catalog:Title(build))
                else A:Message(err) end
            end
        end)
        row:SetScript("OnHide",function(r) U:ClearApplyFeedback(r); r.pressed=nil; r.lastClickID=nil; r.lastClickGeneration=nil; r.build=nil; if U.options and U.options.owner==r.more then U.options:Hide() end; U:HideTooltip(r) end)
        row.link=button(row,"",0,0,32,function()if row.build then U:Action("edit",row.build.id)end end)
        row.link:ClearAllPoints();row.link:SetPoint("RIGHT",-34,0);row.link:SetSize(32,32)
        row.link.label:Hide()
        row.link.icon=row.link:CreateTexture(nil,"ARTWORK");row.link.icon:SetSize(22,22);row.link.icon:SetPoint("CENTER")
        row.link.icon:SetTexture(media.."linked.tga");row.link.icon:SetVertexColor(unpack(C.muted))
        row.link:SetScript("OnEnter",function(btn)if row.build then btn.icon:SetVertexColor(unpack(C.hot));U:ShowTooltip(btn,row.build)end end)
        row.link:SetScript("OnLeave",function(btn)btn.icon:SetVertexColor(unpack(C.muted));U:HideTooltip(btn)end)
        row.link:SetScript("OnMouseDown",function(btn)btn.icon:SetAlpha(.7)end)
        row.link:SetScript("OnMouseUp",function(btn)btn.icon:SetAlpha(1)end)
        row.link:SetScript("OnHide",function(btn)btn.icon:SetAlpha(1);btn.icon:SetVertexColor(unpack(C.muted));U:HideTooltip(btn)end)
        row.more=button(row,"",260,-7,42,function(btn)
            if not A.Apply.op and row.build then U:BuildOptions(row.build.id,btn) end
        end)
        row.more:ClearAllPoints(); row.more:SetPoint("RIGHT",0,0); row.more:SetSize(34,ROW_HEIGHT)
        row.more.label:Hide()
        row.more.icon=row.more:CreateTexture(nil,"ARTWORK");row.more.icon:SetSize(20,20);row.more.icon:SetPoint("CENTER")
        row.more.icon:SetTexture(media.."more.tga");row.more.icon:SetVertexColor(unpack(C.text))
        row.more:SetScript("OnEnter",function(btn)if btn:IsEnabled() then btn.icon:SetVertexColor(unpack(C.hot))end end)
        row.more:SetScript("OnLeave",function(btn)btn.icon:SetVertexColor(unpack(btn:IsEnabled() and C.text or C.dim))end)
        row.more:SetScript("OnMouseDown",function(btn)if btn:IsEnabled() then btn.icon:SetAlpha(.7)end end)
        row.more:SetScript("OnMouseUp",function(btn)btn.icon:SetAlpha(1)end)
        row.more:SetScript("OnHide",function(btn)btn.icon:SetAlpha(1);btn.icon:SetVertexColor(unpack(C.text))end)
        self.rows[i]=row
    end
    self.empty=CreateFrame("Frame",nil,list); self.empty:SetAllPoints()
    self.emptyTitle=text(self.empty,16,C.text,L.EMPTY,12,-70,280)
    self.emptyHelp=text(self.empty,12,C.muted,L.EMPTY_HELP,12,-124,280); self.emptyHelp:SetSpacing(5)
    self.up=button(f,"<",192,-586,36,function() U.offset=math.max(0,U.offset-U.visibleRows); U:Refresh() end)
    self.down=button(f,">",236,-586,36,function() U.offset=math.min(math.max(0,#U.results-U.visibleRows),U.offset+U.visibleRows); U:Refresh() end)
    self.up:ClearAllPoints(); self.up:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",158,72)
    self.down:ClearAllPoints(); self.down:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",194,72)
    self.count:ClearAllPoints(); self.count:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-15,82)
    f:SetScript("OnMouseDown",function() if U.options then U.options:Hide() end end)
    f:SetScript("OnShow",function()
        for _,event in ipairs({"TRAIT_NODE_CHANGED","TRAIT_CONFIG_UPDATED","TRAIT_CONFIG_LIST_UPDATED","SELECTED_LOADOUT_CHANGED","ACTIVE_COMBAT_CONFIG_CHANGED"}) do f:RegisterEvent(event) end
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED"); f:RegisterEvent("UI_SCALE_CHANGED"); f:RegisterEvent("PLAYER_REGEN_DISABLED")
        U.escape:Show(); U:Scale(); U:Refresh();A.Motion:Brand(U.logo,54)
    end)
    f:SetScript("OnEvent",function(_,event,unit)
        if event=="PLAYER_SPECIALIZATION_CHANGED" and unit and unit~="player" then return end
        if event=="PLAYER_REGEN_DISABLED" then A.Motion:Finish(f);A.Motion:StopBrand();U:CloseSocial(); if U.dialog then U.dialog:Hide() end; if U.contextSettings then U.contextSettings:Hide() end; if U.settings then U.settings:Hide() end
        elseif event=="UI_SCALE_CHANGED" then U:Scale(); U:Refresh()
        elseif not U.stateTimer then
            U.stateTimer=C_Timer.NewTimer(0,function() U.stateTimer=nil; if f:IsShown() then U:Refresh() end end)
        end
    end)
    f:SetScript("OnHide",function()
        if U.pendingPrompt then
            A.Apply:CancelPending(U.pendingPrompt);U.pendingPrompt=nil
            StaticPopup_Hide("LYCHEETALENT_PENDING")
        end
        A.Motion:Finish(f);A.Motion:StopBrand(U.logo);U:CloseSocial(); U.closing=false; f:UnregisterAllEvents(); U:HideTooltip()
        if U.stateTimer then U.stateTimer:Cancel(); U.stateTimer=nil end
        if U.dialog then U.dialog:Hide() end
        if U.options then U.options:Hide() end
        if U.contextSettings then U.contextSettings:Hide() end; if U.settings then U.settings:Hide() end
        for i=#U.results,1,-1 do U.results[i]=nil end
        for _,r in ipairs(U.rows) do r.build=nil; r.pressed=nil end
    end)
end
function U:Toggle()
    if self.frame and self.frame:IsShown() and not self.closing then self:Close(); return end
    if InCombatLockdown() then A:Message("COMBAT"); return end
    -- Load Blizzard's demand-loaded UI before using its entry point.
    local loaded=A.Talents:Frame()
    if not loaded then A:Message("NOT_READY"); return end
    local ok,err=A.Talents:OpenNative()
    if not ok then A:Message(err); return end
    A.Dock:Attach(); A.Dock.collapsed=false; A.Dock:Show()
end
function U:Close()
    if self.closing then return end
    A.Dock.collapsed=true
    self.closing=true; if self.dialog then self.dialog:Hide() end
    A.Motion:Presence(self.frame,false,function() U.frame:Hide() end)
end
function U:OpenPage(p)
    self:HideTooltip()
    if self.options then self.options:Hide() end
    if self.settings and self.settings~=p then self.settings:Hide() end
    if self.contextSettings and self.contextSettings~=p then self.contextSettings:Hide() end
    A.Motion:Finish(self.frame)
    p:SetSize(280,self.frame:GetHeight()-88);p:ClearAllPoints();p:SetPoint("TOPLEFT",0,-78)
    p:Show();self:Refresh()
    A.Motion:Slide(p,1)
end
function U:ContentPage()
    for _,key in ipairs({"iconPicker","contextSettings","settings","dialog"})do
        local page=self[key];if page and page:IsShown()then return page end
    end
    return self.buildList
end
function U:Back()
    local page=self:ContentPage();if not page or page==self.buildList then return end
    self:HideTooltip()
    if page==self.iconPicker then self:ExpandIcons(false);return end
    if self.dialog then self.dialog.code:ClearFocus();self.dialog.name:ClearFocus()end
    A.Motion:Slide(page,-1,true,function()
        page:Hide()
        if U.frame:IsShown() and not U.closing then U:Refresh();A.Motion:Slide(U:ContentPage(),-1)end
    end)
end
function U:ClosePage(p)
    if A.Motion.frame==p then A.Motion:Finish(p) end
    self:HideTooltip()
    if self.frame:IsShown() and not self.closing then self:Refresh() end
end
function U:Settings()
    if InCombatLockdown() then return end
    if not self.settings then
        local p=CreateFrame("Frame",nil,self.frame);self.settings=p
        p:SetFrameLevel(self.frame:GetFrameLevel()+5);p:EnableMouse(true);fill(p,C.bg)
        text(p,20,C.text,L.SETTINGS,22,-14,290)
        p.toggle=button(p,L.GLOBAL_REMINDERS,22,-64,296,function()
            A.Store:SetRemindersEnabled(A.Store.db.remindersEnabled==false);p:Render()
        end)
        p.toggle:SetHeight(40);rounded(p.toggle,C.field,6)
        p.toggle.label:ClearAllPoints();p.toggle.label:SetPoint("LEFT",10,0);p.toggle.label:SetFont(STANDARD_TEXT_FONT,16,"")
        p.mark=p.toggle:CreateTexture(nil,"ARTWORK");p.mark:SetSize(22,22);p.mark:SetPoint("RIGHT",-10,0);p.mark:SetTexture(media.."choice-checkbox.tga")
        local heading=text(p,16,C.text,"Talent EX",22,-140,290);heading:SetFont(STANDARD_TEXT_FONT,17,"")
        local help=text(p,12,C.muted,L.TEX_HELP,22,-172,296);help:SetFont(STANDARD_TEXT_FONT,13,"");help:SetSpacing(4)
        p.importEX=button(p,L.TEX_IMPORT_ACTION,22,-228,296,function()
            if not p:IsShown() then return end
            local result,why=A.TalentEx:Import()
            if not result then p.importResult:SetText(L[why] or why);p.viewImports:Hide();return end
            local message=L.TEX_RESULT:format(result.imported,result.duplicate,result.invalid)
            if result.reason then message=message.."\n"..L.TEX_REMAINING:format(result.remaining,L[result.reason] or result.reason) end
            if result.imported+result.duplicate+result.invalid==0 then message=L.TEX_EMPTY end
            p.importResult:SetText(message);p.importedID=result.firstID
            p.viewImports:SetShown(result.imported>0 or result.duplicate>0)
        end)
        p.importEX:SetHeight(40);primaryButton(p.importEX,6)
        p.importEX.label:SetFont(STANDARD_TEXT_FONT,15,"")
        local scope=text(p,10,C.dim,L.TEX_SCOPE,22,-282,296);scope:SetFont(STANDARD_TEXT_FONT,12,"");scope:SetSpacing(3)
        p.importResult=text(p,10,C.muted,"",22,-342,296);p.importResult:SetFont(STANDARD_TEXT_FONT,13,"");p.importResult:SetSpacing(4)
        p.viewImports=button(p,L.TEX_VIEW,22,-416,296,function()
            p:Hide();U.scene="mine";U.offset=0;U.selected=p.importedID;U:Refresh()
        end,true);p.viewImports.label:SetFont(STANDARD_TEXT_FONT,14,"");p.viewImports:Hide()
        self:CreateAbout(p)
        function p:Render()local state=A.Store.db.remindersEnabled~=false and 2 or 0;self.mark:SetTexCoord(state/4,(state+1)/4,0,1)end
        p:SetScript("OnHide",function()U:CloseSocial();U:ClosePage(p)end);p:Hide()
    end
    self.settings:Render();self:OpenPage(self.settings)
end
function U:CloseSocial()
    local s=self.social;if not s or not s.backdrop then return end
    s.input:ClearFocus();s.active=nil;s.code:SetTexture(nil)
    if A.Motion.frame==s.popup then A.Motion:Finish(s.popup)end
    s.backdrop:Hide()
end
function U:OpenSocial(entry,anchor)
    if InCombatLockdown() or not self.settings:IsShown()then return end
    if self.social and self.social.active==entry then self:CloseSocial();return end
    self:CloseSocial();self:HideTooltip()
    local s=self.social
    if not s.backdrop then
        local backdrop=CreateFrame("Button","LycheeTalentSocial",UIParent);s.backdrop=backdrop
        backdrop:SetAllPoints(UIParent);backdrop:SetFrameStrata("DIALOG");backdrop:SetFrameLevel(self.frame:GetFrameLevel()+40)
        local shade=backdrop:CreateTexture(nil,"BACKGROUND");shade:SetAllPoints();shade:SetColorTexture(0,0,0,.2)
        backdrop:SetScript("OnClick",function()U:CloseSocial()end)
        backdrop:SetScript("OnHide",function()s.input:ClearFocus();s.active=nil;s.code:SetTexture(nil);if A.Motion.frame==s.popup then A.Motion:Finish(s.popup)end end)
        table.insert(UISpecialFrames,"LycheeTalentSocial")
        local popup=CreateFrame("Frame",nil,backdrop);s.popup=popup
        popup:EnableMouse(true);popup:SetClampedToScreen(true);rounded(popup,C.bg,10)
        s.title=text(popup,14,C.text,"",20,-16,242)
        s.title:SetMaxLines(1)
        local close=CreateFrame("Button",nil,popup);close:SetSize(32,32);close:SetPoint("TOPRIGHT",-8,-8)
        local back=close:CreateTexture(nil,"ARTWORK");back:SetSize(22,22);back:SetPoint("CENTER");back:SetTexture(media.."back-search.tga")
        close:SetScript("OnClick",function()U:CloseSocial()end)
        close:SetScript("OnEnter",function()back:SetVertexColor(unpack(C.hot))end)
        close:SetScript("OnLeave",function()back:SetVertexColor(unpack(C.text))end)
        s.input=field(popup,20,-54,260,60,true);s.input:SetFont(STANDARD_TEXT_FONT,14,"")
        s.input:SetScript("OnTextChanged",function(edit,user)if user and s.active and s.active.url then edit:SetText(s.active.url);edit:HighlightText()end end)
        s.input:SetScript("OnMouseUp",function(edit)edit:HighlightText()end)
        s.input:SetScript("OnEscapePressed",function()U:CloseSocial()end)
        s.code=popup:CreateTexture(nil,"ARTWORK");s.code:SetSize(208,208);s.code:SetPoint("TOP",0,-50)
        s.hint=text(popup,10,C.muted,"",0,0);s.hint:ClearAllPoints();s.hint:SetPoint("BOTTOM",0,12);s.hint:SetFont(STANDARD_TEXT_FONT,13,"")
    end
    s.active=entry;s.title:SetText(entry.title)
    s.popup:SetSize(244,entry.code and 294 or 152)
    s.popup:SetScale(self.frame:GetEffectiveScale()/UIParent:GetEffectiveScale())
    s.popup:ClearAllPoints();s.popup:SetPoint("BOTTOMLEFT",s.footer,"TOPLEFT",0,12)
    s.code:SetShown(entry.code~=nil);s.input.host:SetShown(not entry.code)
    s.hint:SetText(entry.code and L.SCAN_WECHAT or L.COPY_LINK_HELP)
    if entry.code then s.code:SetTexture(media.."About\\"..entry.code..".tga")else s.input:SetText(entry.url)end
    s.backdrop:Show();A.Motion:Slide(s.popup,1)
    if not entry.code then s.input:SetFocus();s.input:HighlightText()end
end
function U:CreateAbout(parent)
    local footer=CreateFrame("Frame",nil,parent);footer:SetSize(244,56);footer:SetPoint("BOTTOMLEFT",18,18)
    self.social={footer=footer,buttons={}}
    local version=C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("LycheeTalent","Version") or "1.0.0"
    local info=text(footer,10,C.muted,"v"..version,0,0)
    info:ClearAllPoints();info:SetPoint("RIGHT",0,-8);info:SetFont(STANDARD_TEXT_FONT,13,"")
    local entries={{icon="github",title="GitHub",url="https://github.com/Follen/LycheeTalent"}}
    if GetLocale()=="zhCN" or GetLocale()=="zhTW" then
        entries[#entries+1]={icon="wechat",title=L.AUTHOR_WECHAT,code="wechat-contact"}
        entries[#entries+1]={icon="support",title=L.WECHAT_SUPPORT,code="wechat-support"}
    else
        entries[#entries+1]={icon="x",title="Twitter / X · @follenfang",url="https://x.com/follenfang"}
        entries[#entries+1]={icon="paypal",title="PayPal",url="https://www.paypal.me/follenfang"}
    end
    for i,entry in ipairs(entries)do
        local b=CreateFrame("Button",nil,footer);self.social.buttons[i]=b;b.entry=entry
        b:SetSize(40,40);b:SetPoint("TOPLEFT",(i-1)*44,-16)
        local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(20,20);icon:SetPoint("CENTER");icon:SetTexture(media.."About\\"..entry.icon..".tga");icon:SetVertexColor(unpack(C.muted))
        b:SetScript("OnClick",function()U:OpenSocial(entry,b)end)
        b:SetScript("OnEnter",function()icon:SetVertexColor(unpack(C.text))end)
        b:SetScript("OnLeave",function()icon:SetVertexColor(unpack(C.muted))end)
        b:SetScript("OnHide",function()icon:SetVertexColor(unpack(C.muted))end)
    end
end
function U:ContextSettings(id,draft)
    if InCombatLockdown() then return end
    local build=draft or A.Store:Find(id);if not build then return end
    if not self.contextSettings then
        local p=CreateFrame("Frame",nil,self.frame);self.contextSettings=p
        p:SetFrameLevel(self.frame:GetFrameLevel()+5);p:EnableMouse(true);fill(p,C.bg)
        p.title=text(p,20,C.text,L.SCENE_REMINDERS,22,-12,290)
        p.name=text(p,10,C.muted,"",22,-43,290);p.name:SetMaxLines(1)
        p.rows={};p.tabs={}
        for i,item in ipairs({{"mythic",L.MYTHIC},{"raid",L.RAID}}) do
            local tab=button(p,item[2],22+(i-1)*153,-76,144,function(b)
                if p.scene==b.scene then return end
                A.Motion:Finish(p);p.scene=b.scene;p.offset=0;p:Render();A.Motion:Slide(p,b.scene=="raid" and 1 or -1)
            end)
            tab.scene=item[1];p.tabs[i]=tab
            tab.mark=tab:CreateTexture(nil,"ARTWORK");tab.mark:SetSize(24,2);tab.mark:SetPoint("BOTTOM",0,-1);tab.mark:SetColorTexture(unpack(C.red))
        end
        function p:Render()
            self:SetHeight(U.frame:GetHeight()-88)
            self.visibleRows=math.max(2,math.min(10,math.floor((self:GetHeight()-226)/42)))
            self.list={}
            for _,s in ipairs(A.Scenarios) do
                if s.scene==self.scene and (s.mapID or (s.journalID and s.journalID>0)) then self.list[#self.list+1]=s end
            end
            table.sort(self.list,function(a,b)
                if (a.raidOrder or 0)~=(b.raidOrder or 0) then return (a.raidOrder or 0)<(b.raidOrder or 0) end
                if (a.bossOrder or 0)~=(b.bossOrder or 0) then return (a.bossOrder or 0)<(b.bossOrder or 0) end
                return (a.label or a.name)<(b.label or b.name)
            end)
            self.offset=math.min(self.offset,math.max(0,#self.list-self.visibleRows))
            for i,row in ipairs(self.rows) do
                local scene=i<=self.visibleRows and self.list[self.offset+i] or nil;row.context=scene and scene.id;row:SetShown(scene~=nil)
                if scene then
                    row.label:SetText(scene.label or scene.name);row.icon:SetTexture(scene.icon)
                    local checked=self.draft[scene.id]==true
                    row.mark:SetTexCoord(checked and .5 or 0,checked and .75 or .25,0,1);row.bg:SetShown(checked)
                end
            end
            for _,tab in ipairs(self.tabs) do color(tab.label,tab.scene==self.scene and C.text or C.muted);tab.mark:SetShown(tab.scene==self.scene) end
            self.previous:SetShown(#self.list>self.visibleRows);self.next:SetShown(#self.list>self.visibleRows)
            self.previous:SetEnabled(self.offset>0);self.next:SetEnabled(self.offset+self.visibleRows<#self.list)
            self.toggle.label:SetText(self.enabled and L.REMINDER_ON or L.REMINDER_OFF)
        end
        for i=1,10 do
            local row=button(p,"",22,-119-(i-1)*42,296,function(b)
                if b.context then p.draft[b.context]=not p.draft[b.context];p:Render() end
            end)
            row:SetHeight(38);row.bg=fill(row,C.selected)
            row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(26,26);row.icon:SetPoint("LEFT",6,0);row.icon:SetTexCoord(.08,.92,.08,.92)
            row.label:ClearAllPoints();row.label:SetPoint("LEFT",41,0);row.label:SetWidth(168);row.label:SetJustifyH("LEFT");row.label:SetMaxLines(1);row.label:SetFont(STANDARD_TEXT_FONT,16,"")
            row.mark=row:CreateTexture(nil,"OVERLAY");row.mark:SetSize(20,20);row.mark:SetPoint("RIGHT",-5,0);row.mark:SetTexture(media.."choice-checkbox.tga")
            p.rows[i]=row
        end
        p.previous=button(p,"<",0,0,36,function()p.offset=math.max(0,p.offset-p.visibleRows);p:Render()end)
        p.next=button(p,">",0,0,36,function()p.offset=math.min(math.max(0,#p.list-p.visibleRows),p.offset+p.visibleRows);p:Render()end)
        p.previous:ClearAllPoints();p.previous:SetPoint("BOTTOMRIGHT",-55,82)
        p.next:ClearAllPoints();p.next:SetPoint("BOTTOMRIGHT",-18,82)
        p.toggle=button(p,L.REMINDER_ON,0,0,296,function()p.enabled=not p.enabled;p:Render()end)
        p.toggle:ClearAllPoints();p.toggle:SetPoint("BOTTOMLEFT",18,46)
        p.toggle.label:ClearAllPoints();p.toggle.label:SetPoint("LEFT");p.toggle.label:SetFont(STANDARD_TEXT_FONT,16,"")
        p.save=button(p,L.SAVE,0,0,296,function()
            if p.formDraft then
                p.formDraft.contexts=p.draft;p.formDraft.remind=p.enabled;p:Hide();A.Motion:Slide(U:ContentPage(),-1)
            else
                local ok,err=A.Store:SetContexts(p.buildID,p.draft,p.enabled)
                if ok then p:Hide() else p.name:SetText(L[err] or err) end
            end
        end,true)
        p.save:ClearAllPoints();p.save:SetPoint("BOTTOMLEFT",18,6);primaryButton(p.save,7);p.save:SetHeight(34)
        p:SetScript("OnHide",function()
            local fromForm=p.formDraft;p.formDraft=nil;p.draft=nil;p.buildID=nil
            if fromForm and U.frame:IsShown() and not U.closing then
                U.dialog:RefreshAssociations();U.dialogCover:Show();U.dialog:Show()
            end
            U:ClosePage(p)
        end);p:Hide()
    end
    local p=self.contextSettings
    p.buildID=id;p.formDraft=draft;p.draft={};for key,value in pairs(build.contexts or {})do if value==true then p.draft[key]=true end end
    p.enabled=not next(build.contexts or {}) or build.remind~=false;p.scene="mythic";p.offset=0;p.name:SetText(build.name)
    if draft and self.dialog:IsShown() then
        self.dialog.suspended=true;self.dialog:Hide();self.dialog.suspended=nil
    end
    p:Render();self:OpenPage(p)
end
function U:ShowReminder(prompt)
    if InCombatLockdown() then return end
    if not self.reminder then
        local p=CreateFrame("Frame","LycheeTalentReminder",UIParent);self.reminder=p
        p:SetWidth(380);p:SetPoint("CENTER",UIParent,"CENTER",0,150);p:SetFrameStrata("DIALOG");p:SetClampedToScreen(true);p:EnableMouse(true)
        rounded(p,C.bg,10)
        p.logo=p:CreateTexture(nil,"ARTWORK");p.logo:SetSize(44,44);p.logo:SetPoint("TOPLEFT",10,-9);p.logo:SetTexture(media.."logo.tga")
        p.context=text(p,18,C.text,"",0,0)
        p.context:ClearAllPoints();p.context:SetPoint("LEFT",p.logo,"RIGHT",4,0);p.context:SetWidth(208);p.context:SetMaxLines(1)
        p.rows={}
        for i=1,3 do
            local row=button(p,"",0,0,369,function(b)
                local ok,err=A.Reminders:Apply(b.buildID)
                if not ok and err~="PENDING" then p.context:SetText(L[err] or err) end
            end)
            row:SetSize(340,52);row:ClearAllPoints();row:SetPoint("TOPLEFT",20,-72-(i-1)*60)
            row.label:ClearAllPoints();row.label:SetPoint("LEFT",44,0);row.label:SetWidth(212);row.label:SetJustifyH("LEFT");row.label:SetMaxLines(1)
            row.label:SetFont(STANDARD_TEXT_FONT,16,"")
            row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(32,32);row.icon:SetPoint("LEFT",0,0);row.icon:SetTexCoord(.08,.92,.08,.92)
            local action=CreateFrame("Frame",nil,row);action:SetSize(68,32);action:SetPoint("RIGHT");rounded(action,C.red,6)
            row.actionLabel=text(action,10,C.text,L.REMINDER_SWITCH,0,0)
            row.actionLabel:ClearAllPoints();row.actionLabel:SetPoint("CENTER");row.actionLabel:SetFont(STANDARD_TEXT_FONT,14,"")
            row:SetScript("OnEnter",function()action:SetAlpha(.8)end)
            row:SetScript("OnLeave",function()action:SetAlpha(1)end)
            row:SetScript("OnHide",function()action:SetAlpha(1);row.label:SetAlpha(1)end)
            p.rows[i]=row
        end
        function p:Render()
            local shown=math.min(3,#self.prompt.builds-self.offset)
            local footer=72+shown*60
            local paged=#self.prompt.builds>3
            local height=footer+(paged and 36 or 8)
            self:SetHeight(height)
            self:SetScale(math.min(1,(UIParent:GetHeight()-40)/height,(UIParent:GetWidth()-40)/380))
            for i,row in ipairs(self.rows) do
                local build=self.prompt.builds[self.offset+i];row.buildID=build and build.id;row:SetShown(build~=nil)
                if build then row.label:SetText(build.source=="builtin" and L.LYCHEE_RECOMMENDATION or build.name);row.icon:SetTexture(build.icon or 134400)end
            end
            self.previous:ClearAllPoints();self.previous:SetPoint("TOPRIGHT",-56,-footer)
            self.next:ClearAllPoints();self.next:SetPoint("TOPRIGHT",-18,-footer)
            self.previous:SetShown(paged);self.next:SetShown(paged)
            self.previous:SetEnabled(self.offset>0);self.next:SetEnabled(self.offset+3<#self.prompt.builds)
        end
        p.previous=button(p,"<",0,0,34,function()p.offset=math.max(0,p.offset-3);p:Render()end)
        p.next=button(p,">",0,0,34,function()p.offset=math.min(math.max(0,#p.prompt.builds-1),p.offset+3);p:Render()end)
        p.dismiss=button(p,L.NOT_NOW,0,0,200,function()A.Reminders:Hide()end)
        p.dismiss:SetSize(88,32);p.dismiss:ClearAllPoints();p.dismiss:SetPoint("TOPRIGHT",-16,-15)
        p.dismiss.label:ClearAllPoints();p.dismiss.label:SetPoint("RIGHT",-4,0)
        p.dismiss.label:SetFont(STANDARD_TEXT_FONT,14,"");color(p.dismiss.label,C.muted)
        p.dismiss:SetScript("OnLeave",function(b)color(b.label,C.muted)end)
        p:SetScript("OnHide",function()p.prompt=nil;for _,row in ipairs(p.rows)do row.buildID=nil end end)
        UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="LycheeTalentReminder"
    end
    local p=self.reminder;p.prompt=prompt;p.offset=0
    local context=A.Catalog.scenarios[prompt.id]
    p.context:SetText(context and context.label or "")
    p:Render();p:Show()
end
