-- RaidWhiteboard - ui.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later

local toolbar
local toolButtons = {}
local colorButtons = {}
local thicknessButtons = {}

local tools = {
    {"PEN", "Stift"},
    {"TEXT", "Text"},
    {"ERASER", "Radierer"},
}

local colors = {
    {1, 1, .15, .15},
    {2, .2, .6, 1},
    {3, .2, 1, .3},
    {4, 1, .85, .1},
    {5, 1, 1, 1},
    {6, .6, .2, .9},
}

local function CreateButton(parent, label, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    return button
end

local function RefreshDrawButtonText()
    if not toolbar or not toolbar.drawButton then
        return
    end

    if RWB.myDrawActive then
        toolbar.drawButton:SetText("Zeichnen deaktivieren")
    else
        toolbar.drawButton:SetText("Zeichnen aktivieren")
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

local function RefreshAllVisuals()
    RefreshDrawButtonText()
    RefreshToolHighlights()
    RefreshColorHighlights()
    RefreshThicknessHighlights()
end

local function CreateToolbar()
    local frame = CreateFrame("Frame", "RaidWhiteboardToolbar", UIParent)

    frame:SetSize(220, 350)
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
    title:SetText("Zeichenmenü")

    CreateButton(
        frame,
        "Board schließen",
        20,
        -36,
        180,
        function()
            RWB:CloseBoard(true)
        end
    )

    frame.drawButton = CreateButton(
        frame,
        "Zeichnen aktivieren",
        20,
        -62,
        180,
        function()
            RWB:SetMyDrawActive(not RWB.myDrawActive)
            RefreshDrawButtonText()
        end
    )

    CreateButton(
        frame,
        "Rückgängig",
        20,
        -88,
        87,
        function()
            RWB:Undo()
        end
    )

    CreateButton(
        frame,
        "Wiederherst.",
        113,
        -88,
        87,
        function()
            RWB:Redo()
        end
    )

    local toolLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toolLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -118)
    toolLabel:SetText("Werkzeug:")

    for i, tool in ipairs(tools) do
        local button = CreateButton(
            frame,
            tool[2],
            20 + (i - 1) * 62,
            -134,
            58,
            function()
                RWB.activeTool = tool[1]
                RefreshToolHighlights()
            end
        )

        toolButtons[tool[1]] = button
    end

    local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -170)
    colorLabel:SetText("Farbe:")

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
            -186 - row * 28
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
            RWB.activeColor = {
                r = red,
                g = green,
                b = blue,
                a = 1,
            }

            RWB.activeColorId = colorId

            if RWB.db then
                RWB.db.lastColor = RWB.activeColor
                RWB.db.lastColorId = colorId
            end

            RefreshColorHighlights()
        end)

        colorButtons[colorId] = button
    end

    local thicknessLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thicknessLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 120, -170)
    thicknessLabel:SetText("Dicke:")

    local thicknesses = {2, 4, 8}

    for i, thickness in ipairs(thicknesses) do
        local button = CreateButton(
            frame,
            tostring(thickness),
            120,
            -186 - (i - 1) * 28,
            60,
            function()
                RWB.activeThickness = thickness

                if RWB.db then
                    RWB.db.lastThickness = thickness
                end

                RefreshThicknessHighlights()
            end
        )

        thicknessButtons[thickness] = button
    end

    CreateButton(
        frame,
        "Alles löschen",
        20,
        -304,
        180,
        function()
            RWB:ClearCanvas(true)
        end
    )

    frame:Hide()

    return frame
end

function RWB:RefreshToolbarState()
    if not self.canDraw or not self.boardOpen or self.myMinimized then
        if toolbar then
            toolbar:Hide()
        end

        return
    end

    if not toolbar then
        toolbar = CreateToolbar()
        self.toolbarFrame = toolbar
        self:LinkBoardAndToolbar(toolbar)
    end

    toolbar:Show()
    RefreshAllVisuals()
end

SLASH_RAIDWHITEBOARD1 = "/rwb"

SlashCmdList.RAIDWHITEBOARD = function()
    RWB:ToggleBoard()
end