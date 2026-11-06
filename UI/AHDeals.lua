-- AH panel "Deals" page: the deals watcher (Deals.lua) results, the watch list, and one big Buy button.
-- Every purchase is your click: commodities quote first (click 1) then confirm (click 2); other items arm
-- (click 1) then buy out (click 2). A quote above your limit is refused.
local _, ns = ...
local UI, W, U = ns.UI, ns.Widgets, ns.Util
local T = W.Theme
local AH = C_AuctionHouse

local GREEN, GOLD = { 0.38, 1, 0.38 }, { 1, 0.78, 0.25 }

local function Name(id) return U.ItemName(id) or ("item:" .. id) end
local function Icon(id)
    if not (C_Item and C_Item.GetItemIconByID) then return "" end
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    return ok and icon and ("|T%s:16:16:0:0|t  "):format(icon) or ""
end

function UI.CreateAHDeals(parent, setStatus)
    local D = ns.Deals
    local f = CreateFrame("Frame", nil, parent)
    f.mode = "deals"

    -- Top row: Deals | Watch list, Start/Stop, progress.
    f.modeSeg = W.Segmented(f, {
        { key = "deals", label = "Deals" },
        { key = "watch", label = "Watch list" },
    }, function(key) f:SetMode(key) end, 72)
    f.modeSeg:SetPoint("TOPLEFT")
    f.runBtn = W.Button(f, "Start watching", 110, function()
        if D.running then D.Stop() else D.Start() end
    end, true)
    f.runBtn:SetPoint("LEFT", f.modeSeg, "RIGHT", 8, 0)
    f.progress = W.Text(f, "mutedSm", "")
    f.progress:SetPoint("LEFT", f.runBtn, "RIGHT", 10, 0)
    f.progress:SetPoint("RIGHT")
    f.progress:SetJustifyH("LEFT")
    f.progress:SetWordWrap(false)

    ---------------------------------------------------------------------------
    -- Deals list
    ---------------------------------------------------------------------------
    local deals = W.List(f, {
        { title = "Item", get = function(d) return Icon(d.id) .. Name(d.id) end, sortValue = function(d) return Name(d.id):lower() end },
        { title = "Each", width = 62, align = "RIGHT", get = function(d) return U.FormatGoldShort(d.unit) end, sortValue = function(d) return d.unit end },
        { title = "Usual", width = 58, align = "RIGHT", get = function(d)
            return d.usual and U.FormatGoldShort(d.usual) or "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(d) return d.usual or 0 end },
        { title = "Off", width = 44, align = "RIGHT", get = function(d)
            if not d.off then return "-" end
            return ("%d%%"):format(math.floor(d.off * 100 + 0.5)), GREEN[1], GREEN[2], GREEN[3]
        end, sortValue = function(d) return d.off or 0 end },
        { title = "Qty", width = 40, align = "RIGHT", get = function(d) return d.qty end, sortValue = function(d) return d.qty end },
        { title = "Resale", width = 62, align = "RIGHT", get = function(d)
            if not d.profit then return "-", T.muted[1], T.muted[2], T.muted[3] end
            local c = d.profit >= 0 and GREEN or { 1, 0.38, 0.38 }
            return (d.profit >= 0 and "+" or "-") .. U.FormatGoldShort(math.abs(d.profit)), c[1], c[2], c[3]
        end, sortValue = function(d) return d.profit or -math.huge end },
    }, 20)
    deals:SetPoint("TOPLEFT", 0, -32)
    deals:SetPoint("BOTTOMRIGHT", 0, 44)
    deals.sortCol, deals.sortDesc = 4, true
    deals.empty:SetText("No deals yet. Click Start watching (it checks your watch list over and over).")
    deals.onClick = function(d)
        f.selected = d.id
        f:ResetBuy()
    end
    deals.isSelected = function(d) return d.id == f.selected end
    deals.onEnter = function(row, d)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, d.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Cheapest", U.FormatMoney(d.unit) .. " each", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Your limit", U.FormatMoney(d.threshold) .. " each", 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Under your limit", ("%d for %s"):format(d.qty, U.FormatMoney(d.cost)), 1, 0.82, 0, 1, 1, 1)
        if d.usual then GameTooltip:AddDoubleLine("Usual price", U.FormatMoney(d.usual), 1, 0.82, 0, 1, 1, 1) end
        if d.profit then
            GameTooltip:AddDoubleLine("Resell at usual (after cut)", (d.profit >= 0 and "+" or "-") .. U.FormatMoney(math.abs(d.profit)) .. " each",
                1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddLine(("Seen %s"):format(U.Ago(d.t)), 0.55, 0.58, 0.64)
        GameTooltip:Show()
    end
    f.deals = deals

    ---------------------------------------------------------------------------
    -- Watch list
    ---------------------------------------------------------------------------
    local watch = W.List(f, {
        { title = "Item", get = function(r) return Icon(r.id) .. Name(r.id) end, sortValue = function(r) return Name(r.id):lower() end },
        { title = "Limit", width = 96, align = "RIGHT", get = function(r)
            local thr, how, pct = D.Threshold(r.id)
            if not thr then return "no price yet", T.muted[1], T.muted[2], T.muted[3] end
            if how == "max" then return U.FormatGoldShort(thr) .. " max" end
            return ("%s (%d%%)"):format(U.FormatGoldShort(thr), math.floor(pct * 100 + 0.5))
        end },
        { title = "Usual", width = 58, align = "RIGHT", get = function(r)
            local u = D.Usual(r.id)
            return u and U.FormatGoldShort(u) or "-", T.muted[1], T.muted[2], T.muted[3]
        end },
        { title = "From", width = 70, get = function(r) return r.from, T.muted[1], T.muted[2], T.muted[3] end,
          sortValue = function(r) return r.from end },
    }, 20)
    watch:SetPoint("TOPLEFT", 0, -32)
    watch:SetPoint("BOTTOMRIGHT", 0, 44)
    watch.empty:SetText("Nothing watched. On the Buy tab, select an item and click Watch.")
    watch.onClick = function(r)
        f.watchSel = r.id
        local w = D.Watch()[r.id]
        f.maxInput:SetValue(w and w.max or 0)
        f.pctBox:SetText(w and w.pct and tostring(math.floor(w.pct * 100 + 0.5)) or "")
        f:UpdateWatchButtons()
    end
    watch.isSelected = function(r) return r.id == f.watchSel end
    f.watch = watch

    -- Watch editing row: max price or %, Save, Remove.
    local edit = CreateFrame("Frame", nil, f)
    edit:SetPoint("BOTTOMLEFT")
    edit:SetPoint("BOTTOMRIGHT")
    edit:SetHeight(34)
    local maxLabel = W.Text(edit, "label", "MAX")
    maxLabel:SetPoint("LEFT", 0, 0)
    f.maxInput = W.MoneyInput(edit)
    f.maxInput:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0)
    local orLabel = W.Text(edit, "label", "OR %")
    orLabel:SetPoint("LEFT", f.maxInput, "RIGHT", 14, 0)
    f.pctBox = W.EditBox(edit, 40, true)
    f.pctBox:SetMaxLetters(2)
    f.pctBox:SetPoint("LEFT", orLabel, "RIGHT", 6, 0)
    f.removeBtn = W.Button(edit, "Remove", 70, function()
        if f.watchSel then D.RemoveWatch(f.watchSel) f.watchSel = nil f:Refresh() end
    end)
    f.removeBtn:SetPoint("RIGHT")
    f.saveBtn = W.Button(edit, "Save", 60, function()
        local id = f.watchSel
        if not id then return end
        D.AddWatch(id)
        local w = D.Watch()[id]
        local max = f.maxInput:GetValue()
        local pct = tonumber(f.pctBox:GetText())
        w.max = max > 0 and max or nil
        w.pct = pct and pct > 0 and pct / 100 or nil
        D.found[id] = nil
        setStatus(("Watching %s: %s"):format(Name(id), w.max and ("max " .. U.FormatMoney(w.max))
            or ("%d%% of usual"):format(math.floor((w.pct or ns.db.settings.dealsPct) * 100 + 0.5))))
        f:Refresh()
    end, true)
    f.saveBtn:SetPoint("RIGHT", f.removeBtn, "LEFT", -6, 0)
    f.edit = edit

    function f:UpdateWatchButtons()
        local id = self.watchSel
        self.saveBtn:SetEnabled(id ~= nil)
        self.removeBtn:SetEnabled(id ~= nil and D.IsWatched(id))
    end

    ---------------------------------------------------------------------------
    -- Buy button
    ---------------------------------------------------------------------------
    f.buyBtn = W.Button(f, "Select a deal", 100, function() f:OnBuyClick() end, true)
    f.buyBtn:SetPoint("BOTTOMLEFT")
    f.buyBtn:SetPoint("BOTTOMRIGHT")
    f.buyBtn:SetHeight(34)

    local function Current()
        local d = f.selected and D.found[f.selected]
        if not d then
            d = D.List()[1]
            f.selected = d and d.id
        end
        return d
    end

    function f:ResetBuy()
        self.stage, self.quote = nil, nil
        self:UpdateBuy()
    end

    function f:UpdateBuy()
        local d = Current()
        local b = self.buyBtn
        if not d then
            b:SetText("No deal selected")
            b:Disable()
            return
        end
        b:Enable()
        local name = Name(d.id)
        if self.stage == "pricing" then
            b:SetText("Getting price...")
            b:Disable()
        elseif self.stage == "confirm" and self.quote then
            b:SetText(("Confirm: buy %d %s for %s (%s each)"):format(self.quote.qty, name,
                U.FormatMoney(self.quote.total), U.FormatMoney(self.quote.unit)))
        elseif self.stage == "armed" then
            b:SetText(("Click again to buy %s for %s"):format(name, U.FormatMoney(d.auctionPrice or d.unit)))
        elseif self.stage == "buying" then
            b:SetText("Buying...")
            b:Disable()
        elseif d.commodity then
            b:SetText(("Buy %d %s at up to %s each"):format(d.qty, name, U.FormatMoney(d.threshold)))
        else
            b:SetText(("Buy %s for %s"):format(name, U.FormatMoney(d.auctionPrice or d.unit)))
        end
    end

    local function After(msg)
        local d = f.selected and D.found[f.selected]
        setStatus(msg)
        f.stage, f.quote = nil, nil
        if d then
            D.found[d.id] = nil
            -- Look again: there may be more under the limit.
            C_Timer.After(0.5, function()
                local ok, key = pcall(AH.MakeItemKey, d.id)
                if ok and key then ns.AHScan.Search(key) end
            end)
        end
        f:Refresh()
    end

    function f:OnBuyClick()
        local d = Current()
        if not d then return end
        local ok, err
        if d.commodity then
            if self.stage == "confirm" and self.quote then
                self.stage = "buying"
                ok, err = pcall(AH.ConfirmCommoditiesPurchase, d.id, self.quote.qty)
            else
                self.stage, self.pendingQty = "pricing", d.qty
                ok, err = pcall(AH.StartCommoditiesPurchase, d.id, d.qty)
                C_Timer.After(10, function()
                    if f.stage == "pricing" then
                        f.stage = nil
                        setStatus("|cffff9933No price quote from the server. Try again.|r")
                        f:UpdateBuy()
                    end
                end)
            end
        else
            if not d.auctionID then return end
            if self.stage ~= "armed" then
                self.stage = "armed"
                self:UpdateBuy()
                return
            end
            self.stage = "buying"
            ns.AuctionHouse.nextBidLabel = "Buyout: " .. Name(d.id)
            ok, err = pcall(AH.PlaceBid, d.auctionID, d.auctionPrice)
            if not ok then ns.AuctionHouse.nextBidLabel = nil end
        end
        if not ok then
            self.stage = nil
            setStatus("|cffff6060Purchase failed: " .. tostring(err) .. "|r")
        elseif self.stage == "buying" then
            setStatus("Buying...")
            C_Timer.After(6, function() if f.stage == "buying" then After("Purchase sent. Check your mailbox.") end end)
        end
        self:UpdateBuy()
    end

    -- Purchase events (only while this page is mid-purchase; the Buy tab has its own).
    ns:On("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
        if f.stage ~= "pricing" then return end
        local d = Current()
        if d and unitPrice and unitPrice > d.threshold then
            -- Someone bought the cheap ones first: don't pay more than your limit.
            f.stage = nil -- the quote just lapses; nothing is bought without a confirm click
            setStatus(("|cffff9933Price is now %s each, above your limit of %s. Not bought.|r"):format(
                U.FormatMoney(unitPrice), U.FormatMoney(d.threshold)))
            D.found[d.id] = nil
            f:Refresh()
            return
        end
        f.stage = "confirm"
        f.quote = { unit = unitPrice, total = totalPrice, qty = f.pendingQty }
        setStatus("Price quoted. Click again to confirm.")
        f:UpdateBuy()
    end)
    ns:On("COMMODITY_PRICE_UNAVAILABLE", function()
        if f.stage ~= "pricing" then return end
        After("|cffff6060That quantity is no longer available at that price.|r")
    end)
    ns:On("COMMODITY_PURCHASE_SUCCEEDED", function() if f.stage == "buying" then After("|cff60ff60Bought.|r") end end)
    ns:On("COMMODITY_PURCHASE_FAILED", function() if f.stage == "buying" then After("|cffff6060Purchase failed.|r") end end)
    ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function()
        if f.stage == "buying" then After("|cff60ff60Bought. The item is on its way by mail.|r") end
    end)
    ns:On("AUCTION_HOUSE_SHOW_ERROR", function() if f.stage == "buying" then After("|cffff6060The purchase failed.|r") end end)

    -- The scanner waits while a purchase is in progress here or on the Buy tab.
    D.paused = function()
        return f.stage ~= nil or (UI.AHBuyBusy and UI.AHBuyBusy()) or false
    end

    ---------------------------------------------------------------------------
    -- Refresh
    ---------------------------------------------------------------------------
    function f:SetMode(key)
        self.mode = key
        self.modeSeg:SetValue(key)
        local isDeals = key == "deals"
        self.deals:SetShown(isDeals)
        self.buyBtn:SetShown(isDeals)
        self.watch:SetShown(not isDeals)
        self.edit:SetShown(not isDeals)
        self:Refresh()
    end

    function f:RefreshProgress()
        self.runBtn:SetText(D.running and "Stop" or "Start watching")
        local p = D.progress
        if D.running then
            self.progress:SetText(("Checking %d / %d%s"):format(p.i, p.n,
                p.cycle and ("   |cff8c94a3full cycle ~%ds|r"):format(math.floor(p.cycle + 0.5)) or ""))
        elseif D.stopMsg then
            self.progress:SetText("|cffff9933" .. D.stopMsg .. "|r")
        else
            local n = #(D.Targets())
            self.progress:SetText(("%d items to watch   |cff8c94a3one search every ~1s, buying is always your click|r"):format(n))
        end
    end

    function f:Refresh()
        if self.mode == "deals" then
            self.deals:SetData(D.List())
            self:UpdateBuy()
        else
            local rows = {}
            local s = ns.db.settings
            local set = {}
            for id in pairs(D.Watch()) do rows[#rows + 1] = { id = id, from = "Watched" } set[id] = true end
            if s.dealsFavorites then
                for id in pairs(ns.Prices.Favorites()) do
                    if not set[id] then rows[#rows + 1] = { id = id, from = "Favorite" } set[id] = true end
                end
            end
            if s.dealsShopping then
                for _, r in ipairs((ns.Crafting.ShoppingRows())) do
                    if r.remaining > 0 and not set[r.id] then rows[#rows + 1] = { id = r.id, from = "Shopping" } set[r.id] = true end
                end
            end
            self.watch:SetData(rows)
            self:UpdateWatchButtons()
        end
        self:RefreshProgress()
    end

    ns:Register("DEALS_UPDATED", function() if f:IsVisible() then f:Refresh() end end)
    ns:Register("DEALS_PROGRESS", function() if f:IsVisible() then f:RefreshProgress() end end)
    f:SetScript("OnShow", function(self) self:Refresh() end)
    f:SetMode("deals")
    return f
end
