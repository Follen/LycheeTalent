-- Persisted V2 references survive a new Lua session whose spec/macros are
-- temporarily unavailable. This is runtime readiness, not old-schema migration.
local runtime=assert(loadfile("tests/macro_runtime.lua"))()
local function run(replacement)
 local seed=runtime(true)
 seed.A.Store.character.schema="Lychee.Talent.Schema.V2:"
 seed.native[1]={name="Existing",icon=1,body="/say saved current macro"};seed.slots[1]={kind="macro",id=1}
 local snapshot=assert(seed.B:Capture(62));assert(seed.B:SeedDefault(62,snapshot,"fixture"));seed.activate("saved",true,snapshot)
 local savedRoot=seed.copy(seed.A.Store.character)
 local ref=snapshot.macros[snapshot.slots[1].id].nativeID
 local R=runtime(true);R.A.Store.character=savedRoot;R.spec=0
 R.native[1]=replacement and {name="Replacement",icon=2,body="/say unrelated"} or seed.copy(seed.native[1])
 R.slots[1]={kind="macro",id=1}
 local ready=false;local read=GetMacroInfo
 GetMacroInfo=function(index)if ready then return read(index)end end
 R.B:Init()
 assert(savedRoot.nativeMacros.records[ref].index==1,"unready Init erased an existing nativeID before macro data loaded")
 R.emit("UPDATE_MACROS");R.settle()
 assert(savedRoot.nativeMacros.records[ref].index==1,"unready macro event must not tombstone persisted references")
 R.spec=62;ready=true;R.emit("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");R.settle()
 local saved=assert(R.B:Get(62,nil,true))
 if not replacement then
  assert(saved.slots[1].kind=="macro" and saved.macros[saved.slots[1].id].nativeID==ref)
  assert(not saved.pendingMacros and not R.B:Spec(62).applied.partial)
  assert(savedRoot.nativeMacros.records[ref].index==1 and savedRoot.nativeMacros.nextID==1,"same macro keeps the same ID after readiness")
 else
  assert(savedRoot.nativeMacros.records[ref].index==nil and savedRoot.nativeMacros.nextID==2)
  assert(saved.pendingMacros[1].macro.nativeID==ref,"deleted macro retains pending backup")
  assert(R.native[1].name=="Replacement" and saved.macros[saved.slots[1].id].nativeID~=ref,"a reused number is never adopted")
 end
 assert(R.writes==0 and R.placements==0)
end
run(false);run(true)
print("PASS persisted V2 macro readiness: spec0/unreadable load preserves logical ID; readiness restores same reference; genuine deletion rejects replacement")
