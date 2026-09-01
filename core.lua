-- RaidWhiteboard - core.lua
-- Copyright (C) 2026 Lukas Koschine
-- SPDX-License-Identifier: LGPL-3.0-or-later

RWB = RWB or {}
local L = LibStub("AceLocale-3.0"):GetLocale("RWB")

RWB.PREFIX = "RWB"
RWB.VERSION = "1.1.0"
RWB.strokes = {}
RWB.texts = {}
RWB.boardOpen = false
RWB.canDraw = false
RWB.myDrawActive = false
RWB.myMinimized = false
RWB.activeTool = "PEN"
RWB.activeColor = { r = 1, g = 0.15, b = 0.15, a = 1 }
RWB.activeColorId = 1
RWB.activeThickness = 4
RWB._idCounter = 0
RWB.undoStack = {}
RWB.redoStack = {}
RWB.hasReceivedSyncResponse = false

local addonName = L["RWB_PRINT"]
local addonVersion = "1.1.0"

local defaults = {
    templates = {},
    lastColor = nil,
    lastColorId = 1,
    lastThickness = 4,
    minimapAngle = 200,
    boardPoint = "CENTER", boardRelativePoint = "CENTER", boardX = -120, boardY = 0,
    toolbarPoint = "CENTER", toolbarRelativePoint = "CENTER", toolbarX = 300, toolbarY = 0,
    miniPoint = "CENTER", miniRelativePoint = "CENTER", miniX = -120, miniY = 300,
}

function RWB:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidWhiteboard|r: " .. tostring(message))
end

function RWB:IsInRaidGroup() return GetNumRaidMembers() > 0 end
function RWB:IsInPartyGroup() return GetNumPartyMembers() > 0 end

function RWB:UpdateDrawPermission()
    if self:IsInRaidGroup() then
        self.canDraw = IsRaidLeader() or IsRaidOfficer()
    elseif self:IsInPartyGroup() then
        self.canDraw = IsPartyLeader()
    else
        self.canDraw = true
    end
    return self.canDraw
end

function RWB:GenerateStrokeId()
    if type(self._idCounter) ~= "number" then self._idCounter = 0 end
    self._idCounter = self._idCounter + 1
    return (UnitName("player") or "player") .. "-" .. self._idCounter
end

function RWB:SaveFramePosition(frame, prefix)
    if not self.db or not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    self.db[prefix .. "Point"] = point
    self.db[prefix .. "RelativePoint"] = relativePoint
    self.db[prefix .. "X"] = x
    self.db[prefix .. "Y"] = y
end

function RWB:RestoreFramePosition(frame, prefix)
    if not self.db then return end
    frame:ClearAllPoints()
    frame:SetPoint(self.db[prefix .. "Point"], UIParent, self.db[prefix .. "RelativePoint"], self.db[prefix .. "X"], self.db[prefix .. "Y"])
end

function RWB:PushUndoAction(action)
    table.insert(self.undoStack, action)
    if #self.undoStack > 50 then table.remove(self.undoStack, 1) end
    self.redoStack = {}
end

function RWB:Undo()
    if not self.canDraw then return end
    local action = table.remove(self.undoStack)
    if not action then return end
    if action.kind == "stroke" then
        self:RemoveStroke(action.id)
        if self.BroadcastRemoveStroke then self:BroadcastRemoveStroke(action.id) end
    elseif action.kind == "text" then
        self:RemoveText(action.id)
        if self.BroadcastRemoveText then self:BroadcastRemoveText(action.id) end
    end
    table.insert(self.redoStack, action)
end

function RWB:Redo()
    if not self.canDraw then return end
    local action = table.remove(self.redoStack)
    if not action then return end
    if action.kind == "stroke" then
        self:RenderStroke(action.id, action.data)
        if self.BroadcastStroke then self:BroadcastStroke(action.id, action.data) end
    elseif action.kind == "text" then
        self:RenderText(action.id, action.data)
        if self.BroadcastText then self:BroadcastText(action.id, action.data) end
    end
    table.insert(self.undoStack, action)
end

function RWB:ClearHistory()
    self.undoStack = {}
    self.redoStack = {}
end

local eventFrame = CreateFrame("Frame", "RaidWhiteboardEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

local function RefreshUi()
    RWB:UpdateDrawPermission()
    if RWB.UpdateMinimapButton then RWB:UpdateMinimapButton() end
    if RWB.RefreshToolbarState then RWB:RefreshToolbarState() end
end

local function ScheduleSync()
    RWB.hasReceivedSyncResponse = false
    for _, delay in ipairs({2, 5, 9}) do
        local timer = CreateFrame("Frame")
        local elapsed = 0
        timer:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                if not RWB.hasReceivedSyncResponse and (RWB:IsInRaidGroup() or RWB:IsInPartyGroup()) and RWB.RequestSync then
                    RWB:RequestSync()
                end
            end
        end)
    end
end

local wasInGroup = false

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        RaidWhiteboardDB = RaidWhiteboardDB or {}
        for key, value in pairs(defaults) do
            if RaidWhiteboardDB[key] == nil then RaidWhiteboardDB[key] = value end
        end
        RWB.db = RaidWhiteboardDB
        if RWB.db.lastColor then RWB.activeColor = RWB.db.lastColor end
        RWB.activeColorId = RWB.db.lastColorId or 1
        RWB.activeThickness = RWB.db.lastThickness or 4
        RefreshUi()
		RWB:Print(addonName .. " v" .. addonVersion)
	elseif event == "PARTY_LEADER_CHANGED"
		or event == "RAID_ROSTER_UPDATE"
		or event == "PARTY_MEMBERS_CHANGED" then

		local isNowInGroup = RWB:IsInRaidGroup() or RWB:IsInPartyGroup()

		if not wasInGroup and isNowInGroup then
			-- 1. Das alte Solo-Board nur auf diesem Client löschen.
			--    false verhindert einen X/CLEAR-Broadcast an den Raid.
			if RWB.ClearCanvas then
				RWB:ClearCanvas(false)
			end

			-- 2. Board sichtbar halten bzw. öffnen, ohne seinen Zustand
			--    an die Gruppe zu senden.
			if RWB.OpenBoard then
				RWB:OpenBoard(false)
			end

			-- 3. Den vollständigen Zustand beim Lead/Assist anfordern.
			--    Die Funktion sendet Q nach 2, 5 und 9 Sekunden, bis eine
			--    Antwort als empfangen markiert wurde.
			ScheduleSync()
		end

		wasInGroup = isNowInGroup

		local before = RWB.canDraw
		RWB:UpdateDrawPermission()

		if before ~= RWB.canDraw and RWB.RefreshToolbarState then
			RWB:RefreshToolbarState()
		end
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshUi()
		wasInGroup = RWB:IsInRaidGroup() or RWB:IsInPartyGroup()
        if RWB.RegisterComm then RWB:RegisterComm() end
        ScheduleSync()
    else
        RefreshUi()
    end
end)
