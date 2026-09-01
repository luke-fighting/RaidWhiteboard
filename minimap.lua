-- RaidWhiteboard - minimap.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later

local L = LibStub("AceLocale-3.0"):GetLocale("RWB")
local ICON_CLOSED = "Interface\\Icons\\INV_Misc_Map_01"
local ICON_OPEN = "Interface\\Icons\\INV_Misc_Book_09"
local ICON_LOCKED = "Interface\\Icons\\INV_Misc_Key_12"
local button

local function Place(btn, angle)
    local radius = 80
    local a = math.rad(angle)

    btn:ClearAllPoints()
    btn:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(a) * radius,
        math.sin(a) * radius
    )
end

function RWB:UpdateMinimapButton()
    if not button then
        button = CreateFrame("Button", "RaidWhiteboardMinimapButton", Minimap)
        button:SetSize(31,31)
        button:SetFrameStrata("HIGH")
        button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")

        local icon = button:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20,20)
        icon:SetPoint("CENTER", 0, 1)
        button.icon = icon

        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetSize(53,53)
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetPoint("TOPLEFT", 0, 0)

        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        button:SetScript("OnClick", function()
            if not RWB.canDraw then
                return
            end

            RWB:ToggleLocalBoard()
        end)

        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(L["LABEL_RAID_WHITEBOARD"])

            if not RWB.canDraw and RWB:IsInGroup() then
                GameTooltip:AddLine(L["TOOLTIP_LOCKED"], .7, .7, .7)
            elseif RWB:ShouldShowBoard() then
                GameTooltip:AddLine(L["TOOLTIP_DEACTIVATE"], 1, 1, 1)
            else
                GameTooltip:AddLine(L["TOOLTIP_ACTIVATE"], 1, 1, 1)
            end

            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        button:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function(self)
                local mx,my = Minimap:GetCenter()
                local x,y = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                local angle = math.deg(math.atan2(y / scale - my, x / scale - mx))

                Place(self, angle)

                if RWB.db then
                    RWB.db.minimapAngle = angle
                end
            end)
        end)

        button:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        Place(button, (RWB.db and RWB.db.minimapAngle) or 200)
    end

    local visible = self:ShouldShowBoard()

    if not self.canDraw and self:IsInGroup() then
        button.icon:SetTexture(ICON_LOCKED)
        button:SetAlpha(.65)
    elseif visible then
        button.icon:SetTexture(ICON_OPEN)
        button:SetAlpha(1)
    else
        button.icon:SetTexture(ICON_CLOSED)
        button:SetAlpha(1)
    end

    button:Show()
end
