-- Dependency-free test runner. Usage (from repo root):  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local S = require("wowstub")
local ROOT = "." -- run from the repo root: lua tests/run.lua

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name .. "\n       " .. tostring(err))
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
    end
end

local function last(ns) local l = ns.char.entries return l[#l] end

local function ledgerSum(ns)
    local s = 0
    for _, e in ipairs(ns.char.entries) do s = s + e.a end
    return s
end

print("GoblinBooks tests")

test("money formatting", function()
    local ns = S.LoadAddon(ROOT)
    local U = ns.Util
    eq(U.FormatGoldShort(12345678), "1.2k g")
    eq(U.FormatGoldShort(-3500000), "-350g")
    eq(U.FormatGoldShort(4500), "45s")
    eq(U.FormatGoldShort(7), "7c")
    eq(#U.DayKeys(7), 7)
    eq(U.DayKeys(7)[7], U.DateKey(time()))
    eq(U.GoldDecimal(12345), "1.2345")
end)

test("ledger rollups, reclassify, prune", function()
    local ns = S.LoadAddon(ROOT)
    local L, c = ns.Ledger, ns:EnsureChar()
    local t = time()
    L.Add(c, { t = t, a = 100, c = "loot" })
    L.Add(c, { t = t, a = 50, c = "other" })
    local key = ns.Util.DateKey(t)
    eq(c.daily[key].loot, 100)
    L.Reclassify(c, c.entries[2], "quest")
    eq(c.daily[key].other, nil)
    eq(c.daily[key].quest, 50)
    L.Add(c, { t = t - 100 * 86400, a = 1, c = "loot" })
    table.sort(c.entries, function(a, b) return a.t < b.t end)
    eq(L.Prune(c, 90, t), 1)
    eq(#c.entries, 2)
    eq(L.Net(L.Sum({ c }, { key })), 150)
end)

test("FIFO cost basis and flip profit", function()
    local ns = S.LoadAddon(ROOT)
    local CB, c = ns.CostBasis, ns:EnsureChar()
    CB.AddLot(c, 42, 10, 100, "ah", 1)
    CB.AddLot(c, 42, 10, 200, "ah", 2)
    local cost, covered = CB.Consume(c, 42, 15)
    eq(cost, 10 * 100 + 5 * 200)
    eq(covered, 15)
    local q, v = CB.Holdings(c, 42)
    eq(q, 5); eq(v, 1000)
    CB.RecordDeposit(c, 42, "Ore", 50, 3)
    local f = CB.RecordSale(c, 42, "Ore", 10, 5000, 250, 50, 4)  -- 5 covered, 5 uncosted
    eq(f.cost, 1000)
    eq(f.noCost, 5)
    eq(CB.Profit(f), 5000 - 250 - 1000 - 50 + 50)
end)

test("unattributed change goes to Other", function()
    local ns = S.LoadAddon(ROOT, 10000)
    S.AddMoney(123)
    eq(last(ns).c, "other")
    eq(last(ns).a, 123)
end)

test("loot window", function()
    local ns = S.LoadAddon(ROOT, 0)
    S.Fire("LOOT_READY")
    S.AddMoney(5000)
    eq(last(ns).c, "loot")
    S.Fire("LOOT_CLOSED")
    S.Advance(0.5)
    S.AddMoney(100) -- money arriving just after close still counts
    eq(last(ns).c, "loot")
    S.Advance(5)
    S.AddMoney(100)
    eq(last(ns).c, "other")
end)

test("group loot share via CHAT_MSG_MONEY after the fact", function()
    local ns = S.LoadAddon(ROOT, 0)
    S.AddMoney(777)
    eq(last(ns).c, "other")
    S.Fire("CHAT_MSG_MONEY", "You receive loot: 7s 77c")
    eq(last(ns).c, "loot")
    eq(ns.char.daily[ns.Util.DateKey(time())].other, nil)
end)

test("merchant sell, buy (creates lot), repair", function()
    local ns = S.LoadAddon(ROOT, 100000)
    S.merchantItems = { [3] = 2589 }
    S.Fire("MERCHANT_SHOW")
    S.AddMoney(2500)
    eq(last(ns).c, "vendor_sell")
    BuyMerchantItem(3, 20)
    S.AddMoney(-2000)
    eq(last(ns).c, "vendor_buy")
    eq(last(ns).i, 2589)
    local q, v = ns.CostBasis.Holdings(ns.char, 2589)
    eq(q, 20); eq(v, 2000)
    RepairAllItems(false)
    S.AddMoney(-900)
    eq(last(ns).c, "repair")
    S.repairMode = true
    S.AddMoney(-100)
    eq(last(ns).c, "repair")
    S.repairMode = false
end)

test("quest turned in after money arrived", function()
    local ns = S.LoadAddon(ROOT, 0)
    S.AddMoney(15000)
    eq(last(ns).c, "other")
    S.Fire("QUEST_TURNED_IN", 123, 1000, 15000)
    eq(last(ns).c, "quest")
end)

test("quest reward via GetQuestReward hook", function()
    local ns = S.LoadAddon(ROOT, 0)
    GetQuestReward(1)
    S.AddMoney(4200)
    eq(last(ns).c, "quest")
end)

test("sending mail with gold splits into mail_out + postage", function()
    local ns = S.LoadAddon(ROOT, 1000000)
    S.Fire("MAIL_SHOW")
    S.sendMoney, S.sendPostage = 500000, 30
    SendMail("Alt", "gold", "")
    S.AddMoney(-500030)
    local n = #ns.char.entries
    eq(ns.char.entries[n - 1].c, "mail_out")
    eq(ns.char.entries[n - 1].a, -500000)
    eq(ns.char.entries[n].c, "postage")
    eq(ns.char.entries[n].a, -30)
end)

test("mail from a player", function()
    local ns = S.LoadAddon(ROOT, 0)
    S.Fire("MAIL_SHOW")
    S.inbox = { [1] = { header = { sender = "Friend", subject = "here", money = 10000, canReply = true } } }
    TakeInboxMoney(1)
    S.AddMoney(10000)
    eq(last(ns).c, "mail_in")
    eq(last(ns).s, "Friend")
end)

test("AH flip: buy commodity, post, sell via invoice mail", function()
    local ns = S.LoadAddon(ROOT, 10000000)
    S.itemNames = { [190396] = "Serevite Ore" }
    S.Fire("AUCTION_HOUSE_SHOW")
    -- buy 100 ore for 100g total
    C_AuctionHouse.ConfirmCommoditiesPurchase(190396, 100)
    S.AddMoney(-1000000)
    eq(last(ns).c, "ah_buy")
    -- post 100 ore, 2g deposit
    C_AuctionHouse.PostCommodity({ itemID = 190396, name = "Serevite Ore" }, 1, 100, 15000)
    S.AddMoney(-20000)
    eq(last(ns).c, "ah_deposit")
    S.Fire("AUCTION_HOUSE_CLOSED")
    S.Advance(60)
    -- sale invoice: 100 sold for 150g, 5% cut 7.5g, deposit refunded 2g
    S.Fire("MAIL_SHOW")
    S.inbox = { [1] = {
        header = { sender = "Auction House", subject = "Auction successful", money = 1500000 - 75000 + 20000 },
        invoice = { type = "seller", itemName = "Serevite Ore", playerName = "Buyer", bid = 1500000, deposit = 20000, consignment = 75000, count = 100 },
    } }
    TakeInboxMoney(1)
    S.AddMoney(1445000)
    local n = #ns.char.entries
    eq(ns.char.entries[n - 1].c, "ah_sale")
    eq(ns.char.entries[n - 1].a, 1425000)
    eq(ns.char.entries[n].c, "ah_deposit")
    eq(ns.char.entries[n].a, 20000)
    local f = ns.char.flips[190396]
    eq(f.sold, 100)
    eq(f.cost, 1000000)
    eq(ns.CostBasis.Profit(f), 1500000 - 75000 - 1000000 - 20000 + 20000)
end)

test("AH buyer invoice adds lot for non-commodity, no double count for commodities", function()
    local ns = S.LoadAddon(ROOT, 10000000)
    S.Fire("AUCTION_HOUSE_SHOW")
    C_AuctionHouse.ConfirmCommoditiesPurchase(500, 10)
    S.AddMoney(-10000)
    S.Fire("MAIL_SHOW")
    S.inbox = {
        [1] = { header = { sender = "Auction House", money = 0 }, invoice = { type = "buyer", itemName = "Herb", bid = 10000, count = 10 }, link = "|Hitem:500::|h[Herb]|h" },
        [2] = { header = { sender = "Auction House", money = 0 }, invoice = { type = "buyer", itemName = "Sword", bid = 500000, count = 1 }, link = "|Hitem:777::|h[Sword]|h" },
    }
    AutoLootMailItem(1)
    AutoLootMailItem(2)
    eq((ns.CostBasis.Holdings(ns.char, 500)), 10)
    local q, v = ns.CostBasis.Holdings(ns.char, 777)
    eq(q, 1); eq(v, 500000)
end)

test("trade and services contexts", function()
    local ns = S.LoadAddon(ROOT, 1000000)
    S.Fire("TRADE_SHOW")
    S.AddMoney(5000)
    eq(last(ns).c, "trade_in")
    eq(last(ns).s, "Partner")
    S.Fire("TRADE_CLOSED")
    S.Advance(10)
    S.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 2) -- taxi
    S.AddMoney(-300)
    eq(last(ns).c, "flight")
end)

test("ledger always reconciles with actual gold", function()
    local ns = S.LoadAddon(ROOT, 50000)
    local start = S.money
    S.Fire("LOOT_READY"); S.AddMoney(100); S.Fire("LOOT_CLOSED")
    S.Advance(10)
    S.Fire("MERCHANT_SHOW"); S.AddMoney(250); S.AddMoney(-40); S.Fire("MERCHANT_CLOSED")
    S.Advance(10)
    S.AddMoney(-7)
    eq(ledgerSum(ns), S.money - start)
    eq(ns.Money.session, S.money - start)
end)

test("gold read as 0 at logout doesn't count as offline income", function()
    local ns = S.LoadAddon(ROOT, 1000)
    local saved = GoblinBooksDB
    S.money = 0 -- WoW Forever reports 0 while logging out
    S.Fire("PLAYER_LOGOUT")
    S.money = 1000
    _G.GoblinBooksDB = saved
    S.frames = {}
    local n = { UI = { Toggle = function() end, ShowExport = function() end } }
    for _, file in ipairs({ "Core.lua", "Util.lua", "Categories.lua", "Ledger.lua", "CostBasis.lua", "Money.lua" }) do
        assert(loadfile(ROOT .. "/" .. file))("GoblinBooks", n)
    end
    S.Fire("ADDON_LOADED", "GoblinBooks")
    S.Fire("PLAYER_LOGIN")
    eq(#n.char.entries, 0, "no offline entry")
end)

test("offline change recorded on login", function()
    local ns = S.LoadAddon(ROOT, 1000)
    local saved = GoblinBooksDB
    S.Fire("PLAYER_LOGOUT")
    -- simulate relog with different gold
    S.money = 1500
    local ns2 = {}
    _G.GoblinBooksDB = saved
    ns2 = (function()
        S.frames = {}
        local n = { UI = { Toggle = function() end, ShowExport = function() end } }
        for _, file in ipairs({ "Core.lua", "Util.lua", "Categories.lua", "Ledger.lua", "CostBasis.lua", "Money.lua" }) do
            assert(loadfile(ROOT .. "/" .. file))("GoblinBooks", n)
        end
        S.Fire("ADDON_LOADED", "GoblinBooks")
        S.Fire("PLAYER_LOGIN")
        return n
    end)()
    eq(last(ns2).a, 500)
    eq(last(ns2).c, "other")
end)

test("AH bid is held (neutral); outbid refund releases it, never income", function()
    _G.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
    local ns = S.LoadAddon(ROOT, 100000)
    S.Fire("AUCTION_HOUSE_SHOW")
    ns.AuctionHouse.nextBidLabel = "Bid: Linen Cloth"
    C_AuctionHouse.PlaceBid(42, 5000)
    S.AddMoney(-5000)
    eq(last(ns).c, "ah_bid")
    eq(#ns.char.heldBids, 1)
    S.Fire("AUCTION_HOUSE_CLOSED")
    S.Advance(60)
    S.Fire("MAIL_SHOW")
    S.inbox = { [1] = { header = { sender = "Auction House", subject = "Outbid on Linen Cloth", money = 5000 } } }
    TakeInboxMoney(1)
    S.AddMoney(5000)
    eq(last(ns).c, "ah_bid", "refund category")
    eq(#ns.char.heldBids, 0)
    eq(ns.Categories.IsNeutral("ah_bid"), true)
    _G.AUCTION_OUTBID_MAIL_SUBJECT = nil
end)

test("AH won bid converts the hold into a purchase", function()
    local ns = S.LoadAddon(ROOT, 100000)
    S.Fire("AUCTION_HOUSE_SHOW")
    ns.AuctionHouse.nextBidLabel = "Bid: Linen Cloth"
    C_AuctionHouse.PlaceBid(42, 5000)
    S.AddMoney(-5000)
    S.Fire("AUCTION_HOUSE_CLOSED")
    S.Advance(60)
    S.Fire("MAIL_SHOW")
    S.inbox = { [1] = {
        header = { sender = "Auction House", subject = "Auction won", money = 0 },
        invoice = { type = "buyer", itemName = "Linen Cloth", playerName = "Seller", bid = 5000, count = 1 },
    } }
    TakeInboxItem(1)
    eq(#ns.char.heldBids, 0)
    eq(last(ns).c, "ah_buy")
    eq(last(ns).a, -5000)
    eq(ledgerSum(ns), S.money - 100000, "zero-sum conversion keeps the ledger reconciled")
end)

test("AH buyout is a purchase, not a hold", function()
    local ns = S.LoadAddon(ROOT, 100000)
    S.Fire("AUCTION_HOUSE_SHOW")
    ns.AuctionHouse.nextBidLabel = "Buyout: Linen Cloth"
    C_AuctionHouse.PlaceBid(43, 8000)
    S.AddMoney(-8000)
    eq(last(ns).c, "ah_buy")
    eq(#ns.char.heldBids, 0)
end)

test("AH cut rate is measured from sale invoices", function()
    local ns = S.LoadAddon(ROOT, 0)
    local CB = ns.CostBasis
    local rate, measured = CB.CutRate(ns.db)
    eq(rate, 0.05, "default before any sale")
    eq(measured, false)
    CB.RecordSale(ns.char, 1, "Thing", 1, 200000, 10000, 0, S.walltime)
    CB.RecordCutSample(ns.db, 200000, 10000, S.walltime)
    CB.RecordSale(ns.char, 2, "Other", 1, 100000, 5000, 0, S.walltime)
    CB.RecordCutSample(ns.db, 100000, 5000, S.walltime)
    rate, measured = CB.CutRate(ns.db)
    eq(measured, true)
    eq(math.floor(rate * 10000 + 0.5), 500, "5.00%")
    local st = CB.CutStats(ns.db)
    eq(st.samples, 2)
    eq(CB.CutLabel(rate), "5%")
end)

test("favorites toggle and survive price pruning", function()
    local ns = S.LoadAddon(ROOT)
    local P = ns.Prices
    eq(P.IsFavorite(9), false)
    eq(P.ToggleFavorite(9, "Old Thing"), true)
    eq(P.IsFavorite(9), true)
    P.Record(9, 100, 1, nil, S.walltime - 200 * 86400)
    P.Prune(60, S.walltime)
    eq(P.Get(9) ~= nil, true, "favorite entry kept")
    eq(P.ToggleFavorite(9), false)
    eq(P.IsFavorite(9), false)
end)

test("minimum-deposit bug: assumed until a post shows it fixed", function()
    local ns = S.LoadAddon(ROOT, 100000)
    local AH = ns.AuctionHouse
    local d, bug = AH:EffectiveDeposit(4)
    eq(d, 100, "assume 1s minimum")
    eq(bug, true)
    eq(AH:EffectiveDeposit(250), 250, "large deposits unaffected")
    -- A post estimated at 4c that cost 1s confirms the bug.
    S.Fire("AUCTION_HOUSE_SHOW")
    AH.nextPostEstimate = 4
    C_AuctionHouse.PostCommodity({}, 1, 1, 30)
    S.AddMoney(-100)
    eq(ns.db.depositCheck.last, "bug")
    -- A later post charged exactly as estimated means it was fixed.
    AH.nextPostEstimate = 4
    C_AuctionHouse.PostCommodity({}, 1, 1, 30)
    S.AddMoney(-4)
    eq(ns.db.depositCheck.last, "ok")
    d, bug = AH:EffectiveDeposit(4)
    eq(d, 4)
    eq(bug, false)
end)

test("market activity estimate counts drops between complete counts", function()
    local ns = S.LoadAddon(ROOT)
    local P = ns.Prices
    local t = S.walltime
    P.Record(5, 100, 50, nil, t - 120, true)
    P.Record(5, 100, 30, nil, t - 60, true) -- 20 left
    P.Record(5, 100, 45, nil, t, true)        -- new listings: no negative drop
    local e = P.Get(5)
    eq(e.out[ns.Util.DateKey(t)], 20)
    eq(P.EstimatedDaily(e, 7, t), 20)
    P.Record(5, 100, 10, nil, t + 10, false)  -- incomplete counts are ignored
    eq(e.out[ns.Util.DateKey(t)], 20)
end)

test("flip candidates: current low well below usual", function()
    local ns = S.LoadAddon(ROOT)
    local P = ns.Prices
    local t = S.walltime
    for i = 1, 5 do P.Record(77, 10000, 10, "Cheap Now", t - i * 86400) end
    P.Record(77, 6000, 10, nil, t - 60) -- 60s now vs 1g usual
    for i = 1, 5 do P.Record(78, 10000, 10, "Fair", t - i * 86400) end
    P.Record(78, 9800, 10, nil, t - 60)
    local list = P.FlipCandidates({ cut = 0.05, minMargin = 0.2, minProfit = 100, maxAge = 3600, minDays = 3, now = t })
    eq(#list, 1)
    eq(list[1].id, 77)
    eq(math.floor(list[1].profit + 0.5), 3500, "1g * 0.95 - 60s")
end)

test("sell-through: posts resolved by sales and expirations", function()
    local ns = S.LoadAddon(ROOT)
    local CB, c = ns.CostBasis, ns.char
    local t = S.walltime
    CB.RecordPost(c, 9, "Ore", 10, t - 7200)
    CB.RecordPost(c, 9, "Ore", 5, t - 3600)
    CB.RecordSale(c, 9, "Ore", 10, 1000, 50, 0, t, t)
    CB.RecordUnsold(c, 9, "Ore", 5, "expired")
    local f = c.flips[9]
    local rate, resolved, avg = CB.SellThrough(f)
    eq(resolved, 15)
    eq(math.floor(rate * 100 + 0.5), 67)
    eq(avg, 7200, "the 10 sold were posted 2h earlier")
    eq(c.postQueue[9], nil, "queue drained")
end)

test("crafting: cheapest reagent source and profit after the cut", function()
    local ns = S.LoadAddon(ROOT)
    local P, CR = ns.Prices, ns.Crafting
    local t = S.walltime
    P.Record(1, 500, 10, "Copper Bar", t)      -- AH 5s
    CR.RecordVendorPrice(2, 40)                -- vendor thread 40c
    P.Record(2, 90, 10, "Coarse Thread", t)    -- AH thread 90c (vendor is cheaper)
    P.Record(3, 4000, 5, "Copper Bracers", t)  -- output sells for 40s
    local rec = { n = "Copper Bracers", out = 3, qmin = 1, qmax = 1, r = { { i = 1, q = 4 }, { i = 2, q = 2 } } }
    local res = CR.Evaluate(rec, 0.05)
    eq(res.cost, 4 * 500 + 2 * 40)
    eq(res.parts[2].source, "Vendor")
    eq(res.valueSource, "AH")
    eq(math.floor(res.profit + 0.5), 3800 - 2080)
    eq(res.missing, 0)
    local res2 = CR.Evaluate({ n = "X", out = 3, r = { { i = 999, q = 1 } } }, 0.05)
    eq(res2.missing, 1, "unpriced reagent flagged")
end)

test("sold auctions wait for the mailbox and teach the delay", function()
    local ns = S.LoadAddon(ROOT)
    local AH = ns.AuctionHouse
    eq(AH:MailDelay(), 3600, "default delay")
    local owned = { { auctionID = 7, status = 0, itemKey = { itemID = 2770 }, itemLink = "|Hitem:2770|h[Copper Ore]|h", quantity = 5, buyoutAmount = 100 } }
    C_AuctionHouse.GetNumOwnedAuctions = function() return #owned end
    C_AuctionHouse.GetOwnedAuctionInfo = function(i) return owned[i] end
    AH:TrackOwned()                       -- listed
    S.Advance(120)
    owned[1].status = 1                   -- now sold: the client reports the whole sale's total
    owned[1].buyoutAmount = 500
    AH:TrackOwned()
    local p = ns.char.pendingSales[7]
    eq(p.amount, 500)
    eq(p.eta, S.walltime + 3600)
    eq(p.soldAt, S.walltime)
    eq(#AH:PendingSales(), 1)
    -- The sale mail was sent 50 minutes after the sale: collected now.
    AH:ResolvePendingSale("Copper Ore", 500, S.walltime + 3000)
    eq(ns.char.pendingSales[7], nil)
    eq(AH:MailDelay(), 3000, "learned delay")
end)

test("crafting moves the reagents' cost into the crafted item", function()
    local ns = S.LoadAddon(ROOT)
    local CB, CR = ns.CostBasis, ns.Crafting
    local c = ns.char
    CB.AddLot(c, 2589, 10, 30, "ah", S.walltime)      -- 10 Linen Cloth bought at 30c
    CR.TransferCost(c, { [2589] = 4 }, { { id = 2996, qty = 2 } }, S.walltime) -- 2 bolts from 4 cloth
    local q, v = CB.Holdings(c, 2996)
    eq(q, 2)
    eq(v, 120, "bolts carry the cloth's cost")
    eq((CB.Holdings(c, 2589)), 6, "cloth used up")
    -- Selling a bolt now counts its cost.
    local f, cost = CB.RecordSale(c, 2996, "Bolt of Linen Cloth", 1, 100, 5, 0, S.walltime)
    eq(cost, 60)
    eq(f.noCost, 0)
    -- Looted reagents (no cost) don't give the output a free lot.
    CR.TransferCost(c, { [9999] = 2 }, { { id = 8888, qty = 1 } }, S.walltime)
    eq(c.lots[8888], nil)
end)

test("deals: listings under the limit, not your own", function()
    local ns = S.LoadAddon(ROOT)
    local D = ns.Deals
    local list = {
        { unit = 50, qty = 5 }, { unit = 60, qty = 3, mine = true }, { unit = 70, qty = 10 }, { unit = 90, qty = 4 },
    }
    local d = D.Evaluate(2589, list, true, 75)
    eq(d.unit, 50)
    eq(d.qty, 15, "5 + 10 (own listing skipped, 90 over the limit)")
    eq(d.cost, 5 * 50 + 10 * 70)
    eq(D.Evaluate(2589, list, true, 40), nil, "nothing under 40")
    -- Non-commodity: the auction price is for the whole stack.
    local item = D.Evaluate(9, { { unit = 400, qty = 4, id = 77 } }, false, 120)
    eq(item.unit, 100)
    eq(item.auctionID, 77)
    eq(item.auctionPrice, 400)
    -- Max price beats the % rule.
    D.AddWatch(2589)
    D.Watch()[2589].max = 33
    eq((D.Threshold(2589)), 33)
end)

test("net worth: gold plus items at the better of AH and vendor", function()
    local ns = S.LoadAddon(ROOT, 10000)
    local I, P = ns.Inventory, ns.Prices
    ns.char.inv = { bags = { [1] = 10, [2] = 3 }, bank = { [1] = 5 }, boundBags = { [2] = 3 }, boundBank = {} }
    P.Record(1, 200, 5, "Ore", S.walltime)
    local vendor = function(id) return ({ [1] = 50, [2] = 400 })[id] or 0 end
    local nw = I.NetWorth(vendor)
    eq(nw.gold, 10000)
    -- 15 ore at 200 * 0.95 = 190 each; 3 bound items at vendor 400.
    eq(math.floor(nw.items + 0.5), 15 * 190 + 3 * 400)
    local o = I.Owned(1)
    eq(o.total, 15)
    eq(o.mine.bank, 5)
end)

test("shopping list totals reagents across crafts", function()
    local ns = S.LoadAddon(ROOT)
    local P, CR = ns.Prices, ns.Crafting
    P.Record(1, 500, 10, "Copper Bar", S.walltime)
    local rec = { n = "Copper Bracers", out = 3, r = { { i = 1, q = 4 }, { i = 2, q = 2 } } }
    CR.AddToShopping(rec, 3, 0.05)
    CR.AddToShopping({ n = "Copper Ring", r = { { i = 1, q = 2 } } }, 1, 0.05)
    local list = CR.Shopping()
    eq(list[1].need, 14, "4*3 + 2")
    eq(list[2].need, 6)
    local rows, total, unpriced = CR.ShoppingRows()
    eq(#rows, 2)
    eq(total, 14 * 500)
    eq(unpriced, 1, "item 2 has no price")
    CR.RemoveShopping(2)
    eq(CR.Shopping()[2], nil)
end)

test("price database records daily lows and latest price", function()
    local ns = S.LoadAddon(ROOT)
    local P = ns.Prices
    local t = S.walltime
    P.Record(100, 5000, 20, "Peacebloom", t)
    P.Record(100, 4200, 30, nil, t + 60)
    P.Record(100, 4800, 25, nil, t + 120)
    local e = P.Get(100)
    eq(e.p, 4800, "latest")
    eq(e.q, 25)
    eq(e.n, "Peacebloom")
    eq(e.d[ns.Util.DateKey(t)], 4200, "daily low")
    eq(P.Market(100, t + 200), 4800)
    P.Record(100, 0, 1, nil, t) -- ignored
    eq(P.Get(100).p, 4800)
end)

test("price average and prune", function()
    local ns = S.LoadAddon(ROOT)
    local P, U = ns.Prices, ns.Util
    local t = S.walltime
    P.Record(7, 1000, 1, nil, t - 2 * 86400)
    P.Record(7, 3000, 1, nil, t)
    eq(P.Average(P.Get(7), U.DayKeys(7, t)), 2000)
    P.Record(8, 500, 1, nil, t - 100 * 86400)
    eq(P.Prune(60, t), 1)
    eq(P.Get(8), nil)
    eq(P.Get(7).p, 3000)
end)


test("caches: day keys are copies, market price updates on new prices", function()
    local ns = S.LoadAddon(ROOT)
    local U, P = ns.Util, ns.Prices
    local k = U.DayKeys(7)
    k[#k] = nil
    eq(#U.DayKeys(7), 7, "a caller changing its copy doesn't change the cache")
    P.Record(555, 1000, 5)
    eq(P.Market(555), 1000)
    P.Record(555, 800, 5)
    eq(P.Market(555), 800, "new price seen right away")
    eq(P.Market(556), nil)
    P.Record(556, 50, 1)
    eq(P.Market(556), 50, "a missing price isn't cached forever")
end)


test("full scan reads and saves in slices, reporting progress", function()
    local ns = S.LoadAddon(ROOT)
    local auctions = {}
    for i = 1, 250 do auctions[i] = { id = 100 + (i % 3), count = 2, buyout = 1000 + i * 10 } end
    C_AuctionHouse.ReplicateItems = function() end
    C_AuctionHouse.GetNumReplicateItems = function() return #auctions end
    C_AuctionHouse.GetReplicateItemInfo = function(idx)
        local a = auctions[idx + 1]
        return "Item" .. a.id, nil, a.count, nil, nil, nil, nil, nil, nil, a.buyout, nil, nil, nil, nil, nil, nil, a.id
    end
    assert(loadfile(ROOT .. "/AuctionScan.lua"))("GoblinBooks", ns)
    local after = C_Timer.After
    C_Timer.After = function(delay, fn) if delay <= 0 then fn() end end -- skip the 60s no-answer timeout
    local states = {}
    ns:Register("SCAN_PROGRESS", function(state) states[#states + 1] = state end)
    ns.db.lastFullScan = nil
    local ok = ns.AHScan.FullScan()
    eq(ok, true)
    eq(states[1], "waiting")
    S.Fire("REPLICATE_ITEM_LIST_UPDATE")
    eq(states[#states], "done")
    eq(ns.AHScan.scanning, false)
    -- Item 101: auctions i = 1, 4, 7...; cheapest is i = 1 (1010 for 2) = 505 each.
    eq(ns.Prices.Get(101).p, 505)
    eq(ns.Prices.Get(100).q, 83 * 2, "quantity summed")
    C_Timer.After = after
end)


test("sale mails taken at once (one combined gold change) are each booked as AH sales", function()
    local ns = S.LoadAddon(ROOT, 0)
    S.Fire("MAIL_SHOW")
    S.inbox = {
        [1] = { header = { sender = "Auction House", subject = "Auction successful", money = 950 + 100 },
                invoice = { type = "seller", itemName = "Salt", playerName = "A", bid = 1000, deposit = 100, consignment = 50, count = 5 } },
        [2] = { header = { sender = "Auction House", subject = "Auction successful", money = 1900 },
                invoice = { type = "seller", itemName = "Linen", playerName = "B", bid = 2000, deposit = 0, consignment = 100, count = 20 } },
        [3] = { header = { sender = "Auction House", subject = "Auction successful", money = 475 },
                invoice = { type = "seller", itemName = "Egg", playerName = "C", bid = 500, deposit = 0, consignment = 25, count = 4 } },
    }
    TakeInboxMoney(1)
    TakeInboxMoney(2)
    TakeInboxMoney(3)
    S.AddMoney(1050 + 1900) -- the client reports mails 1 and 2 as one change
    S.AddMoney(475)
    local cats, sum = {}, 0
    for _, e in ipairs(ns.char.entries) do
        cats[e.c] = (cats[e.c] or 0) + e.a
        sum = sum + e.a
    end
    eq(sum, 3425, "ledger still matches gold")
    eq(cats.mail_in, nil, "nothing booked as mail")
    eq(cats.ah_sale, 950 + 1900 + 475)
    eq(cats.ah_deposit, 100)
    local sold = 0
    for _, f in pairs(ns.char.flips) do sold = sold + f.sold end
    eq(sold, 5 + 20 + 4, "every sale reaches the Auction P/L")
end)

test("migration 4 moves sender-less mail money next to AH sales into AH sales", function()
    local ns = S.LoadAddon(ROOT, 0)
    local c = ns.char
    local function add(e) ns.Ledger.Add(c, e) end
    add({ t = 1000, a = 500, c = "ah_sale", n = "Salt" })
    add({ t = 1001, a = 1200, c = "mail_in" })
    add({ t = 5000, a = 300, c = "mail_in", s = "Friend" })
    add({ t = 9000, a = 700, c = "mail_in" }) -- no AH sale nearby: left alone
    GoblinBooksDB.version = 3
    ns:InitDB() -- runs migration 4
    eq(c.entries[2].c, "ah_sale")
    eq(c.entries[3].c, "mail_in", "has a sender")
    eq(c.entries[4].c, "mail_in", "no sale nearby")
    local day = c.daily[ns.Util.DateKey(1001)]
    eq(day.ah_sale, 1700)
end)


test("full scan: a slow server's data is still used, and closing the AH ends the wait", function()
    local ns = S.LoadAddon(ROOT)
    assert(loadfile(ROOT .. "/AuctionScan.lua"))("GoblinBooks", ns)
    local after, pending = C_Timer.After, {}
    C_Timer.After = function(delay, fn) if delay <= 0 then fn() else pending[#pending + 1] = fn end end
    C_AuctionHouse.ReplicateItems = function() end
    C_AuctionHouse.GetNumReplicateItems = function() return 1 end
    C_AuctionHouse.GetReplicateItemInfo = function()
        return "Ore", nil, 5, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 2770
    end
    local states = {}
    ns:Register("SCAN_PROGRESS", function(state) states[#states + 1] = state end)
    local function RunTimers(seconds)
        S.Advance(seconds)
        local list = pending
        pending = {}
        for _, fn in ipairs(list) do fn() end
    end

    -- No answer for longer than the wait limit: shown as failed...
    ns.db.lastFullScan = nil
    eq(ns.AHScan.FullScan(), true)
    for _ = 1, ns.AHScan.WAIT_LIMIT / 5 do RunTimers(5) end
    eq(states[#states], "failed")
    eq(ns.AHScan.scanning, false)
    -- ...but the data arriving afterwards is still read and saved.
    S.Fire("REPLICATE_ITEM_LIST_UPDATE")
    eq(states[#states], "done")
    eq(ns.Prices.Get(2770).p, 100)

    -- Closing the auction house while waiting ends the scan with a clear reason; later data is ignored.
    ns.db.lastFullScan = nil
    eq(ns.AHScan.FullScan(), true)
    S.Fire("AUCTION_HOUSE_CLOSED")
    eq(states[#states], "failed")
    local n = #states
    S.Fire("REPLICATE_ITEM_LIST_UPDATE")
    eq(#states, n, "no scan running")
    C_Timer.After = after
end)


test("category scan: pages through each chosen category, then finishes; it can be stopped", function()
    local ns = S.LoadAddon(ROOT)
    assert(loadfile(ROOT .. "/AuctionScan.lua"))("GoblinBooks", ns)
    local after, pending = C_Timer.After, {}
    C_Timer.After = function(delay, fn) if delay <= 0 then fn() else pending[#pending + 1] = fn end end
    local function RunTimers(seconds)
        S.Advance(seconds)
        local list = pending
        pending = {}
        for _, fn in ipairs(list) do fn() end
    end
    AuctionCategories = {
        { name = "Weapons", filters = { { classID = 2 } } },
        { name = "Trade Goods", filters = { { classID = 7 } } },
        { name = "Consumables", filters = { { classID = 0 } } },
    }
    local queries, more, results, full = {}, 0, {}, false
    C_AuctionHouse.SendBrowseQuery = function(q) queries[#queries + 1] = q.itemClassFilters[1].classID end
    C_AuctionHouse.GetBrowseResults = function() return results end
    C_AuctionHouse.HasFullBrowseResults = function() return full end
    C_AuctionHouse.RequestMoreBrowseResults = function() more = more + 1 end
    C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
    local function Row(id, price, qty) return { itemKey = { itemID = id }, minPrice = price, totalQuantity = qty } end
    local states = {}
    ns:Register("SCAN_PROGRESS", function(state) states[#states + 1] = state end)

    -- Crafting markets: Trade Goods and Consumables only (not Weapons).
    eq(ns.AHScan.CategoryScan("crafting"), true)
    eq(ns.AHScan.catScanning, true)
    eq(queries[1], 7)
    -- Trade Goods: two pages.
    results, full = { Row(2770, 500, 10), Row(2771, 900, 4) }, false
    S.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    RunTimers(1) -- waits for the request spacing, then asks for the next page
    eq(more, 1)
    full = true
    S.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { Row(2772, 300, 20) })
    eq(queries[2], nil, "requests stay spaced out")
    RunTimers(1)
    eq(queries[2], 0, "then Consumables")
    results = { Row(118, 50, 40) }
    S.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    eq(#queries, 2, "Weapons skipped")
    eq(states[#states], "done")
    eq(ns.AHScan.catScanning, false)
    eq(ns.db.lastScanResult.items, 4)
    eq(ns.db.lastScanResult.auctions, 74)
    eq(ns.db.lastScanResult.kind, "categories")
    eq(ns.Prices.Get(2772).p, 300)

    -- Stopping keeps what was found and frees the search budget.
    eq(ns.AHScan.CategoryScan("all"), true)
    eq(ns.AHScan.CategoryScan("all"), false, "one at a time")
    ns.AHScan.StopCategoryScan()
    eq(states[#states], "stopped")
    eq(ns.AHScan.catScanning, false)
    C_Timer.After = after
    AuctionCategories = nil
end)


print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
