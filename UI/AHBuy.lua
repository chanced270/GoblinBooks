-- AH panel "Buy" page: search, compare listings against price history, and buy.
-- Commodities: StartCommoditiesPurchase -> server quote (COMMODITY_PRICE_UPDATED) -> ConfirmCommoditiesPurchase.
-- Items: pick a listing, click twice -> PlaceBid at the buyout price; or enter a bid (>= minimum) and confirm.
-- The ledger's hooks on ConfirmCommoditiesPurchase / PlaceBid record the cost basis as before.
local _, ns = ...
local UI, W, U, P, S = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.AHScan
local T = W.Theme
local AH = C_AuctionHouse

local PRICEY = 1.5 -- warn when paying more than this multiple of the 7-day average
local ORANGE, GREEN = { 1, 0.6, 0.2 }, { 0.38, 1, 0.38 }
local TIME_LEFT = { [0] = "under 30m", [1] = "30m to 2h", [2] = "2h to 12h", [3] = "12h to 48h" }

local function KeyInfo(itemKey)
    if not (AH.GetItemKeyInfo and itemKey) then return nil end
    local ok, info = pcall(AH.GetItemKeyInfo, itemKey)
    return ok and info or nil
end

local function ResultName(r)
    if not r.name then
        local info = KeyInfo(r.key)
        r.name = info and info.itemName or U.ItemName(r.itemID)
        r.icon = r.icon or (info and info.iconFileID)
        if info and info.isCommodity ~= nil and r.commodity == nil then r.commodity = info.isCommodity end
    end
    return r.name or ("item:" .. r.itemID)
end

function UI.CreateAHBuy(parent, setStatus)
    local f = CreateFrame("Frame", nil, parent)

    f.search = W.EditBox(f, 200, false, "Search the auction house...")
    f.search:SetPoint("TOPLEFT")
    f.search:SetPoint("RIGHT", -78, 0)
    f.searchBtn = W.Button(f, "Search", 72, function() f:DoSearch() end, true)
    f.searchBtn:SetPoint("TOPRIGHT")
    f.search:SetScript("OnEnterPressed", function(e)
        e:ClearFocus()
        f:DoSearch()
    end)

    -- Category filters + favorites.
    local cats = S.CategoryTree()
    local catOpts = { { key = "all", label = "All categories" } }
    for i, c in ipairs(cats) do catOpts[#catOpts + 1] = { key = i, label = c.label } end
    f.catDrop = W.Dropdown(f, 116, function(key)
        f.cat = cats[key]
        f.sub = nil
        f:UpdateSubOptions()
        if f.cat then f:DoSearch() end
    end)
    f.catDrop:SetOptions(catOpts)
    f.catDrop:SetValue("all")
    f.catDrop:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", 0, -8)
    f.subDrop = W.Dropdown(f, 116, function(key)
        f.sub = f.cat and f.cat.subs[key] or nil
        f:DoSearch()
    end)
    f.subDrop:SetPoint("LEFT", f.catDrop, "RIGHT", 6, 0)
    function f:UpdateSubOptions()
        local opts = { { key = "all", label = self.cat and "All subcategories" or "Subcategory" } }
        for i, sc in ipairs(self.cat and self.cat.subs or {}) do opts[#opts + 1] = { key = i, label = sc.label } end
        self.subDrop:SetOptions(opts)
        self.subDrop:SetValue("all")
        self.subDrop:SetEnabled(#opts > 1)
    end
    f:UpdateSubOptions()
    f.favBtn = W.Button(f, P.FAV_ICON .. " Favorites", 88, function() f:ShowFavorites() end)
    f.favBtn:SetPoint("LEFT", f.subDrop, "RIGHT", 6, 0)
    f.shopBtn = W.Button(f, "Shopping", 80, function() f:ShowShopping() end)
    f.shopBtn:SetPoint("LEFT", f.favBtn, "RIGHT", 6, 0)

    -- Search results.
    local results = W.List(f, {
        { title = "Item", get = function(r)
            local name = ResultName(r)
            return (P.IsFavorite(r.itemID) and (P.FAV_ICON .. " ") or "")
                .. (r.icon and ("|T%s:16:16:0:0|t  "):format(r.icon) or "") .. name
        end, sortValue = function(r) return ResultName(r):lower() end },
        { title = "From", width = 62, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.min) end,
          sortValue = function(r) return r.min end },
        { title = "Avail", width = 44, align = "RIGHT", get = function(r) return r.qty end,
          sortValue = function(r) return r.qty end },
    }, 20)
    results:SetPoint("TOPLEFT", 0, -64)
    results:SetPoint("RIGHT")
    results.empty:SetText("Search for an item or pick a category")
    results.onClick = function(r)
        if r.shop then f:OpenItem(r.itemID, r.remaining)
        elseif r.fav then f:OpenItem(r.itemID)
        else f:Select(r) end
    end
    results.isSelected = function(r) return f.sel == r end
    results.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        pcall(GameTooltip.SetItemByID, GameTooltip, r.itemID)
        GameTooltip:Show()
    end
    f.results = results

    f.buyBtn = W.Button(f, "Select an item", 100, function() f:OnBuyClick() end, true)
    f.buyBtn:SetHeight(30)
    f.buyBtn:SetPoint("BOTTOMLEFT")
    f.buyBtn:SetPoint("BOTTOMRIGHT")

    -- Detail: selected item, its listings, quantity.
    local d = W.Panel(f)
    d:SetPoint("BOTTOMLEFT", f.buyBtn, "TOPLEFT", 0, 8)
    d:SetPoint("BOTTOMRIGHT", f.buyBtn, "TOPRIGHT", 0, 8)
    d:SetHeight(236)
    results:SetPoint("BOTTOM", d, "TOP", 0, 10)
    f.detail = d

    d.name = W.Text(d, "heading", "")
    d.name:SetPoint("TOPLEFT", 12, -12)
    d.name:SetPoint("RIGHT", -40, 0)
    d.star = CreateFrame("Button", nil, d)
    d.star:SetSize(22, 22)
    d.star:SetPoint("TOPRIGHT", -10, -8)
    d.star.tex = d.star:CreateTexture(nil, "ARTWORK")
    d.star.tex:SetAllPoints()
    d.star.tex:SetTexture("Interface\\Common\\FavoritesIcon")
    d.star:SetScript("OnClick", function()
        if f.sel then
            P.ToggleFavorite(f.sel.itemID, ResultName(f.sel))
            f:Update()
            results:Refresh()
        end
    end)
    d.star:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:AddLine(f.sel and P.IsFavorite(f.sel.itemID) and "Remove from favorites" or "Add to favorites")
        GameTooltip:Show()
    end)
    d.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.star:Hide()

    -- Watch for deals on this item (Deals tab).
    d.watchBtn = W.Button(d, "Watch", 56, function()
        local sel = f.sel
        if not sel then return end
        if ns.Deals.IsWatched(sel.itemID) then
            ns.Deals.RemoveWatch(sel.itemID)
            setStatus("No longer watching " .. (U.ItemName(sel.itemID) or "it") .. ".")
        else
            ns.Deals.AddWatch(sel.itemID)
            local thr = ns.Deals.Threshold(sel.itemID)
            setStatus(("Watching %s for deals%s. Set a max price on the Deals tab."):format(U.ItemName(sel.itemID) or "it",
                thr and (" under " .. U.FormatMoney(thr)) or ""))
        end
        f:Update()
    end)
    d.watchBtn:SetHeight(22)
    d.watchBtn:SetPoint("RIGHT", d.star, "LEFT", -6, 0)
    d.watchBtn:Hide()
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.info = W.Text(d, "mutedSm", "")
    d.info:SetPoint("TOPLEFT", 12, -32)
    d.info:SetPoint("RIGHT", -12, 0)
    d.info:SetJustifyH("LEFT")

    local listings = W.List(d, {
        -- Buyout auctions show only their price; bid details appear only on auctions with no buyout.
        { title = "Price each", get = function(l)
            local text
            if l.unit then
                text = U.FormatMoney(l.unit)
            elseif l.winning then
                text = ("|cff60ff60bid only, you lead at %s|r"):format(U.FormatGoldShort(l.bid or l.minBid))
            else
                text = ("|cff8c94a3bid only, min %s|r"):format(U.FormatGoldShort(l.minBid or 0))
            end
            return text .. (l.mine and "  |cffffc640(yours)|r" or "")
        end },
        { title = "Qty", width = 44, align = "RIGHT", get = function(l) return l.qty end },
        { title = "vs avg", width = 54, align = "RIGHT", get = function(l)
            local avg = f.sel and Avg(f.sel.itemID)
            if not l.unit then return "-", T.muted[1], T.muted[2], T.muted[3] end
            if not avg or avg == 0 then return "-", T.muted[1], T.muted[2], T.muted[3] end
            local pct = (l.unit - avg) / avg * 100
            local c = pct <= 0 and GREEN or (l.unit > avg * PRICEY and { 1, 0.38, 0.38 } or ORANGE)
            return ("%+.0f%%"):format(pct), c[1], c[2], c[3]
        end },
    }, 18)
    listings:SetPoint("TOPLEFT", 8, -52)
    listings:SetPoint("BOTTOMRIGHT", -8, 40)
    listings.empty:SetText("")
    listings.onClick = function(l)
        if f.sel and not f.sel.commodity then
            f:ResetPurchase()
            f.pick = l
            if not l.unit and l.minBid then d.bid:SetValue(l.minBid) end
            f:Update()
        end
    end
    listings.isSelected = function(l) return f.pick == l end
    listings.onEnter = function(row, l)
        if not l.link then return end
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(l.link)
        if not l.unit and l.minBid then
            GameTooltip:AddLine(" ")
            if l.bid then GameTooltip:AddDoubleLine("Current bid", U.FormatMoney(l.bid), 1, 0.82, 0, 1, 1, 1) end
            GameTooltip:AddDoubleLine("Minimum bid", U.FormatMoney(l.minBid), 1, 0.82, 0, 1, 1, 1)
            if l.winning then GameTooltip:AddLine("You are the high bidder", 0.38, 1, 0.38) end
        end
        if TIME_LEFT[l.timeLeft] then GameTooltip:AddDoubleLine("Time left", TIME_LEFT[l.timeLeft], 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:Show()
    end
    d.listings = listings

    d.qtyLabel = W.Text(d, "label", "QUANTITY")
    d.qtyLabel:SetPoint("BOTTOMLEFT", 12, 16)
    d.qty = W.EditBox(d, 64, true)
    d.qty:SetMaxLetters(6)
    d.qty:SetPoint("LEFT", d.qtyLabel, "RIGHT", 10, 0)
    d.qty:HookScript("OnTextChanged", function(_, user)
        if user then
            f:ResetPurchase()
            f:Update()
        end
    end)
    d.maxBtn = W.Button(d, "Max", 44, function()
        local _, _, avail = f:Estimate(math.huge)
        d.qty:SetText(tostring(avail))
        f:ResetPurchase()
        f:Update()
    end)
    d.maxBtn:SetPoint("LEFT", d.qty, "RIGHT", 6, 0)
    d.estimate = W.Text(d, "body", "")
    d.estimate:SetPoint("LEFT", d.maxBtn, "RIGHT", 10, 0)
    d.estimate:SetPoint("RIGHT", -12, 0)
    d.estimate:SetJustifyH("RIGHT")

    d.bidLabel = W.Text(d, "label", "BID")
    d.bidLabel:SetPoint("BOTTOMLEFT", 12, 16)
    d.bid = W.MoneyInput(d, function()
        f.bidStage = nil
        f:Update()
    end)
    d.bid:SetPoint("LEFT", d.bidLabel, "RIGHT", 10, 0)
    d.bidBtn = W.Button(d, "Bid", 66, function() f:OnBidClick() end)
    d.bidBtn:SetPoint("BOTTOMRIGHT", -12, 10)

    -- Price chart (full-window mode only): right column above the detail panel.
    f.chart = UI.CreatePriceChart(f, { listings = true })
    f.chart:Hide()

    --- Wide: results on the left, chart + detail + Buy on the right. Narrow: single column, no chart.
    function f:SetWide(wide)
        self.wide = wide
        self.search:ClearAllPoints()
        self.searchBtn:ClearAllPoints()
        results:ClearAllPoints()
        self.buyBtn:ClearAllPoints()
        self.chart:ClearAllPoints()
        if wide then
            local leftW = math.floor((self:GetWidth() - 12) * 0.45)
            self.search:SetPoint("TOPLEFT")
            self.search:SetWidth(leftW - 78)
            self.searchBtn:SetPoint("LEFT", self.search, "RIGHT", 6, 0)
            results:SetPoint("TOPLEFT", 0, -64)
            results:SetPoint("BOTTOMLEFT")
            results:SetWidth(leftW)
            self.buyBtn:SetPoint("BOTTOMLEFT", results, "BOTTOMRIGHT", 12, 0)
            self.buyBtn:SetPoint("BOTTOMRIGHT")
            self.chart:SetPoint("TOPLEFT", results, "TOPRIGHT", 12, 64)
            self.chart:SetPoint("RIGHT")
            self.chart:SetPoint("BOTTOM", d, "TOP", 0, 10)
        else
            self.search:SetPoint("TOPLEFT")
            self.search:SetPoint("RIGHT", -78, 0)
            self.searchBtn:SetPoint("TOPRIGHT")
            results:SetPoint("TOPLEFT", 0, -64)
            results:SetPoint("RIGHT")
            results:SetPoint("BOTTOM", d, "TOP", 0, 10)
            self.buyBtn:SetPoint("BOTTOMLEFT")
            self.buyBtn:SetPoint("BOTTOMRIGHT")
        end
        self.chart:SetShown(wide)
    end
    f:HookScript("OnSizeChanged", function(self) if self.wide then self:SetWide(true) end end)

    -----------------------------------------------------------------------
    -- Logic
    -----------------------------------------------------------------------
    -- Keep the shopping list current as purchases land in your bags.
    ns:On("BAG_UPDATE_DELAYED", function()
        if f.mode == "shopping" and f:IsVisible() then f:ShowShopping() end
    end)

    function f:DoSearch(textOverride)
        local text = textOverride or self.search:GetText() or ""
        local group = self.sub or self.cat
        local filters = not textOverride and group and group.filters or nil
        if text == "" and not filters then return end
        self.searching = true
        self.mode = "search"
        results.empty:SetText("Searching...")
        if not S.Browse(text, filters) then
            results.empty:SetText("Search is not available")
            return
        end
        local where = filters and (" in " .. group.label) or ""
        setStatus(text ~= "" and ("Searching for \"%s\"%s..."):format(text, where) or ("Browsing %s..."):format(group.label))
    end

    function f:OnBrowse()
        if not self.searching or not AH.GetBrowseResults then return end
        local rows, open = {}, nil
        for _, r in ipairs(AH.GetBrowseResults() or {}) do
            local key = r.itemKey
            if key and key.itemID and (key.battlePetSpeciesID or 0) == 0 then
                local row = { key = key, itemID = key.itemID, min = r.minPrice or 0, qty = r.totalQuantity or 0 }
                rows[#rows + 1] = row
                if self.pendingOpen and key.itemID == self.pendingOpen and not open then open = row end
            end
        end
        results:SetData(rows)
        results.empty:SetText("No results")
        if self.pendingOpen then
            local name = U.ItemName(self.pendingOpen) or "that item"
            self.pendingOpen = nil
            if open then
                self:Select(open)
                setStatus(("Showing %s"):format(name))
            else
                setStatus(("No %s listed right now"):format(name))
            end
        else
            setStatus(("%d results"):format(#rows))
        end
    end

    --- Jump straight to one item: browse by its name, then select the matching result.
    function f:OpenItem(itemID, wantQty)
        self.wantQty = wantQty and wantQty > 0 and wantQty or nil
        local fav = P.Favorites()[itemID]
        local name = U.ItemName(itemID) or (fav and fav.n) or (P.Get(itemID) or {}).n
        if not name then
            setStatus("|cffff9933Item info not loaded yet, try again in a moment.|r")
            return
        end
        self.search:SetText(name)
        self.pendingOpen = itemID
        self:DoSearch(name)
    end

    --- Crafting shopping list in the results (items still needed); clicking one loads it with the
    --- missing quantity filled in.
    function f:ShowShopping()
        self.searching, self.pendingOpen = false, nil
        self.mode = "shopping"
        local rows = {}
        for _, s in ipairs((ns.Crafting.ShoppingRows())) do
            if s.remaining > 0 then
                local e = P.Get(s.id)
                rows[#rows + 1] = {
                    itemID = s.id, name = ("%s  |cffffc640need %d|r"):format(s.n or U.ItemName(s.id) or ("item:" .. s.id), s.remaining),
                    min = e and e.p or 0, qty = e and e.q or 0, shop = true, remaining = s.remaining,
                }
            end
        end
        results:SetData(rows)
        results.empty:SetText("Nothing left to buy. Add recipes to the shopping list in the Crafting tab.")
        setStatus(("%d reagents still needed. Click one to load it with the missing amount."):format(#rows))
    end

    --- Show favorites in the results list (last known prices); clicking one loads live listings.
    function f:ShowFavorites()
        self.searching, self.pendingOpen = false, nil
        self.mode = "favorites"
        local rows = {}
        for itemID, fav in pairs(P.Favorites()) do
            local e = P.Get(itemID)
            rows[#rows + 1] = { itemID = itemID, name = fav.n or (e and e.n), min = e and e.p or 0, qty = e and e.q or 0, fav = true }
        end
        results:SetData(rows)
        results.empty:SetText("No favorites yet. Select an item and click the star to add it.")
        setStatus(("%d favorites. Click one to load its current listings."):format(#rows))
    end

    function f:Select(r)
        self:ResetPurchase()
        self.sel, self.listings, self.pick = r, nil, nil
        self.chart:SetItem(r.itemID)
        ResultName(r)
        d.qty:SetText(r.commodity == false and "" or "1")
        listings:SetData({})
        listings.empty:SetText("Loading listings...")
        S.Search(r.key)
        self:Update()
    end

    function f:OnListings(itemID, list, isCommodity, bidOnly)
        if not self.sel or self.sel.itemID ~= itemID then return end
        self.sel.commodity = isCommodity and true or false
        if isCommodity and self.wantQty then
            d.qty:SetText(tostring(self.wantQty))
            self.wantQty = nil
        end
        self.listings = list
        -- Items: buyout listings first, then bid-only auctions.
        local shown = list
        if not isCommodity and bidOnly and #bidOnly > 0 then
            shown = {}
            for _, l in ipairs(list) do shown[#shown + 1] = l end
            for _, l in ipairs(bidOnly) do shown[#shown + 1] = l end
        end
        if self.pick then
            local found
            for _, l in ipairs(shown) do if l.id and l.id == self.pick.id then found = l end end
            self.pick = found
        end
        listings:SetData(shown)
        self.chart:SetListings(list)
        listings.empty:SetText("Nothing listed right now")
        self:Update()
    end

    --- Walk commodity listings cheapest-first (skipping ours): total cost, units filled, units available.
    function f:Estimate(qty)
        local total, filled, avail = 0, 0, 0
        for _, l in ipairs(self.listings or {}) do
            if not l.mine then
                avail = avail + l.qty
                local take = math.min(l.qty, qty - filled)
                if take > 0 then
                    total = total + take * l.unit
                    filled = filled + take
                end
            end
        end
        return total, filled, avail
    end

    function f:ResetPurchase()
        if self.stage == "pricing" or self.stage == "confirm" then
            if self.sel and self.sel.commodity and AH.CancelCommoditiesPurchase then pcall(AH.CancelCommoditiesPurchase) end
        end
        self.stage, self.quote, self.bidStage = nil, nil, nil
    end

    --- Why the entered bid can't be placed (nil if it can).
    function f:BidProblem(amount)
        local pick = self.pick
        if not pick or not pick.minBid then return "No bid" end
        if pick.mine then return "Yours" end
        if pick.winning then return "Winning" end
        if amount < pick.minBid then return "Min " .. U.FormatGoldShort(pick.minBid) end
        if pick.unit and amount >= pick.unit then return "Use Buy" end
        if GetMoney() < amount then return "No gold" end
    end

    function f:UpdateBid()
        -- Only for a picked auction that has no buyout; buyout auctions just use the Buy button.
        local items = self.sel ~= nil and self.sel.commodity == false and self.pick ~= nil and not self.pick.unit
        d.bidLabel:SetShown(items)
        d.bid:SetShown(items)
        d.bidBtn:SetShown(items)
        if not items then return end
        local problem = self:BidProblem(d.bid:GetValue())
        if self.bidStage == "bidding" then
            d.bidBtn:SetText("Bidding...")
            d.bidBtn:Disable()
        elseif problem then
            d.bidBtn:SetText(problem)
            d.bidBtn:Disable()
        else
            d.bidBtn:SetText(self.bidStage == "confirm" and "Confirm" or "Bid")
            d.bidBtn:Enable()
        end
    end

    function f:OnBidClick()
        local pick = self.pick
        local amount = d.bid:GetValue()
        if not pick or self:BidProblem(amount) then return end
        if self.bidStage ~= "confirm" then
            self.bidStage = "confirm"
            setStatus(("Bid %s on %s? Click Confirm. The gold is held until you win or are outbid."):format(
                U.FormatMoney(amount), ResultName(self.sel)))
            self:Update()
            return
        end
        self.bidStage = "bidding"
        ns.AuctionHouse.nextBidLabel = "Bid: " .. ResultName(self.sel)
        local ok, err = pcall(AH.PlaceBid, pick.id, amount)
        if not ok then
            ns.AuctionHouse.nextBidLabel = nil
            self.bidStage = nil
            setStatus("|cffff6060Bid failed: " .. tostring(err) .. "|r")
        else
            setStatus("Placing bid...")
            C_Timer.After(6, function()
                if f.bidStage == "bidding" then f.AfterBid("Bid sent.") end
            end)
        end
        self:Update()
    end

    local function SetBuy(text, enabled)
        f.buyBtn:SetText(text)
        f.buyBtn:SetEnabled(enabled and true or false)
    end

    function f:Update()
        local sel = self.sel
        local commodity = sel and sel.commodity
        d.qtyLabel:SetShown(commodity ~= false and sel ~= nil)
        d.qty:SetShown(commodity ~= false and sel ~= nil)
        d.maxBtn:SetShown(commodity ~= false and sel ~= nil)
        d.estimate:SetText("")
        listings:Refresh()
        self:UpdateBid()
        d.star:SetShown(sel ~= nil)
        d.watchBtn:SetShown(sel ~= nil)
        if sel then d.watchBtn:SetText(ns.Deals.IsWatched(sel.itemID) and "Watching" or "Watch") end
        if sel then
            local fav = P.IsFavorite(sel.itemID)
            d.star.tex:SetDesaturated(not fav)
            d.star.tex:SetAlpha(fav and 1 or 0.45)
        end
        if not sel then
            d.name:SetText("Select an item")
            d.info:SetText("")
            SetBuy("Select an item", false)
            return
        end
        d.name:SetText(((sel.icon and ("|T%s:18:18:0:0|t  "):format(sel.icon)) or "") .. ResultName(sel))
        local e, avg = P.Get(sel.itemID), Avg(sel.itemID)
        local parts = {}
        if avg then parts[#parts + 1] = "7-day avg " .. U.FormatMoney(avg) end
        if e then parts[#parts + 1] = ("seen %s"):format(U.Ago(e.t)) end
        local pick = self.pick
        if commodity == false and pick then
            if not pick.unit and pick.bid then parts[#parts + 1] = "current bid " .. U.FormatGoldShort(pick.bid) end
            if TIME_LEFT[pick.timeLeft] then parts[#parts + 1] = TIME_LEFT[pick.timeLeft] .. " left" end
        elseif commodity == false then
            parts[#parts + 1] = "click a listing to buy it"
        end
        d.info:SetText(#parts > 0 and table.concat(parts, "   ") or "No price history yet")
        if not self.listings then
            SetBuy("Loading listings...", false)
            return
        end

        local money = GetMoney()
        local unit, cost
        if commodity then
            local qty = tonumber(d.qty:GetText()) or 0
            if self.stage == "confirm" and self.quote then
                cost, unit = self.quote.total, self.quote.unit
                d.estimate:SetText(("Quoted %s each"):format(U.FormatMoney(unit)))
                SetBuy(("Confirm: buy %d for %s"):format(self.quote.qty, U.FormatMoney(cost)), money >= cost)
            elseif self.stage == "pricing" then
                SetBuy("Getting a price from the server...", false)
            elseif self.stage == "buying" then
                SetBuy("Buying...", false)
            else
                local total, filled = self:Estimate(qty)
                if qty <= 0 then
                    SetBuy("Enter a quantity", false)
                elseif filled < qty then
                    SetBuy(("Only %d available"):format(filled), false)
                else
                    cost, unit = total, total / qty
                    d.estimate:SetText(("~%s each"):format(U.FormatMoney(unit)))
                    SetBuy(money >= cost and ("Buy %d for ~%s"):format(qty, U.FormatMoney(cost)) or "Not enough gold", money >= cost)
                end
            end
        else
            local pick = self.pick
            if not pick then
                SetBuy("Select a listing", false)
            elseif pick.mine then
                SetBuy("That's your own auction", false)
            elseif not pick.unit then
                SetBuy("No buyout: bid below instead", false)
            elseif self.stage == "buying" then
                SetBuy("Buying...", false)
            else
                cost, unit = pick.unit, pick.unit
                if money < cost then
                    SetBuy("Not enough gold", false)
                elseif self.stage == "confirm" then
                    SetBuy(("Click again to buy for %s"):format(U.FormatMoney(cost)), true)
                else
                    SetBuy(("Buy for %s"):format(U.FormatMoney(cost)), true)
                end
            end
        end
        if unit and avg and unit > avg * PRICEY then
            d.info:SetText(("|cffff9933%.0f%% above the 7-day average (%s)|r"):format((unit - avg) / avg * 100, U.FormatMoney(avg)))
        end
    end

    local function AfterPurchase(msg)
        setStatus(msg)
        f:ResetPurchase()
        if f.sel then C_Timer.After(0.5, function() if f.sel then S.Search(f.sel.key) end end) end
        f:Update()
    end
    f.AfterPurchase = AfterPurchase

    function f:OnBuyClick()
        local sel = self.sel
        if not sel or not self.listings then return end
        local ok, err
        if sel.commodity then
            if self.stage == "confirm" and self.quote then
                self.stage = "buying"
                ok, err = pcall(AH.ConfirmCommoditiesPurchase, sel.itemID, self.quote.qty)
            else
                local qty = tonumber(d.qty:GetText()) or 0
                if qty <= 0 then return end
                self.stage, self.pendingQty = "pricing", qty
                ok, err = pcall(AH.StartCommoditiesPurchase, sel.itemID, qty)
                C_Timer.After(10, function()
                    if f.stage == "pricing" then
                        f.stage = nil
                        setStatus("|cffff9933No price quote from the server. Try again.|r")
                        f:Update()
                    end
                end)
            end
        else
            local pick = self.pick
            if not pick or pick.mine or not pick.id or not pick.unit then return end
            if self.stage ~= "confirm" then
                self.stage = "confirm"
                self:Update()
                return
            end
            self.stage = "buying"
            ns.AuctionHouse.nextBidLabel = "Buyout: " .. ResultName(sel)
            ok, err = pcall(AH.PlaceBid, pick.id, pick.unit)
            if not ok then ns.AuctionHouse.nextBidLabel = nil end
        end
        if not ok then
            self.stage = nil
            setStatus("|cffff6060Purchase failed: " .. tostring(err) .. "|r")
        elseif self.stage == "buying" then
            setStatus("Buying...")
            -- If no result event arrives, unlock the button and refresh anyway.
            C_Timer.After(6, function() if f.stage == "buying" then AfterPurchase("Purchase sent. Check your mailbox.") end end)
        end
        self:Update()
    end

    -----------------------------------------------------------------------
    -- Events
    -----------------------------------------------------------------------
    ns:Register("AH_BROWSE_UPDATED", function() f:OnBrowse() end)
    ns:Register("AH_SEARCH_RESULTS", function(itemID, list, isCommodity, bidOnly)
        f:OnListings(itemID, list, isCommodity, bidOnly)
    end)
    ns:On("ITEM_KEY_ITEM_INFO_RECEIVED", function()
        if f:IsVisible() then results:Refresh() end
    end)
    ns:On("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
        if f.stage ~= "pricing" then return end
        f.stage = "confirm"
        f.quote = { unit = unitPrice, total = totalPrice, qty = f.pendingQty }
        setStatus("Price quoted. Click again to confirm.")
        f:Update()
    end)
    ns:On("COMMODITY_PRICE_UNAVAILABLE", function()
        if f.stage ~= "pricing" then return end
        f.stage = nil
        setStatus("|cffff6060That quantity is no longer available at that price.|r")
        if f.sel then S.Search(f.sel.key) end
        f:Update()
    end)
    ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
        if f.stage == "buying" then AfterPurchase("|cff60ff60Purchase complete.|r") end
    end)
    ns:On("COMMODITY_PURCHASE_FAILED", function()
        if f.stage == "buying" then AfterPurchase("|cffff6060Purchase failed.|r") end
    end)
    ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
        if f.stage == "buying" then AfterPurchase("|cff60ff60Bought. The item is on its way by mail.|r") end
    end)
    ns:On("AUCTION_HOUSE_SHOW_ERROR", function()
        if f.stage == "buying" then AfterPurchase("|cffff6060The purchase failed.|r") end
    end)

    function f.AfterBid(msg)
        setStatus(msg)
        f.bidStage = nil
        if f.sel then C_Timer.After(0.5, function() if f.sel then S.Search(f.sel.key) end end) end
        f:Update()
    end
    ns:On("BID_ADDED", function()
        if f.bidStage == "bidding" then f.AfterBid("|cff60ff60Bid placed. Track it under Auctions > Bids.|r") end
    end)
    ns:On("AUCTION_HOUSE_SHOW_NOTIFICATION", function()
        if f.bidStage == "bidding" then f.AfterBid("|cff60ff60Bid placed.|r") end
    end)
    ns:On("AUCTION_HOUSE_SHOW_ERROR", function()
        if f.bidStage == "bidding" then f.AfterBid("|cffff6060The bid was not accepted.|r") end
    end)

    f:SetScript("OnHide", function() f:ResetPurchase() end)
    f:SetScript("OnShow", function() f:Update() end)
    return f
end
