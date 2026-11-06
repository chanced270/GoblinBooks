-- Mail: AH sale invoices, AH purchase invoices, gold from other players/system, COD and sending gold.
local _, ns = ...
local M, U = ns.Money, ns.Util

M:RegisterContext("mail", function(delta)
    return delta > 0 and "mail_in" or "postage"
end)

ns:On("MAIL_SHOW", function() M:Enter("mail") end)
ns:On("MAIL_CLOSED", function() M:Leave("mail", 2) end)

local processedBuyerInvoices = {}

local function InboxInfo(index)
    local _, _, sender, subject, money, cod, daysLeft, _, _, _, _, canReply = GetInboxHeaderInfo(index)
    local invoiceType, itemName, playerName, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
    -- AH mails last 30 days, so the time left dates when it was sent (when the auction resolved).
    local sentAt = daysLeft and (time() - math.max(0, 30 - daysLeft) * 86400) or nil
    return {
        sentAt = sentAt,
        sender = sender, subject = subject, money = money or 0, cod = cod or 0, daysLeft = daysLeft,
        canReply = canReply, invoiceType = invoiceType, itemName = itemName, playerName = playerName,
        bid = bid or 0, deposit = deposit or 0, consignment = consignment or 0, count = count,
    }
end

-- Localized AH mail subjects ("Outbid on %s", "Auction expired: %s", "Auction cancelled: %s") -> Lua
-- patterns capturing the item name.
local function SubjectPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    return "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end
local OUTBID_PATTERN = SubjectPattern(AUCTION_OUTBID_MAIL_SUBJECT)
local EXPIRED_PATTERN = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
local CANCELLED_PATTERN = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT)

local function OutbidItem(subject)
    if OUTBID_PATTERN and subject then return subject:match(OUTBID_PATTERN) end
end

--- "expired"/"cancelled" and the item name for an unsold-auction mail.
local function UnsoldMail(subject)
    if not subject then return nil end
    local name = EXPIRED_PATTERN and subject:match(EXPIRED_PATTERN)
    if name then return "expired", name end
    name = CANCELLED_PATTERN and subject:match(CANCELLED_PATTERN)
    if name then return "cancelled", name end
end

local processedUnsold = {}

local function ExpectMoney(index, info)
    if info.money <= 0 then return end
    local outbid = not info.invoiceType and OutbidItem(info.subject)
    if info.invoiceType == "seller" then
        ns.AuctionHouse:ExpectSale(info)
    elseif outbid then
        -- Not income: this is our own bid coming back. Release the matching hold.
        M:Expect({
            cat = "ah_bid", amount = info.money, ttl = 10, n = "Outbid, bid returned: " .. outbid,
            onRecord = function() ns.AuctionHouse:TakeHeldBid(outbid, info.money) end,
        })
    else
        M:Expect({
            cat = "mail_in", amount = info.money, ttl = 10,
            s = info.sender, n = info.subject ~= "" and info.subject or nil,
        })
    end
end

local function HandleItemTake(index, info)
    if info.cod > 0 then
        M:Expect({ cat = "mail_out", amount = -info.cod, ttl = 10, s = info.sender, n = "COD payment" })
    end
    local kind, unsoldName = nil, nil
    if not info.invoiceType then kind, unsoldName = UnsoldMail(info.subject) end
    if kind then
        local itemID, count
        if GetInboxItem then
            local ok, _, id, _, n = pcall(GetInboxItem, index, 1)
            if ok then itemID, count = id, n end
        end
        local key = table.concat({ info.subject, tostring(info.daysLeft), tostring(count) }, "|")
        if not processedUnsold[key] then
            processedUnsold[key] = true
            ns.AuctionHouse:OnUnsoldMail(unsoldName, itemID, count, kind)
        end
    end
    if info.invoiceType == "buyer" then
        -- Deduplicate: the same mail can be touched by several take calls.
        local key = table.concat({ tostring(info.itemName), info.bid, tostring(info.daysLeft), tostring(info.playerName) }, "|")
        if not processedBuyerInvoices[key] then
            processedBuyerInvoices[key] = true
            local link = GetInboxItemLink and GetInboxItemLink(index, 1)
            ns.AuctionHouse:OnBuyerInvoice(info, link)
        end
    end
end

local function Safe(fn)
    return function(index, ...)
        if not index then return end
        local ok, info = pcall(InboxInfo, index)
        if ok and info then fn(index, info, ...) end
    end
end

U.HookGlobal("TakeInboxMoney", Safe(function(index, info)
    ExpectMoney(index, info)
end))

U.HookGlobal("AutoLootMailItem", Safe(function(index, info)
    ExpectMoney(index, info)
    HandleItemTake(index, info)
end))

U.HookGlobal("TakeInboxItem", Safe(function(index, info)
    HandleItemTake(index, info)
end))

-- Sending: gold sent and postage may arrive as one combined change or as two.
U.HookGlobal("SendMail", function(recipient)
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    local postage = GetSendMailPrice and GetSendMailPrice() or 0
    if money > 0 then
        M:Expect({
            amount = -(money + postage), ttl = 10,
            resolve = function()
                local out = { { a = -money, c = "mail_out", s = recipient } }
                if postage > 0 then out[2] = { a = -postage, c = "postage", s = recipient } end
                return out
            end,
        })
        M:Expect({ cat = "mail_out", amount = -money, ttl = 10, s = recipient })
    end
    if postage > 0 then
        M:Expect({ cat = "postage", amount = -postage, ttl = 10, s = recipient })
    end
end)
