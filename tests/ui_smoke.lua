-- Lifecycle/dispatch substitute; not a renderer and not a claim of in-game visual QA.
local objects={};local methods={}
local function new(kind,parent)
    local v=setmetatable({kind=kind,parent=parent,shown=true,enabled=true,scripts={},events={},w=0,h=0,alpha=1}, {__index=methods})
    objects[#objects+1]=v;return v
end
function methods:SetScript(k,v)self.scripts[k]=v end
function methods:HookScript(k,v)local old=self.scripts[k];self.scripts[k]=function(...)if old then old(...)end;v(...)end end
function methods:GetEffectiveScale()return 1 end
function methods:GetRight()return 1100 end
function methods:GetLeft()return self.mouseOver and 600 or 900 end
function methods:GetTop()return 800 end
function methods:GetBottom()return 600 end
function methods:IsInspecting()return false end
function methods:RegisterEvent(k)self.events[k]=true end
function methods:UnregisterEvent(k)self.events[k]=nil end
function methods:UnregisterAllEvents()self.events={} end
function methods:SetSize(w,h)self.w=w;self.h=h end
function methods:SetWidth(w)self.w=w end
function methods:SetHeight(h)self.h=h end
function methods:GetWidth()return self.w end
function methods:GetHeight()return self.h end
function methods:SetPoint(...)self.point={...} end
function methods:GetPoint()return "CENTER",UIParent,"CENTER",0,0 end
function methods:ClearAllPoints()self.point=nil end
function methods:SetAllPoints()end
function methods:CreateFontString()return new("FontString",self)end
function methods:CreateTexture()return new("Texture",self)end
function methods:SetText(v)self.value=v;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false)end end
function methods:GetText()return self.value or "" end
function methods:GetStringWidth()return #(self.value or "")*5 end
function methods:IsMouseOver()return self.mouseOver==true end
function methods:Show()local was=self.shown;self.shown=true;if not was and self.scripts.OnShow then self.scripts.OnShow(self)end end
function methods:Hide()local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self)end end
function methods:SetShown(v)if v then self:Show()else self:Hide()end end
function methods:IsShown()return self.shown and (not self.parent or self.parent:IsShown())end
function methods:SetEnabled(v)self.enabled=v end
function methods:IsEnabled()return self.enabled end
function methods:GetFrameLevel()return self.level or 1 end
function methods:SetFrameLevel(v)self.level=v end
function methods:SetAlpha(v)self.alpha=v end
function methods:GetAlpha()return self.alpha end
function methods:SetScrollChild(v)self.child=v end
function methods:GetVerticalScroll()return self.scroll or 0 end
function methods:SetVerticalScroll(v)self.scroll=v end
function methods:GetVerticalScrollRange()return 0 end
function methods:SetOwner(v)self.owner=v end
function methods:IsOwned(v)return self.owner==v end
for _,name in ipairs({"SetFont","SetShadowOffset","SetJustifyH","SetTextColor","SetColorTexture","SetTexCoord","SetVertexColor",
"SetTexture","SetRotation","SetDrawLayer","SetBackdrop","SetBackdropColor","SetBackdropBorderColor","EnableMouse","EnableMouseWheel","SetAutoFocus","SetMultiLine",
"SetMaxBytes","ClearFocus","SetFocus","HighlightText","SetFrameStrata","SetClampedToScreen","SetMovable","RegisterForDrag",
"SetOrientation","SetValueStep","SetObeyStepOnDrag","SetMinMaxValues","SetValue","SetThumbTexture",
"StartMoving","StopMovingOrSizing","SetSpacing","SetWordWrap","SetMaxLines","SetScale","AddLine"})do methods[name]=function()end end
function methods:SetFont(path,size,flags)self.font={path,size,flags}end
function methods:SetVertexColor(r,g,b,a)self.tint={r,g,b,a}end
function methods:SetColorTexture(r,g,b,a)self.color={r,g,b,a}end
function methods:SetValue(value)self.sliderValue=value end
CreateFrame=function(kind,name,parent)local f=new(kind,parent);if name then _G[name]=f end;return f end
UIParent=new("Frame");UIParent:SetSize(1920,1080);GameTooltip=new("Frame");UISpecialFrames={};SlashCmdList={}
GetCursorPosition=function()return 700,700 end
GetLocale=function()return "zhCN" end;STANDARD_TEXT_FONT="test-font";time=function()return 1790400000 end;date=os.date
UnitClass=function()return "战士","WARRIOR" end;InCombatLockdown=function()return false end
C_SpecializationInfo={GetSpecialization=function()return 1 end,GetSpecializationInfo=function()return 71,"武器" end}
C_ChallengeMode={GetMapTable=function()return {}end}
C_AddOns={DoesAddOnExist=function()return true end,LoadAddOn=function()dofile("addon/LycheeTalent_Data_WARRIOR/Data.lua");return true end}
local timers={}
C_Timer={NewTimer=function(_,fn)local t={fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t end}
local A={}
for _,name in ipairs({"Locales","Storage","Scenarios","Catalog","Talents","TalentEx","Apply","Motion","UI","Dock","Core"})do assert(loadfile("addon/LycheeTalent/"..name..".lua"))("LycheeTalent",A)end
A.Store:Init();A.Store.db.reducedMotion=true
PlayerSpellsFrame=new("Frame",UIParent);PlayerSpellsFrame:SetSize(1100,820);PlayerSpellsFrame:Hide()
PlayerSpellsFrame.TalentsFrame=new("Frame",PlayerSpellsFrame)
A.Talents.Frame=function()return PlayerSpellsFrame.TalentsFrame end
A.Talents.OpenNative=function()PlayerSpellsFrame:Show();PlayerSpellsFrame.TalentsFrame:Show();return true end
A.Dock:Init()
A:Toggle()
assert(A.UI.frame:IsShown() and #A.UI.results>0,"published builtins display")
assert(not A.UI.scenarioList and #A.UI.rows==18,"only one bounded build pool")
assert(A.UI.frame.parent==PlayerSpellsFrame.TalentsFrame,"panel is parented to native talent page")
assert(A.UI.frame.point[2]==PlayerSpellsFrame and A.UI.frame.point[3]=="TOPRIGHT","right-side anchor")
assert(A.UI.frame:GetWidth()==280,"compact dock layout")
assert(A.UI.frame:GetHeight()==PlayerSpellsFrame:GetHeight(),"portrait panel")
assert(A.UI.buildList:IsShown(),"builds display directly without scene drilldown")
assert(not A.UI.allTargets and not A.UI.tabs,"redundant navigation hidden")
local seen={}
for _,build in ipairs(A.UI.results) do
    assert(A.Catalog:Title(build)==A.Catalog:Target(build),"builtin title is only the dungeon name")
    assert(not seen[build.scenarioID],"one highest build per dungeon")
    seen[build.scenarioID]=true
end
local beforeResize=#objects
PlayerSpellsFrame:SetHeight(900);PlayerSpellsFrame.scripts.OnSizeChanged()
assert(A.UI.frame:GetHeight()==900 and A.UI.frame.point[5]==0,"native resize preserves aligned edges")
assert(#objects==beforeResize,"resize reuses row pools")
PlayerSpellsFrame:SetHeight(820);PlayerSpellsFrame.scripts.OnSizeChanged()
local first=A.UI.rows[1]
assert(first.build,"selected scenario has a build")
assert(not A.UI.search and not A.UI.status,"no search controls or footer explanation")
assert(not A.UI.back:IsShown(),"primary page has no close or back control")
assert(not A.UI.footer:IsShown(),"recommended dungeon page has no personal management actions")
local actualStart=A.Apply.Start
local applied
A.Apply.Start=function(_,build,shared) applied={build=build,shared=shared};return true end
if arg[1]=="pending-prompt" then
    StaticPopupDialogs={}
    local popup
    StaticPopup_Show=function(key,title,_,data)popup={key=key,title=title,data=data};return popup end
    StaticPopup_Hide=function(key)if popup then StaticPopupDialogs[key].OnCancel(nil,popup.data);popup=nil end end
    local ticket={build={id=first.build.id}}
    A.Apply.Start=function()A.Apply.pendingTicket=ticket;return nil,"PENDING",ticket end
    local accepted
    A.Apply.ConfirmPending=function(_,data)accepted=data;return true end
    local function click()
        first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnClick(first,"LeftButton")
        first.scripts.OnDoubleClick(first,"LeftButton")
    end
    click()
    assert(popup and popup.data==ticket and not accepted,"double-click opens a bound confirmation without applying")
    assert(popup.title==A.Catalog:Title(first.build),"confirmation names the selected dungeon")
    StaticPopupDialogs[popup.key].OnCancel(nil,popup.data)
    assert(not A.Apply.pendingTicket and not A.UI.pendingPrompt and not accepted,"cancel does not apply")
    click();StaticPopupDialogs[popup.key].OnAccept(nil,popup.data)
    assert(accepted==ticket and not A.UI.pendingPrompt,"accept passes exact ticket")
    click();A.UI.frame:Hide()
    assert(not A.Apply.pendingTicket and not A.UI.pendingPrompt and not popup,"closing talents cancels pending confirmation")
    print("PASS pending confirmation UI: accept, cancel, hidden cleanup");return
end
first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnClick(first,"LeftButton")
assert(not applied and A.UI.selected==first.build.id,"single click selects without applying")
if arg[1]=="same-build-refresh" then
    A.UI:Refresh()
    first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnDoubleClick(first,"LeftButton")
    assert(applied and applied.build.id==first.build.id,"unchanged-row refresh swallowed a real double click")
    print("PASS same-build refresh between clicks")
    return
end
first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnDoubleClick(first,"LeftButton")
assert(applied and applied.build.id==first.build.id,"double click applies its build")
applied=nil;first.scripts.OnDoubleClick(first,"LeftButton")
assert(not applied,"one double click dispatches once")
first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnClick(first,"LeftButton")
A.UI.scene="raid";A.UI:Refresh();first.scripts.OnMouseDown(first,"LeftButton");first.scripts.OnDoubleClick(first,"LeftButton")
assert(not applied,"rebound row rejects double click from previous binding")
A.UI.scene="mythic";A.UI:Refresh()
assert(not A.UI.detailPanel,"click never opens a detail page")
A.Apply.Start=actualStart
assert(not first.mark:IsShown(),"click alone cannot mark current")
local currentReader=A.Apply.CurrentBuildID
A.Apply.CurrentBuildID=function()return first.build.id end
A.UI:Refresh();assert(first.mark:IsShown(),"verified state renders current accent")
A.Apply.CurrentBuildID=function()return nil end
A.Apply.op={buildID=first.build.id};A.UI:Refresh()
assert(not first:IsEnabled() and first.progress:GetText()==A.L.APPLYING_SHORT,"busy state blocks repeated click and shows progress")
assert(not first.more:IsShown(),"status replaces the menu button while applying")
assert(not first.mark:IsShown(),"in-flight state has no false success mark")
A.Apply.op=nil;A.Apply.CurrentBuildID=currentReader;A.UI:Refresh()
assert(first:IsEnabled() and first.progress:GetText()=="","finished operation releases row")
assert(first.more:IsShown(),"menu returns on failure or cleared status")
-- Explicit completion feedback does not depend on differing talent contents.
local feedbackID=first.build.id
GetTime=function()return 100 end
A.UI:ShowApplySuccess(feedbackID,GetTime()-.1)
assert(first.progress:GetText()==A.L.APPLYING_SHORT and not first.successFlash,"fast completion keeps text-only switching feedback")
assert(not first.more:IsShown(),"minimum display time keeps menu hidden")
first.scripts.OnUpdate(first,1.3)
assert(first.progress:GetText()==A.L.APPLYING_SHORT,"switching remains for at least 1.5 seconds total")
A.UI:Refresh()
assert(first.progress:GetText()==A.L.APPLYING_SHORT,"ordinary refresh preserves the minimum display time")
first.scripts.OnUpdate(first,.11)
assert(first.progress:GetText()==A.L.APPLIED_SHORT,"success follows minimum switching time")
assert(not first.more:IsShown(),"success occupies the same menu position")
first.scripts.OnUpdate(first,1.4)
assert(first.progress:GetText()==A.L.APPLIED_SHORT,"success text stays readable too")
first.scripts.OnUpdate(first,.1)
assert(first.progress:GetText()=="" and not first.scripts.OnUpdate,"feedback expires without a permanent update driver")
assert(first.more:IsShown(),"menu returns after confirmation expires")
local previousReducedMotion=A.Store.db.reducedMotion
A.Store.db.reducedMotion=true
A.UI:ShowApplySuccess(feedbackID,GetTime()-2)
assert(first.progress:GetText()==A.L.APPLIED_SHORT,"slow completion does not add a second switching delay")
first.scripts.OnUpdate(first,.2)
assert(not first.successFlash and first.progress:GetText()==A.L.APPLIED_SHORT,"reduced motion uses the same text-only confirmation")
A.Store.db.reducedMotion=previousReducedMotion
A.UI.scene="raid";A.UI:Refresh()
assert(not first.successRemaining and not first.switchRemaining and not first.scripts.OnUpdate,"recycled row clears prior feedback")
A.UI.scene="mythic";A.UI:Refresh()
A.UI:ShowApplySuccess(first.build.id,GetTime())
A.Apply.op={buildID=first.build.id};A.UI:Refresh()
assert(not first.switchRemaining and not first.successRemaining and first.progress:GetText()==A.L.APPLYING_SHORT,"new operation replaces old feedback")
A.Apply.op=nil;A.UI:Refresh()
assert(first.progress:GetText()=="","failed operation does not inherit success feedback")
local id=A.UI.rows[1].build.id
local shift=false
IsShiftKeyDown=function()return shift end
first.mouseOver=true
first.scripts.OnEnter(first)
local tip=A.UI.tooltip
assert(tip:IsShown() and tip.meta:GetText():find("WCL",1,true),"owned tooltip exposes record summary")
assert(not tip.copy and not tip.edit and not tip.url and not tip.events.MODIFIER_STATE_CHANGED,"source links and Shift interaction removed from tooltip")
first.mouseOver=false;first.scripts.OnLeave(first)
assert(not tip:IsShown() and not tip.owner and next(tip.events)==nil,"leaving clears tooltip ownership and events")
local tooltipCount=#objects
for i=1,100 do first.scripts.OnEnter(first);first.scripts.OnLeave(first) end
assert(#objects==tooltipCount,"tooltip controls reused")
first.mouseOver=true;first.scripts.OnEnter(first)
A.UI.scene="raid";A.UI:Refresh()
local expectedBosses={"3470","3445","3497","3455","3420","3421","3429","3492","3379"}
for i,id in ipairs(expectedBosses) do assert(tostring(A.UI.results[i].scenarioID)==id,"raid journal order at position "..i) end
assert(not tip:IsShown(),"row rebinding dismisses obsolete source")
A.UI.scene="mythic";A.UI:Refresh()
assert(not A.Catalog:SourceURL({report="bad/path",fight=1}) and not A.Catalog:SourceURL({report="Valid",fight=0}),"invalid reports do not create links")
A.UI:BuildOptions(id,A.UI.rows[1].more)
for _,action in ipairs(A.UI.options.actions) do
    assert(action.key~="favorite" and action.key~="diff" and action.key~="restore","removed actions must not appear in menus")
end
assert(A.UI.options.option.checked,"build defaults to independent bars")
A.UI.options.option.scripts.OnMouseDown(A.UI.options.option,"LeftButton");A.UI.options.option.scripts.OnClick(A.UI.options.option)
assert(A.Store.character.modes[tostring(id)]==true,"menu saves this build as shared")
local other=A.Store:Save("独立方案","example-code","mythic","副本",71)
A.UI:BuildOptions(other.id,A.UI.rows[1].more)
assert(A.UI.options.option.checked,"another build retains independent bars")
A.Store:Delete(other.id)
A.UI:BuildOptions(id,A.UI.rows[1].more)
assert(not A.UI.options.option.checked,"menu restores this build preference")
A.UI.options.option.scripts.OnMouseDown(A.UI.options.option,"LeftButton");A.UI.options.option.scripts.OnClick(A.UI.options.option)
assert(A.Store.character.modes[tostring(id)]==false,"independent preference is per build")
assert(A.UI.options.option.label.point[1]=="RIGHT","menu option reserves a right-aligned check")
assert(A.UI.options.title:GetText()==A.L.ACTION_MENU,"Lychee-style action menu heading")
A.UI.options.mouseOver=false;A.UI.rows[1].more.mouseOver=false
A.UI.options.scripts.OnEvent()
assert(not A.UI.options:IsShown() and next(A.UI.options.events)==nil,"outside click closes menu and releases events")
A.UI:BuildOptions(id,A.UI.rows[1].more);A.UI.escape:Hide()
assert(not A.UI.options:IsShown() and A.UI.frame:IsShown(),"Escape dismisses menu before panel")
A.UI.scene="raid";A.UI:Refresh()
assert(not A.UI.footer:IsShown(),"raid page has no import or save-current buttons")
assert(A.UI.difficultyButton:IsShown(),"raid shows paired difficulty choices")
local heroic=A.UI.difficultyChoices[1];local mythic=A.UI.difficultyChoices[2]
heroic.scripts.OnClick(heroic)
assert(A.UI.difficulty==4 and heroic.selected:IsShown() and not mythic.selected:IsShown(),"heroic is explicit selected choice")
mythic.scripts.OnClick(mythic)
assert(A.Store.character.raidDifficulty==5 and mythic.selected:IsShown() and not heroic.selected:IsShown(),"mythic selection is remembered")
A.UI.scene="mythic";A.UI:Refresh();assert(not A.UI.difficultyButton:IsShown(),"difficulty hidden outside raid")
assert(not A.UI.barOption,"no global action bar option")
local highWater=#objects
for i=1,100 do A:Toggle();A:Toggle() end
assert(#objects==highWater,"reopening cannot allocate frames or regions")
A.UI.target=nil;A.UI.scene="mine";A.UI.source="user";A.UI:Refresh();assert(#A.UI.results==0,"source filter")
assert(A.UI.footer:IsShown(),"import and save-current belong to My Builds")
local b=A.Store:Save("自建测试","example-code","mythic","副本",71)
A.UI:Refresh();assert(#A.UI.results==1,"new user build displays")
local row=A.UI.rows[1]
row.scripts.OnMouseDown(row);b.code="changed-fixture";A.UI:Refresh();A.UI.selected=nil;row.scripts.OnClick(row)
assert(A.UI.selected==nil,"rebound row cannot execute old click")
A.UI:Dialog(false,{name="Save copy",code="valid-fixture"})
assert(A.UI.dialog.name.host:IsShown() and A.UI.dialog.code.host:IsShown() and A.UI.dialog.associations:IsShown(),"creating a copy exposes name, string and associations")
A.UI.dialog:Hide()
A.UI:Dialog(true,{name="Export",code="fixture-string"})
assert(not A.UI.dialog.name.host:IsShown() and A.UI.dialog.code.host:IsShown(),"export displays only the copy field")
assert(A.UI.dialog.originalCode=="fixture-string","readonly copy field retains its source")
assert(A.UI.back:IsShown() and not A.UI.buildList:IsShown() and A.UI.dialogCover:IsShown(),"secondary page owns content and exposes back navigation")
A.UI.back.scripts.OnClick()
assert(not A.UI.back:IsShown() and not A.UI.dialogCover:IsShown() and A.UI.buildList:IsShown() and A.UI.frame:IsShown(),"back restores list without closing sidebar")
A.UI:Dialog(false)
assert(not A.UI.dialog.sceneButton and not A.UI.dialog.target and not A.UI.dialog.help:IsShown(),"import only asks for code and optional name")
assert(not A.UI.dialog.save:IsEnabled(),"empty import cannot submit")
local validate=A.Talents.Validate
A.Talents.Validate=function(_,code)if code=="import-fixture" then return code,71 end;return nil,"BAD_CODE" end
A.UI.dialog.code:SetText("bad-fixture");A.UI.dialog.save.scripts.OnClick(A.UI.dialog.save)
assert(A.UI.dialog:IsShown() and A.UI.dialog.error:GetText()==A.L.BAD_CODE,"invalid code stays in the form")
A.UI.dialog.code:SetText("import-fixture");A.UI.dialog.name:SetText("   ")
local providerCount,providerReleased,providerActive=0,0,0
IconDataProviderMixin={};IconDataProviderExtraType={Spellbook=2};IconDataProviderIconType={Spell=1,Item=2}
A.Icons={Create=function()
    providerCount=providerCount+1
    providerActive=providerActive+1
    return {Release=function(self)assert(not self.released,'provider released twice');self.released=true;providerReleased=providerReleased+1;providerActive=providerActive-1 end,
        SetIconTypes=function(self,v)assert(not self.released);self.filter=v end,GetNumIcons=function(self)assert(not self.released);return self.filter and 35 or 65 end,
        GetIconByIndex=function(_,i)return 130000+i end}
end}
assert(not A.UI.iconPicker,"icon catalog is lazy")
A.UI:ChooseIcon();local picker=A.UI.iconPicker
assert(#picker.cells==35 and not picker.pages and not picker.next and not picker.previous and not picker.position,
    'virtual icon grid has a bounded row pool and no pagination controls')
assert(picker.parent==picker.clip and picker.clip.parent==A.UI.dialog,'picker expands inside its editor')
assert(A.UI.dialog.expansion==336 and A.UI.dialog.name.host.point[3]==-440 and A.UI.dialog.save.point[3]==-806,
    'expanded picker pushes fields and save down instead of covering them')
assert(A.UI.dialogScroll.child==A.UI.dialog and A.UI.dialogScrollBar:IsShown(),'expanded editor has a scrollable viewport')
for _,bar in ipairs({picker.scroll,A.UI.dialogScrollBar}) do
    assert(bar:GetWidth()==12 and bar.thumb:GetWidth()==3,'Lychee thin thumb retains a larger drag gutter')
    assert(bar.thumb.color[1]==.835 and bar.thumb.color[2]==.235 and bar.thumb.color[3]==.285,'both scrollbars use the Lychee accent, never a white block')
    assert(bar.thumb:GetHeight()>=24 and bar.thumb:GetHeight()<=48,'thumb uses Lychee length bounds')
end
local countIcons=picker.provider.GetNumIcons
picker.provider.GetNumIcons=function()return 5 end;picker:Refresh()
assert(not picker.scroll:IsShown(),'one icon page has no scrollbar')
picker.provider.GetNumIcons=countIcons;picker:Refresh()
local poolSize=#objects
picker.provider.GetNumIcons=function()return 75799 end;picker:Refresh()
picker:ScrollTo(51)
assert(picker.cells[1].index==6 and picker.grid:GetVerticalScroll()==7 and picker.scroll.sliderValue==51,'thumb and continuous row offset stay synchronized')
picker:ScrollTo(1e9)
assert(picker.offset==picker.maximum and picker.cells[29].index==75799 and not picker.cells[30]:IsShown(),'last partial row is reachable without overscroll')
A.UI.dialogScroll:SetVerticalScroll(100)
A.UI.dialogScroll.mouseOver=true;picker.clip.mouseOver=true;picker.grid.mouseOver=true
picker.grid.scripts.OnMouseWheel(picker.grid,-1)
assert(A.UI.dialogScroll:GetVerticalScroll()==100,'inner bottom edge does not scroll the outer form')
picker:ScrollTo(0);picker.cells[1].scripts.OnMouseWheel(picker.cells[1],-1)
assert(picker.offset==44 and A.UI.dialogScroll:GetVerticalScroll()==100,'wheel over an icon moves one inner row only')
A.UI.dialogScroll.scripts.OnMouseWheel(A.UI.dialogScroll,-1)
assert(picker.offset==88 and A.UI.dialogScroll:GetVerticalScroll()==100,'outer-delivered wheel over the visible grid routes inward')
picker.grid.mouseOver=false
A.UI.dialogScroll.scripts.OnMouseWheel(A.UI.dialogScroll,-1)
assert(picker.offset==88 and A.UI.dialogScroll:GetVerticalScroll()==144,'wheel outside the grid moves only the outer form')
picker.grid.mouseOver=true;picker.clip.mouseOver=false
A.UI.dialogScroll.scripts.OnMouseWheel(A.UI.dialogScroll,1)
assert(picker.offset==88 and A.UI.dialogScroll:GetVerticalScroll()==100,'clipped-away grid cannot intercept the outer wheel')
picker.clip.mouseOver=true
assert(#objects==poolSize,'large catalog scrolling allocates no additional controls')
picker.provider.GetNumIcons=countIcons;picker:ScrollTo(0);A.UI.dialogScroll:SetVerticalScroll(0)
local cell=picker.cells[1]
cell.scripts.OnMouseDown(cell,"LeftButton")
picker.grid.scripts.OnMouseWheel(picker.grid,-1)
cell.scripts.OnClick(cell,"LeftButton")
assert(picker:IsShown() and A.UI.dialog.iconValue==134400,"scrolling rejects stale presses")
cell.scripts.OnMouseDown(cell,"LeftButton");cell.scripts.OnClick(cell,"LeftButton")
assert(not picker:IsShown() and A.UI.dialog.iconValue==130006,"selecting changes only the draft")
assert(not picker.provider and providerActive==0,'closed picker must release its icon catalog')
assert(A.UI.dialog.expansion==0 and A.UI.dialog.save.point[3]==-470,'selection restores form layout')
A.UI:ChooseIcon();A.UI.back.scripts.OnClick()
assert(not picker:IsShown() and A.UI.dialog:IsShown() and A.UI.dialog.code:GetText()=="import-fixture","picker back retains input")
A.UI.dialog.save.scripts.OnClick(A.UI.dialog.save)
local imported=A.Store:Find(A.UI.selected)
assert(imported.icon==130006,"selected icon persists with saved build")
A.UI:Dialog(false,{name=imported.name,code=imported.code,icon=imported.icon,editID=imported.id})
A.UI:ChooseIcon();picker.tabs[3].scripts.OnClick(picker.tabs[3]);assert(picker.offset==0 and picker.maximum==44,"category changes reset the inner scroll range")
cell.scripts.OnMouseDown(cell,"LeftButton");cell.scripts.OnClick(cell,"LeftButton")
A.UI.dialog:Hide();assert(imported.icon==130006,"cancelling edit preserves saved icon")
local iconObjects=#objects
for i=1,100 do A.UI:Dialog(false);A.UI:ChooseIcon();A.UI.dialog:Hide() end
assert(#objects==iconObjects and providerCount==providerReleased and providerActive==0 and not picker.provider and not picker:IsShown(),"picker reuses UI but releases its catalog on every close")
A.UI:Dialog(false);A.Store.db.reducedMotion=false;A.UI:ChooseIcon()
assert(picker.clip.scripts.OnUpdate and A.UI.dialog.expansion==0,'expansion starts at the existing layout')
picker.clip.scripts.OnUpdate(nil,.08)
local partial=A.UI.dialog.expansion
assert(partial>0 and partial<336 and picker.clip:GetHeight()==partial-16,'height reveal and form movement stay synchronized')
A.UI:ChooseIcon();picker.clip.scripts.OnUpdate(nil,.2)
assert(not picker:IsShown() and A.UI.dialog.expansion==0 and not picker.provider and not picker.clip.scripts.OnUpdate,'reversal collapses and releases exactly once')
A.UI:ChooseIcon();picker.clip.scripts.OnUpdate(nil,.3)
assert(A.UI.dialog.expansion==336 and not picker.clip.scripts.OnUpdate,'expanded state has no idle animation')
A.UI:ExpandIcons(false);picker.clip.scripts.OnUpdate(nil,.04);A.UI:ChooseIcon();picker.clip.scripts.OnUpdate(nil,.3)
assert(picker:IsShown() and A.UI.dialog.expansion==336,'reopening cancels the pending collapse')
A.UI.dialog:Hide()
assert(not picker.provider and not picker.clip.scripts.OnUpdate and A.UI.dialog.expansion==0,'parent hide cancels expansion and catalog ownership')
A.Store.db.reducedMotion=true
assert(imported and imported.code=="import-fixture" and imported.name:find("武器",1,true) and A.UI.scene=="mine","optional name imports directly into My Builds with a specialization name")
A.Talents.Validate=validate
A.UI:Dialog(false);A.UI.dialog:Hide();local afterDialog=#objects
for i=1,100 do A.UI:Dialog(false);A.UI.dialog:Hide() end
assert(#objects==afterDialog,"dialog controls are reused")
A.UI.frame:Hide();assert(not A.UI.searchTimer and next(A.UI.frame.events)==nil,"hidden UI releases timers and subscriptions")
-- Native hide, page switching and re-open retain one set of hooks/controls.
PlayerSpellsFrame.TalentsFrame:Hide()
assert(not A.UI.frame.shown,"switching away from talents hides dock")
PlayerSpellsFrame.TalentsFrame:Show()
assert(A.UI.frame:IsShown(),"returning to talent page restores dock")
PlayerSpellsFrame:Hide()
assert(not A.UI.frame.shown and not A.UI.searchTimer,"native close releases dock")
PlayerSpellsFrame:Show();PlayerSpellsFrame.TalentsFrame.scripts.OnShow()
assert(A.UI.frame:IsShown(),"native reopening restores dock")
A.UI:Close();assert(not A.UI.frame:IsShown(),"close collapses panel only")
assert(PlayerSpellsFrame:IsShown(),"collapse preserves native frame")
assert(not A.Dock.button,"no extra native talent window button")
A:Toggle();assert(A.UI.frame:IsShown(),"slash command reopens collapsed panel")
local count=#objects
for i=1,100 do A.Dock:Attach() end
assert(#objects==count,"attachment is idempotent")
-- Talent EX may create its frame after our native addon-loaded handler.
TalentLoadoutExMainFrame=new("Frame",PlayerSpellsFrame)
A.Dock.events.scripts.OnEvent(A.Dock.events,"ADDON_LOADED","TalentLoadoutsEx")
assert(A.Dock.anchorTimer,"late addon load schedules discovery")
A.Dock.anchorTimer.fn()
A.UI:Scale()
assert(A.UI.frame.point[2]==TalentLoadoutExMainFrame and A.UI.frame.point[3]=="TOPRIGHT","dock follows visible Talent EX")
local exShow=TalentLoadoutExMainFrame.scripts.OnShow
for i=1,100 do A.Dock:Anchor()end
assert(TalentLoadoutExMainFrame.scripts.OnShow==exShow,"external hooks installed only once")
TalentLoadoutExMainFrame:Hide()
assert(A.UI.frame.point[2]==PlayerSpellsFrame,"hidden Talent EX restores native anchor")
TalentLoadoutExMainFrame:Show()
assert(A.UI.frame.point[2]==TalentLoadoutExMainFrame,"reopened Talent EX restores adjacent docking")
TalentLoadoutExMainFrame.scripts.OnSizeChanged(TalentLoadoutExMainFrame)
assert(A.UI.frame.point[2]==TalentLoadoutExMainFrame,"resizing preserves adjacent docking")
TalentLoadoutExMainFrame:Hide()
-- Scene associations are draft-only until saved, and both overlays reuse pools.
A.UI:ContextSettings(imported.id)
local contexts=A.UI.contextSettings
assert(#contexts.rows==10 and contexts:IsShown(),'bounded scene association picker')
assert(contexts.parent==A.UI.frame and A.UI.back:IsShown() and not A.UI.buildList:IsShown(),'association replaces sidebar content with a back action')
local contextRow=contexts.rows[1];local contextID=contextRow.context
contextRow.scripts.OnClick(contextRow)
contexts:Hide();assert(not next(imported.contexts or {}),'cancel discards scene association draft')
A.UI:ContextSettings(imported.id);contextRow.scripts.OnClick(contextRow)
contexts.save.scripts.OnClick(contexts.save)
assert(imported.contexts[contextID] and imported.remind,'save enables explicitly selected arrival reminders')
A.UI.settingsButton.scripts.OnClick(A.UI.settingsButton)
assert(A.UI.settings:IsShown() and A.UI.settings.parent==A.UI.frame and not A.UI.buildList:IsShown(),'gear replaces sidebar content')
assert(A.UI.brand.font[2]==24,'secondary pages preserve primary brand typography')
local gear,back=A.UI.settingsButton,A.UI.back
assert(gear.w==back.w and gear.h==back.h and gear.icon.w==back.icon.w and gear.icon.h==back.icon.h,'header actions share visual and hit sizes')
gear.scripts.OnEnter();back.scripts.OnEnter()
for i=1,3 do assert(gear.icon.tint[i]==back.icon.tint[i],'header actions share hover color')end
gear.scripts.OnMouseDown();assert(gear.icon.alpha==.7,'gear shows pressed feedback')
gear.scripts.OnLeave();assert(gear.icon.alpha==1 and gear.icon.tint[1]~=back.icon.tint[1],'gear restores default feedback')
back.scripts.OnLeave()
A.UI.settings.toggle.scripts.OnClick(A.UI.settings.toggle)
assert(A.Store.db.remindersEnabled==false,'global setting persists off')
A.UI.settings.toggle.scripts.OnClick(A.UI.settings.toggle)
assert(A.Store.db.remindersEnabled==true,'global setting persists on')
A.UI.settings:Hide()
A.UI:Refresh()
local linkedRow
for _,r in ipairs(A.UI.rows)do if r.build and r.build.id==imported.id then linkedRow=r end end
assert(linkedRow and linkedRow.link:IsShown(),'bound personal builds expose the linked affordance')
assert(linkedRow.link:GetWidth()==32 and linkedRow.link:GetHeight()==32 and linkedRow.link.icon:GetWidth()==22,'linked affordance has a larger icon and full hit area')
assert(linkedRow.more:GetWidth()==34 and linkedRow.more.icon:GetWidth()==20 and linkedRow.more.icon.point[1]=="CENTER",'more dots are centered in their hit area')
linkedRow.more.scripts.OnEnter(linkedRow.more)
assert(linkedRow.more.icon.tint[1]>.9,'more dots highlight on hover')
linkedRow.more.scripts.OnMouseDown(linkedRow.more)
assert(linkedRow.more.icon.alpha==.7,'more dots show pressed feedback')
linkedRow.more.scripts.OnMouseUp(linkedRow.more)
linkedRow.more.scripts.OnLeave(linkedRow.more)
assert(linkedRow.more.icon.alpha==1 and linkedRow.more.icon.tint[1]<.95,'more dots restore their default state')
assert(linkedRow.title:GetWidth()==122,'linked build title uses the space released by the text badge')
linkedRow.link.scripts.OnEnter(linkedRow.link)
assert(A.UI.tooltip.bindings and #A.UI.tooltip.bindings==1,'Lychee tooltip includes bound encounter')
assert(linkedRow.link.icon.tint[1]>.9,'linked icon highlights on hover')
linkedRow.link.scripts.OnLeave(linkedRow.link)
assert(not A.UI.tooltip:IsShown(),'linked tooltip closes on leave')
linkedRow.link.scripts.OnClick(linkedRow.link)
assert(A.UI.dialog:IsShown() and A.UI.dialog.code.host:IsShown(),'linked affordance opens the unified editable form')
local preserved=imported.contexts[contextID]
A.UI.dialog.associations.scripts.OnClick(A.UI.dialog.associations)
assert(contexts:IsShown() and not A.UI.dialog:IsShown(),'form swaps to association picker')
contextRow.scripts.OnClick(contextRow);contexts.save.scripts.OnClick(contexts.save)
assert(A.UI.dialog:IsShown() and imported.contexts[contextID]==preserved,'association changes stay in form draft until final save')
A.UI.back.scripts.OnClick(A.UI.back)
assert(not A.UI.dialog:IsShown() and A.UI.buildList:IsShown() and imported.contexts[contextID]==preserved,'cancel form restores list and preserves persisted associations')
-- Editing string and associations commits together; the old string is not locked.
A.UI:Dialog(false,{name=imported.name,code=imported.code,icon=imported.icon,editID=imported.id,contexts=imported.contexts,remind=imported.remind})
local oldValidate=A.Talents.Validate
A.Talents.Validate=function(_,code)if code=="edited-string"then return code,71 end;return nil,"BAD_CODE"end
A.UI.dialog.code:SetText("edited-string")
A.UI.dialog.name:SetText("统一保存")
A.UI.dialog.iconValue=130032
A.UI.dialog.associations.scripts.OnClick(A.UI.dialog.associations)
contexts.rows[1].scripts.OnClick(contexts.rows[1]);contexts.save.scripts.OnClick(contexts.save)
assert(imported.code~="edited-string" and imported.contexts[contextID],'edits remain draft-only')
A.UI.dialog.save.scripts.OnClick(A.UI.dialog.save)
assert(imported.name=="统一保存" and imported.icon==130032 and imported.code=="edited-string" and not imported.contexts[contextID],
    'one save updates name, icon, string and associations')
A.Talents.Validate=oldValidate
local reminderChoice
A.Reminders={Apply=function(_,id)reminderChoice=id;return true end,Hide=function()A.UI.reminder:Hide()end}
local prompt={id=contextID,builds={imported}}
A.UI:ShowReminder(prompt)
assert(A.UI.reminder.parent==UIParent,'reminder lives independently of native talent window')
A.UI.reminder.rows[1].scripts.OnClick(A.UI.reminder.rows[1]);assert(reminderChoice==imported.id,'reminder dispatches exact stable build ID')
A.UI.reminder:Hide()
local overlayObjects=#objects
for i=1,100 do A.UI:ContextSettings(imported.id);contexts:Hide();A.UI:ShowReminder(prompt);A.UI.reminder:Hide()end
assert(#objects==overlayObjects,'association and reminder controls reused across 100 openings')
A.UI:Settings()
local settings=A.UI.settings
settings.importEX.scripts.OnClick(settings.importEX)
assert(settings.importResult:GetText()==A.L.TEX_UNAVAILABLE and not settings.viewImports:IsShown(),"missing Talent EX is explained in settings")
local validateEX=A.Talents.Validate
A.Talents.Validate=function(_,code)return code,71 end
TalentLoadoutEx={WARRIOR={[1]={{name="EX imported",text="ex-ui-fixture",icon=456}}}}
settings.importEX.scripts.OnClick(settings.importEX)
assert(settings.viewImports:IsShown() and settings.importedID,"settings import offers navigation to saved builds")
local exID=settings.importedID
settings.viewImports.scripts.OnClick(settings.viewImports)
assert(A.UI.scene=="mine" and A.UI.selected==exID and not settings:IsShown(),"import destination is My Builds")
A.UI:Settings();settings.importEX.scripts.OnClick(settings.importEX)
assert(settings.importResult:GetText()==A.L.TEX_RESULT:format(0,1,0),"repeated UI import skips duplicates")
A.Talents.Validate=validateEX;TalentLoadoutEx=nil
assert(#A.UI.social.buttons==3 and A.UI.social.buttons[2].entry.icon=='wechat' and A.UI.social.buttons[3].entry.icon=='support','Chinese footer exposes GitHub and WeChat only')
local social=A.UI.social
A.UI:OpenSocial(social.buttons[1].entry,social.buttons[1])
assert(social.input:GetText()=='https://github.com/Follen/LycheeTalent' and social.input.host:IsShown(),'project link opens as copyable text')
A.UI:OpenSocial(social.buttons[2].entry,social.buttons[2])
assert(social.code:IsShown() and not social.input.host:IsShown(),'WeChat opens QR without link field')
A.UI:CloseSocial();local socialObjects=#objects
for i=1,100 do A.UI:OpenSocial(social.buttons[1].entry,social.buttons[1]);A.UI:CloseSocial()end
assert(#objects==socialObjects and not social.backdrop:IsShown(),'social popup reuses frames and closes fully')
A.UI:OpenSocial(social.buttons[1].entry,social.buttons[1]);A.UI.settings:Hide()
assert(not social.backdrop:IsShown() and not social.active,'leaving settings closes link popup')
local priorLocale=GetLocale
for _,locale in ipairs({'enUS','deDE','zhTW'})do
 GetLocale=function()return locale end
 A.UI:CreateAbout(new('Frame',A.UI.frame))
 local buttons=A.UI.social.buttons
 assert(#buttons==3,'regional footer has three actions')
 assert(buttons[2].entry.icon==(locale=='zhTW' and 'wechat' or 'x') and buttons[3].entry.icon==(locale=='zhTW' and 'support' or 'paypal'),'regional links must not leak across locales')
end
GetLocale=priorLocale;A.UI.social=social
print("PASS UI lifecycle: 100 open/close cycles, 100 dialog cycles, fixed row pools, stale click rejection, hidden cleanup; objects="..#objects)
