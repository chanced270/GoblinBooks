-- The money-delta engine. Every PLAYER_MONEY change becomes ledger entries that sum exactly to the delta.
-- Attribution order: (1) pending expectations set by API hooks, (2) the most recent open context
-- (merchant, mail, AH, ...), (3) "other".
local _, ns = ...
local M = {}
ns.Money = M

M.now = function() return GetTime() end   -- monotonic seconds, for expiry
M.clock = function() return time() end    -- wall clock, for entry timestamps

local classifiers = {}
local contexts = {}
local pendings = {}
local seq = 0

M.session, M.sessionOther = 0, 0

function M:Reset()
    wipe(contexts)
    wipe(pendings)
    seq = 0
    self.last, self.session, self.sessionOther = nil, 0, 0
end

---------------------------------------------------------------------------
-- Contexts: an open window/interaction that explains money changes.
-- classify(delta, data) -> category, sub   (nil to pass)
---------------------------------------------------------------------------
function M:RegisterContext(name, classify)
    classifiers[name] = classify
end

function M:Enter(name, data)
    seq = seq + 1
    contexts[name] = { seq = seq, data = data }
end

--- Leave a context. `linger` keeps it alive briefly because money often arrives after the window closes.
function M:Leave(name, linger)
    local c = contexts[name]
    if not c then return end
    if linger and linger > 0 then
        c.expires = self.now() + linger
    else
        contexts[name] = nil
    end
end

function M:IsActive(name)
    local c = contexts[name]
    return c ~= nil and (not c.expires or c.expires > self.now())
end

function M:ContextData(name)
    local c = contexts[name]
    return c and c.data
end

---------------------------------------------------------------------------
-- Expectations: one-shot attributions from hooked API calls.
-- spec = { cat, s?, i?, q?, n?, sign? (+1/-1), amount? (exact delta), ttl?,
--          resolve?(delta, spec) -> entries, onRecord?(entries, delta) }
---------------------------------------------------------------------------
function M:Expect(spec)
    spec.expires = self.now() + (spec.ttl or 3)
    pendings[#pendings + 1] = spec
    return spec
end

local function Matches(spec, delta)
    if spec.amount then return spec.amount == delta end
    if spec.sign then return (delta > 0) == (spec.sign > 0) end
    return true
end

--- Several exact expectations whose amounts add up to delta (e.g. sale mails taken at once, whose gold
--- the client reports as one change). Oldest expectations are tried first. Returns a list or nil.
local MAX_COMBO = 16
local function FindCombo(delta)
    local cands = {}
    for _, spec in ipairs(pendings) do
        local a = spec.amount
        if a and a ~= 0 and (a > 0) == (delta > 0) and math.abs(a) < math.abs(delta) then
            cands[#cands + 1] = spec
            if #cands >= MAX_COMBO then break end
        end
    end
    if #cands < 2 then return nil end
    local chosen = {}
    local function Search(start, left)
        if left == 0 then return #chosen >= 2 end
        for i = start, #cands do
            local a = cands[i].amount
            if (delta > 0 and a <= left) or (delta < 0 and a >= left) then
                chosen[#chosen + 1] = cands[i]
                if Search(i + 1, left - a) then return true end
                chosen[#chosen] = nil
            end
        end
        return false
    end
    if Search(1, delta) then return chosen end
    return nil
end

--- The expectation for this change: one spec, or { combo = { specs } } when several add up to it.
function M:TakePending(delta)
    local now = self.now()
    for i = #pendings, 1, -1 do
        if pendings[i].expires <= now then table.remove(pendings, i) end
    end
    -- Exact amount first, then a combination of exact amounts, then sign-only expectations.
    for i, spec in ipairs(pendings) do
        if spec.amount ~= nil and Matches(spec, delta) then
            table.remove(pendings, i)
            return spec
        end
    end
    local combo = FindCombo(delta)
    if combo then
        for _, spec in ipairs(combo) do
            for i, p in ipairs(pendings) do
                if p == spec then table.remove(pendings, i) break end
            end
        end
        return { combo = combo }
    end
    for i, spec in ipairs(pendings) do
        if spec.amount == nil and Matches(spec, delta) then
            table.remove(pendings, i)
            return spec
        end
    end
end

function M:FromContext(delta)
    local now = self.now()
    local active = {}
    for name, c in pairs(contexts) do
        if c.expires and c.expires <= now then
            contexts[name] = nil
        else
            active[#active + 1] = { name = name, c = c }
        end
    end
    table.sort(active, function(a, b) return a.c.seq > b.c.seq end)
    for _, item in ipairs(active) do
        local fn = classifiers[item.name]
        if fn then
            local cat, sub = fn(delta, item.c.data)
            if cat then return cat, sub end
        end
    end
end

local function SpecEntries(spec, delta)
    local entries
    if spec.resolve then
        local ok, res = pcall(spec.resolve, delta, spec)
        if ok then entries = res end
    end
    if not entries or #entries == 0 then
        entries = { { a = delta, c = spec.cat or "other", s = spec.s, i = spec.i, q = spec.q, n = spec.n } }
    end
    return entries
end

--- Turn a delta into ledger entries. Guarantees sum(entries.a) == delta.
function M:Classify(delta)
    local spec = self:TakePending(delta)
    local entries
    if spec and spec.combo then
        entries = {}
        for _, s in ipairs(spec.combo) do
            for _, e in ipairs(SpecEntries(s, s.amount)) do entries[#entries + 1] = e end
        end
    elseif spec then
        entries = SpecEntries(spec, delta)
    else
        local cat, sub = self:FromContext(delta)
        entries = { { a = delta, c = cat or "other", s = sub } }
    end
    local sum = 0
    for _, e in ipairs(entries) do sum = sum + e.a end
    if sum ~= delta then entries[1].a = entries[1].a + (delta - sum) end
    return entries, spec
end

function M:Record(delta)
    local entries, spec = self:Classify(delta)
    local t = self.clock()
    local recorded = {}
    for _, e in ipairs(entries) do
        if e.a ~= 0 then
            e.t = t
            ns.Ledger.Add(ns.char, e)
            recorded[#recorded + 1] = e
            if e.c == "other" then self.sessionOther = self.sessionOther + e.a end
            if ns.db.settings.debug then
                ns:Print(("%s  %s%s"):format(ns.Util.FormatMoney(e.a, true), ns.Categories.Label(e.c),
                    (e.s or e.n) and ("  (" .. tostring(e.n or e.s) .. ")") or ""))
            end
        end
    end
    for _, s in ipairs(spec and (spec.combo or { spec }) or {}) do
        if s.onRecord then
            local ok, err = pcall(s.onRecord, recorded, s.amount or delta)
            if not ok and ns.db.settings.debug then ns:Print("onRecord error: " .. tostring(err)) end
        end
    end
    ns:Fire("LEDGER_UPDATED")
    return recorded
end

--- Reclassify a just-recorded "other" entry when attribution info arrives after the money changed.
--- amount == nil matches any positive entry. Returns true if handled (or already correct).
function M:ClaimRecent(cat, amount, window, sub, note)
    local list = ns.char and ns.char.entries
    if not list then return false end
    local now = self.clock()
    for i = #list, math.max(1, #list - 10), -1 do
        local e = list[i]
        if now - e.t > window then break end
        local amountOK = (amount == nil and e.a > 0) or e.a == amount
        if amountOK then
            if e.c == cat then return true end
            if e.c == "other" then
                ns.Ledger.Reclassify(ns.char, e, cat, sub, note)
                self.sessionOther = self.sessionOther - e.a
                ns:Fire("LEDGER_UPDATED")
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:OnMoney()
    if not ns.char then return end
    local money = GetMoney()
    if not self.last then self.last = money return end
    local delta = money - self.last
    self.last = money
    ns.char.lastMoney = money
    if delta ~= 0 then
        self.session = self.session + delta
        self:Record(delta)
    end
end

function M:Start()
    local money = GetMoney()
    local c = ns.char
    -- lastMoney 0 can be a leftover of that logout bug, so it isn't trusted.
    if c.lastMoney and c.lastMoney ~= 0 and c.lastMoney ~= money then
        -- Gold changed while the addon wasn't watching (addon disabled, other tools...). Keep books balanced.
        ns.Ledger.Add(c, { t = self.clock(), a = money - c.lastMoney, c = "other", n = "Changed while offline" })
    end
    c.lastMoney = money
    self.last = money
    self.sessionStart = money
    self.session, self.sessionOther = 0, 0
end

function M:Reconcile()
    local actual = GetMoney() - (self.sessionStart or GetMoney())
    local U = ns.Util
    ns:Print(("Session: actual change %s, ledger %s, drift %s"):format(
        U.FormatMoney(actual, true), U.FormatMoney(self.session, true), U.FormatMoney(actual - self.session, true)))
    ns:Print(("Unattributed ('Other') this session: %s"):format(U.FormatMoney(self.sessionOther, true)))
end

ns:On("PLAYER_MONEY", function() M:OnMoney() end)
-- No PLAYER_LOGOUT update: lastMoney is already current (set at login and on every change), and on
-- WoW Forever GetMoney() reports 0 while logging out, which made the next login book the whole balance
-- as "Changed while offline".
