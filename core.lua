-- RaidWhiteboard - core.lua
-- Copyright (C) 2026 Lukas Koschine
-- SPDX-License-Identifier: LGPL-3.0-or-later

RWB = RWB or {}
local L = LibStub("AceLocale-3.0"):GetLocale("RWB")

RWB.PREFIX = "RWB"
RWB.VERSION = "1.2.0"
RWB.strokes = {}
RWB.texts = {}
RWB.boardOpen = false
RWB.presentation = false
RWB.syncEnabled = true
RWB.canDraw = false
RWB.myDrawActive = false
-- true = locally hidden. The addon starts hidden after login.
RWB.myMinimized = true
RWB.activeTool = "PEN"
RWB.activeColor = { r = 1, g = 0.15, b = 0.15, a = 1 }
RWB.activeColorId = 1
RWB.activeThickness = 4
RWB._idCounter = 0
RWB.undoStack = {}
RWB.redoStack = {}
RWB.hasReceivedSyncResponse = false

local addonName = L["RWB_PRINT"]
local addonVersion = "1.2.0"

local defaults = {
    templates = {},
    lastColor = nil,
    lastColorId = 1,
    lastThickness = 4,
    minimapAngle = 200,
    boardPoint = "CENTER", boardRelativePoint = "CENTER", boardX = -120, boardY = 0,
    toolbarPoint = "CENTER", toolbarRelativePoint = "CENTER", toolbarX = 300, toolbarY = 0,
    syncEnabledV2 = true,
    backgroundMode = "transparent",
}

function RWB:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffRaidWhiteboard|r: " .. tostring(message))
end

function RWB:IsInRaidGroup() return GetNumRaidMembers() > 0 end
function RWB:IsInPartyGroup() return GetNumPartyMembers() > 0 end
function RWB:IsInGroup() return self:IsInRaidGroup() or self:IsInPartyGroup() end

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

function RWB:ShouldShowBoard()
    if not self:IsInGroup() then
        return not self.myMinimized
    end

    -- Lead/assist may always control their own local visibility.
    if self.canDraw then
        return not self.myMinimized
    end

    -- Normal group members only see the board through Presentation.
    return self.presentation
end

function RWB:RefreshVisibility()
    local visible = self:ShouldShowBoard()
    local board = self:GetBoard()

    if visible then
        board:Show()
        board:Raise()
        if self.RefreshToolbarState then self:RefreshToolbarState() end
    else
        board:Hide()
        if self.myDrawActive then self:SetMyDrawActive(false) end
        if self.toolbarFrame then self.toolbarFrame:Hide() end
    end

    if self.UpdateMinimizeButton then self:UpdateMinimizeButton() end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
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
    if RWB.RefreshVisibility then RWB:RefreshVisibility() end
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
                if not RWB.hasReceivedSyncResponse and RWB:IsInGroup() and RWB.RequestSync then
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
        -- New switch version: default ON, independent of older test settings.
        if RWB.db.syncEnabledV2 == nil then
            RWB.db.syncEnabledV2 = true
        end
        RWB.syncEnabled = RWB.db.syncEnabledV2 ~= false
        RWB.backgroundMode = RWB.db.backgroundMode or "transparent"
        if RWB.backgroundMode ~= "transparent" and RWB.backgroundMode ~= "dark" and RWB.backgroundMode ~= "light" then
            RWB.backgroundMode = "transparent"
            RWB.db.backgroundMode = "transparent"
        end
        -- Always start locally hidden after login/reload.
        RWB.myMinimized = true
        RWB.presentation = false
        RWB.boardOpen = false

        if RWB.db.lastColor then RWB.activeColor = RWB.db.lastColor end
        RWB.activeColorId = RWB.db.lastColorId or 1
        RWB.activeThickness = RWB.db.lastThickness or 4

        RefreshUi()
        RWB:Print(addonName .. " v" .. addonVersion)

    elseif event == "PARTY_LEADER_CHANGED"
        or event == "RAID_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED" then

        local isNowInGroup = RWB:IsInGroup()

        if not wasInGroup and isNowInGroup then
            -- A normal group member must discard private solo content before
            -- accepting the group's presentation/snapshot.
            RWB:UpdateDrawPermission()
            if not RWB.canDraw then
                if RWB.ClearCanvas then RWB:ClearCanvas(false) end
                RWB.myMinimized = false
                if RWB.GetBoard then RWB:GetBoard():Hide() end
                if RWB.toolbarFrame then RWB.toolbarFrame:Hide() end
            end
            ScheduleSync()

        elseif wasInGroup and not isNowInGroup then
            -- Leaving a group starts a new private/solo presentation.
            RWB.presentation = false
            RWB.boardOpen = false
            RWB.myMinimized = true
            if RWB.GetBoard then RWB:GetBoard():Hide() end
            if RWB.toolbarFrame then RWB.toolbarFrame:Hide() end
        end

        wasInGroup = isNowInGroup

        RWB:UpdateDrawPermission()
        RefreshUi()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Login/reload: never show the addon automatically.
        RWB.myMinimized = true
        RWB.presentation = false
        RWB.boardOpen = false
        RWB:UpdateDrawPermission()
        RefreshUi()

        wasInGroup = RWB:IsInGroup()
        if RWB.RegisterComm then RWB:RegisterComm() end
        ScheduleSync()
    else
        RefreshUi()
    end
end)
