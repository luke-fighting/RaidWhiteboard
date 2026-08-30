-- RaidWhiteboard - minimap.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later

local ICON_LOCKED = "Interface\\Icons\\INV_Misc_Key_12"
local ICON_READY = "Interface\\Icons\\INV_Misc_Map_01"
local ICON_ACTIVE = "Interface\\Icons\\INV_Misc_Book_09"
local button

local function Place(btn,angle)
    local radius = 80
    local a = math.rad(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*radius,math.sin(a)*radius)
end

function RWB:UpdateMinimapButton()
    if not button then
        button = CreateFrame("Button","RaidWhiteboardMinimapButton",Minimap)
        button:SetSize(31,31)
        button:SetFrameStrata("HIGH")
        button:SetFrameLevel(Minimap:GetFrameLevel()+10)
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        local icon = button:CreateTexture(nil,"BACKGROUND")
        icon:SetSize(20,20)
        icon:SetPoint("CENTER",0,1)
        button.icon = icon
        local border = button:CreateTexture(nil,"OVERLAY")
        border:SetSize(53,53)
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetPoint("TOPLEFT",0,0)
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        button:SetScript("OnClick",function()
            if not RWB.canDraw then
                RWB:Print("Whiteboard-Steuerung nur für Raidleiter/Assistenten.")
            elseif RWB.boardOpen then
                RWB:CloseBoard(true)
            else
                RWB:OpenBoard(true)
            end
        end)
        button:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_LEFT")
            GameTooltip:AddLine("Raid Whiteboard")
            if not RWB.canDraw then
                GameTooltip:AddLine("Gesperrt: kein Raidleiter/Assistent",.7,.7,.7)
            elseif RWB.boardOpen then
                GameTooltip:AddLine("Klicken zum Ausschalten",1,1,1)
            else
                GameTooltip:AddLine("Klicken zum Einschalten",1,1,1)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave",function() GameTooltip:Hide() end)
        button:SetScript("OnDragStart",function(self)
            self:SetScript("OnUpdate",function(self)
                local mx,my = Minimap:GetCenter()
                local x,y = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                local angle = math.deg(math.atan2(y/scale-my,x/scale-mx))
                Place(self,angle)
                RWB.db.minimapAngle = angle
            end)
        end)
        button:SetScript("OnDragStop",function(self) self:SetScript("OnUpdate",nil) end)
        Place(button,(RWB.db and RWB.db.minimapAngle) or 200)
    end
    if not self.canDraw then
        button.icon:SetTexture(ICON_LOCKED)
        button:SetAlpha(.65)
    elseif self.boardOpen then
        button.icon:SetTexture(ICON_ACTIVE)
        button:SetAlpha(1)
    else
        button.icon:SetTexture(ICON_READY)
        button:SetAlpha(1)
    end
    button:Show()
end
