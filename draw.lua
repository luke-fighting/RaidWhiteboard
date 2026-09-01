-- RaidWhiteboard - draw.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later
local L = LibStub("AceLocale-3.0"):GetLocale("RWB")
local BOARD_NAME = "RaidWhiteboardBoard"
local LINE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BOARD_WIDTH, BOARD_HEIGHT = 800, 500
local MIN_SEGMENT_DISTANCE = 3

RWB.board = nil
RWB.canvas = nil
RWB.toolbarFrame = nil
RWB.miniFrame = nil
RWB.segmentPool = {}
RWB.activeSegments = {}
RWB._drawing = false
RWB._currentStrokeId = nil
RWB._currentPoints = nil
RWB._lastX = nil
RWB._lastY = nil

function RWB:LinkBoardAndToolbar(movedFrame)
    if not self.board or not self.toolbarFrame then return end
    if movedFrame == self.board then
        self.toolbarFrame:ClearAllPoints()
        self.toolbarFrame:SetPoint("TOPLEFT", self.board, "TOPRIGHT", 8, 0)
    elseif movedFrame == self.toolbarFrame then
        self.board:ClearAllPoints()
        self.board:SetPoint("TOPRIGHT", self.toolbarFrame, "TOPLEFT", -8, 0)
    end
end

local function CreateBoard()
    local board = CreateFrame("Frame", BOARD_NAME, UIParent)
    board:SetSize(BOARD_WIDTH + 20, BOARD_HEIGHT + 20)
    board:SetFrameStrata("HIGH")
    board:SetMovable(true)
    RWB:RestoreFramePosition(board, "board")
    board:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    board:SetBackdropColor(0, 0, 0, 0.6)

    local bar = CreateFrame("Frame", nil, board)
    bar:SetHeight(18)
    bar:SetPoint("TOPLEFT", board, "TOPLEFT")
    bar:SetPoint("TOPRIGHT", board, "TOPRIGHT")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() board:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        board:StopMovingOrSizing()
        RWB:SaveFramePosition(board, "board")
        RWB:LinkBoardAndToolbar(board)
    end)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", bar, "TOP", 0, -2)
    title:SetText("Raid Whiteboard")

    local minimize = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    minimize:SetSize(20, 16)
    minimize:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -1)
    minimize:SetText("_")
    minimize:SetScript("OnClick", function() RWB:SetMinimized(true) end)

    local canvas = CreateFrame("Frame", nil, board)
    canvas:SetSize(BOARD_WIDTH, BOARD_HEIGHT)
    canvas:SetPoint("CENTER", board, "CENTER", 0, -9)
    canvas:EnableMouse(false)
    canvas:SetScript("OnUpdate", function() RWB:OnCanvasUpdate() end)
    board.canvas = canvas
    board:Hide()
    return board, canvas
end

function RWB:GetBoard()
    if not self.board then self.board, self.canvas = CreateBoard() end
    return self.board
end
function RWB:GetCanvas()
    if not self.canvas then self:GetBoard() end
    return self.canvas
end

function RWB:GetMiniFrame()
    if self.miniFrame then return self.miniFrame end
    local frame = CreateFrame("Frame", "RaidWhiteboardMiniFrame", UIParent)
    frame:SetSize(140, 32)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    RWB:RestoreFramePosition(frame, "mini")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); RWB:SaveFramePosition(frame, "mini") end)
    frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=3,right=3,top=3,bottom=3}})
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetPoint("CENTER")
    button:SetText(L["BUTTON_MAXIMIZE"])
    button:SetScript("OnClick", function() RWB:SetMinimized(false) end)
    frame:Hide()
    self.miniFrame = frame
    return frame
end

function RWB:SetMinimized(value)
    self.myMinimized = value
    if value then
        self:GetBoard():Hide()
        if self.toolbarFrame then self.toolbarFrame:Hide() end
        self:GetMiniFrame():Show()
    else
        self:GetBoard():Show()
        if self.toolbarFrame and self.canDraw then self.toolbarFrame:Show() end
        self:GetMiniFrame():Hide()
    end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
end

function RWB:OpenBoard(broadcast)
    self.boardOpen = true
    if self.myMinimized then self:GetMiniFrame():Show() else self:GetBoard():Show() end
    if self.RefreshToolbarState then self:RefreshToolbarState() end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
    if broadcast and self.BroadcastBoardState then self:BroadcastBoardState(true) end
end

function RWB:CloseBoard(broadcast)
    self.boardOpen = false
    self:GetBoard():Hide()
    if self.toolbarFrame then self.toolbarFrame:Hide() end
    if self.miniFrame then self.miniFrame:Hide() end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
    if broadcast and self.BroadcastBoardState then self:BroadcastBoardState(false) end
end

function RWB:ToggleBoard()
    if not self.canDraw then
        self:Print("Whiteboard-Steuerung nur für Raidleiter/Assistenten.")
        return
    end
    if self.boardOpen then self:CloseBoard(true) else self:OpenBoard(true) end
end

function RWB:GetCursorCanvasPos()
    local canvas = self:GetCanvas()
    local scale = canvas:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()

    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local left = canvas:GetLeft() or 0
    local bottom = canvas:GetBottom() or 0

    local x = cursorX - left
    local y = cursorY - bottom

    -- Harte Begrenzung auf die tatsächliche Board-Innenfläche.
    -- Diese Begrenzung passiert vor jeder Distanz- und Segmentberechnung.
    x = math.max(0, math.min(BOARD_WIDTH, x))
    y = math.max(0, math.min(BOARD_HEIGHT, y))

    return x, y
end

function RWB:AcquireSegment()
    local segment = table.remove(self.segmentPool)
    if not segment then
        segment = self:GetCanvas():CreateTexture(nil, "OVERLAY")
        segment:SetTexture(LINE_TEXTURE)
    end
    segment:Show()
    return segment
end
function RWB:ReleaseSegment(segment)
    segment:Hide()
    segment:ClearAllPoints()
    table.insert(self.segmentPool, segment)
end
function RWB:DrawSegment(segment, x1, y1, x2, y2, width, color)
    local dx, dy = x2-x1, y2-y1
    segment:ClearAllPoints()
    segment:SetSize(math.max(math.sqrt(dx*dx+dy*dy), 0.001), width or 4)
    segment:SetPoint("LEFT", self:GetCanvas(), "BOTTOMLEFT", x1, y1)
    if segment.SetRotation then segment:SetRotation(math.atan2(dy, dx)) end
    segment:SetVertexColor(color.r, color.g, color.b, color.a or 1)
end

function RWB:RenderStroke(id, data)
    if self.activeSegments[id] then
        for _, segment in ipairs(self.activeSegments[id]) do self:ReleaseSegment(segment) end
    end
    self.activeSegments[id] = {}
    self.strokes[id] = data
    for i=1,#data.points-1 do
        local p1,p2 = data.points[i],data.points[i+1]
        local segment = self:AcquireSegment()
        self:DrawSegment(segment,p1.x,p1.y,p2.x,p2.y,data.thickness,data.color)
        table.insert(self.activeSegments[id],segment)
    end
end
function RWB:RenderRemoteStroke(id,data) self:RenderStroke(id,data) end
function RWB:RemoveStroke(id)
    if self.activeSegments[id] then
        for _, segment in ipairs(self.activeSegments[id]) do self:ReleaseSegment(segment) end
    end
    self.activeSegments[id] = nil
    self.strokes[id] = nil
end
function RWB:ClearCanvas(broadcast)
    for id in pairs(self.strokes) do self:RemoveStroke(id) end
    if self.ClearAllTexts then self:ClearAllTexts() end
    self:ClearHistory()
    if broadcast and self.BroadcastClear then self:BroadcastClear() end
end

function RWB:SetMyDrawActive(active)
    if active and (not self.canDraw or not self.boardOpen) then return end
    self.myDrawActive = active
    local canvas = self:GetCanvas()
    canvas:EnableMouse(active)
    if not active then
        canvas:SetScript("OnMouseDown", nil)
        canvas:SetScript("OnMouseUp", nil)
        return
    end
    canvas:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local x,y = RWB:GetCursorCanvasPos()
        if RWB.activeTool == "TEXT" then RWB:OpenTextInputAt(x,y); return end
        if RWB.activeTool == "ERASER" then RWB:EraseAtCursor(); return end
        RWB._drawing = true
        RWB._currentStrokeId = RWB:GenerateStrokeId()
        RWB._currentPoints = {{x=x,y=y}}
        RWB._lastX,RWB._lastY = x,y
        RWB.activeSegments[RWB._currentStrokeId] = {}
    end)
    canvas:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or not RWB._drawing then return end
        RWB._drawing = false
        if #RWB._currentPoints < 2 then return end
        local data = {points=RWB._currentPoints,color=RWB.activeColor,thickness=RWB.activeThickness,tool="PEN"}
        RWB.strokes[RWB._currentStrokeId] = data
        RWB:PushUndoAction({kind="stroke",id=RWB._currentStrokeId,data=data})
        if RWB.BroadcastStroke then RWB:BroadcastStroke(RWB._currentStrokeId,data) end
        RWB._currentStrokeId,RWB._currentPoints = nil,nil
    end)
end

function RWB:OnCanvasUpdate()
    if not(self.myDrawActive and self._drawing) then return end
    local x,y = self:GetCursorCanvasPos()
    local dx,dy = x-self._lastX,y-self._lastY
    if math.sqrt(dx*dx+dy*dy) < MIN_SEGMENT_DISTANCE then return end
    local segment = self:AcquireSegment()
    self:DrawSegment(segment,self._lastX,self._lastY,x,y,self.activeThickness,self.activeColor)
    table.insert(self.activeSegments[self._currentStrokeId],segment)
    table.insert(self._currentPoints,{x=x,y=y})
    self._lastX,self._lastY = x,y
end

function RWB:EraseAtCursor()
    local x,y = self:GetCursorCanvasPos()
    for id,data in pairs(self.strokes) do
        for _,point in ipairs(data.points) do
            if math.sqrt((point.x-x)^2+(point.y-y)^2) < 15 then
                self:RemoveStroke(id)
                if self.BroadcastRemoveStroke then self:BroadcastRemoveStroke(id) end
                return
            end
        end
    end
end
