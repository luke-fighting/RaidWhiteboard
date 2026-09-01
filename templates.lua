-- RaidWhiteboard - templates.lua
-- SPDX-License-Identifier: LGPL-3.0-or-later
local L = LibStub("AceLocale-3.0"):GetLocale("RWB")
function RWB:CountObjects(tableValue)
    local count = 0
    for _ in pairs(tableValue or {}) do count = count + 1 end
    return count
end

function RWB:SaveTemplate(name)
    if not name or name:trim() == "" then
        self:Print("Bitte einen Namen angeben: /rwb save <Name>")
        return
    end
    local strokes, texts = {}, {}
    for id, data in pairs(self.strokes) do strokes[id] = data end
    for id, data in pairs(self.texts) do texts[id] = data end
    self.db.templates[name] = {strokes=strokes,texts=texts,savedAt=date("%Y-%m-%d %H:%M")}
    self:Print("Vorlage '"..name.."' gespeichert.")
end

function RWB:LoadTemplate(name, broadcast)
    local template = self.db.templates[name]
    if not template then self:Print("Vorlage nicht gefunden: "..tostring(name));return end
    self:ClearCanvas(false)
    for id,data in pairs(template.strokes or {}) do self:RenderStroke(id,data) end
    for id,data in pairs(template.texts or {}) do self:RenderText(id,data) end
    if not self.boardOpen then self:OpenBoard(broadcast) end
    if broadcast then
        for id,data in pairs(template.strokes or {}) do self:BroadcastStroke(id,data) end
        for id,data in pairs(template.texts or {}) do self:BroadcastText(id,data) end
    end
end

function RWB:ListTemplates()
    local names = {}
    for name in pairs(self.db.templates) do table.insert(names,name) end
    table.sort(names)
    if #names == 0 then self:Print("Keine Vorlagen gespeichert.") else self:Print("Vorlagen: "..table.concat(names,", ")) end
end
