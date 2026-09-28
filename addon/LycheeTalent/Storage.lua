local _, A = ...
local S = {}
A.Store = S
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
function S:Init()
    if type(LycheeTalentDB) ~= "table" then LycheeTalentDB = {} end
    self.db = LycheeTalentDB
    if type(LycheeTalentCharacterDB) ~= "table" then LycheeTalentCharacterDB = {} end
    self.character=LycheeTalentCharacterDB
    self.readonly = type(self.db.version) == "number" and self.db.version > 1
    if self.readonly then self.builds = {}; return end
    self.db.version = 1
    self.db.builds = type(self.db.builds) == "table" and self.db.builds or {}
    self.db.nextID = tonumber(self.db.nextID) or 0
    self.builds = self.db.builds
    for _,b in ipairs(self.builds) do
        if type(b)=="table" and type(b.id)=="number" then self.db.nextID=math.max(self.db.nextID,b.id) end
    end
    if type(LycheeTalentCharacterDB) ~= "table" then LycheeTalentCharacterDB = {} end
    self.character = LycheeTalentCharacterDB
end
function S:Save(name, code, scene, target, specID)
    if self.readonly then return nil, "SCHEMA" end
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
    if self.readonly then return nil,"SCHEMA" end
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
    if self.readonly then return end
    local b,i = self:Find(id)
    if b then self.undo = table.remove(self.builds,i); if A.Reminders then A.Reminders:RefreshSettings() end; return true end
end
function S:SetRemindersEnabled(enabled)
    if self.readonly then return nil,"SCHEMA" end
    self.db.remindersEnabled=enabled==true
    if A.Reminders then A.Reminders:RefreshSettings() end
    return true
end
function S:SetContexts(id,contexts,enabled)
    if self.readonly then return nil,"SCHEMA" end
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
    if not self.readonly and self.undo and #self.builds < 1000 then
        self.builds[#self.builds+1] = self.undo; self.undo=nil; return true
    end
end
function S:Update(id,name,code,scene,target,specID)
    if self.readonly then return nil,"SCHEMA" end
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
