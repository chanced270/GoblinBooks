-- AH panel "Auctions" page. Selling: your auctions with undercut status, a price check, and cancel.
-- Bids: auctions you've bid on, winning/outbid, and a one-click minimum re-bid.
local _, ns = ...
local UI, W, U, P, S = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.AHScan
local T = W.Theme
local AH = C_AuctionHouse

local SOLD = 1 -- Enum.AuctionStatus.Sold
local CHECK_INTERVAL = 1.2
local GREEN, RED, ORANGE = { 0.38, 1, 0.38 }, { 1, 0.38, 0.38 }, { 1, 0.6, 0.2 }

local function TimeLeft(sec)
    if not sec then return "?" end
    if sec >= 3600 then return ("%dh"):format(math.floor(sec / 3600)) end
    return ("%dm"):format(math.max(1, math.floor(sec / 60)))
end

local function Icon(itemID)
    if not (C_Item and C_Item.GetItemIconByID) then return "" end
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    return ok and icon and ("|T%s:16:16:0:0|t  "):format(icon) or ""
end

local function ItemText(r)
    local a = r.a
    local name = a.itemLink and a.itemLink:gsub("|H.-|h(.-)|h", "%1"):gsub("%[(.-)%]", "%1")
        or U.ItemName(r.itemID) or ("item:" .. r.itemID)
    local qty = (a.quantity or 1) > 1 and ("  |cff8c94a3x%d|r"):format(a.quantity) or ""
    return Icon(r.itemID) .. name .. qty
end

--- Price per item. Listed auctions report a per-item price; sold ones report the whole sale's total.
local function Price(r)
    local amount = r.a.buyoutAmount or r.a.bidAmount or 0
    if r.a.status == SOLD then return amount / math.max(1, r.a.quantity or 1) end
    return amount
end

local CB = ns.CostBasis

--- If this auction sells at its price: what you keep after the AH cut, minus what the items cost you
--- (average of your recorded cost lots). Deposits aren't counted: a sale refunds them.
--- Returns profit, proceeds, cost, costKnown.
local function PL(r)
    local qty = r.a.quantity or 1
    local proceeds = Price(r) * qty * (1 - CB.CutRate(ns.db))
    local held, value = 0, 0
    if ns.char then held, value = CB.Holdings(ns.char, r.itemID) end
    if held and held > 0 then
        local cost = value / held * qty
        return proceeds - cost, proceeds, cost, true
    end
    return proceeds, proceeds, 0, false
end

local function PLText(r)
    local profit, _, _, known = PL(r)
    local text = (profit >= 0 and "+" or "-") .. U.FormatGoldShort(math.abs(profit))
    if not known then return text .. "*", T.muted[1], T.muted[2], T.muted[3] end
    local c = profit >= 0 and GREEN or RED
    return text, c[1], c[2], c[3]
end

--- The pending sale for a sold row (its gold on the way to the mailbox).
local function Pending(r)
    local c = ns.char
    return c and c.pendingSales and c.pendingSales[r.id]
end

--- "Sold · 42m" until the gold should be in the mailbox, then "Sold · in mail".
local function SoldLabel(r)
    local p = Pending(r)
    if not p then return "Sold" end
    local left = p.eta - time()
    if left <= 0 then return "Sold · in mail" end
    return "Sold · " .. TimeLeft(left)
end

--- Status label, color, the competing price, and a sort rank (higher = needs attention).
local function State(r)
    if r.a.status == SOLD then return SoldLabel(r), GREEN, nil, 0 end
    local price = Price(r)
    local c = S.competitor[r.itemID]
    if c then
        if not c.p then return "Lowest", GREEN, nil, 1 end
        if c.p < price then return "Undercut", RED, c.p, 4 end
        if c.p == price then return "Tied", ORANGE, c.p, 3 end
        return "Lowest", GREEN, c.p, 1
    end
    local e = P.Get(r.itemID)
    if e and e.p < price then return "Undercut?", ORANGE, e.p, 2 end
    return "Unchecked", T.muted, e and e.p, 1
end

local function Owned()
    local out = {}
    if not (AH and AH.GetNumOwnedAuctions) then return out end
    for i = 1, AH.GetNumOwnedAuctions() or 0 do
        local a = AH.GetOwnedAuctionInfo(i)
        if a and a.itemKey and a.itemKey.itemID then
            out[#out + 1] = { a = a, itemID = a.itemKey.itemID, id = a.auctionID }
        end
    end
    return out
end

function UI.CreateAHAuctions(parent, setStatus, onCount)
    local f = CreateFrame("Frame", nil, parent)

    f.modeSeg = W.Segmented(f, {
        { key = "selling", label = "Selling" },
        { key = "bids", label = "Bids" },
    }, function(key) f:SetMode(key) end, 58)
    f.modeSeg:SetPoint("TOPLEFT")
    f.checkBtn = W.Button(f, "Check prices", 100, function() f:CheckPrices() end, true)
    f.checkBtn:SetPoint("LEFT", f.modeSeg, "RIGHT", 6, 0)
    f.checkBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Check prices")
        GameTooltip:AddLine("Searches each item you have listed to find the cheapest auction that isn't yours.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.checkBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.countFS = W.Text(f, "mutedSm")
    f.countFS:SetPoint("LEFT", f.modeSeg, "RIGHT", 116, 0)
    f.countFS:SetPoint("RIGHT")
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local columns = {
        { title = "Item", get = ItemText, sortValue = function(r) return (U.ItemName(r.itemID) or ""):lower() end },
        { title = "Yours", width = 58, align = "RIGHT", get = function(r) return U.FormatGoldShort(Price(r)) end,
          sortValue = Price },
        { title = "Lowest", width = 58, align = "RIGHT", get = function(r)
            local _, _, other = State(r)
            if not other then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return U.FormatGoldShort(other)
        end, sortValue = function(r) local _, _, other = State(r) return other or 0 end },
        { title = "P/L", width = 62, align = "RIGHT", get = PLText, sortValue = function(r) return (PL(r)) end },
        { title = "Status", width = 86, get = function(r)
            local label, c = State(r)
            return label, c[1], c[2], c[3]
        end, sortValue = function(r) local _, _, _, rank = State(r) return rank end },
    }
    local list = W.List(f, columns, 20)
    list:SetPoint("TOPLEFT", 0, -32)
    list:SetPoint("BOTTOMRIGHT", 0, 38)
    list.sortCol, list.sortDesc = 5, true
    list.empty:SetText("You have no auctions listed")
    list.onEnter = function(row, r)
        local a = r.a
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        if a.itemLink then GameTooltip:SetHyperlink(a.itemLink) else pcall(GameTooltip.SetItemByID, GameTooltip, r.itemID) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Your price (each)", U.FormatMoney(Price(r)), 1, 0.82, 0, 1, 1, 1)
        local label, c, other = State(r)
        if other then GameTooltip:AddDoubleLine("Lowest other", U.FormatMoney(other), 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:AddDoubleLine("Status", label, 1, 0.82, 0, c[1], c[2], c[3])
        local profit, proceeds, cost, known = PL(r)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(("If it sells, you keep (%s cut)"):format(CB.CutLabel(CB.CutRate(ns.db))),
            U.FormatMoney(proceeds), 1, 0.82, 0, 1, 1, 1)
        if known then
            GameTooltip:AddDoubleLine("Your cost", ("%s  |cff8c94a3(%s each)|r"):format(U.FormatMoney(cost),
                U.FormatMoney(cost / (a.quantity or 1))), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine(profit >= 0 and "Profit" or "Loss", U.FormatMoney(math.abs(profit)), 1, 0.82, 0,
                profit >= 0 and 0.38 or 1, profit >= 0 and 1 or 0.38, 0.38)
        else
            GameTooltip:AddLine("* No recorded cost (looted, crafted, or bought before GoblinBooks), so it counts as free.", 0.55, 0.58, 0.64, true)
        end
        GameTooltip:AddLine("Deposits aren't counted: a sale refunds them.", 0.55, 0.58, 0.64, true)
        if a.status ~= SOLD then GameTooltip:AddDoubleLine("Time left", TimeLeft(a.timeLeftSeconds), 1, 0.82, 0, 1, 1, 1) end
        local p = a.status == SOLD and Pending(r)
        if p then
            local left = p.eta - time()
            GameTooltip:AddDoubleLine("Gold to mailbox", left > 0 and ("in %s (about %s)"):format(TimeLeft(left), date("%H:%M", p.eta))
                or "should be there now", 1, 0.82, 0, 0.38, 1, 0.38)
            if not p.exact then
                local _, n = ns.AuctionHouse:MailDelay()
                GameTooltip:AddLine(n > 0 and ("Estimated from your last %d sale mails."):format(n)
                    or "Estimated (1 hour until GoblinBooks learns the real delay from your sale mails).", 0.55, 0.58, 0.64, true)
            end
        end
        local checked = S.competitor[r.itemID]
        GameTooltip:AddLine(checked and ("Checked " .. U.Ago(checked.t)) or "Not checked this session", 0.55, 0.58, 0.64)
        GameTooltip:Show()
    end
    list.onClick = function(r)
        f.selected = r.id
        f.confirmCancel = false
        f:UpdateCancel()
    end
    list.isSelected = function(r) return r.id == f.selected end
    f.list = list

    f.cancelBtn = W.Button(f, "Cancel selected auction", 100, function() f:Cancel() end)
    f.cancelBtn:SetHeight(30)
    f.cancelBtn:SetPoint("BOTTOMLEFT")
    f.cancelBtn:SetPoint("BOTTOMRIGHT")

    -----------------------------------------------------------------------
    -- Bids
    -----------------------------------------------------------------------
    local function Winning(r)
        local me = UnitGUID and UnitGUID("player")
        return me ~= nil and r.a.bidder == me
    end
    local bidList = W.List(f, {
        { title = "Item", get = ItemText, sortValue = function(r) return (U.ItemName(r.itemID) or ""):lower() end },
        { title = "High bid", width = 62, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.a.bidAmount or 0) end,
          sortValue = function(r) return r.a.bidAmount or 0 end },
        { title = "Buyout", width = 58, align = "RIGHT", get = function(r)
            if (r.a.buyoutAmount or 0) <= 0 then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return U.FormatGoldShort(r.a.buyoutAmount)
        end, sortValue = function(r) return r.a.buyoutAmount or 0 end },
        { title = "Status", width = 60, get = function(r)
            if Winning(r) then return "Winning", GREEN[1], GREEN[2], GREEN[3] end
            return "Outbid", RED[1], RED[2], RED[3]
        end, sortValue = function(r) return Winning(r) and 0 or 1 end },
    }, 20)
    bidList:SetPoint("TOPLEFT", 0, -32)
    bidList:SetPoint("BOTTOMRIGHT", 0, 38)
    bidList.sortCol, bidList.sortDesc = 4, true
    bidList.empty:SetText("You have no active bids")
    bidList.onEnter = function(row, r)
        local a = r.a
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        if a.itemLink then GameTooltip:SetHyperlink(a.itemLink) else pcall(GameTooltip.SetItemByID, GameTooltip, r.itemID) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("High bid", U.FormatMoney(a.bidAmount or 0), 1, 0.82, 0, 1, 1, 1)
        if a.minBid then GameTooltip:AddDoubleLine("Minimum next bid", U.FormatMoney(a.minBid), 1, 0.82, 0, 1, 1, 1) end
        if (a.buyoutAmount or 0) > 0 then GameTooltip:AddDoubleLine("Buyout", U.FormatMoney(a.buyoutAmount), 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:AddLine(Winning(r) and "You are the high bidder" or "You have been outbid",
            Winning(r) and 0.38 or 1, Winning(r) and 1 or 0.38, 0.38)
        GameTooltip:Show()
    end
    bidList.onClick = function(r)
        f.bidSelected = r.id
        f.confirmBid = false
        f:UpdateRebid()
    end
    bidList.isSelected = function(r) return r.id == f.bidSelected end
    bidList:Hide()
    f.bidList = bidList

    f.rebidBtn = W.Button(f, "Select an outbid auction", 100, function() f:Rebid() end, true)
    f.rebidBtn:SetHeight(30)
    f.rebidBtn:SetPoint("BOTTOMLEFT")
    f.rebidBtn:SetPoint("BOTTOMRIGHT")
    f.rebidBtn:Hide()

    function f:SelectedBid()
        for _, r in ipairs(self.bidRows or {}) do if r.id == self.bidSelected then return r end end
    end

    function f:UpdateRebid()
        local r = self:SelectedBid()
        local btn = self.rebidBtn
        if not r then
            btn:SetText("Select an outbid auction")
            btn:Disable()
        elseif Winning(r) then
            btn:SetText("You're the high bidder")
            btn:Disable()
        elseif not r.a.minBid then
            btn:SetText("Bidding unavailable")
            btn:Disable()
        elseif GetMoney() < r.a.minBid then
            btn:SetText("Not enough gold to re-bid")
            btn:Disable()
        else
            btn:SetText(self.confirmBid and ("Confirm bid of %s"):format(U.FormatMoney(r.a.minBid))
                or ("Bid the minimum: %s"):format(U.FormatMoney(r.a.minBid)))
            btn:Enable()
        end
    end

    function f:Rebid()
        local r = self:SelectedBid()
        if not r or Winning(r) or not r.a.minBid then return end
        if not self.confirmBid then
            self.confirmBid = true
            self:UpdateRebid()
            return
        end
        self.confirmBid = false
        ns.AuctionHouse.nextBidLabel = "Bid: " .. (U.ItemName(r.itemID) or "item")
        local ok, err = pcall(AH.PlaceBid, r.id, r.a.minBid)
        if not ok then ns.AuctionHouse.nextBidLabel = nil end
        setStatus(ok and "Placing bid..." or ("|cffff6060Bid failed: " .. tostring(err) .. "|r"))
        C_Timer.After(1, function() f:QueryBids() end)
        self:UpdateRebid()
    end

    function f:QueryBids()
        if AH and AH.QueryBids then pcall(AH.QueryBids, {}, {}) end
    end

    function f:RebuildBids()
        local rows = {}
        if AH and AH.GetNumBids then
            for i = 1, AH.GetNumBids() or 0 do
                local a = AH.GetBidInfo(i)
                if a and a.itemKey and a.itemKey.itemID then
                    rows[#rows + 1] = { a = a, itemID = a.itemKey.itemID, id = a.auctionID }
                end
            end
        end
        self.bidRows = rows
        bidList:SetData(rows)
        self:UpdateModeSwitch()
        local outbid = 0
        for _, r in ipairs(rows) do if not Winning(r) then outbid = outbid + 1 end end
        self.outbid = outbid
        if self.mode == "bids" then
            self.countFS:SetText(("%d bids%s"):format(#rows, outbid > 0 and ("   |cffff6060%d outbid|r"):format(outbid) or ""))
        end
        self:ReportCount()
        self:UpdateRebid()
    end

    function f:ReportCount()
        if onCount then onCount((self.undercut or 0) + (self.outbid or 0)) end
    end

    --- Hide the Selling | Bids switch when there are no bids (most auctions are buyout-only).
    function f:UpdateModeSwitch()
        local show = #(self.bidRows or {}) > 0 or self.mode == "bids"
        self.modeSeg:SetShown(show)
        self.checkBtn:ClearAllPoints()
        if show then
            self.checkBtn:SetPoint("LEFT", self.modeSeg, "RIGHT", 6, 0)
        else
            self.checkBtn:SetPoint("TOPLEFT")
        end
        self.countFS:ClearAllPoints()
        self.countFS:SetPoint("LEFT", self.checkBtn, "RIGHT", 10, 0)
        self.countFS:SetPoint("RIGHT")
    end

    function f:SetMode(key)
        self.mode = key
        self.modeSeg:SetValue(key)
        local selling = key == "selling"
        list:SetShown(selling)
        self.checkBtn:SetShown(selling)
        self.cancelBtn:SetShown(selling)
        bidList:SetShown(not selling)
        self.rebidBtn:SetShown(not selling)
        if selling then self:Query() else self:QueryBids() end
    end

    function f:SelectedRow()
        for _, r in ipairs(self.rows or {}) do if r.id == self.selected then return r end end
    end

    function f:UpdateCancel()
        local r = self:SelectedRow()
        local can = r and r.a.status ~= SOLD
        if can and AH.CanCancelAuction then
            local ok, res = pcall(AH.CanCancelAuction, r.id)
            can = ok and res
        end
        self.cancelBtn:SetEnabled(can and true or false)
        self.cancelBtn:SetText(self.confirmCancel and "Click again to cancel (deposit is not refunded)" or "Cancel selected auction")
    end

    function f:Cancel()
        local r = self:SelectedRow()
        if not r or not AH.CancelAuction then return end
        if not self.confirmCancel then
            self.confirmCancel = true
            self:UpdateCancel()
            return
        end
        self.confirmCancel = false
        local ok, err = pcall(AH.CancelAuction, r.id)
        setStatus(ok and "Cancelling auction..." or ("|cffff6060Cancel failed: " .. tostring(err) .. "|r"))
        self:UpdateCancel()
    end

    function f:Query()
        if AH and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {}) end
    end

    function f:Rebuild()
        self.rows = Owned()
        list:SetData(self.rows)
        local active, undercut, total = 0, 0, 0
        for _, r in ipairs(self.rows) do
            if r.a.status ~= SOLD then active = active + 1 end
            total = total + (PL(r))
            local _, _, _, rank = State(r)
            if rank >= 3 then undercut = undercut + 1 end
        end
        if not self.checking and self.mode ~= "bids" then
            local plText = #self.rows > 0 and ("   %sP/L if all sell %s%s|r"):format(total >= 0 and "|cff60ff60" or "|cffff6060",
                total >= 0 and "+" or "-", U.FormatGoldShort(math.abs(total))) or ""
            self.countFS:SetText(("%d active%s%s"):format(active,
                undercut > 0 and ("   |cffff6060%d undercut|r"):format(undercut) or "", plText))
        end
        self.undercut = undercut
        self:ReportCount()
        self:UpdateCancel()
    end

    -- Search each listed item in turn (the server throttles rapid searches).
    function f:CheckPrices()
        if self.checking then return end
        local queue, seen = {}, {}
        for _, r in ipairs(self.rows or {}) do
            if r.a.status ~= SOLD and not seen[r.itemID] then
                seen[r.itemID] = true
                queue[#queue + 1] = r.a.itemKey
            end
        end
        if #queue == 0 then
            setStatus("Nothing to check.")
            return
        end
        self.checking = true
        self.checkBtn:Disable()
        local i = 0
        local function Step()
            i = i + 1
            if i > #queue or not f:IsVisible() then
                f.checking = false
                f.checkBtn:Enable()
                setStatus(i > #queue and "|cff60ff60Price check complete.|r" or "Price check stopped.")
                f:Rebuild()
                return
            end
            f.countFS:SetText(("Checking %d / %d..."):format(i, #queue))
            S.Search(queue[i])
            C_Timer.After(CHECK_INTERVAL, Step)
        end
        Step()
    end

    ns:On("OWNED_AUCTIONS_UPDATED", function() f:Rebuild() end)
    ns:On("AUCTION_CANCELED", function()
        setStatus("|cff60ff60Auction cancelled. The item is on its way by mail.|r")
        f.selected = nil
        f:Query()
    end)
    -- Refresh your auctions once you've stopped posting (a moment after the last post).
    local postToken = 0
    ns:On("AUCTION_HOUSE_AUCTION_CREATED", function()
        postToken = postToken + 1
        local token = postToken
        C_Timer.After(2.5, function() if token == postToken then f:Query() end end)
    end)
    ns:Register("AH_SEARCH_RESULTS", function()
        if f:IsVisible() then list:Refresh() end
        if not f.checking and f.rows then f:Rebuild() end
    end)

    ns:On("BIDS_UPDATED", function() f:RebuildBids() end)
    ns:On("BID_ADDED", function() C_Timer.After(0.5, function() f:QueryBids() end) end)

    f.mode = "selling"
    f.modeSeg:SetValue("selling")
    f:UpdateModeSwitch()
    f:SetScript("OnShow", function() f:SetMode(f.mode or "selling") end)
    return f
end
