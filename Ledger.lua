local _, CP = ...
-- Gold ledger: every copper that comes in or goes out, sorted by where it came from or went.
-- Account-wide, per day (ProfiteerDB.ledger[day][category] = copper), plus all-time totals per character.
local L = {}
CP.Ledger = L

L.INCOME = {
  { "sales", "AH sales" }, { "depositBack", "AH deposits returned" }, { "vendorSales", "Vendor sales" },
  { "quests", "Quest rewards" }, { "loot", "Looted coin" }, { "mailIn", "Gold from mail" }, { "tradeIn", "Trades received" },
  { "otherIn", "Other income" },
}
L.COSTS = {
  { "deposits", "AH deposits" }, { "cut", "AH cut (sale fees)" }, { "ahBuys", "AH purchases" },
  { "vendorBuys", "Vendor purchases" }, { "repairs", "Repairs" }, { "mailOut", "Postage / COD" },
  { "training", "Training" }, { "flights", "Flights" }, { "bank", "Bank slots" }, { "tradeOut", "Trades given" },
  { "otherOut", "Other spending" },
}
-- moved between your own characters or into the guild bank: not earned, not spent
L.MOVED = {
  { "transferIn", "Mailed in from your characters" }, { "transferOut", "Mailed out to your characters" },
  { "guildOut", "Put in guild bank" }, { "guildIn", "Taken from guild bank" },
}

local function DayKey(t) return date("%Y-%m-%d", t or time()) end

function L.Record(cat, copper)
  if not CP.db or not copper or copper == 0 then return end
  CP.db.ledger = CP.db.ledger or {}
  local d = CP.db.ledger[DayKey()]
  if not d then d = {} CP.db.ledger[DayKey()] = d end
  d[cat] = (d[cat] or 0) + copper
  L.dirty = true
  if CP.charKey then
    CP.db.ledgerDC = CP.db.ledgerDC or {}
    local dd = CP.db.ledgerDC[DayKey()]
    if not dd then dd = {} CP.db.ledgerDC[DayKey()] = dd end
    local cc = dd[CP.charKey]
    if not cc then cc = {} dd[CP.charKey] = cc end
    cc[cat] = (cc[cat] or 0) + copper
    CP.db.ledgerChars = CP.db.ledgerChars or {}
    local c = CP.db.ledgerChars[CP.charKey]
    if not c then c = {} CP.db.ledgerChars[CP.charKey] = c end
    c[cat] = (c[cat] or 0) + copper
  end
end

local lastMoney

-- what each item earned (from sale invoices), per day
function L.RecordItem(name, sale, cut)
  if not (CP.db and name) then return end
  CP.db.ledgerItems = CP.db.ledgerItems or {}
  local d = CP.db.ledgerItems[DayKey()]
  if not d then d = {} CP.db.ledgerItems[DayKey()] = d end
  local e = d[name]
  if not e then e = { n = 0, g = 0, c = 0 } d[name] = e end
  e.n, e.g, e.c = e.n + 1, e.g + (sale or 0), e.c + (cut or 0)
end

-- gold on hand per character, per day: the first value seen that day and the latest
local function Worth()
  if not (CP.db and CP.charKey) then return end
  CP.db.worth = CP.db.worth or {}
  local d = CP.db.worth[DayKey()]
  if not d then d = {} CP.db.worth[DayKey()] = d end
  local e = d[CP.charKey]
  local m = GetMoney()
  if not e then d[CP.charKey] = { s = lastMoney or m, e = m } else e.e = m end
end

------------------------------------------------------------------------
-- What is going on right now (decides which category a money change belongs to)
------------------------------------------------------------------------
local ctx = { ah = false, merchant = false, mail = false, trainer = false, taxi = false, trade = false, bank = false, guild = false }
local postedAt, repairAt, questAt, questMoney = -10, -10, -10, 0
local pending = {}          -- seller invoices taken from the mailbox, waiting for their money to arrive
local snap = {}             -- mailbox index -> { sender, money } as last seen (the hooks run after the money is gone)
local sendMoney, sendTo = 0, nil   -- gold attached to the mail being sent
local sessionStart, sessionMoney

local function IsMine(name)
  if not (name and CP.db) then return false end
  name = name:match("^([^%-]+)") or name
  for k in pairs(CP.db.chars or {}) do
    if CP.ShortName(k):lower() == name:lower() then return true end
  end
  return false
end

local function Now() return GetTime and GetTime() or 0 end

local function Classify(delta)
  local t = Now()
  if delta > 0 then
    -- gold that came with auction sale mails: split into the sale, the fee and the returned deposit
    if ctx.mail then
      for i = #pending, 1, -1 do
        if t - pending[i].t > 8 then table.remove(pending, i) end
      end
      local i = 1
      while i <= #pending and delta > 0 do
        local p = pending[i]
        if p.net <= delta and p.transfer then
          L.Record("transferIn", p.net)
          delta = delta - p.net
          table.remove(pending, i)
        elseif p.net <= delta then
          L.Record("sales", p.sale)
          L.Record("depositBack", p.deposit)
          L.Record("cut", -p.cut)
          L.RecordItem(p.item, p.sale, p.cut)
          delta = delta - p.net
          table.remove(pending, i)
        else
          i = i + 1
        end
      end
      if delta > 0 then L.Record("mailIn", delta) end
      return
    end
    if questMoney > 0 and t - questAt < 3 then
      local q = math.min(delta, questMoney)
      L.Record("quests", q)
      questMoney = questMoney - q
      delta = delta - q
      if delta <= 0 then return end
    end
    if ctx.guild then L.Record("guildIn", delta) return end
    if ctx.trade then L.Record("tradeIn", delta) return end
    if ctx.merchant then L.Record("vendorSales", delta) return end
    L.Record("loot", delta)
  else
    local c = -delta
    if ctx.ah then
      if t - postedAt < 2 then L.Record("deposits", -c) else L.Record("ahBuys", -c) end
    elseif ctx.merchant then
      if t - repairAt < 2 then L.Record("repairs", -c) else L.Record("vendorBuys", -c) end
    elseif ctx.guild then L.Record("guildOut", -c)
    elseif ctx.trade then L.Record("tradeOut", -c)
    elseif ctx.mail then
      if sendMoney > 0 and IsMine(sendTo) and c >= sendMoney then
        L.Record("transferOut", -sendMoney)
        c = c - sendMoney
        sendMoney = 0
        if c > 0 then L.Record("mailOut", -c) end
      else
        sendMoney = 0
        L.Record("mailOut", -c)
      end
    elseif ctx.bank then L.Record("bank", -c)
    elseif ctx.trainer then L.Record("training", -c)
    elseif ctx.taxi then L.Record("flights", -c)
    else L.Record("otherOut", -c) end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
  "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "PLAYER_LOGOUT", "TRADE_SHOW", "TRADE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "QUEST_TURNED_IN" }) do
  CP.Register(f, e)
end
f:SetScript("OnEvent", CP.Safe("ledger", function(_, event, a1, a2, a3)
  if event == "PLAYER_LOGIN" then
    lastMoney = GetMoney()
    sessionStart, sessionMoney = time(), lastMoney
    Worth()
  elseif event == "PLAYER_LOGOUT" then
    Worth()
  elseif event == "PLAYER_MONEY" then
    local now = GetMoney()
    local delta = now - (lastMoney or now)
    if delta ~= 0 then Classify(delta) end
    lastMoney = now
    Worth()
  elseif event == "MAIL_INBOX_UPDATE" then
    snap = {}
    if GetInboxNumItems and GetInboxHeaderInfo then
      for i = 1, GetInboxNumItems() or 0 do
        local _, _, sender, _, money = GetInboxHeaderInfo(i)
        snap[i] = { sender = sender, money = money or 0 }
      end
    end
  elseif event == "TRADE_SHOW" then ctx.trade = true
  elseif event == "TRADE_CLOSED" then ctx.trade = false
  elseif event == "BANKFRAME_OPENED" then ctx.bank = true
  elseif event == "BANKFRAME_CLOSED" then ctx.bank = false
  elseif event == "GUILDBANKFRAME_OPENED" then ctx.guild = true
  elseif event == "GUILDBANKFRAME_CLOSED" then ctx.guild = false
  elseif event == "AUCTION_HOUSE_SHOW" then ctx.ah = true
  elseif event == "AUCTION_HOUSE_CLOSED" then ctx.ah = false
  elseif event == "MERCHANT_SHOW" then ctx.merchant = true
  elseif event == "MERCHANT_CLOSED" then ctx.merchant = false
  elseif event == "MAIL_SHOW" then ctx.mail = true
  elseif event == "MAIL_CLOSED" then ctx.mail = false
  elseif event == "TRAINER_SHOW" then ctx.trainer = true
  elseif event == "TRAINER_CLOSED" then ctx.trainer = false
  elseif event == "TAXIMAP_OPENED" then ctx.taxi = true
  elseif event == "TAXIMAP_CLOSED" then ctx.taxi = false
  elseif event == "QUEST_TURNED_IN" then
    if type(a3) == "number" and a3 > 0 then questMoney, questAt = a3, Now() end
  end
end))

-- Auction posting and repairs are done through the game's functions, so listen for those calls.
local function Hook(tbl, name, fn)
  if tbl and type(tbl[name]) == "function" then pcall(hooksecurefunc, tbl, name, CP.Safe("ledger hook", fn)) end
end
local function Posted() postedAt = Now() end
Hook(_G.C_AuctionHouse, "PostItem", Posted)
Hook(_G.C_AuctionHouse, "PostCommodity", Posted)
Hook(_G, "StartAuction", Posted)
Hook(_G, "RepairAllItems", function() repairAt = Now() end)

-- gold you attach to mail, and who it goes to (mail to your own characters is a transfer, not spending)
Hook(_G, "SetSendMailMoney", function(amount) sendMoney = tonumber(amount) or 0 end)
Hook(_G, "SendMail", function(recipient) sendTo = recipient end)

-- Mailbox: remember what a sale invoice says before the money arrives.
local function TookMail(index)
  if not index then return end
  local sn = snap[index]
  local ok, kind, item, _, bid, buyout, deposit, consignment
  if GetInboxInvoiceInfo then ok, kind, item, _, bid, buyout, deposit, consignment = pcall(GetInboxInvoiceInfo, index) end
  local t = Now()
  if not (ok and kind == "seller") then
    -- plain gold from one of your own characters: a transfer
    if sn and (sn.money or 0) > 0 and IsMine(sn.sender) then
      pending[#pending + 1] = { net = sn.money, transfer = true, t = t }
      sn.money = 0
    end
    return
  end
  local sale = (bid and bid > 0) and bid or (buyout or 0)
  deposit, consignment = deposit or 0, consignment or 0
  local net = sale + deposit - consignment
  if net <= 0 then return end
  -- the same open mailbox can fire both hooks for one mail; ignore an identical entry added a moment ago
  for _, p in ipairs(pending) do
    if p.sale == sale and p.cut == consignment and p.deposit == deposit and t - p.t < 1 then return end
  end
  pending[#pending + 1] = { sale = sale, deposit = deposit, cut = consignment, net = net, t = t, item = item }
end
Hook(_G, "TakeInboxMoney", TookMail)
Hook(_G, "AutoLootMailItem", TookMail)

------------------------------------------------------------------------
-- Report
------------------------------------------------------------------------
local PERIODS = { today = 0, week = 6, month = 29 }

local function Sum(days)
  local tot = {}
  for _, d in pairs(days) do
    for k, v in pairs(d) do tot[k] = (tot[k] or 0) + v end
  end
  return tot
end

local function Block(lines, title, rows, tot)
  local sum = 0
  lines[#lines + 1] = title
  for _, r in ipairs(rows) do
    local v = tot[r[1]] or 0
    if v ~= 0 then
      lines[#lines + 1] = ("  %-30s %s"):format(r[2], CP.MoneyPlain(math.abs(v)))
      sum = sum + v
    end
  end
  return sum
end

local function Period(period)
  local db = CP.db or {}
  local cutoff, label = nil, "all time"
  if PERIODS[period] then
    cutoff = DayKey(time() - PERIODS[period] * 86400)
    label = period == "today" and "today" or period == "week" and "last 7 days" or "last 30 days"
  end
  local function pick(src)
    local out = {}
    for k, d in pairs(src or {}) do if not cutoff or k >= cutoff then out[k] = d end end
    return out
  end
  return pick(db.ledger), pick(db.ledgerItems), pick(db.worth), label
end

local function Fmt(label, v) return ("  %-30s %s"):format(label, CP.MoneyPlain(v)) end

function L.Lines(period)
  local db = CP.db or {}
  local days, items, worth, label = Period(period)
  local tot = Sum(days)
  local lines = { ("Gold ledger, %s (all your characters)"):format(label), "" }

  local income = Block(lines, "COMING IN", L.INCOME, tot)
  lines[#lines + 1] = Fmt("Total in", income)
  lines[#lines + 1] = ""
  local spent = Block(lines, "GOING OUT", L.COSTS, tot)
  lines[#lines + 1] = Fmt("Total out", -spent)
  lines[#lines + 1] = ""
  local net = income + spent
  lines[#lines + 1] = ("NET PROFIT  %s"):format(CP.MoneyPlain(net))
  local overhead = -((tot.deposits or 0) + (tot.depositBack or 0) + (tot.cut or 0) + (tot.repairs or 0) + (tot.flights or 0) + (tot.training or 0) + (tot.bank or 0))
  lines[#lines + 1] = ("OVERHEAD  %s   (deposits kept, sale fees, repairs, flights, training, bank slots)"):format(CP.MoneyPlain(overhead))
  if tot.sales and tot.sales > 0 then
    local ahNet = tot.sales + (tot.cut or 0) + (tot.deposits or 0) + (tot.depositBack or 0) + (tot.ahBuys or 0)
    lines[#lines + 1] = ("AH RESULT  %s   (sales minus fees, deposits and what you bought there)"):format(CP.MoneyPlain(ahNet))
    lines[#lines + 1] = ("Overhead is %d%% of your AH sales"):format(math.floor(100 * overhead / tot.sales + 0.5))
  end

  -- moved around, not earned or spent
  local moved = {}
  for _, r in ipairs(L.MOVED) do
    local v = tot[r[1]] or 0
    if v ~= 0 then moved[#moved + 1] = Fmt(r[2], math.abs(v)) end
  end
  if #moved > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "MOVED, NOT EARNED OR SPENT"
    for _, m in ipairs(moved) do lines[#lines + 1] = m end
  end

  -- what sold best
  local byItem = {}
  for _, d in pairs(items) do
    for name, e in pairs(d) do
      local x = byItem[name]
      if not x then x = { n = 0, g = 0, c = 0 } byItem[name] = x end
      x.n, x.g, x.c = x.n + e.n, x.g + e.g, x.c + e.c
    end
  end
  local list = {}
  for name, e in pairs(byItem) do list[#list + 1] = { name = name, e = e } end
  table.sort(list, function(a, b) return a.e.g > b.e.g end)
  if #list > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BEST SELLERS (gross, from sale invoices)"
    for i = 1, math.min(#list, 10) do
      local e = list[i].e
      lines[#lines + 1] = ("  %-28s %3d sold   %s   (fees %s)"):format(list[i].name, e.n, CP.MoneyPlain(e.g), CP.MoneyPlain(e.c))
    end
  end

  -- gold on hand and a cross-check against the ledger
  local startSum, endSum, chars = 0, 0, {}
  local keys = {}
  for k in pairs(worth) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    for ck, e in pairs(worth[k]) do
      if not chars[ck] then chars[ck] = { s = e.s, e = e.e } else chars[ck].e = e.e end
    end
  end
  local any = false
  for _, c in pairs(chars) do startSum, endSum, any = startSum + c.s, endSum + c.e, true end
  if any then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "GOLD ON HAND (latest seen)"
    for ck, c in pairs(chars) do lines[#lines + 1] = Fmt(CP.ShortName(ck), c.e) end
    lines[#lines + 1] = Fmt("All characters", endSum)
    local change = endSum - startSum
    local moves = (tot.guildIn or 0) + (tot.guildOut or 0) + (tot.transferIn or 0) + (tot.transferOut or 0)
    local unexplained = change - net - moves
    lines[#lines + 1] = ("Change over this period: %s"):format(CP.MoneyPlain(change))
    if math.abs(unexplained) >= 100 then
      lines[#lines + 1] = ("Not explained by the ledger: %s  (gold from a source Profiteer can't see, or before tracking began)"):format(CP.MoneyPlain(unexplained))
    else
      lines[#lines + 1] = "The ledger accounts for all of it."
    end
  end

  -- this session
  if sessionStart and sessionMoney then
    local gained = GetMoney() - sessionMoney
    local hrs = math.max((time() - sessionStart) / 3600, 1 / 60)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("THIS SESSION: %s so far, about %s per hour"):format(CP.MoneyPlain(gained), CP.MoneyPlain(gained / hrs))
  end

  -- per day
  local dkeys = {}
  for k in pairs(days) do dkeys[#dkeys + 1] = k end
  table.sort(dkeys, function(a, b) return a > b end)
  if #dkeys > 1 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BY DAY (in / out / net)"
    for i = 1, math.min(#dkeys, 30) do
      local d = days[dkeys[i]]
      local inn, out = 0, 0
      for _, r in ipairs(L.INCOME) do inn = inn + (d[r[1]] or 0) end
      for _, r in ipairs(L.COSTS) do out = out + (d[r[1]] or 0) end
      lines[#lines + 1] = ("  %s   +%s   -%s   = %s"):format(dkeys[i], CP.MoneyPlain(inn), CP.MoneyPlain(-out), CP.MoneyPlain(inn + out))
    end
  end
  if period == "all" and db.ledgerChars then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BY CHARACTER (net, all time)"
    for ck, c in pairs(db.ledgerChars) do
      local n = 0
      for _, r in ipairs(L.INCOME) do n = n + (c[r[1]] or 0) end
      for _, r in ipairs(L.COSTS) do n = n + (c[r[1]] or 0) end
      lines[#lines + 1] = Fmt(CP.ShortName(ck), n)
    end
  end
  if next(db.ledger or {}) == nil then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Nothing recorded yet. The ledger counts every gold change from now on."
  end
  return lines
end

function L.Show(period)
  period = (period or ""):lower()
  if period == "" then period = "week" end
  if period ~= "today" and period ~= "week" and period ~= "month" and period ~= "all" then period = "week" end
  CP.Report.Open("Gold ledger: " .. period, L.Lines(period),
    "/pf ledger today | week | month | all     Ctrl+C copies this. Scroll with the mouse wheel.")
end

function L.Reset()
  if CP.db then CP.db.ledger, CP.db.ledgerChars, CP.db.ledgerItems, CP.db.worth, CP.db.ledgerDC = {}, {}, {}, {}, {} end
end

------------------------------------------------------------------------
-- The Ledger tab
------------------------------------------------------------------------
local function SumIn(t) local n = 0 for _, r in ipairs(L.INCOME) do n = n + (t[r[1]] or 0) end return n end
local function SumOut(t) local n = 0 for _, r in ipairs(L.COSTS) do n = n + (t[r[1]] or 0) end return -n end
local function Pct(v, of) if not of or of == 0 then return "" end return ("%d%%"):format(math.floor(100 * v / of + 0.5)) end
local M = function(v) return CP.Money(v) end
local function Signed(v) v = math.floor(v + 0.5) return (v >= 0 and "|cff40ff40" or "|cffff4040") .. CP.MoneyPlain(v) .. "|r" end

-- days for the chosen period and (optionally) one character
local function Days(period, ck)
  local cutoff
  if PERIODS[period] then cutoff = DayKey(time() - PERIODS[period] * 86400) end
  local db = CP.db or {}
  local out = {}
  if ck then
    for k, d in pairs(db.ledgerDC or {}) do
      if (not cutoff or k >= cutoff) and d[ck] then out[k] = d[ck] end
    end
  else
    for k, d in pairs(db.ledger or {}) do if not cutoff or k >= cutoff then out[k] = d end end
  end
  return out, cutoff
end

-- Builds the table shown on the tab: { k = "head"|"row"|"gap", a, b, c, d, e } (columns left to right)
function L.Rows(period, ck)
  local db = CP.db or {}
  local days, cutoff = Days(period, ck)
  local tot = Sum(days)
  local rows = {}
  local function head(a, b, c, d, e) rows[#rows + 1] = { k = "head", a, b, c, d, e } end
  local function row(a, b, c, d, e) rows[#rows + 1] = { k = "row", a, b, c, d, e } end
  local function gap() rows[#rows + 1] = { k = "gap" } end

  local inn, out = SumIn(tot), SumOut(tot)
  local net = inn - out

  -- summary
  local keys = {}
  for k in pairs(days) do keys[#keys + 1] = k end
  table.sort(keys)
  head("SUMMARY")
  row("Days with activity", #keys)
  if #keys > 0 then
    local best, worst
    for _, k in ipairs(keys) do
      local d = days[k]
      local n = SumIn(d) - SumOut(d)
      if not best or n > best.n then best = { k = k, n = n } end
      if not worst or n < worst.n then worst = { k = k, n = n } end
    end
    row("Average net per active day", Signed(net / #keys))
    row("Best day", Signed(best.n), best.k)
    row("Worst day", Signed(worst.n), worst.k)
  end
  if sessionStart and sessionMoney and not ck then
    local gained = GetMoney() - sessionMoney
    local hrs = math.max((time() - sessionStart) / 3600, 1 / 60)
    row("This session so far", Signed(gained), (M(math.floor(gained / hrs))) .. " per hour")
  end
  gap()

  head("COMING IN", "Amount", "% of income")
  for _, r in ipairs(L.INCOME) do
    local v = tot[r[1]] or 0
    if v ~= 0 then row(r[2], M(v), Pct(v, inn)) end
  end
  row("|cffffd100Total in|r", M(inn))
  gap()
  head("GOING OUT", "Amount", "% of spending")
  for _, r in ipairs(L.COSTS) do
    local v = -(tot[r[1]] or 0)
    if v ~= 0 then row(r[2], M(v), Pct(v, out)) end
  end
  row("|cffffd100Total out|r", M(out))
  gap()

  -- auction house in detail
  local items = {}
  do
    local cut2 = cutoff
    for k, d in pairs(db.ledgerItems or {}) do
      if not cut2 or k >= cut2 then
        for name, e in pairs(d) do
          local x = items[name]
          if not x then x = { n = 0, g = 0, c = 0 } items[name] = x end
          x.n, x.g, x.c = x.n + e.n, x.g + e.g, x.c + e.c
        end
      end
    end
  end
  local nSales = 0
  for _, e in pairs(items) do nSales = nSales + e.n end
  local sales, fees = tot.sales or 0, -(tot.cut or 0)
  local dep, depBack = -(tot.deposits or 0), tot.depositBack or 0
  if sales > 0 or dep > 0 or (tot.ahBuys or 0) ~= 0 then
    head("AUCTION HOUSE" .. (ck and " (sales counts: all characters)" or ""))
    if nSales > 0 then
      row("Sales made", nSales)
      row("Average sale", M(math.floor(sales / nSales)))
    end
    row("Gross sales", M(sales))
    row("Fees (the AH cut)", M(fees), Pct(fees, sales) .. (sales > 0 and " of sales" or ""))
    row("Deposits paid", M(dep))
    row("Deposits returned", M(depBack))
    row("Deposits lost (expired or cancelled)", M(math.max(0, dep - depBack)))
    row("Spent buying on the AH", M(-(tot.ahBuys or 0)))
    row("|cffffd100AH result|r", Signed(sales - fees - (dep - depBack) + (tot.ahBuys or 0)), "sales minus fees and lost deposits, minus buys")
    gap()
  end

  -- overhead
  local overhead = fees + (dep - depBack) + -(tot.repairs or 0) + -(tot.flights or 0) + -(tot.training or 0) + -(tot.bank or 0)
  head("OVERHEAD (cost of doing business)", "Amount", "% of sales")
  row("AH fees", M(fees), Pct(fees, sales))
  row("Deposits lost", M(math.max(0, dep - depBack)), Pct(math.max(0, dep - depBack), sales))
  if (tot.repairs or 0) ~= 0 then row("Repairs", M(-tot.repairs), Pct(-tot.repairs, sales)) end
  if (tot.flights or 0) ~= 0 then row("Flights", M(-tot.flights), Pct(-tot.flights, sales)) end
  if (tot.training or 0) ~= 0 then row("Training", M(-tot.training), Pct(-tot.training, sales)) end
  if (tot.bank or 0) ~= 0 then row("Bank slots", M(-tot.bank), Pct(-tot.bank, sales)) end
  row("|cffffd100Total overhead|r", M(overhead), Pct(overhead, sales))
  gap()

  -- best sellers
  local list = {}
  for name, e in pairs(items) do list[#list + 1] = { name = name, e = e } end
  table.sort(list, function(a, b) return a.e.g > b.e.g end)
  if #list > 0 then
    head("BEST SELLERS", "Sold", "Gross", "Fees", "Average")
    for i = 1, math.min(#list, 15) do
      local e = list[i].e
      row(list[i].name, e.n, M(e.g), M(e.c), M(math.floor(e.g / e.n)))
    end
    gap()
  end

  -- moved
  local any = false
  for _, r in ipairs(L.MOVED) do if (tot[r[1]] or 0) ~= 0 then any = true end end
  if any then
    head("MOVED, NOT EARNED OR SPENT")
    for _, r in ipairs(L.MOVED) do
      local v = tot[r[1]] or 0
      if v ~= 0 then row(r[2], M(math.abs(v))) end
    end
    gap()
  end

  -- by character
  if not ck then
    local per = {}
    for k, d in pairs(db.ledgerDC or {}) do
      if not cutoff or k >= cutoff then
        for c, t in pairs(d) do
          local x = per[c]
          if not x then x = { i = 0, o = 0 } per[c] = x end
          x.i, x.o = x.i + SumIn(t), x.o + SumOut(t)
        end
      end
    end
    local names = {}
    for c in pairs(per) do names[#names + 1] = c end
    table.sort(names)
    if #names > 0 then
      head("BY CHARACTER", "In", "Out", "Net")
      for _, c in ipairs(names) do row(CP.ShortName(c), M(per[c].i), M(per[c].o), Signed(per[c].i - per[c].o)) end
      gap()
    end
  end

  -- by day, newest first
  if #keys > 0 then
    head("BY DAY", "In", "Out", "Net")
    for i = #keys, math.max(1, #keys - 29), -1 do
      local d = days[keys[i]]
      row(keys[i], M(SumIn(d)), M(SumOut(d)), Signed(SumIn(d) - SumOut(d)))
    end
    gap()
  end

  -- gold on hand and the cross-check
  local chars = {}
  local wk = {}
  for k in pairs(db.worth or {}) do if not cutoff or k >= cutoff then wk[#wk + 1] = k end end
  table.sort(wk)
  for _, k in ipairs(wk) do
    for c, e in pairs(db.worth[k]) do
      if not ck or c == ck then
        if not chars[c] then chars[c] = { s = e.s, e = e.e } else chars[c].e = e.e end
      end
    end
  end
  local cnames, startSum, endSum = {}, 0, 0
  for c, v in pairs(chars) do cnames[#cnames + 1] = c startSum, endSum = startSum + v.s, endSum + v.e end
  table.sort(cnames)
  if #cnames > 0 then
    head("GOLD ON HAND", "Now", "Start of period", "Change")
    for _, c in ipairs(cnames) do
      row(CP.ShortName(c), M(chars[c].e), M(chars[c].s), Signed(chars[c].e - chars[c].s))
    end
    row("|cffffd100All shown|r", M(endSum), M(startSum), Signed(endSum - startSum))
    local moves = (tot.guildIn or 0) + (tot.guildOut or 0) + (tot.transferIn or 0) + (tot.transferOut or 0)
    local unexplained = (endSum - startSum) - net - moves
    if math.abs(unexplained) >= 100 then
      row("Not explained by the ledger", Signed(unexplained), "a source Profiteer can't see, or before tracking began")
    else
      row("|cff40ff40The ledger accounts for all of it|r")
    end
  end
  if #rows == 0 or next(days) == nil then
    rows = { { k = "row", "Nothing recorded for this period yet. The ledger counts every gold change from now on." } }
  end
  return rows, { inn = inn, out = out, net = net, overhead = overhead }
end

local PERIOD_LABELS = { { "today", "Today" }, { "week", "7 days" }, { "month", "30 days" }, { "all", "All time" } }
local COLW = { 270, 120, 130, 110, 110 }
local ROWH = 16

function L.BuildPanel(parent, width, height)
  if L.panel then return L.panel end
  L.period = L.period or "week"
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(width, height)
  p:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, -48)
  L.panel = p

  -- period buttons + character picker
  L.pbtn = {}
  local x = 0
  for _, pl in ipairs(PERIOD_LABELS) do
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(80, 22)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", x, 0)
    b:SetText(pl[2])
    b:SetScript("OnClick", function() L.period = pl[1] L.Refresh() end)
    L.pbtn[pl[1]] = b
    x = x + 84
  end
  local cb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  cb:SetSize(190, 22)
  cb:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  cb:SetScript("OnClick", function()
    local names = {}
    for c in pairs((CP.db and CP.db.ledgerChars) or {}) do names[#names + 1] = c end
    table.sort(names)
    local nxt
    if not L.char then nxt = names[1] else
      for i, c in ipairs(names) do if c == L.char then nxt = names[i + 1] end end
    end
    L.char = nxt
    L.Refresh()
  end)
  L.charBtn = cb

  -- four headline numbers
  L.tiles = {}
  local tw = math.floor((width - 3 * 8) / 4)
  local tiles = { { "net", "NET PROFIT" }, { "inn", "TOTAL IN" }, { "out", "TOTAL OUT" }, { "overhead", "OVERHEAD" } }
  for i, t in ipairs(tiles) do
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(1, 1, 1, 0.06)
    bg:SetSize(tw, 40)
    bg:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (tw + 8), -28)
    local l = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -5)
    l:SetText(t[2])
    local v = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    v:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 8, 5)
    L.tiles[t[1]] = v
  end

  -- the scrolling table
  local scroll = CreateFrame("ScrollFrame", nil, p)
  scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -76)
  scroll:SetSize(width - 4, height - 76)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur, max = self:GetVerticalScroll(), self:GetVerticalScrollRange()
    if type(cur) ~= "number" or type(max) ~= "number" then return end
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * ROWH * 3)))
  end)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width - 4, 100)
  scroll:SetScrollChild(content)
  L.scroll, L.content, L.lines = scroll, content, {}

  p:SetScript("OnShow", function() L.dirty = true L.Refresh() end)
  local acc = 0
  p:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc >= 1 then
      acc = 0
      if L.dirty then L.Refresh() end
    end
  end)
  return p
end

local function Line(i)
  local ln = L.lines[i]
  if ln then return ln end
  ln = { fs = {} }
  local x = 0
  for c = 1, 5 do
    local fs = L.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", L.content, "TOPLEFT", x, -(i - 1) * ROWH)
    fs:SetWidth(COLW[c])
    fs:SetHeight(ROWH)
    fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    ln.fs[c] = fs
    x = x + COLW[c] + 4
  end
  L.lines[i] = ln
  return ln
end

function L.Refresh()
  if not (L.panel and L.panel:IsShown() and CP.db) then return end
  L.dirty = false
  -- a character that no longer exists falls back to everyone
  if L.char and not (CP.db.ledgerChars and CP.db.ledgerChars[L.char]) then L.char = nil end
  for key, b in pairs(L.pbtn) do b:SetEnabled(key ~= L.period) end
  L.charBtn:SetText(L.char and ("Character: " .. CP.ShortName(L.char)) or "All characters")
  local rows, t = L.Rows(L.period, L.char)
  L.tiles.net:SetText(Signed(t.net))
  L.tiles.inn:SetText(M(t.inn))
  L.tiles.out:SetText(M(t.out))
  L.tiles.overhead:SetText(M(t.overhead))
  for i, r in ipairs(rows) do
    local ln = Line(i)
    for c = 1, 5 do
      local v = r[c]
      if r.k == "head" and v ~= nil then v = "|cffffd100" .. tostring(v) .. "|r" end
      if r.k == "gap" then v = nil end
      ln.fs[c]:SetText(v ~= nil and tostring(v) or "")
      ln.fs[c]:Show()
    end
  end
  for i = #rows + 1, #L.lines do
    for c = 1, 5 do L.lines[i].fs[c]:Hide() end
  end
  L.content:SetHeight(math.max(10, #rows * ROWH + 8))
end
