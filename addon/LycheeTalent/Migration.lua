local _, A = ...
local R = {schema="Lychee.Talent.Schema.V1:"}
A.Migration=R
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
function R:Layout(snapshot,native)
    local out=copy(snapshot)
    if out.version==2 then return out end
    if out.version~=1 then return nil,"BARS_INVALID" end
    out.version=2;out.macros={};out.bindings={}
    for slot,entry in ipairs(out.slots) do
        if entry.kind=="macro" then
            local index=entry.id;local current=native[index];local macro
            if type(entry.name)=="string" and type(entry.body)=="string" then
                -- Early snapshots already saved the source. The old index
                -- may now be empty or point at an unrelated player macro.
                local matching=current and current.name==entry.name and current.body==entry.body
                macro={name=entry.name,body=entry.body,icon=entry.icon or (matching and current.icon) or 134400}
            else macro=current end
            if macro then
                local ref=tostring(index)
                if out.macros[ref] and not A.Macros:Same(out.macros[ref],macro) then ref=ref..":"..slot end
                out.macros[ref]=copy(macro)
                if A.Macros:Same(macro,current) then out.bindings[ref]={index=index,native=copy(current)} end
                out.slots[slot]={kind="macro",id=ref}
            else
                -- Index-only snapshots cannot recover a deleted macro. Use
                -- the existing preserve-slot representation instead of
                -- inventing source text or clearing the player's action.
                out.slots[slot]={kind="unreadableMacro",id=slot}
            end
        end
    end
    return out
end
function R:Layouts(value,context)
    if type(value)~="table" then return value end
    if type(value.slots)=="table" and type(value.spec)=="number" and value.version then
        if value.version==1 and not context.native then context.native=A.Macros:Scan() end
        return self:Layout(value,context.native or {})
    end
    local out={}
    for k,v in pairs(value) do
        local migrated,why=self:Layouts(v,context)
        if why then return nil,why end
        out[k]=migrated
    end
    return out
end
function R:Run(account,character)
    account=type(account)=="table" and account or {}
    character=type(character)=="table" and character or {}
    for _,value in ipairs({account,character}) do
        if value.schema and value.schema~=self.schema then return nil,"SCHEMA" end
    end
    if not account.schema and type(account.version)=="number" and account.version>1 then return nil,"SCHEMA" end
    local db=account
    if not account.schema then
        db=copy(account);db.version=nil
        db.builds=type(db.builds)=="table" and db.builds or {}
        db.nextID=tonumber(db.nextID) or 0
        for _,build in ipairs(db.builds) do
            if type(build)=="table" and type(build.id)=="number" then db.nextID=math.max(db.nextID,build.id) end
        end
        db.schema=self.schema
    end
    local char=character
    if not character.schema then
        local why;char,why=self:Layouts(character,{})
        if not char then return nil,why end
        char.actionBars=char.actionBars or {version=1,specs={}}
        local root=char.actionBars
        if root.version~=1 or type(root.specs)~="table" then return nil,"SCHEMA" end
        local function state(spec)
            root.specs[spec]=root.specs[spec] or {profiles={}}
            return root.specs[spec]
        end
        for _,build in ipairs(db.builds) do if build.specID then state(build.specID) end end
        if char.applied and char.applied.spec then
            local target=state(char.applied.spec)
            target.applied=target.applied or char.applied
        end
        for _,target in pairs(root.specs) do
            target.modes=target.modes or {}
            for id,shared in pairs(char.modes or {}) do
                if target.modes[id]==nil then target.modes[id]=shared end
            end
        end
        char.modes=nil;char.applied=nil
        char.schema=self.schema
    end
    return db,char
end
