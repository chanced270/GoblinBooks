-- Auction house companion panel: sellable bag items, live competitor listings, suggested price,
-- cost-basis profit preview, one-click posting, and the full price scan.
local _, ns = ...
local UI, W, U, P, S, CB = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.AHScan, ns.CostBasis
local T = W.Theme
local AH = C_AuctionHouse

local PANEL_W = 440          -- docked width (beside the Blizzard AH window)
local FULL_W, FULL_H = 980, 660 -- default full-window size
local MIN_W, MIN_H = 760, 520   -- smallest full window
local TINY = 0.001              -- scale for the invisible Blizzard window in full-window mode
-- AH cut rate measured from your sale mails (5% until the first sale is recorded).
local function Cut() return CB.CutRate(ns.db) end
local DURATIONS = { { key = 1, label = "12h" }, { key = 2, label = "24h" }, { key = 3, label = "48h" } }
local LISTING_ROWS = 4

local panel, toggle

local function GetInfo(itemID)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, name, _, _, _, _, _, _, maxStack, _, _, sellPrice = pcall(fn, itemID)
    if ok then return name, maxStack, sellPrice end
end

local function IsCommodity(loc, itemID)
    if AH.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
        local ok, status = pcall(AH.GetItemCommodityStatus, loc)
        if ok and status == Enum.ItemCommodityStatus.Commodity then return true end
        if ok and status == Enum.ItemCommodityStatus.Item then return false end
    end
    local _, maxStack = GetInfo(itemID)
    return (maxStack or 1) > 1
end

--- Link text without the hyperlink wrapper or brackets, keeping the quality color.
local function DisplayName(row)
    local text = row.link and row.link:gsub("|H.-|h(.-)|h", "%1"):gsub("%[(.-)%]", "%1") or GetInfo(row.itemID) or ("item:" .. row.itemID)
    return text
end

local function PlainName(row)
    return (GetInfo(row.itemID) or (row.link and row.link:match("%[(.-)%]")) or ""):lower()
end

-- Tooltip lines that mean an item can't go on the auction house.
local BOUND_LINES = {}
for _, name in ipairs({ "ITEM_SOULBOUND", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT",
                        "ITEM_BIND_TO_BNETACCOUNT", "ITEM_ACCOUNTBOUND_UNTIL_EQUIP" }) do
    local text = _G[name]
    if type(text) == "string" then BOUND_LINES[text] = true end
end

--- Soulbound or account bound? The slot's flag first, then the item itself, then its tooltip text
--- (in case the client's flags are wrong for some items).
local function IsBoundSlot(info, loc, bag, slot)
    if info.isBound then return true end
    if C_Item and C_Item.IsBound then
        local ok, bound = pcall(C_Item.IsBound, loc)
        if ok and bound then return true end
    end
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        for _, line in ipairs(ok and data and data.lines or {}) do
            if line.leftText and BOUND_LINES[line.leftText] then return true end
        end
    end
    return false
end

-- AH category of a bag item (top level, by label), from the game's AH categories. Cached per item.
local catTree, catOf = nil, {}
local OTHER_CAT = "Other"
local function CategoryOf(itemID)
    local c = catOf[itemID]
    if c then return c end
    catTree = catTree or S.CategoryTree()
    c = OTHER_CAT
    for _, cat in ipairs(catTree) do
        if S.ItemMatches(itemID, cat.filters) then c = cat.label break end
    end
    catOf[itemID] = c
    return c
end

local function IconFor(info)
    if info.iconFileID then return info.iconFileID end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, info.itemID)
        if ok then return icon end
    end
end

local function ScanBags()
    local rows, byKey = {}, {}
    if not (C_Container and ItemLocation and AH.IsSellItemValid) then return rows end
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local loc = info and info.itemID and ItemLocation:CreateFromBagAndSlot(bag, slot)
            if loc and not IsBoundSlot(info, loc, bag, slot) then
                local ok, valid = pcall(AH.IsSellItemValid, loc, false)
                if ok and valid then
                    local commodity = IsCommodity(loc, info.itemID)
                    local key = commodity and info.itemID or (info.hyperlink or info.itemID)
                    local r = byKey[key]
                    if not r then
                        r = { key = key, itemID = info.itemID, link = info.hyperlink, icon = IconFor(info),
                              count = 0, loc = loc, commodity = commodity, cat = CategoryOf(info.itemID) }
                        byKey[key] = r
                        rows[#rows + 1] = r
                    end
                    r.count = r.count + (info.stackCount or 1)
                end
            end
        end
    end
    return rows
end

--- Stack-wide (AH market after cut - vendor) for a bag row; nil without both prices.
local function BagVendorDiff(row)
    local m = P.Market(row.itemID)
    local _, _, sellPrice = GetInfo(row.itemID)
    if not m or not sellPrice or sellPrice <= 0 then return nil end
    return (math.floor(m * (1 - Cut()) + 0.5) - sellPrice) * row.count
end

local function ItemKeyFor(row)
    local fn = row.commodity and AH.MakeItemKey or AH.GetItemKeyFromItem
    if not fn then return nil end
    local ok, key = pcall(fn, row.commodity and row.itemID or row.loc)
    return ok and key or nil
end

local function AvgCost(itemID)
    if not ns.char then return nil end
    local q, v = CB.Holdings(ns.char, itemID)
    if q and q > 0 then return v / q end
end

---------------------------------------------------------------------------
-- Sell form
---------------------------------------------------------------------------
local function CreateSellForm(p)
    local f = W.Panel(p)
    f:SetHeight(300)

    f.name = W.Text(f, "heading", "Select an item to sell")
    f.name:SetPoint("TOPLEFT", 12, -12)
    f.name:SetPoint("RIGHT", -90, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.owned = W.Text(f, "mutedSm")
    f.owned:SetPoint("TOPRIGHT", -12, -14)

    f.market = W.Text(f, "body")
    f.market:SetPoint("TOPLEFT", 12, -34)
    f.cost = W.Text(f, "body")
    f.cost:SetPoint("TOPLEFT", 12, -52)

    -- Competitor listings; clicking one undercuts it.
    local lhead = W.Text(f, "label", "CURRENT LISTINGS")
    lhead:SetPoint("TOPLEFT", 12, -76)
    f.listingRows = {}
    for i = 1, LISTING_ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(17)
        b:SetPoint("TOPLEFT", 8, -90 - (i - 1) * 17)
        b:SetPoint("RIGHT", -8, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        W.SetColor(hl, T.hover)
        b.price = W.Text(b, "body")
        b.price:SetPoint("LEFT", 4, 0)
        b.qty = W.Text(b, "mutedSm")
        b.qty:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function(s)
            if s.listing then
                local undercut = s.listing.mine and 0 or ns.db.settings.undercut
                f.price:SetValue(math.max(1, s.listing.unit - undercut))
                f:Update()
            end
        end)
        f.listingRows[i] = b
    end
    f.noListings = W.Text(f, "muted", "")
    f.noListings:SetPoint("TOPLEFT", 12, -94)

    local plabel = W.Text(f, "label", "PRICE EACH")
    plabel:SetPoint("TOPLEFT", 12, -168)
    f.price = W.MoneyInput(f, function() f:Update() end)
    f.price:SetPoint("TOPLEFT", 12, -182)

    local qlabel = W.Text(f, "label", "QUANTITY")
    qlabel:SetPoint("TOPLEFT", 12, -214)
    f.qty = W.EditBox(f, 56, true)
    f.qty:SetMaxLetters(5)
    f.qty:SetPoint("TOPLEFT", 12, -228)
    f.qty:HookScript("OnTextChanged", function(_, user) if user then f:Update() end end)
    f.maxBtn = W.Button(f, "Max", 44, function()
        if f.row then f.qty:SetText(tostring(f.row.count)) f:Update() end
    end)
    f.maxBtn:SetPoint("LEFT", f.qty, "RIGHT", 6, 0)

    local dlabel = W.Text(f, "label", "DURATION")
    f.duration = W.Segmented(f, DURATIONS, function(key)
        ns.db.settings.postDuration = key
        f:Update()
    end, 46)
    f.duration:SetPoint("TOPRIGHT", -12, -227)
    dlabel:SetPoint("BOTTOMLEFT", f.duration, "TOPLEFT", 0, 4)

    f.summary = W.Text(f, "mutedSm")
    f.summary:SetPoint("TOPLEFT", 12, -258)
    f.summary:SetPoint("RIGHT", -12, 0)
    f.summary:SetJustifyH("LEFT")
    f.vendor = W.Text(f, "mutedSm")
    f.vendor:SetPoint("TOPLEFT", 12, -274)
    f.vendor:SetPoint("RIGHT", -12, 0)
    f.vendor:SetJustifyH("LEFT")

    function f:Values()
        local qty = tonumber(self.qty:GetText()) or 0
        if self.row then qty = math.min(qty, self.row.count) end
        return self.price:GetValue(), qty, self.duration.value or 2
    end

    --- Deposit you'll actually be charged, whether the WoW Forever minimum-deposit bug applies, and the
    --- client's own estimate.
    function f:Deposit(qty, dur)
        local row = self.row
        if not row or qty <= 0 then return 0, false, 0 end
        local ok, dep
        if row.commodity then
            ok, dep = pcall(AH.CalculateCommodityDeposit, row.itemID, dur, qty)
        else
            ok, dep = pcall(AH.CalculateItemDeposit, row.loc, dur, qty)
        end
        local estimate = ok and dep or 0
        local actual, bug = ns.AuctionHouse:EffectiveDeposit(estimate)
        return actual, bug, estimate
    end

    function f:SetRow(row)
        local changed = not self.row or not row or self.row.key ~= row.key
        self.row = row
        if changed and p.sellChart then p.sellChart:SetItem(row and row.itemID) end
        if changed then
            self.listings, self.priceSet = nil, false
            self.price:SetValue(0)
            self.qty:SetText(row and tostring(row.commodity and row.count or 1) or "")
            if row then
                local market = P.Market(row.itemID)
                if market then self.price:SetValue(market) end
                self.searching = S.Search(ItemKeyFor(row))
            end
        end
        self:Update()
    end

    function f:OnListings(listings)
        self.listings = listings
        if p.sellChart then p.sellChart:SetListings(listings) end
        self.searching = false
        if not self.priceSet then
            local first = listings[1]
            if first then
                local undercut = first.mine and 0 or ns.db.settings.undercut
                self.price:SetValue(math.max(1, first.unit - undercut))
            end
            self.priceSet = true
        end
        self:Update()
    end

    function f:Update()
        local row = self.row
        self.duration:SetValue(ns.db.settings.postDuration)
        for _, b in ipairs(self.listingRows) do b:Hide() end
        if not row then
            self.name:SetText("Select an item to sell")
            self.owned:SetText("")
            self.market:SetText("")
            self.cost:SetText("")
            self.summary:SetText("")
            self.vendor:SetText("")
            self.noListings:SetText("")
            p.postBtn:Disable()
            return
        end
        self.name:SetText(DisplayName(row))
        self.owned:SetText(("%d in bags"):format(row.count))

        local e = P.Get(row.itemID)
        local parts = {}
        if e then
            parts[1] = ("Lowest %s   |cff8c94a3seen %s|r"):format(U.FormatMoney(e.p), U.Ago(e.t))
        else
            parts[1] = "|cff8c94a3No price history yet|r"
        end
        -- Exact: your own results for this item across characters.
        local merged = CB.MergeFlips(ns:AllCharTables())[row.itemID]
        local rate, resolved, avg
        if merged then rate, resolved, avg = CB.SellThrough(merged) end
        if rate then
            parts[#parts + 1] = ("You: %.0f%% sold of %d%s"):format(rate * 100, resolved, avg and (", ~" .. U.Duration(avg)) or "")
        end
        -- Estimate: units leaving the AH (sales, expirations and cancellations).
        local est = U.PerDay(P.EstimatedDaily(e, 7))
        if est then parts[#parts + 1] = ("|cff8c94a3market est. %s|r"):format(est) end
        self.market:SetText(table.concat(parts, "   "))
        local avgCost = AvgCost(row.itemID)
        local _, _, sellPrice = GetInfo(row.itemID)
        local costText = avgCost and ("Your cost %s each"):format(U.FormatMoney(avgCost)) or "|cff8c94a3No recorded cost|r"
        if sellPrice and sellPrice > 0 then
            costText = costText .. ("   |cff8c94a3Vendor %s each|r"):format(U.FormatMoney(sellPrice))
        end
        self.cost:SetText(costText)

        local listings = self.listings or {}
        for i, b in ipairs(self.listingRows) do
            local l = listings[i]
            b.listing = l
            if l then
                b.price:SetText(U.FormatMoney(l.unit) .. (l.mine and "  |cffffc640(yours)|r" or ""))
                b.qty:SetText(("x%d"):format(l.qty))
                b:Show()
            end
        end
        if self.searching and not self.listings then
            self.noListings:SetText("Searching...")
        elseif #listings == 0 then
            self.noListings:SetText(self.listings and "No competition, set your own price" or "")
        else
            self.noListings:SetText("")
        end

        local price, qty, dur = self:Values()
        local deposit, depositBug, estimate = self:Deposit(qty, dur)
        local cutRate = Cut()
        local proceeds = price * qty * (1 - cutRate)
        local total = price * qty
        if qty > 0 and price > 0 then
            local ret = total - deposit
            self.summary:SetText(("|cffebedf2Total %s|r   Deposit %s%s   %sReturn %s|r"):format(
                U.FormatMoney(total), U.FormatMoney(deposit), depositBug and "|cffff9933*|r" or "",
                ret < 0 and "|cffff6060" or "|cffffc640", U.FormatMoney(ret)))
            -- On a sale the deposit is refunded, so what you actually keep is the total minus the AH cut.
            local parts = { ("If it sells you keep %s (%s cut)"):format(U.FormatGoldShort(proceeds), CB.CutLabel(cutRate)) }
            if avgCost then
                local profit = proceeds - avgCost * qty
                parts[#parts + 1] = (profit >= 0 and "|cff60ff60" or "|cffff6060") .. "Profit " .. U.FormatGoldShort(profit) .. "|r"
            end
            if sellPrice and sellPrice > 0 and P.IsJunk(row.itemID) then
                parts[#parts + 1] = ("|cffffc640Junk: vendor recommended (%s), it rarely sells on the AH|r"):format(
                    U.FormatGoldShort(sellPrice * qty))
            elseif sellPrice and sellPrice > 0 then
                local diff = proceeds - sellPrice * qty
                parts[#parts + 1] = diff >= 0 and ("|cff60ff60vs vendor AH +%s|r"):format(U.FormatGoldShort(diff))
                    or ("|cffffc640vs vendor: vendor +%s|r"):format(U.FormatGoldShort(-diff))
            elseif sellPrice == 0 then
                parts[#parts + 1] = "no vendor price"
            end
            if depositBug then
                parts[#parts + 1] = ("|cffff9933* 1s minimum (WoW Forever bug; game shows %s)|r"):format(U.FormatMoney(estimate))
            end
            self.vendor:SetText(table.concat(parts, "   "))
        else
            self.summary:SetText("")
            self.vendor:SetText("")
        end
        p.postBtn:SetEnabled(price > 0 and qty > 0)
        -- Warn before listing when the deposit is more than the whole listing is worth.
        local warnKey = (qty > 0 and price > 0 and deposit > total) and table.concat({ tostring(row.key), price, qty, dur }, "|") or nil
        self.depositWarn = warnKey and { key = warnKey, deposit = deposit, total = total } or nil
        if p.depositOK and p.depositOK ~= warnKey then p.depositOK = nil end -- price/qty/duration/item changed
        if not p.pendingConfirm then
            if not warnKey then
                p.postBtn:SetText("Post auction")
            elseif p.depositOK == warnKey then
                p.postBtn:SetText("|cffff6060Click again to post anyway (deposit is more than the price)|r")
            else
                p.postBtn:SetText("|cffff6060Post auction (deposit exceeds price)|r")
            end
        end
    end

    return f
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function SetStatus(text) if panel then panel.status:SetText(text or "") end end

local function Post()
    local f = panel.form
    local row = f.row
    if not row then return end
    local price, qty, dur = f:Values()
    if price <= 0 or qty <= 0 then return end
    local warn = f.depositWarn
    if warn and not panel.pendingConfirm and panel.depositOK ~= warn.key then
        panel.depositOK = warn.key
        SetStatus(("|cffff6060The deposit (%s) is more than the listing (%s). It's lost if the item doesn't sell. Click Post again to list anyway.|r"):format(
            U.FormatMoney(warn.deposit), U.FormatMoney(warn.total)))
        f:Update()
        return
    end
    panel.depositOK = nil
    -- Posting goes through the same server request limit as searches: hold background searches (Deals
    -- watcher, category scan) for a moment so the next post isn't stuck behind them.
    S.postHoldUntil = GetTime() + S.POST_HOLD
    local ok, err
    if panel.pendingConfirm then
        local c = panel.pendingConfirm
        panel.pendingConfirm = nil
        if c.commodity then
            ok, err = pcall(AH.ConfirmPostCommodity, c.loc, c.dur, c.qty, c.price)
        else
            ok, err = pcall(AH.ConfirmPostItem, c.loc, c.dur, c.qty, nil, c.price)
        end
    else
        panel.lastPost = { commodity = row.commodity, loc = row.loc, dur = dur, qty = qty, price = price }
        local _, _, estimate = f:Deposit(qty, dur)
        ns.AuctionHouse.nextPostEstimate = estimate -- lets the ledger check what was really charged
        if row.commodity then
            ok, err = pcall(AH.PostCommodity, row.loc, dur, qty, price)
        else
            ok, err = pcall(AH.PostItem, row.loc, dur, qty, nil, price)
        end
    end
    panel.postBtn:SetText("Post auction")
    if ok then
        SetStatus(("Posting %d x %s..."):format(qty, DisplayName(row)))
    else
        SetStatus("|cffff6060Post failed: " .. tostring(err) .. "|r")
    end
end

local bagsDirty = true
local function RefreshBags()
    if not panel or not panel:IsShown() then return end
    -- The bag list is only on the Sell page: checking every bag slot with the AH can wait until it's shown.
    if panel.page ~= "sell" then bagsDirty = true return end
    bagsDirty = false
    local rows = ScanBags()
    panel.list:SetData(panel.FilterRows(rows))
    local sel = panel.form.row
    local match
    if sel then
        for _, r in ipairs(rows) do if r.key == sel.key then match = r end end
    end
    panel.form:SetRow(match)
end

local function Create()
    local p = CreateFrame("Frame", "GoblinBooksAHPanel", UIParent, "BackdropTemplate")
    p:SetWidth(PANEL_W)
    if p.SetDontSavePosition then p:SetDontSavePosition(true) end -- resizing must not save a layout-cache position
    p:SetBackdrop(W.FLAT)
    W.Backdrop(p, T.bg, { 1, 1, 1, 0.10 })
    p:EnableMouse(true)

    local header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(40)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    W.SetColor(hbg, T.surface)
    local hline = W.Divider(header)
    hline:SetPoint("BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT")
    local title = header:CreateTexture(nil, "ARTWORK")
    title:SetTexture("Interface\\AddOns\\GoblinBooks\\Media\\mark")
    title:SetSize(28, 28)
    title:SetPoint("LEFT", 12, 0)
    local close = W.CloseButton(header, function()
        if ns.db.settings.ahReplace and AH.CloseAuctionHouse then
            pcall(AH.CloseAuctionHouse) -- the Blizzard window is hidden, so closing means leaving the AH
        else
            p:Hide()
        end
    end)
    close:SetPoint("RIGHT", -8, 0)
    p.scanBtn = W.Button(header, "Scan", 84, function()
        if S.catScanning then S.StopCategoryScan() return end -- click again to stop a category scan
        if S.scanning then return end -- the button shows the progress; nothing to do
        local mode = ns.db.settings.scanMode or "full"
        local ok, msg
        if mode == "full" then ok, msg = S.FullScan() else ok, msg = S.CategoryScan(mode) end
        if not ok then UI.ScanNotReady(msg, mode) end
    end, true)
    p.modeBtn = W.Button(header, "Expand", 64, function()
        ns.db.settings.ahReplace = not ns.db.settings.ahReplace
        UI:LayoutAHPanel()
    end)
    p.modeBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    p.modeBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        if ns.db.settings.ahReplace then
            GameTooltip:AddLine("Dock beside the Blizzard auction house")
        else
            GameTooltip:AddLine("Expand to a full window")
            GameTooltip:AddLine("Replaces the standard auction house window with a large, resizable GoblinBooks window.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    p.modeBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    p.scanMode = W.Dropdown(header, 22, function(key)
        ns.db.settings.scanMode = key
    end)
    p.scanMode.label:Hide()
    p.scanMode.arrow:ClearAllPoints()
    p.scanMode.arrow:SetPoint("CENTER", 0, -2)
    p.scanMode:SetOptions({
        { key = "full", label = "Full scan (every 15 min)" },
        { key = "crafting", label = "Categories: crafting markets" },
        { key = "all", label = "Categories: everything" },
    })
    p.scanMode:SetValue(ns.db.settings.scanMode or "full")
    p.scanMode:SetPoint("RIGHT", p.modeBtn, "LEFT", -6, 0)
    p.scanMode:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Scan type")
        GameTooltip:AddLine("Full scan: one snapshot of the whole auction house, once every 15 minutes.", 1, 1, 1, true)
        GameTooltip:AddLine("Category scan: searches category by category, saving prices as it goes, and you can stop it. Crafting markets (trade goods, consumables, recipes, gems, reagents, item enhancements): no cooldown. Everything: at most once every 5 minutes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.scanMode:HookScript("OnLeave", function() GameTooltip:Hide() end)
    p.scanBtn:SetPoint("RIGHT", p.scanMode, "LEFT", -2, 0)
    -- Scan progress lives on the button (percentage) and a thin bar under it, not in the shared status line.
    p.scanBar = CreateFrame("Frame", nil, header)
    p.scanBar:SetPoint("TOPLEFT", p.scanBtn, "BOTTOMLEFT", 0, -2)
    p.scanBar:SetPoint("TOPRIGHT", p.scanBtn, "BOTTOMRIGHT", 0, -2)
    p.scanBar:SetHeight(3)
    p.scanBar.bg = p.scanBar:CreateTexture(nil, "BACKGROUND")
    p.scanBar.bg:SetAllPoints()
    p.scanBar.bg:SetColorTexture(1, 1, 1, 0.08)
    p.scanBar.fill = p.scanBar:CreateTexture(nil, "ARTWORK")
    p.scanBar.fill:SetPoint("TOPLEFT")
    p.scanBar.fill:SetPoint("BOTTOMLEFT")
    W.SetColor(p.scanBar.fill, T.accent, 0.9)
    p.scanBar:Hide()
    p.scanBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        local mode = ns.db.settings.scanMode or "full"
        if mode == "full" then
            GameTooltip:AddLine("Full price scan")
            GameTooltip:AddLine("Reads every auction and records the lowest price per item. The server allows one every 15 minutes.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(mode == "all" and "Category scan: every category" or "Category scan: crafting markets")
            GameTooltip:AddLine(("Searches one category at a time and saves prices as it goes. %s Click again while it runs to stop (what it found is kept)."):format(
                mode == "all" and "At most one every 5 minutes." or "No cooldown."), 1, 1, 1, true)
        end
        GameTooltip:AddLine("Change the scan type with the arrow next to this button.", 0.55, 0.58, 0.64, true)
        local info = p.scanInfo
        if info then GameTooltip:AddLine(info, 1, 0.82, 0, true) end
        local ready, left = S.FullScanReady()
        if mode ~= "full" then ready, left = S.CategoryScanReady(mode) end
        if not ready and not S.scanning and not S.catScanning then
            GameTooltip:AddLine(("Available in %dm %ds"):format(math.floor(left / 60), left % 60), 1, 0.6, 0.2)
        end
        local last = ns.db.lastScanResult
        if last and not S.scanning and not S.catScanning then
            -- A full scan counts auctions; category searches only report units listed (stacks added up).
            local categories = last.kind == "categories"
            GameTooltip:AddLine(("Last %s %s: %s items, %s %s"):format(categories and "category scan" or "full scan",
                U.Ago(last.t), U.CommaNumber(last.items), U.CommaNumber(last.auctions),
                categories and "units listed" or "auctions"), 0.55, 0.58, 0.64, true)
        end
        GameTooltip:Show()
    end)
    p.scanBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    p.pageSeg = W.Segmented(header, {
        { key = "buy", label = "Buy" },
        { key = "sell", label = "Sell" },
        { key = "auctions", label = "Auctions" },
        { key = "flips", label = "Flips" },
        { key = "deals", label = "Deals" },
    }, function(key) p:ShowPage(key) end, 52)
    p.pageSeg:SetPoint("LEFT", title, "RIGHT", 10, 0)

    p.status = W.Text(p, "mutedSm", "Pick an item from your bags to see listings.")
    p.status:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -10)
    p.status:SetPoint("RIGHT", -14, 0)
    p.status:SetJustifyH("LEFT")
    p.status:SetWordWrap(false)

    p.search = W.EditBox(p, 140, false, "Filter bags...")
    p.search:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
    p.search:SetPoint("RIGHT", -12, 0)
    p.search:HookScript("OnTextChanged", function(_, user) if user then p.list:SetData(p.FilterRows(ScanBags())) end end)

    -- Category breakdown: what's in your bags per AH category (count and market value); pick one to narrow
    -- the list. The choice is kept by label: ns.db.sellCat.
    p.catDrop = W.Dropdown(p, 150, function(key)
        ns.db.sellCat = key ~= "all" and key or nil
        p.list:SetData(p.FilterRows(ScanBags()))
    end)

    local columns = {
        { title = "Item", get = function(r)
            return (r.icon and ("|T%s:16:16:0:0|t  "):format(r.icon) or "") .. DisplayName(r)
        end, sortValue = PlainName },
        { title = "Qty", width = 34, align = "RIGHT", get = function(r) return r.count end, sortValue = function(r) return r.count end },
        { title = "Market", width = 56, align = "RIGHT", get = function(r)
            local m = P.Market(r.itemID)
            if m then return U.FormatGoldShort(m) end
            return "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return (P.Market(r.itemID) or 0) * r.count end },
        -- Whole stack: AH buyout market price after the AH cut, minus what a vendor pays.
        { title = "vs vendor", width = 70, align = "RIGHT", get = function(r)
            if P.IsJunk(r.itemID) then return "Vendor", T.accent[1], T.accent[2], T.accent[3] end
            local diff = BagVendorDiff(r)
            if not diff then return "-", T.muted[1], T.muted[2], T.muted[3] end
            if diff >= 0 then return "AH +" .. U.FormatGoldShort(diff), 0.38, 1, 0.38 end
            return "V +" .. U.FormatGoldShort(-diff), T.accent[1], T.accent[2], T.accent[3]
        end, sortValue = function(r)
            if P.IsJunk(r.itemID) then return -math.huge end
            return BagVendorDiff(r) or -math.huge
        end },
    }
    local list = W.List(p, columns, 20)
    list:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -8)
    list:SetPoint("RIGHT", -12, 0)
    list.sortCol, list.sortDesc = 3, true
    list.empty:SetText("Nothing in your bags can be auctioned")
    list.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        if r.link then GameTooltip:SetHyperlink(r.link) else pcall(GameTooltip.SetItemByID, GameTooltip, r.itemID) end
        local diff = BagVendorDiff(r)
        if P.IsJunk(r.itemID) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Junk: sell it to a vendor. Gray items rarely sell on the AH.", 1, 0.78, 0.25, true)
        elseif diff then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(("Whole stack (x%d)"):format(r.count),
                diff >= 0 and ("|cff60ff60AH earns %s more|r"):format(U.FormatMoney(diff))
                    or ("|cffffc640vendor pays %s more|r"):format(U.FormatMoney(-diff)), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:Show()
    end
    list.onClick = function(r)
        p.pendingConfirm = nil
        p.postBtn:SetText("Post auction")
        p.form:SetRow(r)
    end
    list.isSelected = function(r) return p.form.row and p.form.row.key == r.key end
    p.list = list

    --- Rebuild the category options from these rows: { "Trade Goods (12) - 3g 40s", ... }, biggest value first.
    local function UpdateCategories(rows)
        local by, order = {}, {}
        for _, r in ipairs(rows) do
            local c = r.cat or OTHER_CAT
            local e = by[c]
            if not e then
                e = { label = c, n = 0, value = 0 }
                by[c] = e
                order[#order + 1] = e
            end
            e.n = e.n + 1
            e.value = e.value + (P.Market(r.itemID) or 0) * r.count
        end
        table.sort(order, function(a, b)
            if a.value ~= b.value then return a.value > b.value end
            return a.label < b.label
        end)
        local opts = { { key = "all", label = ("All items (%d)"):format(#rows) } }
        for _, e in ipairs(order) do
            opts[#opts + 1] = { key = e.label, label = e.value > 0 and ("%s (%d) - %s"):format(e.label, e.n, U.FormatGoldShort(e.value))
                or ("%s (%d)"):format(e.label, e.n) }
        end
        -- A saved category with nothing in your bags right now falls back to all items (but stays saved).
        local cur = ns.db.sellCat
        if cur and not by[cur] then cur = nil end
        p.catDrop:SetOptions(opts)
        p.catDrop:SetValue(cur or "all")
        return cur
    end

    function p.FilterRows(rows)
        local cat = UpdateCategories(rows)
        local q = (p.search:GetText() or ""):lower()
        if q == "" and not cat then return rows end
        local out = {}
        for _, r in ipairs(rows) do
            if (q == "" or PlainName(r):find(q, 1, true)) and (not cat or r.cat == cat) then out[#out + 1] = r end
        end
        return out
    end

    p.postBtn = W.Button(p, "Post auction", 100, Post, true)
    p.postBtn:SetHeight(30)
    p.postBtn:SetPoint("BOTTOMLEFT", 12, 12)
    p.postBtn:SetPoint("BOTTOMRIGHT", -12, 12)

    p.form = CreateSellForm(p)
    p.form:SetPoint("BOTTOMLEFT", p.postBtn, "TOPLEFT", 0, 8)
    p.form:SetPoint("BOTTOMRIGHT", p.postBtn, "TOPRIGHT", 0, 8)
    list:SetPoint("BOTTOM", p.form, "TOP", 0, 10)
    p.sellWidgets = { p.search, p.catDrop, list, p.form, p.postBtn }
    p.sellChart = UI.CreatePriceChart(p, { listings = true })
    p.sellChart:Hide()

    --- Full-window mode: bag list on the left; price chart, sell form and Post on the right.
    --- Docked: single column, no chart (not enough height).
    function p:ApplyWide()
        local wide = ns.db.settings.ahReplace
        self.wide = wide
        local header = self.header
        self.search:ClearAllPoints()
        self.catDrop:ClearAllPoints()
        list:ClearAllPoints()
        self.postBtn:ClearAllPoints()
        self.sellChart:ClearAllPoints()
        if wide then
            local leftW = math.floor((self:GetWidth() - 36) * 0.45)
            self.search:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
            self.search:SetWidth(leftW - self.catDrop:GetWidth() - 6)
            self.catDrop:SetPoint("LEFT", self.search, "RIGHT", 6, 0)
            list:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -8)
            list:SetPoint("BOTTOMLEFT", 12, 12)
            list:SetWidth(leftW)
            self.postBtn:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 12, 0)
            self.postBtn:SetPoint("BOTTOMRIGHT", -12, 12)
            self.sellChart:SetPoint("TOPLEFT", self.catDrop, "TOPRIGHT", 12, 0)
            self.sellChart:SetPoint("RIGHT", -12, 0)
            self.sellChart:SetPoint("BOTTOM", self.form, "TOP", 0, 10)
        else
            self.search:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
            self.catDrop:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -30)
            self.search:SetPoint("RIGHT", self.catDrop, "LEFT", -6, 0)
            list:SetPoint("TOPLEFT", self.search, "BOTTOMLEFT", 0, -8)
            list:SetPoint("RIGHT", -12, 0)
            list:SetPoint("BOTTOM", self.form, "TOP", 0, 10)
            self.postBtn:SetPoint("BOTTOMLEFT", 12, 12)
            self.postBtn:SetPoint("BOTTOMRIGHT", -12, 12)
        end
        self.sellChart:SetShown(wide and self.page == "sell")
        if self.buy then self.buy:SetWide(wide) end
    end

    p.auctions = UI.CreateAHAuctions(p, SetStatus, function(undercut)
        p.pageSeg:SetLabel("auctions", undercut > 0 and ("Auctions |cffff6060%d|r"):format(undercut) or "Auctions")
    end)
    p.auctions:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
    p.auctions:SetPoint("BOTTOMRIGHT", -12, 12)

    p.buy = UI.CreateAHBuy(p, SetStatus)
    p.buy:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
    p.buy:SetPoint("BOTTOMRIGHT", -12, 12)

    p.flips = UI.CreateAHFlips(p, SetStatus, function(itemID)
        p:ShowPage("buy")
        p.buy:OpenItem(itemID)
    end)
    p.flips:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
    p.flips:SetPoint("BOTTOMRIGHT", -12, 12)

    p.deals = UI.CreateAHDeals(p, SetStatus)
    p.deals:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -30)
    p.deals:SetPoint("BOTTOMRIGHT", -12, 12)
    -- The deals scanner pauses while you're mid-purchase on the Buy tab.
    UI.AHBuyBusy = function() return p.buy.stage ~= nil or p.buy.bidStage ~= nil end

    function p:ShowPage(key)
        self.page = key
        ns.db.settings.ahPage = key
        self.pageSeg:SetValue(key)
        for _, w in ipairs(self.sellWidgets) do w:SetShown(key == "sell") end
        if key == "sell" and bagsDirty and self:IsShown() then RefreshBags() end
        self.sellChart:SetShown(key == "sell" and self.wide or false)
        self.auctions:SetShown(key == "auctions")
        self.buy:SetShown(key == "buy")
        self.flips:SetShown(key == "flips")
        self.deals:SetShown(key == "deals")
    end
    p:ShowPage(ns.db.settings.ahPage or "buy")

    p.header = header
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if ns.db.settings.ahReplace then p:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        p:StopMovingOrSizing()
        if ns.db.settings.ahReplace then p.SaveState() end
    end)
    p:HookScript("OnSizeChanged", function(self) if self.wide then self:ApplyWide() end end)

    p.grip = W.MakeResizable(p, 600, 420)
    p.SaveState = function()
        ns.db.settings.ahWindow = { w = p:GetWidth(), h = p:GetHeight(), x = p:GetLeft(), y = p:GetTop() }
    end
    p.grip:Hide()

    p:SetScript("OnShow", function()
        p.pendingConfirm = nil
        bagsDirty = true
        RefreshBags()
        -- Your auctions fill the undercut / outbid badge even on another page; ask once the window is drawn.
        C_Timer.After(0.3, function()
            if not p:IsShown() then return end
            p.auctions:Query()
            p.auctions:QueryBids()
        end)
    end)
    p:Hide()
    return p
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
--- Docked: a side panel beside the Blizzard AH window.
--- Full window: the Blizzard window stays open (hiding it would close the AH) but is made invisible and
--- shrunk to almost nothing, so it can't catch clicks anywhere. GoblinBooks floats freely: drag its header.
local ahfScale -- the Blizzard window's own scale, restored when docking or closing

local function ShrinkBlizzard(ahf)
    if ahf:GetScale() > TINY * 10 then ahfScale = ahf:GetScale() end
    ahf:SetAlpha(0)
    ahf:SetScale(TINY)
end

local function RestoreBlizzard(ahf)
    if ahfScale then ahf:SetScale(ahfScale) end
    ahf:SetAlpha(1)
end

function UI:LayoutAHPanel()
    local ahf = AuctionHouseFrame
    if not (panel and ahf) then return end
    local s = ns.db.settings
    panel:ClearAllPoints()
    panel:SetFrameStrata(ahf:GetFrameStrata()) -- the AH window's level, not above the action bars
    if s.ahReplace then
        local saved = s.ahWindow or {}
        -- First time: open where the Blizzard window would be (read before shrinking it).
        local x, y = saved.x, saved.y
        if not x and ahf:GetScale() > TINY * 10 and ahf:GetLeft() then
            local k = ahf:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = ahf:GetLeft() * k, ahf:GetTop() * k
        end
        ShrinkBlizzard(ahf)
        panel:SetSize(math.max(MIN_W, saved.w or FULL_W), math.max(MIN_H, saved.h or FULL_H))
        if panel.SetResizeBounds then panel:SetResizeBounds(MIN_W, MIN_H) end
        if x then
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        else
            panel:SetPoint("CENTER")
        end
        -- A strata above the Blizzard window: it raises itself when shown, and its invisible parts would
        -- otherwise sit over our header and swallow clicks on the tabs.
        panel:SetFrameStrata("DIALOG")
        W.Backdrop(panel, { T.bg[1], T.bg[2], T.bg[3], 1 }, { 1, 1, 1, 0.10 })
        panel:SetToplevel(true)
        panel:Raise()
        panel.grip:Show()
        panel.modeBtn:SetText("Dock")
        panel:ApplyWide()
        if toggle then toggle:Hide() end
        panel:Show()
    else
        RestoreBlizzard(ahf)
        W.Backdrop(panel, T.bg, { 1, 1, 1, 0.10 })
        panel:SetWidth(PANEL_W)
        panel:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 4, 0)
        panel:SetPoint("BOTTOMLEFT", ahf, "BOTTOMRIGHT", 4, 0)
        panel.grip:Hide()
        panel.modeBtn:SetText("Expand")
        panel:ApplyWide()
        if not toggle then
            toggle = W.Button(ahf, "GoblinBooks", 96, function() UI:ToggleAHPanel() end, true)
            toggle:SetHeight(22)
            toggle:SetPoint("BOTTOMRIGHT", ahf, "TOPRIGHT", 0, 2)
        end
        toggle:Show()
        panel:SetShown(s.ahPanel)
    end
end

local hookedAHF = false
local function Attach()
    local ahf = AuctionHouseFrame
    if not ahf then return end
    panel = panel or Create()
    if not hookedAHF then
        hookedAHF = true
        ahf:HookScript("OnShow", function(self)
            if ns.db.settings.ahReplace then self:SetAlpha(0) end -- no flash; Layout then shrinks it
        end)
    end
    UI:LayoutAHPanel()
end

--- Quick link: show the Buy tab with this item selected. Returns false if the AH isn't open.
function UI:OpenInAH(itemID, wantQty)
    if not (panel and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
    if not panel:IsShown() then
        ns.db.settings.ahPanel = true
        UI:LayoutAHPanel()
        panel:Show()
    end
    panel:ShowPage("buy")
    panel.buy:OpenItem(itemID, wantQty)
    return true
end

function UI:ToggleAHPanel()
    if not panel then return end
    local show = not panel:IsShown()
    panel:SetShown(show)
    ns.db.settings.ahPanel = show
end

ns:On("AUCTION_HOUSE_SHOW", function() Attach() end)
ns:On("AUCTION_HOUSE_CLOSED", function()
    if panel then panel:Hide() end
    if AuctionHouseFrame then RestoreBlizzard(AuctionHouseFrame) end
    W.CloseMenu()
end)

local bagPending = false
ns:On("BAG_UPDATE_DELAYED", function()
    if bagPending or not panel or not panel:IsShown() then return end
    bagPending = true
    C_Timer.After(0.2, function()
        bagPending = false
        RefreshBags()
    end)
end)

ns:Register("AH_SEARCH_RESULTS", function(itemID, listings)
    if panel and panel:IsShown() and panel.form.row and panel.form.row.itemID == itemID then
        panel.form:OnListings(listings)
    end
end)

ns:Register("PRICES_UPDATED", function()
    if panel and panel:IsShown() then panel.list:Refresh() end
end)

local postRefresh = 0
ns:On("AUCTION_HOUSE_AUCTION_CREATED", function()
    if not panel then return end
    SetStatus("|cff60ff60Auction posted.|r")
    panel.form.priceSet = true -- keep the user's price while listings refresh
    S.postHoldUntil = GetTime() + S.POST_HOLD
    -- Refresh the listings once you've stopped posting (2s after the last post), not after every post.
    postRefresh = postRefresh + 1
    local token = postRefresh
    C_Timer.After(S.POST_HOLD, function()
        if token ~= postRefresh or not panel:IsShown() then return end
        local row = panel.form.row
        if row then S.Search(ItemKeyFor(row)) end
    end)
end)

-- The server asks for confirmation when a price is far below market.
ns:On("AUCTION_HOUSE_POST_WARNING", function()
    if not panel or not panel.lastPost then return end
    panel.pendingConfirm = panel.lastPost
    panel.postBtn:SetText("Confirm post (price is well below market)")
    SetStatus("|cffff9933Price is well below market. Click again to confirm.|r")
end)

ns:On("AUCTION_HOUSE_POST_ERROR", function()
    SetStatus("|cffff6060The auction could not be posted.|r")
end)

-- One overall percentage: reading the auctions is most of the work (0-80%), saving prices the rest.
local function ScanPercent(state, done, total)
    local frac = (total and total > 0) and math.min(1, done / total) or 0
    if state == "reading" then return math.floor(frac * 80) end
    if state == "saving" then return 80 + math.floor(frac * 20) end
    return 0
end

local scanResetTimer
local function ScanButton(text, pct)
    if not panel then return end
    local btn, bar = panel.scanBtn, panel.scanBar
    btn:SetText(text)
    if pct then
        bar.fill:SetWidth(math.max(1, bar:GetWidth() * pct / 100))
        bar:Show()
    else
        bar:Hide()
    end
end

--- The scan couldn't start (cooldown, client): say so on the button for a few seconds.
function UI.ScanNotReady(msg, mode)
    if not panel then return end
    if scanResetTimer then scanResetTimer:Cancel() end
    -- Full scans have the server's 15-minute limit; a scan of every category has our own 5-minute one.
    local left
    if mode == "full" then left = select(2, S.FullScanReady()) else left = select(2, S.CategoryScanReady(mode)) end
    ScanButton(left > 0 and ("|cffff9933%dm left|r"):format(math.ceil(left / 60)) or "|cffff9933Not now|r", nil)
    panel.scanInfo = "|cffff9933" .. tostring(msg) .. "|r"
    scanResetTimer = C_Timer.NewTimer(4, function()
        scanResetTimer = nil
        panel.scanInfo = nil
        if not S.scanning then ScanButton("Scan", nil) end
    end)
end

ns:Register("SCAN_PROGRESS", function(state, done, total, label, items)
    if not panel then return end
    if scanResetTimer then scanResetTimer:Cancel() scanResetTimer = nil end
    if state == "waiting" then
        local waited = done or 0
        panel.scanInfo = ("Waiting for the server to send the auctions (%ds). A big auction house can take a minute or two."):format(waited)
        ScanButton(waited >= 5 and ("Waiting %ds"):format(waited) or "Waiting...", 0)
    elseif state == "categories" then
        local pct = total > 0 and math.floor((done - 1) * 100 / total) or 0
        panel.scanInfo = ("Scanning %s (%d of %d): %s items priced so far."):format(label or "?", done, total,
            U.CommaNumber(items or 0))
        ScanButton(("Scan %d%%"):format(pct), pct)
    elseif state == "reading" or state == "saving" then
        local pct = ScanPercent(state, done, total)
        panel.scanInfo = state == "reading"
            and ("Reading %s / %s auctions"):format(U.CommaNumber(done), U.CommaNumber(total))
            or ("Saving prices: %s / %s items"):format(U.CommaNumber(done), U.CommaNumber(total))
        ScanButton(("Scan %d%%"):format(pct), pct)
    else
        if state == "done" then
            panel.scanInfo = nil
            ScanButton("|cff60ff60Done|r", 100)
            if ns.db.settings.debug then ns:Print("scan complete") end
        elseif state == "stopped" then
            panel.scanInfo = ("Stopped: %s items priced before stopping."):format(U.CommaNumber(done or 0))
            ScanButton("Stopped", nil)
        else
            panel.scanInfo = "|cffff6060Last scan failed: " .. (type(done) == "string" and done or "no response from the server") .. "|r"
            ScanButton("|cffff6060Failed|r", nil)
        end
        scanResetTimer = C_Timer.NewTimer(8, function()
            scanResetTimer = nil
            if not S.scanning then ScanButton("Scan", nil) end
        end)
    end
end)
