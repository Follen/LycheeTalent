local frame
CreateFrame=function()
 frame={}
 function frame:RegisterEvent()end
 function frame:SetScript()end
 return frame
end
SlashCmdList={}
local index,id,reads=1,65,0
C_SpecializationInfo={GetSpecialization=function()return index end,GetSpecializationInfo=function()
 reads=reads+1;return id,'name','description',123,'HEALER',1,84,'background',84,true
end}
local A={}
assert(loadfile('addon/LycheeTalent/Core.lua'))('LycheeTalent',A)
assert(A:GetSpec()==65)
for _,value in ipairs({0,-1,1.5,'1',false})do
 index=value;reads=0;assert(A:GetSpec()==nil and reads==0,'invalid specialization index reached the native detail API')
end
index=nil;assert(A:GetSpec()==nil)
index=1
for _,value in ipairs({0,-1,65.5,'65',false})do
 id=value;assert(A:GetSpec()==nil,'unready specialization ID was treated as valid')
end
id=nil;assert(A:GetSpec()==nil)
id=65;assert(select('#',A:GetSpec())==10 and A:GetSpec()==65)
local _,name,description,icon,role,stat,points,background,preview,unlocked=A:GetSpec()
assert(name=='name' and description=='description' and icon==123 and role=='HEALER' and stat==1 and points==84
 and background=='background' and preview==84 and unlocked,'metadata return contract changed')
print('PASS core specialization boundary: unready indices/IDs rejected; native name/icon/metadata contract retained')
