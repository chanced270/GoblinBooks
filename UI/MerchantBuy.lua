-- Shift-click a vendor item: instead of the small "how many?" box, a GoblinBooks confirmation to buy a
-- full stack (or as many as you can afford / the vendor has), with the total price. The amount can be
-- changed before buying. Gold-priced items only: items bought with currencies or tokens keep the
-- Blizzard behavior. Purchases go through BuyMerchantItem, so the ledger records them as usual.
--
-- Hooks MerchantItemButton_OnModifiedClick (runs after Blizzard's handler; nothing of Blizzard's is
-- replaced) and never in combat.
local _, ns = ...
local UI, W, U = ns.UI, ns.Widgets, ns.Util
local T = W.Theme

local dialog

local function MerchantInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" and info.name then
            return info.name, info.texture, info.price, info.stackCount or 1, info.numAvailable, info.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local ok, name, tex, price, stack, avail, _, _, ext = pcall(GetMerchantItemInfo, index)
        if ok and name then return name, tex, price, stack or 1, avail, ext end
    end
end

--- The item's full stack size (what "max stack" means), and how many one purchase may take.
local function StackLimits(index)
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    local itemStack
    if itemID then
        local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if fn then
            local ok, _, _, _, _, _, _, _, maxStack = pcall(fn, itemID)
            if ok then itemStack = maxStack end
        end
    end
    local perBuy = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)
    return itemID, itemStack or perBuy or 1, perBuy or itemStack or 1
end

--- Largest quantity worth offering: a full stack, capped by gold, vendor stock and the per-purchase cap,
--- rounded down to the vendor's bundle size. Returns qty, reason it was capped (or nil).
local function MaxQuantity(d)
    local want, reason = d.itemStack, nil
    if d.perBuy and d.perBuy < want then want = d.perBuy end
    local unit = d.price / d.bundle
    if unit > 0 then
        local afford = math.floor(GetMoney() / unit)
        if afford < want then want, reason = afford, "all you can afford" end
    end
    if d.available and d.available >= 0 then
        local stock = d.available * d.bundle
        if stock < want then want, reason = stock, "all the vendor has" end
    end
    want = math.floor(want / d.bundle) * d.bundle
    return math.max(0, want), reason
end

local function Create()
    local f = CreateFrame("Frame", "GoblinBooksMerchantBuy", UIParent, "BackdropTemplate")
    f:SetSize(300, 150)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop(W.FLAT)
    W.Backdrop(f, T.bg, { 1, 1, 1, 0.14 })
    tinsert(UISpecialFrames, "GoblinBooksMerchantBuy") -- Escape closes it

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOPLEFT", 14, -14)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.name = W.Text(f, "heading")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
    f.name:SetPoint("RIGHT", -12, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.sub = W.Text(f, "mutedSm")
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", -12, 0)
    f.sub:SetJustifyH("LEFT")

    local ql = W.Text(f, "body", "Quantity")
    ql:SetPoint("TOPLEFT", 14, -66)
    f.qty = W.EditBox(f, 70, true)
    f.qty:SetMaxLetters(5)
    f.qty:SetPoint("LEFT", ql, "RIGHT", 10, 0)
    f.qty:HookScript("OnTextChanged", function() f:Update() end)
    f.qty:SetScript("OnEnterPressed", function() f:Buy() end)
    f.qty:SetScript("OnEscapePressed", function() f:Hide() end)
    f.maxBtn = W.Button(f, "Max", 46, function()
        f.qty:SetText(tostring((MaxQuantity(f.d))))
    end)
    f.maxBtn:SetHeight(22)
    f.maxBtn:SetPoint("LEFT", f.qty, "RIGHT", 6, 0)
    f.total = W.Text(f, "accent")
    f.total:SetPoint("LEFT", f.maxBtn, "RIGHT", 10, 0)
    f.total:SetPoint("RIGHT", -12, 0)
    f.total:SetJustifyH("RIGHT")

    f.buy = W.Button(f, "Buy", 130, function() f:Buy() end, true)
    f.buy:SetPoint("BOTTOMRIGHT", -12, 12)
    f.cancel = W.Button(f, "Cancel", 80, function() f:Hide() end)
    f.cancel:SetPoint("RIGHT", f.buy, "LEFT", -6, 0)

    function f:Quantity()
        return math.max(0, math.floor(tonumber(self.qty:GetText()) or 0))
    end

    function f:Update()
        local d = self.d
        if not d then return end
        local q = self:Quantity()
        local cost = d.price * q / d.bundle
        local ok = q > 0 and q % d.bundle == 0 and cost <= GetMoney() and (not d.perBuy or q <= d.perBuy)
        self.total:SetText(q > 0 and U.FormatMoney(math.floor(cost + 0.5)) or "")
        self.buy:SetText(q > 0 and ("Buy %d"):format(q) or "Buy")
        self.buy:SetEnabled(ok)
        if q % d.bundle ~= 0 then
            self.total:SetText(("|cffff6060sold in %ds|r"):format(d.bundle))
        elseif cost > GetMoney() then
            self.total:SetText("|cffff6060not enough gold|r")
        end
    end

    function f:Buy()
        local d, q = self.d, self:Quantity()
        if not d or not self.buy:IsEnabled() then return end
        -- The vendor list may have changed (another page, closed): only buy the same item.
        if not MerchantFrame or not MerchantFrame:IsShown() or (GetMerchantItemID and GetMerchantItemID(d.index) ~= d.itemID) then
            ns:Print("the vendor window changed; shift-click the item again")
            self:Hide()
            return
        end
        BuyMerchantItem(d.index, q)
        self:Hide()
    end

    f:SetScript("OnHide", function(self) self.d = nil end)
    ns:On("MERCHANT_CLOSED", function() f:Hide() end)
    f:Hide()
    return f
end

local function Open(button, index)
    local name, tex, price, bundle, available, extended = MerchantInfo(index)
    if not name or extended or not price or price <= 0 then return false end
    local itemID, itemStack, perBuy = StackLimits(index)
    dialog = dialog or Create()
    local d = { index = index, itemID = itemID, price = price, bundle = math.max(1, bundle or 1),
        itemStack = math.max(itemStack or 1, bundle or 1), perBuy = perBuy, available = available }
    dialog.d = d
    dialog.icon:SetTexture(tex)
    dialog.name:SetText(name)
    local qty, reason = MaxQuantity(d)
    local per = price / d.bundle
    dialog.sub:SetText(("%s each  ·  full stack %d%s"):format(U.FormatMoney(math.floor(per + 0.5)), d.itemStack,
        reason and ("  ·  capped to " .. reason) or ""))
    dialog.qty:SetText(tostring(qty))
    dialog:ClearAllPoints()
    dialog:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    dialog:Show()
    dialog:Raise()
    dialog.qty:SetFocus()
    dialog.qty:HighlightText()
    dialog:Update()
    return true
end

local function OnModifiedClick(button, mouse)
    if not ns.db or not ns.db.settings.merchantStackBuy then return end
    if InCombatLockdown() or mouse ~= "LeftButton" or not IsShiftKeyDown() then return end
    if not MerchantFrame or MerchantFrame.selectedTab ~= 1 then return end -- not the buyback tab
    -- Shift-click with the chat box open links the item in chat: leave that alone.
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
    local index = button and button.GetID and button:GetID()
    if not index or index <= 0 then return end
    if Open(button, index) and StackSplitFrame and StackSplitFrame:IsShown() then
        StackSplitFrame:Hide() -- ours replaces Blizzard's "how many?" box
    end
end

if MerchantItemButton_OnModifiedClick then
    hooksecurefunc("MerchantItemButton_OnModifiedClick", function(button, mouse)
        local ok, err = pcall(OnModifiedClick, button, mouse)
        if not ok and ns.db and ns.db.settings.debug then ns:Print("merchant buy: " .. tostring(err)) end
    end)
end
