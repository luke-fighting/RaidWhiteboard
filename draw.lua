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
RWB.segmentPool = {}
RWB.activeSegments = {}
RWB._drawing = false
RWB._currentStrokeId = nil
RWB._currentPoints = nil
RWB._lastX = nil
RWB._lastY = nil

function RWB:LinkBoardAndToolbar(movedFrame)
    if not self.board then return end

    local toolbar = self.toolbarFrame
    if not toolbar then return end

    if movedFrame == self.board then
        toolbar:ClearAllPoints()
        toolbar:SetPoint("TOPLEFT", self.board, "TOPRIGHT", 8, 0)
    elseif movedFrame == toolbar then
        self.board:ClearAllPoints()
        self.board:SetPoint("TOPRIGHT", toolbar, "TOPLEFT", -8, 0)
    end
end

local function CreateBoard()
    local board = CreateFrame("Frame", BOARD_NAME, UIParent)
    board:SetSize(BOARD_WIDTH + 20, BOARD_HEIGHT + 20)
    board:SetFrameStrata("HIGH")
    board:SetMovable(true)

    RWB:RestoreFramePosition(board, "board")

    board:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    board:SetBackdropColor(0, 0, 0, 0.6)

    local bar = CreateFrame("Frame", nil, board)
    bar:SetHeight(18)
    bar:SetPoint("TOPLEFT", board, "TOPLEFT")
    bar:SetPoint("TOPRIGHT", board, "TOPRIGHT")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")

    bar:SetScript("OnDragStart", function()
        board:StartMoving()
    end)

    bar:SetScript("OnDragStop", function()
        board:StopMovingOrSizing()
        RWB:SaveFramePosition(board, "board")
        RWB:LinkBoardAndToolbar(board)
    end)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", bar, "TOP", 0, -2)
    title:SetText(L["LABEL_RAID_WHITEBOARD"])

    local minimize = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    minimize:SetSize(20, 16)
    minimize:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -1)
    minimize:SetText("_")
    minimize:SetScript("OnClick", function()
        if RWB.canDraw then
            RWB:SetMinimized(true)
        end
    end)

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
    if not self.board then
        self.board, self.canvas = CreateBoard()
    end
    return self.board
end

function RWB:GetCanvas()
    if not self.canvas then self:GetBoard() end
    return self.canvas
end

function RWB:SetMinimized(value)
    if not self.canDraw then
        return
    end

    self.myMinimized = value and true or false
    self:RefreshVisibility()
end

function RWB:ToggleLocalBoard()
    -- Only solo players and lead/assist may actively change local visibility.
    if not self.canDraw then
        return
    end

    self:SetMinimized(not self.myMinimized)
end

-- Presentation is the raid/party-wide visibility state.
-- The sender's own local visibility is deliberately not changed.
function RWB:SetPresentation(enabled, broadcast)
    if broadcast and not self.canDraw then
        return
    end

    self.presentation = enabled and true or false
    self.boardOpen = self.presentation

    -- Presentation ON opens the board on every client, including the lead
    -- and assistants. They can immediately minimize it locally afterwards.
    -- Presentation OFF only hides ordinary group members; lead/assist keep
    -- their local visibility unchanged.
    if self.presentation then
        self.myMinimized = false
    elseif self:IsInGroup() and not self.canDraw then
        self.myMinimized = true
    end

    self:RefreshVisibility()

    if broadcast and self.BroadcastBoardState then
        -- Presentation is visibility only. It never transfers canvas data.
        self:BroadcastBoardState(self.presentation)
    end
end

-- Compatibility wrappers used by templates and older code.
function RWB:OpenBoard(broadcast)
    if self:IsInGroup() then
        if self.canDraw then
            self:SetPresentation(true, broadcast)
        end
    else
        self:SetMinimized(false)
    end
end

function RWB:CloseBoard(broadcast)
    if self:IsInGroup() then
        if self.canDraw then
            self:SetPresentation(false, broadcast)
        end
    else
        self:SetMinimized(true)
    end
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
        for _, segment in ipairs(self.activeSegments[id]) do
            self:ReleaseSegment(segment)
        end
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

function RWB:RenderRemoteStroke(id,data)
    self:RenderStroke(id,data)
end

function RWB:RemoveStroke(id)
    if self.activeSegments[id] then
        for _, segment in ipairs(self.activeSegments[id]) do
            self:ReleaseSegment(segment)
        end
    end
    self.activeSegments[id] = nil
    self.strokes[id] = nil
end

function RWB:ClearCanvas(broadcast)
    for id in pairs(self.strokes) do
        self:RemoveStroke(id)
    end

    if self.ClearAllTexts then self:ClearAllTexts() end
    self:ClearHistory()

    if broadcast and self.BroadcastClear then
        self:BroadcastClear()
    end
end

function RWB:SetMyDrawActive(active)
    -- Drawing is a local capability. Solo/lead/assist have canDraw=true.
    -- A board that is locally hidden cannot remain in drawing mode.
    if active and (not self.canDraw or self.myMinimized or not self:ShouldShowBoard()) then
        return
    end

    self.myDrawActive = active
    local canvas = self:GetCanvas()
    canvas:EnableMouse(active)

    if not active then
        self._drawing = false
        self._currentStrokeId = nil
        self._currentPoints = nil
        canvas:SetScript("OnMouseDown", nil)
        canvas:SetScript("OnMouseUp", nil)
        return
    end

    canvas:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end

        local x,y = RWB:GetCursorCanvasPos()

        if RWB.activeTool == "TEXT" then
            RWB:OpenTextInputAt(x,y)
            return
        end

        if RWB.activeTool == "ERASER" then
            RWB:EraseAtCursor()
            return
        end

        RWB._drawing = true
        RWB._currentStrokeId = RWB:GenerateStrokeId()
        RWB._currentPoints = {{x=x,y=y}}
        RWB._lastX,RWB._lastY = x,y
        RWB.activeSegments[RWB._currentStrokeId] = {}
    end)

    canvas:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or not RWB._drawing then return end

        RWB._drawing = false

        if #RWB._currentPoints < 2 then
            RWB._currentStrokeId,RWB._currentPoints = nil,nil
            return
        end

        local data = {
            points=RWB._currentPoints,
            color=RWB.activeColor,
            thickness=RWB.activeThickness,
            tool="PEN"
        }

        RWB.strokes[RWB._currentStrokeId] = data
        RWB:PushUndoAction({
            kind="stroke",
            id=RWB._currentStrokeId,
            data=data
        })

        if RWB.BroadcastStroke then
            RWB:BroadcastStroke(RWB._currentStrokeId,data)
        end

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

    -- Text is checked first so the eraser can remove a text object directly.
    -- FontStrings are positioned by their bottom-left corner on the canvas.
    for id,data in pairs(self.texts) do
        local fontString = self.textFontStrings and self.textFontStrings[id]
        if fontString then
            local textX = data.x or 0
            local textY = data.y or 0
            local width = fontString:GetWidth() or 0
            local height = fontString:GetHeight() or (data.fontSize or 14)

            if x >= textX - 4 and x <= textX + width + 4
                and y >= textY - 4 and y <= textY + height + 4 then
                local oldData = data
                self:RemoveText(id)
                self:PushUndoAction({kind="text", id=id, data=oldData})
                if self.BroadcastRemoveText then
                    self:BroadcastRemoveText(id)
                end
                return
            end
        end
    end

    for id,data in pairs(self.strokes) do
        for _,point in ipairs(data.points) do
            if math.sqrt((point.x-x)^2+(point.y-y)^2) < 15 then
                self:RemoveStroke(id)
                if self.BroadcastRemoveStroke then
                    self:BroadcastRemoveStroke(id)
                end
                return
            end
        end
    end
end
