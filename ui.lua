-- RaidWhiteboard - ui.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later

local L = LibStub("AceLocale-3.0"):GetLocale("RWB")

local toolbar
local toolButtons = {}
local colorButtons = {}
local thicknessButtons = {}

local tools = {
    {"PEN", L["BUTTON_PEN"]},
    {"TEXT", L["BUTTON_TEXT"]},
    {"ERASER", L["BUTTON_RUBBER"]},
}

local colors = {
    {1, 1, .15, .15},
    {2, .2, .6, 1},
    {3, .2, 1, .3},
    {4, 1, .85, .1},
    {5, 1, 1, 1},
    {6, .6, .2, .9},
}

local function SetTooltip(button, text)
    if not button or not text then return end
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateButton(parent, label, x, y, width, callback, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    SetTooltip(button, tooltip)
    return button
end

local function RefreshDrawButtonText()
    if not toolbar or not toolbar.drawButton then return end

    if RWB.myDrawActive then
        toolbar.drawButton:SetText(L["BUTTON_DEACTIVATE"])
    else
        toolbar.drawButton:SetText(L["BUTTON_ACTIVATE"])
    end
end

local function RefreshToolHighlights()
    for key, button in pairs(toolButtons) do
        if key == RWB.activeTool then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

local function RefreshColorHighlights()
    for id, button in pairs(colorButtons) do
        if id == RWB.activeColorId then
            button:SetBackdropBorderColor(0, 1, 1, 1)
        else
            button:SetBackdropBorderColor(.15, .15, .15, 1)
        end
    end
end

local function RefreshThicknessHighlights()
    for thickness, button in pairs(thicknessButtons) do
        if thickness == RWB.activeThickness then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

local function RefreshSwitches()
    if not toolbar then return end

    if toolbar.syncButton then
        toolbar.syncButton:SetText(
            RWB.syncEnabled and L["BUTTON_SYNC_ON"] or L["BUTTON_SYNC_OFF"]
        )
    end

    if toolbar.presentationButton then
        toolbar.presentationButton:SetText(
            RWB.presentation and L["BUTTON_PRESENTATION_ON"] or L["BUTTON_PRESENTATION_OFF"]
        )
        if RWB:IsInGroup() and RWB.canDraw then
            toolbar.presentationButton:Enable()
        else
            toolbar.presentationButton:Disable()
        end
    end
end

local function RefreshAllVisuals()
    RefreshDrawButtonText()
    RefreshToolHighlights()
    RefreshColorHighlights()
    RefreshThicknessHighlights()
    RefreshSwitches()
end

local function CreateToolbar()
    local frame = CreateFrame("Frame", "RaidWhiteboardToolbar", UIParent)

    frame:SetSize(220, 410)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)

    RWB:RestoreFramePosition(frame, "toolbar")

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {
            left = 11,
            right = 12,
            top = 12,
            bottom = 11,
        },
    })

    local dragBar = CreateFrame("Frame", nil, frame)
    dragBar:SetHeight(20)
    dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -8)
    dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -8)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")

    dragBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)

    dragBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        RWB:SaveFramePosition(frame, "toolbar")
        RWB:LinkBoardAndToolbar(frame)
    end)

    local title = dragBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", dragBar, "TOP", 0, -2)
    title:SetText(L["LABEL_MENU"])

    frame.drawButton = CreateButton(
        frame,
        L["BUTTON_ACTIVATE"],
        20, -36, 180,
        function()
            if not RWB.canDraw then return end

            RWB:SetMyDrawActive(not RWB.myDrawActive)
            RefreshDrawButtonText()
        end,
        L["TOOLTIP_DRAW"]
    )

    CreateButton(frame, L["BUTTON_UNDO"], 20, -62, 87, function()
        if RWB.canDraw then RWB:Undo() end
    end, L["TOOLTIP_UNDO"])

    CreateButton(frame, L["BUTTON_REDO"], 113, -62, 87, function()
        if RWB.canDraw then RWB:Redo() end
    end, L["TOOLTIP_REDO"])

    local toolLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toolLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -89)
    toolLabel:SetText(L["LABEL_TOOL"])

    for i, tool in ipairs(tools) do
        local button = CreateButton(
            frame,
            tool[2],
            20 + (i - 1) * 62,
            -102,
            58,
            function()
                if not RWB.canDraw then return end
                RWB.activeTool = tool[1]
                RefreshToolHighlights()
            end,
            L["TOOLTIP_" .. tool[1]]
        )

        toolButtons[tool[1]] = button
    end

    local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -128)
    colorLabel:SetText(L["LABEL_COLOR"])

    for i, color in ipairs(colors) do
        local row = math.floor((i - 1) / 3)
        local col = (i - 1) % 3

        local button = CreateFrame("Button", nil, frame)
        button:SetSize(24, 24)
        button:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            20 + col * 28,
            -144 - row * 28
        )

        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })

        button:SetBackdropColor(color[2], color[3], color[4], 1)
        button:SetBackdropBorderColor(.15, .15, .15, 1)

        local colorId = color[1]
        local red = color[2]
        local green = color[3]
        local blue = color[4]

        button:SetScript("OnClick", function()
            if not RWB.canDraw then return end

            RWB.activeColor = { r=red, g=green, b=blue, a=1 }
            RWB.activeColorId = colorId

            if RWB.db then
                RWB.db.lastColor = RWB.activeColor
                RWB.db.lastColorId = colorId
            end

            RefreshColorHighlights()
        end)

        colorButtons[colorId] = button
        SetTooltip(button, L["TOOLTIP_COLOR"])
    end

    local thicknessLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thicknessLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 120, -128)
    thicknessLabel:SetText(L["LABEL_THICKNESS"])

    local thicknesses = {2, 4, 8}

    for i, thickness in ipairs(thicknesses) do
        local button = CreateButton(
            frame,
            tostring(thickness),
            120,
            -144 - (i - 1) * 28,
            60,
            function()
                if not RWB.canDraw then return end

                RWB.activeThickness = thickness

                if RWB.db then
                    RWB.db.lastThickness = thickness
                end

                RefreshThicknessHighlights()
            end,
            L["TOOLTIP_THICKNESS"]
        )

        thicknessButtons[thickness] = button
    end

    CreateButton(
        frame,
        L["BUTTON_CLEAR"],
        20, -252, 180,
        function()
            if RWB.canDraw then RWB:ClearCanvas(true) end
        end,
        L["TOOLTIP_CLEAR"]
    )

    frame.syncButton = CreateButton(
        frame,
        L["BUTTON_SYNC_ON"],
        20, -278, 180,
        function()
            if not RWB.canDraw then return end

            RWB.syncEnabled = not RWB.syncEnabled
            if RWB.db then
                RWB.db.syncEnabledV2 = RWB.syncEnabled
            end

            -- Turning outgoing Sync on sends the current canvas as a snapshot.
            if RWB.syncEnabled and RWB.BroadcastCurrentCanvas and RWB:IsInGroup() then
                RWB:BroadcastCurrentCanvas()
            end

            RefreshSwitches()
        end,
        L["TOOLTIP_SYNC"]
    )

    frame.presentationButton = CreateButton(
        frame,
        L["BUTTON_PRESENTATION_OFF"],
        20, -304, 180,
        function()
            if not RWB.canDraw then return end

            RWB:SetPresentation(not RWB.presentation, true)
            RefreshSwitches()
        end,
        L["TOOLTIP_PRESENTATION"]
    )

    frame:Hide()

    -- The toolbar is always attached to the board. Never restore it as an
    -- independent frame after login; that was the source of the overlap.
    RWB:GetBoard()
    RWB:LinkBoardAndToolbar(frame)

    return frame
end

function RWB:RefreshToolbarState()
    local inGroup = self:IsInGroup()
    local hasMenuRights = (not inGroup) or self.canDraw
    local boardVisible = self:ShouldShowBoard()

    if not hasMenuRights or not boardVisible then
        if toolbar then toolbar:Hide() end
        return
    end

    if not toolbar then
        toolbar = CreateToolbar()
        self.toolbarFrame = toolbar
    end

    self:LinkBoardAndToolbar(toolbar)
    toolbar:Show()
    RefreshAllVisuals()
end

SLASH_RAIDWHITEBOARD1 = "/rwb"

SlashCmdList.RAIDWHITEBOARD = function()
    RWB:ToggleLocalBoard()
end
