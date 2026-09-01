-- RaidWhiteboard - text.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later
local L = LibStub("AceLocale-3.0"):GetLocale("RWB")
RWB.textFontStrings = {}
local inputBox

local function CreateInputBox()
    local box = CreateFrame("EditBox", "RaidWhiteboardTextInput", RWB:GetCanvas())
    box:SetSize(220, 26)
    box:SetAutoFocus(true)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 3, 3)
    box:SetFrameStrata("DIALOG")
    box:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=8,edgeSize=8,insets={left=3,right=3,top=3,bottom=3}})
    box:SetBackdropColor(0,0,0,0.9)
    box:SetScript("OnEnterPressed", function(self)
        local value = self:GetText()
        self:Hide()
        self:ClearFocus()
        RWB:GetCanvas():EnableMouse(RWB.myDrawActive)
        if value and value:trim() ~= "" then
            RWB:CreateTextObject(self.posX,self.posY,value)
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:Hide()
        self:ClearFocus()
        RWB:GetCanvas():EnableMouse(RWB.myDrawActive)
    end)
    box:Hide()
    return box
end

function RWB:OpenTextInputAt(x,y)
    local canvas = self:GetCanvas()
    canvas:EnableMouse(false)
    if not inputBox then inputBox = CreateInputBox() end
    inputBox:ClearAllPoints()
    inputBox:SetPoint("BOTTOMLEFT",canvas,"BOTTOMLEFT",x,y)
    inputBox.posX,inputBox.posY = x,y
    inputBox:SetTextColor(self.activeColor.r,self.activeColor.g,self.activeColor.b,1)
    inputBox:SetText("")
    inputBox:Show()
    inputBox:SetFocus()
end

function RWB:CreateTextObject(x,y,text,id,color,fontSize)
    id = id or self:GenerateStrokeId()
    local data = {x=x,y=y,text=text,color=color or self.activeColor,fontSize=fontSize or 14}
    self:RenderText(id,data)
    self:PushUndoAction({kind="text",id=id,data=data})
    if self.BroadcastText then self:BroadcastText(id,data) end
end

function RWB:RenderText(id,data)
    if self.textFontStrings[id] then self.textFontStrings[id]:Hide() end
    local fontString = self:GetCanvas():CreateFontString(nil,"OVERLAY")
    fontString:SetFont("Fonts\\FRIZQT__.TTF",data.fontSize,"OUTLINE")
    fontString:SetPoint("BOTTOMLEFT",self:GetCanvas(),"BOTTOMLEFT",data.x,data.y)
    fontString:SetText(data.text)
    fontString:SetTextColor(data.color.r,data.color.g,data.color.b,1)
    self.textFontStrings[id] = fontString
    self.texts[id] = data
end
function RWB:RenderRemoteText(id,data) self:RenderText(id,data) end
function RWB:RemoveText(id)
    if self.textFontStrings[id] then self.textFontStrings[id]:Hide() end
    self.textFontStrings[id] = nil
    self.texts[id] = nil
end
function RWB:ClearAllTexts()
    for id in pairs(self.texts) do self:RemoveText(id) end
end
