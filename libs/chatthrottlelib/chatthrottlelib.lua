-- ChatThrottleLib-compatible FIFO sender for WoW WotLK 3.3.5a.
-- Uses the WotLK global SendAddonMessage API, never C_ChatInfo.
if ChatThrottleLib then return end

ChatThrottleLib = {queue = {}, avail = 4000, MAX_CPS = 800, BURST = 4000, MSG_OVERHEAD = 40}
local CTL = ChatThrottleLib
local frame = CreateFrame("Frame")
frame:Hide()

frame:SetScript("OnUpdate", function(self, elapsed)
    CTL.avail = math.min(CTL.avail + CTL.MAX_CPS * elapsed, CTL.BURST)
    while #CTL.queue > 0 and CTL.avail > 0 do
        local item = CTL.queue[1]
        local cost = #item.text + CTL.MSG_OVERHEAD
        if cost > CTL.avail and #CTL.queue > 1 then break end
        table.remove(CTL.queue, 1)
        CTL.avail = CTL.avail - cost
        if item.target then
            SendAddonMessage(item.prefix,item.text,item.channel,item.target)
        else
            SendAddonMessage(item.prefix,item.text,item.channel)
        end
    end
    if #CTL.queue == 0 then self:Hide() end
end)

function CTL:SendAddonMessage(_, prefix, text, channel, target)
    table.insert(self.queue,{prefix=prefix,text=text,channel=channel,target=target})
    frame:Show()
end
