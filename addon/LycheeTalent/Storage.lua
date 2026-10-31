local _, A = ...
local S = {}
A.Store = S
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local schema="Lychee.Talent.Schema.V2:"
function S:Init()
    -- Each root has its own lifetime: resetting a different character must
    -- never discard account builds already created under the current schema.
    if type(LycheeTalentDB)~="table" or LycheeTalentDB.schema~=schema then
        LycheeTalentDB={schema=schema,nextID=0,builds={},remindersEnabled=true,reducedMotion=false}
    end
    if type(LycheeTalentCharacterDB)~="table" or LycheeTalentCharacterDB.schema~=schema then
        LycheeTalentCharacterDB={schema=schema,raidDifficulty=5,heroChoices={},actionBars={version=1,specs={}}}
    end
    self.db,self.character=LycheeTalentDB,LycheeTalentCharacterDB
    self.builds=self.db.builds;self.undo=nil
end
function S:GetHero(specID)
    local choices=self.character and self.character.heroChoices
    return choices and choices[tostring(specID)]
end
function S:SetHero(specID,heroTree)
    if type(specID)~="number" or specID<=0 or specID%1~=0 then return nil,"HERO_UNKNOWN" end
    for _,hero in ipairs(A.Catalog:Heroes(specID)) do
        if hero.id==heroTree then
            self.character.heroChoices=self.character.heroChoices or {}
            self.character.heroChoices[tostring(specID)]=heroTree
            return true
        end
    end
    return nil,"HERO_UNKNOWN"
end
function S:Save(name, code, scene, target, specID)
    name, target = trim(name), trim(target)
    if name == "" or #name > 160 then return nil, "BAD_NAME" end
    if type(code) ~= "string" or #code > 16384 then return nil, "BAD_CODE" end
    if #self.builds >= 1000 then return nil, "CAPACITY" end
    local bytes=#code+#name+#target
    for _,v in ipairs(self.builds) do if type(v)=="table" then bytes=bytes+#(v.code or "")+#(v.name or "")+#(v.target or "") end end
    if bytes>16*1024*1024 then return nil,"CAPACITY" end
    self.db.nextID = self.db.nextID + 1
    local b = {id=self.db.nextID, name=name, code=code, scene=scene == "raid" and "raid" or "mythic",
        target=target:sub(1,240), specID=specID, updated=time(), source="user"}
    self.builds[#self.builds+1] = b
    return b
end
function S:Find(id)
    for i, b in ipairs(self.builds) do if type(b)=="table" and b.id==id then return b,i end end
end
function S:OrderLess(a,b)
    local ao,bo=tonumber(a.sortOrder) or math.huge,tonumber(b.sortOrder) or math.huge
    if ao~=bo then return ao<bo end
    -- Preserve the catalog's existing order until the first manual move.
    return tostring(a.id)<tostring(b.id)
end
function S:Move(id,targetID,after)
    local build,target=self:Find(id),self:Find(targetID)
    if not build or not target or build.specID~=target.specID then return nil,"BAD_CODE" end
    if id==targetID then return true end
    local ordered={}
    for _,b in ipairs(self.builds) do
        if type(b)=="table" and b.specID==build.specID and type(b.name)=="string" and type(b.code)=="string" then
            ordered[#ordered+1]=b
        end
    end
    table.sort(ordered,function(a,b)return self:OrderLess(a,b)end)
    for i,b in ipairs(ordered) do if b.id==id then table.remove(ordered,i);break end end
    for i,b in ipairs(ordered) do
        if b.id==targetID then table.insert(ordered,i+(after and 1 or 0),build);break end
    end
    for i,b in ipairs(ordered) do b.sortOrder=i end
    return true
end
function S:Delete(id)
    local b,i = self:Find(id)
    if b then self.undo = table.remove(self.builds,i); if A.Reminders then A.Reminders:RefreshSettings() end; return true end
end
function S:SetRemindersEnabled(enabled)
    self.db.remindersEnabled=enabled==true
    if A.Reminders then A.Reminders:RefreshSettings() end
    return true
end
function S:SetContexts(id,contexts,enabled)
    local b=self:Find(id)
    if not b or type(contexts)~="table" then return nil,"BAD_CODE" end
    local selected,count={},0
    for key,value in pairs(contexts) do
        if value==true then
            if type(key)~="string" or not A.Catalog.scenarios[key] then return nil,"REMINDER_CHANGED" end
            count=count+1;if count>32 then return nil,"CAPACITY" end
            selected[key]=true
        end
    end
    b.contexts=selected;b.remind=enabled==true and count>0;b.updated=time()
    if A.Reminders then A.Reminders:RefreshSettings() end
    return true
end
function S:Undo()
    if self.undo and #self.builds < 1000 then
        self.builds[#self.builds+1] = self.undo; self.undo=nil; return true
    end
end
function S:Update(id,name,code,scene,target,specID)
    local b=self:Find(id); if not b then return nil,"BAD_CODE" end
    name=trim(name); if name=="" or #name>160 then return nil,"BAD_NAME" end
    if type(code)~="string" or #code>16384 or b.specID~=specID then return nil,"BAD_CODE" end
    b.name,b.code,b.scene,b.target,b.updated=name,code,scene,trim(target):sub(1,240),time()
    return b
end
function S:Query(specID, scene, source, query, out)
    for i=#out,1,-1 do out[i]=nil end
    if source == "builtin" then return out end
    query=trim(query):lower()
    for _,b in ipairs(self.builds) do
        if type(b)=="table" and b.specID==specID and type(b.name)=="string" and type(b.code)=="string" then
            local name=b.name:lower()
            local target=type(b.target)=="string" and b.target:lower() or ""
            local match=query=="" or name:find(query,1,true) or target:find(query,1,true)
            -- A query searches all scenarios of the current spec; navigation applies when empty.
            if match and (query~="" or scene=="mine" or scene==b.scene) then out[#out+1]=b end
        end
    end
    table.sort(out,function(a,b)
        local an,bn=a.name:lower(),b.name:lower()
        local ae,be=query~="" and an==query,query~="" and bn==query
        if ae~=be then return ae end
        local ap,bp=query~="" and an:sub(1,#query)==query,query~="" and bn:sub(1,#query)==query
        if ap~=bp then return ap end
        if a.sortOrder or b.sortOrder then return self:OrderLess(a,b) end
        if (a.updated or 0)~=(b.updated or 0) then return (a.updated or 0)>(b.updated or 0) end
        return tostring(a.id)>tostring(b.id)
    end)
    return out
end
