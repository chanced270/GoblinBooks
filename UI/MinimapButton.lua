-- Minimap button: left-click toggles GoblinBooks, right-click opens settings, drag to move around the minimap.
-- No libraries; the angle is saved in settings.minimapAngle. Nothing here runs in Blizzard code paths
-- (hooks only fire after Blizzard's own handlers), so it can't taint combat UI.
local _, ns = ...
local UI = ns.UI

local button

local function UpdatePosition()
    local angle = math.rad(ns.db.settings.minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function Create()
    local b = CreateFrame("Button", "GoblinBooksMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\GoblinBooks\\Media\\mark")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns:OpenOptions() else UI:Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    b:SetScript("OnMouseDown", function() icon:SetSize(16, 16) end)
    b:SetScript("OnMouseUp", function() icon:SetSize(18, 18) end)
    b:SetScript("OnEnter", function(self)
        GoblinBooks_OnAddonCompartmentEnter(nil, self)
        GameTooltip:AddLine("Right-click for settings, drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function UI:UpdateMinimapButton()
    if not (Minimap and ns.db) then return end
    if ns.db.settings.minimapButton then
        button = button or Create()
        UpdatePosition()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns:Register("READY", function()
    UI:UpdateMinimapButton()
    -- Apply the "Show minimap button" option when the settings panel closes (no callbacks inside Blizzard's
    -- settings code; see Options.lua).
    if SettingsPanel and SettingsPanel.HookScript then
        SettingsPanel:HookScript("OnHide", function() UI:UpdateMinimapButton() end)
    end
end)
