-- Auction house: purchases (cost basis lots), posting deposits, and sales from mail invoices.
local _, ns = ...
local M, U, CB = ns.Money, ns.Util, ns.CostBasis
local AH = {}
ns.AuctionHouse = AH

M:RegisterContext("auction", function(delta)
    return delta < 0 and "ah_buy" or "ah_sale"
end)

ns:On("AUCTION_HOUSE_SHOW", function() M:Enter("auction") end)
ns:On("AUCTION_HOUSE_CLOSED", function() M:Leave("auction", 5) end)

local function RememberName(itemID, name)
    if itemID and name and ns.char then ns.char.nameToID[name] = itemID end
end

local function ItemFromLocation(loc)
    if not loc or not C_Item then return nil end
    local okID, itemID = pcall(C_Item.GetItemID, loc)
    local okName, name = pcall(C_Item.GetItemName, loc)
    itemID = okID and itemID or nil
    name = okName and name or U.ItemName(itemID)
    return itemID, name
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
local function OnCommodityConfirm(itemID, quantity)
    if not itemID or not quantity or quantity <= 0 then return end
    local name = U.ItemName(itemID)
    M:Expect({
        cat = "ah_buy", sign = -1, ttl = 20, i = itemID, q = quantity, n = name,
        onRecord = function(_, delta)
            local c = ns.char
            CB.AddLot(c, itemID, quantity, -delta / quantity, "ah", time())
            RememberName(itemID, name)
            -- If the purchase is later delivered by mail with a buyer invoice, skip adding the lot twice.
            c.awaiting[itemID] = (c.awaiting[itemID] or 0) + quantity
        end,
    })
end

if C_AuctionHouse then
    U.HookMethod(C_AuctionHouse, "ConfirmCommoditiesPurchase", OnCommodityConfirm)

    -- Non-commodity buyouts/bids: item identity is attached when the buyer invoice mail is collected.
    -- PlaceBid is used for both bids and buyouts. A buyout is a purchase; a bid only puts gold on hold
    -- ("ah_bid", neutral) until we win it (converted on the buyer invoice) or are outbid (refunded by mail).
    -- The GoblinBooks buy page sets AH.nextBidLabel ("Bid: <item>" / "Buyout: <item>") just before calling PlaceBid.
    U.HookMethod(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
        local label = AH.nextBidLabel
        AH.nextBidLabel = nil
        local listing = ns.AHScan and ns.AHScan.auctions[auctionID]
        local isBid
        if label then
            isBid = label:find("^Bid:") ~= nil
        elseif listing then
            isBid = not listing.unit or (bidAmount or 0) < listing.unit
        end
        local itemID = listing and listing.link and U.ItemIDFromName(listing.link)
        local name = (itemID and U.ItemName(itemID)) or (label and label:match("^%a+: (.+)$"))
        if isBid then
            M:Expect({
                cat = "ah_bid", amount = bidAmount and -bidAmount or nil, sign = -1, ttl = 20, i = itemID,
                n = "Bid on " .. (name or "item"),
                onRecord = function(_, delta)
                    local held = ns.char.heldBids
                    held[#held + 1] = { a = -delta, n = name, i = itemID, id = auctionID, t = time() }
                end,
            })
        else
            M:Expect({ cat = "ah_buy", amount = bidAmount and -bidAmount or nil, sign = -1, ttl = 20, i = itemID,
                n = name and ("Buyout: " .. name) or label or "Bid/buyout" })
        end
    end)

    -----------------------------------------------------------------------
    -- Posting (deposit)
    -----------------------------------------------------------------------
    local function OnPost(loc, _, quantity)
        local itemID, name = ItemFromLocation(loc)
        RememberName(itemID, name)
        -- The GoblinBooks sell page sets the client's deposit estimate just before posting.
        local estimate = AH.nextPostEstimate
        AH.nextPostEstimate = nil
        M:Expect({
            cat = "ah_deposit", sign = -1, ttl = 20, i = itemID, q = quantity, n = name,
            onRecord = function(_, delta)
                CB.RecordDeposit(ns.char, itemID, name, -delta, time())
                AH:RecordDepositCheck(estimate, -delta)
                CB.RecordPost(ns.char, itemID, name, quantity, time())
            end,
        })
    end
    U.HookMethod(C_AuctionHouse, "PostItem", OnPost)
    U.HookMethod(C_AuctionHouse, "PostCommodity", OnPost)
end

---------------------------------------------------------------------------
-- Sold auctions on their way to the mailbox. A sale is spotted when your auctions list shows it as
-- sold (only while the AH is open). Its gold arrives after a delay learned from your sale mails
-- (mail sent - sale seen); the client's own countdown on sold auctions is wrong on WoW Forever.
--   char.pendingSales[auctionID] = { i, n, q, amount, seen, soldAt?, eta, notified? }
--   char.activeSeen[auctionID]   = last time the auction was seen still listed
--   db.mailDelays                = learned delays (seconds), most recent last
---------------------------------------------------------------------------
AH.DEFAULT_MAIL_DELAY = 3600
local SOLD = 1 -- Enum.AuctionStatus.Sold
local MAX_DELAY_SAMPLES = 30

--- Median learned delay, or the default; also returns how many sales it's based on.
function AH:MailDelay()
    local list = ns.db and ns.db.mailDelays or {}
    if #list == 0 then return AH.DEFAULT_MAIL_DELAY, 0 end
    local sorted = {}
    for i, v in ipairs(list) do sorted[i] = v end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)], #sorted
end

function AH:RecordMailDelay(sec)
    if not sec or sec < 0 or sec > 6 * 3600 then return end -- outside that, the sale time wasn't known well
    ns.db.mailDelays = ns.db.mailDelays or {}
    local list = ns.db.mailDelays
    list[#list + 1] = math.floor(sec + 0.5)
    while #list > MAX_DELAY_SAMPLES do table.remove(list, 1) end
end

local function LinkName(link)
    return link and link:match("%[(.-)%]") or nil
end

--- Read your auctions list: new sales become pending, listed ones remember when they were last seen.
function AH:TrackOwned()
    local c = ns.char
    local api = C_AuctionHouse
    if not c or not (api and api.GetNumOwnedAuctions) then return end
    c.pendingSales = c.pendingSales or {}
    c.activeSeen = c.activeSeen or {}
    local now = time()
    local listed = {}
    for i = 1, api.GetNumOwnedAuctions() or 0 do
        local a = api.GetOwnedAuctionInfo(i)
        if a and a.auctionID then
            local id = a.auctionID
            if a.status == SOLD then
                local p = c.pendingSales[id]
                -- The client's countdown on sold auctions isn't the mail delay on WoW Forever (it said 3 minutes
                -- for gold that took an hour), so it's not used: the delay learned from sale mails is.
                if not p then
                    local itemID = a.itemKey and a.itemKey.itemID
                    local qty = a.quantity or 1
                    -- Seen listed a few minutes ago: it sold just now, so this sale can teach us the delay.
                    local last = c.activeSeen[id]
                    p = {
                        i = itemID, n = LinkName(a.itemLink) or U.ItemName(itemID), q = qty,
                        amount = a.buyoutAmount or a.bidAmount or 0, seen = now, -- sold: already the total
                        soldAt = last and now - last <= 600 and now or nil,
                    }
                    p.eta = now + AH:MailDelay()
                    c.pendingSales[id] = p
                    ns:Fire("PENDING_SALES")
                else
                    -- Fix pending sales saved before (they multiplied the total by the quantity again).
                    p.amount = a.buyoutAmount or a.bidAmount or p.amount
                    -- Saved from the client's countdown: estimate again, and allow one (correct) mailbox alert.
                    if p.exact then
                        p.exact, p.notified = nil, nil
                        p.eta = p.seen + AH:MailDelay()
                    end
                end
            else
                listed[id] = true
                c.activeSeen[id] = now
            end
        end
    end
    -- Forget listings that are gone (sold ones were turned into pending sales above).
    for id in pairs(c.activeSeen) do
        if not listed[id] then c.activeSeen[id] = nil end
    end
end

--- Pending sales for a char, soonest first. Drops ones older than the 30-day mail limit.
function AH:PendingSales(c)
    c = c or ns.char
    local out = {}
    if not c or not c.pendingSales then return out end
    local now = time()
    for id, p in pairs(c.pendingSales) do
        if now - p.eta > 31 * 86400 then
            c.pendingSales[id] = nil
        else
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b) return a.eta < b.eta end)
    return out
end

--- The sale mail's money was collected: drop the matching pending sale and learn the delay.
function AH:ResolvePendingSale(name, bid, sentAt)
    local c = ns.char
    if not c or not c.pendingSales or not name then return end
    local bestID, best
    for id, p in pairs(c.pendingSales) do
        if p.n == name then
            -- Prefer the same amount, then the oldest.
            local score = (p.amount == bid and 0 or 1) * 1e12 + p.seen
            if not best or score < best then bestID, best = id, score end
        end
    end
    if not bestID then return end
    local p = c.pendingSales[bestID]
    c.pendingSales[bestID] = nil
    if p.soldAt and sentAt then AH:RecordMailDelay(sentAt - p.soldAt) end
    ns:Fire("PENDING_SALES")
end

ns:On("OWNED_AUCTIONS_UPDATED", function() AH:TrackOwned() end)

-- Tell you once when a sale's gold should be in the mailbox.
ns:Register("READY", function()
    C_Timer.NewTicker(30, function()
        local now = time()
        for _, p in ipairs(AH:PendingSales()) do
            if not p.notified and now >= p.eta then
                p.notified = true
                ns:Print(("gold from your %s sale (%s) should be in your mailbox now"):format(
                    p.n or "auction", U.FormatMoney(p.amount)))
            end
        end
    end)
end)

---------------------------------------------------------------------------
-- Selling (called from Mail when a "seller" invoice's money is taken)
---------------------------------------------------------------------------
function AH:ExpectSale(info)
    local c = ns.char
    local name = info.itemName
    local itemID = (name and c.nameToID[name]) or U.ItemIDFromName(name)
    local count = info.count or 1
    local net = info.bid - info.consignment
    -- The mail's money is authoritative; anything beyond bid - cut is the refunded deposit.
    local refund = math.max(0, info.money - net)
    M:Expect({
        amount = info.money, ttl = 15,
        resolve = function()
            local out = { { a = info.money - refund, c = "ah_sale", i = itemID, q = count, n = name, s = info.playerName } }
            if refund > 0 then
                out[2] = { a = refund, c = "ah_deposit", i = itemID, n = (name or "?") .. " (deposit refund)" }
            end
            return out
        end,
        onRecord = function()
            CB.RecordSale(ns.char, itemID, name, count, info.bid, info.consignment, refund, time(), info.sentAt)
            CB.RecordCutSample(ns.db, info.bid, info.consignment, time())
            AH:ResolvePendingSale(name, info.bid, info.sentAt)
            if itemID then ns:Fire("ITEM_SOLD", itemID, count, net, "ah", time(), ns.charKey) end
        end,
    })
end

---------------------------------------------------------------------------
-- Deposit check. Known WoW: Forever bug (Sept 2026): deposits the client shows as under 1 silver are
-- charged 1 silver (the extra is refunded only if the item sells). We assume the bug until one of our own
-- posts shows an under-1s deposit charged exactly as estimated, so a server fix is picked up automatically.
---------------------------------------------------------------------------
AH.DEPOSIT_MIN = 100

--- Deposit you'll actually be charged for a client estimate; second value is true when the bug applies.
function AH:EffectiveDeposit(estimate)
    estimate = estimate or 0
    if estimate <= 0 or estimate >= AH.DEPOSIT_MIN then return estimate, false end
    local check = ns.db and ns.db.depositCheck
    if check and check.last == "ok" then return estimate, false end
    return AH.DEPOSIT_MIN, true
end

--- Compare a post's estimate with the gold actually taken (only small deposits tell us anything).
function AH:RecordDepositCheck(estimate, actual)
    if not estimate or estimate <= 0 or estimate >= AH.DEPOSIT_MIN or not actual then return end
    ns.db.depositCheck = ns.db.depositCheck or {}
    local c = ns.db.depositCheck
    c.last = actual > estimate and "bug" or "ok"
    c.estimate, c.actual, c.t = estimate, actual, time()
end

---------------------------------------------------------------------------
-- Held bids
---------------------------------------------------------------------------
--- Remove and return the held bid for this item name and exact amount (won-bid invoices and outbid
--- refunds both carry exactly the amount we bid). Exact matching keeps buyouts from being mistaken for won bids.
function AH:TakeHeldBid(name, amount)
    local held = ns.char and ns.char.heldBids
    if not held or not amount then return nil end
    for i, h in ipairs(held) do
        if h.a == amount and (not name or not h.n or h.n == name) then
            return table.remove(held, i)
        end
    end
end

--- A won bid: the held gold was really spent. Move it from "held" to "AH purchase" with a zero-sum pair.
local function ConvertWonBid(itemID, name, amount)
    local h = AH:TakeHeldBid(name, amount)
    if not h then return end
    local t = time()
    local L = ns.Ledger
    L.Add(ns.char, { t = t, a = h.a, c = "ah_bid", i = itemID, n = "Won bid released: " .. (name or "item") })
    L.Add(ns.char, { t = t, a = -h.a, c = "ah_buy", i = itemID, n = "Won bid: " .. (name or "item") })
    ns:Fire("LEDGER_UPDATED")
end

---------------------------------------------------------------------------
-- Unsold auctions coming back by mail (expired / cancelled): sell-through bookkeeping.
---------------------------------------------------------------------------
function AH:OnUnsoldMail(itemName, itemID, count, kind)
    local c = ns.char
    itemID = itemID or (itemName and c.nameToID[itemName]) or U.ItemIDFromName(itemName)
    if not itemID then return end
    CB.RecordUnsold(c, itemID, itemName, count or 1, kind)
    ns:Fire("LEDGER_UPDATED")
end

---------------------------------------------------------------------------
-- Purchase delivered by mail (non-commodities): add the cost basis lot.
---------------------------------------------------------------------------
function AH:OnBuyerInvoice(info, link)
    local c = ns.char
    local itemID = U.ItemIDFromName(link) or (info.itemName and c.nameToID[info.itemName]) or U.ItemIDFromName(info.itemName)
    ConvertWonBid(itemID, info.itemName, info.bid)
    if not itemID then return end
    local count = info.count or 1
    RememberName(itemID, info.itemName)
    local waiting = c.awaiting[itemID] or 0
    if waiting >= count then
        local left = waiting - count
        c.awaiting[itemID] = left > 0 and left or nil
        return
    end
    CB.AddLot(c, itemID, count, info.bid / count, "ah", time())
end
