local _,A=...
local M={}
A.Motion=M
function M:Stop()
    if self.frame and self.anchor then
        self.frame:ClearAllPoints();self.frame:SetPoint(unpack(self.anchor));self.frame:SetAlpha(1)
    end
    if self.driver then self.driver:SetScript("OnUpdate",nil); self.driver:Hide() end
    self.frame=nil; self.done=nil;self.anchor=nil;self.slide=nil
end
function M:Presence(frame,shown,done)
    if A.Store.db.reducedMotion or InCombatLockdown() then
        self:Stop(); frame:SetAlpha(1); if done then done() end; return
    end
    if self.frame~=frame or self.slide then
        self:Stop()
        local p,relative,rp,x,y=frame:GetPoint(1)
        self.anchor={p,relative,rp,x,y}; self.phase=shown and 0 or 1
    end
    self.frame,self.done,self.direction=frame,done,shown and 1 or -1
    if not self.driver then self.driver=CreateFrame("Frame") end
    self.driver:Show()
    self.driver:SetScript("OnUpdate",function(_,elapsed)
        local f=M.frame; if not f then M:Stop(); return end
        M.phase=math.max(0,math.min(1,M.phase+elapsed*M.direction/.42))
        local q=M.phase; local eased=q*(2-q); local alpha=math.min(1,q*.42/.10); alpha=alpha*(2-alpha)
        local a=M.anchor
        f:ClearAllPoints(); f:SetPoint(a[1],a[2],a[3],a[4]+16*(1-eased),a[5]); f:SetAlpha(alpha)
        if (M.direction==1 and q==1) or (M.direction==-1 and q==0) then
            local finish=M.done
            f:ClearAllPoints(); f:SetPoint(unpack(a)); f:SetAlpha(1)
            M:Stop(); if finish then finish() end
        end
    end)
end
function M:Finish(frame)
    if self.frame==frame and self.anchor then frame:ClearAllPoints(); frame:SetPoint(unpack(self.anchor)); frame:SetAlpha(1) end
    self:Stop()
end

-- One bounded driver shared with root presence; a new navigation cancels stale callbacks.
function M:Slide(frame,direction,leaving,done)
    self:Stop()
    if not frame or A.Store.db.reducedMotion or InCombatLockdown() or not frame:IsShown() then
        if done then done() end;return
    end
    self.anchor={frame:GetPoint(1)};self.frame=frame;self.done=done;self.slide=true
    self.phase=0
    local duration=leaving and .10 or .18
    local distance=(direction or 1)*(leaving and -8 or 12)
    if not self.driver then self.driver=CreateFrame("Frame")end
    if not leaving then frame:SetAlpha(.4)end
    self.driver:Show()
    self.driver:SetScript("OnUpdate",function(_,elapsed)
        local f=M.frame;if not f then M:Stop();return end
        if not f:IsShown() or InCombatLockdown() then M:Stop();return end
        M.phase=math.min(1,M.phase+elapsed/duration)
        local q=M.phase;local eased=1-(1-q)^3;local a=M.anchor
        f:ClearAllPoints();f:SetPoint(a[1],a[2],a[3],a[4]+distance*(leaving and eased or 1-eased),a[5])
        f:SetAlpha(leaving and 1-eased or .4+.6*eased)
        if q==1 then local finish=M.done;M:Stop();if finish then finish()end end
    end)
end

-- Lychee's original squash / lift / settle poses, on a separate bounded driver.
local brandPoses={
    {.168,1.075,.925,0,.42,0,.70,1,.42,0,.75,1},
    {.504,.960,1.045,7,.16,.6,.25,1,.16,.6,.25,1},
    {.840,1.035,.965,0,.30,0,.60,1,.42,0,.60,1},
    {1.092,.990,1.012,1,.16,.7,.30,1,.16,.7,.30,1},
    {1.386,1,1,0,.20,.7,.30,1,.20,.7,.30,1},
}
local function brandEase(u,x1,y1,x2,y2)
    if u<=0 then return 0 elseif u>=1 then return 1 end
    local low,high,t=0,1,u
    for i=1,16 do t=(low+high)*.5;local v=1-t
        if 3*v*v*t*x1+3*v*t*t*x2+t*t*t<u then low=t else high=t end
    end
    local v=1-t;return 3*v*v*t*y1+3*v*t*t*y2+t*t*t
end
function M:StopBrand(region)
    local job=self.brand;if region and job and job.region~=region then return end
    if self.brandDriver then self.brandDriver:SetScript("OnUpdate",nil);self.brandDriver:Hide()end
    if not job or InCombatLockdown()then return end
    job.region:SetSize(job.size,job.size);job.region:ClearAllPoints();job.region:SetPoint(unpack(job.anchor));self.brand=nil
end
function M:Brand(region,size)
    if InCombatLockdown() or A.Store.db.reducedMotion or not region:IsShown()then self:StopBrand(region);return end
    if self.brand and self.brand.region==region and self.brandDriver and self.brandDriver:IsShown()then return end
    self:StopBrand()
    local job={region=region,size=size,anchor={region:GetPoint(1)},elapsed=0};self.brand=job
    if not self.brandDriver then self.brandDriver=CreateFrame("Frame")end
    self.brandDriver:Show();self.brandDriver:SetScript("OnUpdate",function(_,elapsed)
        if InCombatLockdown() or A.Store.db.reducedMotion or not region:IsShown()then M:StopBrand();return end
        job.elapsed=job.elapsed+elapsed;if job.elapsed>=1.386 then M:StopBrand();return end
        local at,sx,sy,offset=0,1,1,0
        for _,pose in ipairs(brandPoses)do
            if job.elapsed<=pose[1]then
                local t=(job.elapsed-at)/(pose[1]-at)
                local scale=brandEase(t,pose[5],pose[6],pose[7],pose[8]);local move=brandEase(t,pose[9],pose[10],pose[11],pose[12])
                local x,y=sx+(pose[2]-sx)*scale,sy+(pose[3]-sy)*scale
                region:SetSize(size*x,size*y)
                local a=job.anchor;region:ClearAllPoints();region:SetPoint(a[1],a[2],a[3],a[4],a[5]+size/128*(39*(y-1)+offset+(pose[4]-offset)*move))
                return
            end
            at,sx,sy,offset=pose[1],pose[2],pose[3],pose[4]
        end
    end)
end
