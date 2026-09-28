local A={}
time=function()return 100 end
C_SpecializationInfo={GetSpecialization=function()return 1 end}
for _,name in ipairs({"Storage","Catalog"}) do
    assert(loadfile("addon/LycheeTalent/"..name..".lua"))("LycheeTalent",A)
end
A.Store:Init()
local s=A.Store
local builds={}
for i=1,15 do builds[i]=assert(s:Save("Build "..i,"code-"..i,"mythic","",71)) end
local other=assert(s:Save("Other spec","other","mythic","",72))
local out={}
local function query()
    A.Catalog:Query(71,"mine","user","",nil,nil,out)
    return out
end
query()
local original={};for i,b in ipairs(out)do original[i]=b.id end
assert(s:Move(original[1],original[4],true),"move after a target")
query()
assert(out[4].id==original[1] and out[1].id==original[2],"move down preserves intervening order")
assert(s:Move(original[1],original[2],false),"move before a target")
query();for i,b in ipairs(out)do assert(b.id==original[i],"move up restores original order")end
assert(not s:Move(original[1],other.id,true),"cross-spec drop is rejected")
assert(not s:Move(original[1],999,true),"deleted target is rejected")
assert(not s:Move(999,original[1],true),"deleted source is rejected")
assert(not other.sortOrder,"other specialization remains untouched")
local stamp=out[1].updated
assert(s:Move(original[1],original[1],false),"dropping on itself is a no-op")
assert(out[1].updated==stamp,"sorting does not change content timestamps")
s:Init();query()
for i,b in ipairs(out)do assert(b.id==original[i],"saved order survives init")end
s:Update(original[5],"Renamed","new-code","raid","",71);query()
assert(out[5].id==original[5],"editing does not reorder")
local added=assert(s:Save("New","new","mythic","",71));query()
assert(out[#out]==added,"newly saved/imported builds append after custom order")
s:Delete(original[3]);query()
assert(out[3].id==original[4],"deleting keeps remaining order")
s.readonly=true
assert(not s:Move(original[1],original[4],true),"future schema is read-only")
print("PASS build ordering: up/down, stable IDs, persistence, edits, append, deletion, spec and schema guards")
