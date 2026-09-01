-- RaidWhiteboard - sync.lua
-- WotLK 3.3.5a: uses global SendAddonMessage/RegisterAddonMessagePrefix.
-- SPDX-License-Identifier: LGPL-3.0-or-later

local PREFIX = RWB.PREFIX
local CHUNK_SIZE = 180
local incoming = {}

local function SendRaw(message)
    local channel
    if RWB:IsInRaidGroup() then channel = "RAID"
    elseif RWB:IsInPartyGroup() then channel = "PARTY"
    else return end
    if #PREFIX + #message > 254 then
        RWB:Print("Sync-Nachricht zu lang; Übertragung verworfen.")
        return
    end
    if SendAddonMessage then
        SendAddonMessage(PREFIX,message,channel)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX,message,channel)
    end
end

function RWB:RegisterComm()
    if self.commFrame then return end
    if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent",function(_,_,prefix,message,_,sender)
        if prefix == PREFIX and sender ~= UnitName("player") then RWB:OnComm(message) end
    end)
    self.commFrame = frame
end

local function SerializeStroke(data)
    local points = {}
    for _,p in ipairs(data.points) do table.insert(points,math.floor(p.x+.5)..","..math.floor(p.y+.5)) end
    local c=data.color
    return c.r..","..c.g..","..c.b..","..(c.a or 1)..","..data.thickness.."|"..table.concat(points,";")
end

local function DeserializeStroke(payload)
    local header,rawPoints=payload:match("^(.-)|(.*)$")
    if not header then return nil end
    local r,g,b,a,width=header:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
    local points={}
    for entry in rawPoints:gmatch("[^;]+") do
        local x,y=entry:match("([^,]+),([^,]+)")
        x,y=tonumber(x),tonumber(y)
        if not x or not y then return nil end
        table.insert(points,{x=x,y=y})
    end
    if #points<2 then return nil end
    return {points=points,color={r=tonumber(r),g=tonumber(g),b=tonumber(b),a=tonumber(a)},thickness=tonumber(width),tool="PEN"}
end

function RWB:BroadcastBoardState(open) SendRaw("O:"..(open and"1"or"0")) end
function RWB:BroadcastStroke(id,data)
    local payload=SerializeStroke(data)
    SendRaw("S:"..id)
    for index=1,#payload,CHUNK_SIZE do SendRaw("C:"..id..":"..payload:sub(index,index+CHUNK_SIZE-1)) end
    SendRaw("E:"..id)
end
function RWB:BroadcastRemoveStroke(id) SendRaw("R:"..id) end
function RWB:BroadcastText(id,data)
    SendRaw("T:"..id..":"..data.x..","..data.y..","..data.color.r..","..data.color.g..","..data.color.b.."|"..data.text)
end
function RWB:BroadcastRemoveText(id) SendRaw("TR:"..id) end
function RWB:BroadcastClear() SendRaw("X") end
function RWB:RequestSync() SendRaw("Q") end

function RWB:OnComm(message)
    if message=="X" then self:ClearCanvas(false);return end
    if message=="Q" then
        if self.canDraw then
            self:BroadcastBoardState(self.boardOpen)
            if self.boardOpen then
                for id,data in pairs(self.strokes) do self:BroadcastStroke(id,data) end
                for id,data in pairs(self.texts) do self:BroadcastText(id,data) end
            end
        end
        return
    end
    local kind,rest=message:match("^(%u+):(.*)$")
	if kind == "O" then
		-- Die erste O-Nachricht bestätigt unseren Sync-Request.
		self.hasReceivedSyncResponse = true

		if rest == "1" then
			self:OpenBoard(false)
		elseif rest == "0" then
			self:CloseBoard(false)
		end
    elseif kind=="S" then
        incoming[rest]={}
    elseif kind=="C" then
        local id,chunk=rest:match("^(.-):(.*)$")
        if incoming[id] then table.insert(incoming[id],chunk) end
    elseif kind=="E" then
        local chunks=incoming[rest]
        if chunks then
            local data=DeserializeStroke(table.concat(chunks))
            if data then self:RenderRemoteStroke(rest,data) end
            incoming[rest]=nil
        end
    elseif kind=="R" then
        self:RemoveStroke(rest)
    elseif kind=="T" then
        local id,x,y,r,g,b,text=rest:match("^(.-):([^,]+),([^,]+),([^,]+),([^,]+),([^|]+)|(.+)$")
        if id then self:RenderRemoteText(id,{x=tonumber(x),y=tonumber(y),text=text,color={r=tonumber(r),g=tonumber(g),b=tonumber(b)},fontSize=14}) end
    elseif kind=="TR" then
        self:RemoveText(rest)
    end
end
