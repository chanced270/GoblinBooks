-- Price chart for one item, with two views:
--   History:  daily AH lows over 14/30/60 days as a line with hover points, plus average and vendor lines.
--   Listings: the cheapest current listings (price ladder), cheapest first, with quantities on hover.
-- UI.CreatePriceChart(parent, { listings = true }) adds the Listings view (AH panel); the Prices tab uses History only.
local _, ns = ...
local UI, W, U, P = ns.UI, ns.Widgets, ns.Util, ns.Prices
local T = W.Theme

local RANGES = { { key = 14, label = "14d" }, { key = 30, label = "30d" }, { key = 60, label = "60d" } }
local VIEWS = { { key = "history", label = "History" }, { key = "listings", label = "Listings" } }
local MAX_BARS = 24

local function Pool(create)
    local pool = { items = {}, used = 0 }
    function pool:Acquire()
        self.used = self.used + 1
        local item = self.items[self.used]
        if not item then
            item = create()
            self.items[self.used] = item
        end
        item:Show()
        return item
    end
    function pool:ReleaseAll()
        for _, item in ipairs(self.items) do item:Hide() end
        self.used = 0
    end
    return pool
end

local function VendorPrice(itemID)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(fn, itemID)
    return ok and sellPrice or nil
end

function UI.CreatePriceChart(parent, opts)
    local f = W.Panel(parent)
    f.days = 30
    f.view = "history" -- time chart by default; Listings (price ladder) is an optional view in the AH panel

    f.title = W.Text(f, "heading", "Select an item to see its price history")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetPoint("RIGHT", (opts and opts.listings) and -300 or -170, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.range = W.Segmented(f, RANGES, function(days)
        f.days = days
        f:Render()
    end, 46)
    f.range:SetPoint("TOPRIGHT", -12, -8)
    f.range:SetValue(f.days)
    if opts and opts.listings then
        f.viewSeg = W.Segmented(f, VIEWS, function(view)
            f.view = view
            f:Render()
        end, 62)
        f.viewSeg:SetPoint("RIGHT", f.range, "LEFT", -8, 0)
    end
    f.stats = W.Text(f, "mutedSm", "")
    f.stats:SetPoint("TOPLEFT", 14, -34)
    f.stats:SetPoint("RIGHT", -12, 0)
    f.stats:SetJustifyH("LEFT")
    f.stats:SetWordWrap(false)

    local plot = CreateFrame("Frame", nil, f)
    plot:SetPoint("TOPLEFT", 62, -58)
    plot:SetPoint("BOTTOMRIGHT", -16, 26)
    f.plot = plot
    f.empty = W.Text(plot, "muted", "")
    f.empty:SetPoint("CENTER")

    local canLine = plot.CreateLine ~= nil
    f.grid = Pool(function()
        local t = plot:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 0.06)
        t:SetHeight(1)
        return t
    end)
    f.yLabels = Pool(function()
        local fs = W.Text(f, "mutedSm")
        fs:SetJustifyH("RIGHT")
        fs:SetWidth(56)
        return fs
    end)
    f.xLabels = Pool(function() return W.Text(f, "mutedSm") end)
    f.segments = Pool(function()
        if canLine then
            local l = plot:CreateLine(nil, "ARTWORK")
            l:SetThickness(2)
            return l
        end
        local t = plot:CreateTexture(nil, "ARTWORK") -- fallback: bars
        return t
    end)
    f.refLines = Pool(function()
        local t = plot:CreateTexture(nil, "BORDER")
        t:SetHeight(1)
        return t
    end)
    f.refLabels = Pool(function() return W.Text(plot, "mutedSm") end)
    f.points = Pool(function()
        local b = CreateFrame("Frame", nil, plot)
        b:SetSize(12, 12)
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetSize(6, 6)
        b.dot:SetPoint("CENTER")
        W.SetColor(b.dot, T.accent)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(s)
            s.dot:SetSize(9, 9)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.day, 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Lowest buyout", U.FormatMoney(s.value), 1, 1, 1, 1, 1, 1)
            if s.avg then
                local pct = (s.value - s.avg) / s.avg * 100
                GameTooltip:AddDoubleLine("vs range average", ("%+.0f%%"):format(pct), 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(s)
            s.dot:SetSize(6, 6)
            GameTooltip:Hide()
        end)
        return b
    end)

    f.bars = Pool(function()
        local b = CreateFrame("Frame", nil, plot)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(s)
            s.tex:SetAlpha(1)
            local l = s.listing
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("Listing #%d%s"):format(s.rank, l.mine and "  (yours)" or ""), 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Price each", U.FormatMoney(l.unit), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Quantity", l.qty, 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Available at or below", s.cumulative, 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(s)
            s.tex:SetAlpha(0.8)
            GameTooltip:Hide()
        end)
        return b
    end)

    f.qtyBars = Pool(function()
        local b = CreateFrame("Frame", nil, plot)
        b:SetFrameLevel(plot:GetFrameLevel())
        b.tex = b:CreateTexture(nil, "BACKGROUND")
        b.tex:SetAllPoints()
        b.tex:SetColorTexture(0.55, 0.8, 1, 0.12)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(s)
            s.tex:SetColorTexture(0.55, 0.8, 1, 0.25)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.day, 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Listed (last count)", s.qty, 1, 1, 1, 1, 1, 1)
            if s.out then GameTooltip:AddDoubleLine("Left the AH (estimate)", s.out, 1, 1, 1, 1, 1, 1) end
            GameTooltip:AddLine("Estimate: includes expired and cancelled auctions.", 0.6, 0.63, 0.68, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(s)
            s.tex:SetColorTexture(0.55, 0.8, 1, 0.12)
            GameTooltip:Hide()
        end)
        return b
    end)

    function f:SetItem(itemID)
        if itemID ~= self.itemID then self.listings = nil end
        self.itemID = itemID
        self:Render()
    end

    --- Current listings for the Listings view: { { unit, qty, mine } } (buyout listings only).
    function f:SetListings(listings)
        self.listings = listings
        self:Render()
    end

    local function ReleaseAll()
        for _, pool in ipairs({ f.grid, f.yLabels, f.xLabels, f.segments, f.refLines, f.refLabels, f.points, f.bars, f.qtyBars }) do
            pool:ReleaseAll()
        end
    end

    -- Shared drawing helpers (set up per render).
    local yMin, yMax, ph
    local function Y(v) return (v - yMin) / (yMax - yMin) * ph end
    local function Grid()
        for g = 0, 3 do
            local v = yMin + (yMax - yMin) * g / 3
            local line = f.grid:Acquire()
            line:ClearAllPoints()
            line:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v))
            line:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, Y(v))
            local label = f.yLabels:Acquire()
            label:ClearAllPoints()
            label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, Y(v))
            label:SetText(U.FormatGoldShort(v))
        end
    end
    local function RefLine(v, color, alpha, text, side)
        if not v or v < yMin or v > yMax then return end
        local t = f.refLines:Acquire()
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, Y(v))
        t:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, Y(v))
        t:SetColorTexture(color[1], color[2], color[3], alpha)
        local fs = f.refLabels:Acquire()
        fs:ClearAllPoints()
        if side == "LEFT" then
            fs:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 2, Y(v) + 2)
        else
            fs:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -2, Y(v) + 2)
        end
        fs:SetText(text)
    end
    local function SetRange(lo, hi)
        local pad = (hi - lo) * 0.12
        if pad == 0 then pad = math.max(1, hi * 0.1) end
        yMin, yMax = math.max(0, lo - pad), hi + pad
    end

    function f:RenderListings()
        local itemID = self.itemID
        local list = {}
        for _, l in ipairs(self.listings or {}) do
            if l.unit then list[#list + 1] = l end
        end
        local e = P.Get(itemID)
        self.title:SetText(e and e.n or U.ItemName(itemID) or ("item:" .. itemID))
        if not self.listings then
            self.stats:SetText("")
            self.empty:SetText("Loading current listings...")
            return
        end
        if #list == 0 then
            self.stats:SetText("")
            self.empty:SetText("Nothing listed with a buyout right now")
            return
        end
        self.empty:SetText("")
        local total = 0
        for _, l in ipairs(list) do total = total + l.qty end
        local shown = math.min(#list, MAX_BARS)
        local lo, hi = list[1].unit, list[1].unit
        for i = 1, shown do lo, hi = math.min(lo, list[i].unit), math.max(hi, list[i].unit) end
        -- Clip outliers: cap the scale at 3x the median of the shown listings (at least 2x the lowest).
        local median = list[math.ceil(shown / 2)].unit
        local cap = math.max(median * 3, lo * 2)
        local clipped = hi > cap
        if clipped then hi = cap end
        local avg = e and P.Average(e, U.DayKeys(7))
        local vendor = VendorPrice(itemID)
        local parts = { ("Lowest %s"):format(U.FormatMoney(lo)), ("%d listings, %d available"):format(#list, total) }
        if avg then parts[#parts + 1] = "7-day avg " .. U.FormatGoldShort(avg) end
        if vendor and vendor > 0 then parts[#parts + 1] = "Vendor " .. U.FormatGoldShort(vendor) end
        if clipped then parts[#parts + 1] = "|cffff6060red = far above the rest|r" end
        self.stats:SetText(table.concat(parts, "   "))

        local pw
        pw, ph = plot:GetWidth(), plot:GetHeight()
        if pw <= 0 or ph <= 0 then return end
        SetRange(lo, hi)
        Grid()
        RefLine(avg, T.text, 0.35, "7-day avg", "RIGHT")
        if vendor and vendor > 0 then RefLine(vendor, { 0.55, 0.8, 1 }, 0.5, "vendor", "LEFT") end
        local slot = pw / shown
        local barW = math.max(2, slot * 0.72)
        local cumulative = 0
        local labelEvery = math.max(1, math.ceil(shown / math.max(1, math.floor(pw / 40))))
        for i = 1, shown do
            local l = list[i]
            cumulative = cumulative + l.qty
            local b = self.bars:Acquire()
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", (i - 1) * slot + (slot - barW) / 2, 0)
            b:SetSize(barW, math.max(2, Y(math.min(l.unit, yMax))))
            if l.unit > cap then
                b.tex:SetColorTexture(1, 0.38, 0.38, 0.8)
            elseif l.mine then
                b.tex:SetColorTexture(0.55, 0.8, 1, 0.8)
            else
                b.tex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.8)
            end
            b.listing, b.rank, b.cumulative = l, i, cumulative
            if (i - 1) % labelEvery == 0 then
                local x = self.xLabels:Acquire()
                x:ClearAllPoints()
                x:SetPoint("TOP", plot, "BOTTOMLEFT", (i - 0.5) * slot, -6)
                x:SetText("x" .. l.qty)
            end
        end
    end

    function f:Render()
        ReleaseAll()
        self.range:SetValue(self.days)
        if self.viewSeg then self.viewSeg:SetValue(self.view) end
        self.range:SetShown(self.view == "history")
        local itemID = self.itemID
        if itemID and self.view == "listings" then return self:RenderListings() end
        if not itemID then
            self.title:SetText("Select an item to see its price history")
            self.stats:SetText("")
            self.empty:SetText("")
            return
        end
        local e = P.Get(itemID)
        self.title:SetText(e and e.n or U.ItemName(itemID) or ("item:" .. itemID))
        local keys = U.DayKeys(self.days)
        local values, lo, hi, sum, n = {}, math.huge, 0, 0, 0
        for i, k in ipairs(keys) do
            local v = e and e.d[k]
            values[i] = v
            if v then lo, hi, sum, n = math.min(lo, v), math.max(hi, v), sum + v, n + 1 end
        end
        local vendor = VendorPrice(itemID)
        if n == 0 then
            self.stats:SetText(vendor and vendor > 0 and ("Vendor %s"):format(U.FormatMoney(vendor)) or "")
            self.empty:SetText(("No AH prices recorded in the last %d days"):format(self.days))
            return
        end
        self.empty:SetText("")
        local avg = sum / n
        local latest = e.p
        local parts = {
            ("Low %s"):format(U.FormatGoldShort(lo)), ("High %s"):format(U.FormatGoldShort(hi)),
            ("Avg %s"):format(U.FormatGoldShort(avg)), ("Latest %s (%s)"):format(U.FormatGoldShort(latest), U.Ago(e.t)),
        }
        if vendor and vendor > 0 then parts[#parts + 1] = "Vendor " .. U.FormatGoldShort(vendor) end
        local est = U.PerDay(P.EstimatedDaily(e, 7))
        if est then parts[#parts + 1] = "|cff8c94a3market est. " .. est .. "|r" end
        self.stats:SetText(table.concat(parts, "   "))

        local pw
        pw, ph = plot:GetWidth(), plot:GetHeight()
        if pw <= 0 or ph <= 0 then return end
        SetRange(lo, hi) -- padded; a flat series gets a band around its value
        local slot = #keys > 1 and pw / (#keys - 1) or pw
        local function X(i) return (i - 1) * slot end

        -- Listed quantity per day as faint bars (own scale), behind the price line.
        local qmax = 0
        for _, k in ipairs(keys) do qmax = math.max(qmax, (e.qd and e.qd[k]) or 0) end
        if qmax > 0 then
            for i, k in ipairs(keys) do
                local q = e.qd and e.qd[k]
                if q and q > 0 then
                    local b = self.qtyBars:Acquire()
                    b:ClearAllPoints()
                    b:SetPoint("BOTTOM", plot, "BOTTOMLEFT", X(i), 0)
                    b:SetSize(math.max(2, slot * 0.6), math.max(1, ph * 0.45 * q / qmax))
                    b.day, b.qty, b.out = k, q, e.out and e.out[k]
                end
            end
        end
        Grid()
        RefLine(avg, T.text, 0.35, "avg", "RIGHT")
        if vendor and vendor > 0 then RefLine(vendor, { 0.55, 0.8, 1 }, 0.5, "vendor", "LEFT") end

        local prevX, prevY
        local labelEvery = math.max(1, math.ceil(#keys / math.max(1, math.floor(pw / 46))))
        for i, k in ipairs(keys) do
            local v = values[i]
            if v then
                local x, y = X(i), Y(v)
                local seg = self.segments:Acquire()
                if canLine then
                    if prevX then
                        seg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)
                        seg:SetStartPoint("BOTTOMLEFT", plot, prevX, prevY)
                        seg:SetEndPoint("BOTTOMLEFT", plot, x, y)
                    else
                        seg:Hide()
                    end
                else
                    seg:ClearAllPoints()
                    seg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.6)
                    seg:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x - 2, 0)
                    seg:SetSize(4, math.max(1, y))
                end
                prevX, prevY = x, y
                local pt = self.points:Acquire()
                pt:ClearAllPoints()
                pt:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
                pt.day, pt.value, pt.avg = k, v, avg
            end
            if (#keys - i) % labelEvery == 0 then
                local l = self.xLabels:Acquire()
                l:ClearAllPoints()
                l:SetPoint("TOP", plot, "BOTTOMLEFT", X(i), -6)
                l:SetText(U.ShortDate(k))
            end
        end
    end

    plot:SetScript("OnSizeChanged", function() f:Render() end)
    ns:Register("PRICES_UPDATED", function()
        if f:IsVisible() and f.itemID then f:Render() end
    end)
    return f
end
