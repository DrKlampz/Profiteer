local _, CP = ...
-- Gold ledger: every copper that comes in or goes out, sorted by where it came from or went.
-- Account-wide, per day (ProfiteerDB.ledger[day][category] = copper), plus all-time totals per character.
local L = {}
CP.Ledger = L

L.INCOME = {
  { "sales", "AH sales" }, { "depositBack", "AH deposits returned" }, { "vendorSales", "Vendor sales" },
  { "quests", "Quest rewards" }, { "loot", "Looted coin" }, { "mailIn", "Gold from mail" }, { "otherIn", "Other income" },
}
L.COSTS = {
  { "deposits", "AH deposits" }, { "cut", "AH cut (sale fees)" }, { "ahBuys", "AH purchases" },
  { "vendorBuys", "Vendor purchases" }, { "repairs", "Repairs" }, { "mailOut", "Postage / COD" },
  { "training", "Training" }, { "flights", "Flights" }, { "otherOut", "Other spending" },
}

local function DayKey(t) return date("%Y-%m-%d", t or time()) end

function L.Record(cat, copper)
  if not CP.db or not copper or copper == 0 then return end
  CP.db.ledger = CP.db.ledger or {}
  local d = CP.db.ledger[DayKey()]
  if not d then d = {} CP.db.ledger[DayKey()] = d end
  d[cat] = (d[cat] or 0) + copper
  if CP.charKey then
    CP.db.ledgerChars = CP.db.ledgerChars or {}
    local c = CP.db.ledgerChars[CP.charKey]
    if not c then c = {} CP.db.ledgerChars[CP.charKey] = c end
    c[cat] = (c[cat] or 0) + copper
  end
end

------------------------------------------------------------------------
-- What is going on right now (decides which category a money change belongs to)
------------------------------------------------------------------------
local ctx = { ah = false, merchant = false, mail = false, trainer = false, taxi = false }
local lastMoney
local postedAt, repairAt, questAt, questMoney = -10, -10, -10, 0
local pending = {}          -- seller invoices taken from the mailbox, waiting for their money to arrive

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
        if p.net <= delta then
          L.Record("sales", p.sale)
          L.Record("depositBack", p.deposit)
          L.Record("cut", -p.cut)
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
    if ctx.merchant then L.Record("vendorSales", delta) return end
    L.Record("loot", delta)
  else
    local c = -delta
    if ctx.ah then
      if t - postedAt < 2 then L.Record("deposits", -c) else L.Record("ahBuys", -c) end
    elseif ctx.merchant then
      if t - repairAt < 2 then L.Record("repairs", -c) else L.Record("vendorBuys", -c) end
    elseif ctx.mail then L.Record("mailOut", -c)
    elseif ctx.trainer then L.Record("training", -c)
    elseif ctx.taxi then L.Record("flights", -c)
    else L.Record("otherOut", -c) end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
  "MAIL_SHOW", "MAIL_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "QUEST_TURNED_IN" }) do
  CP.Register(f, e)
end
f:SetScript("OnEvent", CP.Safe("ledger", function(_, event, a1, a2, a3)
  if event == "PLAYER_LOGIN" then
    lastMoney = GetMoney()
  elseif event == "PLAYER_MONEY" then
    local now = GetMoney()
    local delta = now - (lastMoney or now)
    lastMoney = now
    if delta ~= 0 then Classify(delta) end
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

-- Mailbox: remember what a sale invoice says before the money arrives.
local function TookMail(index)
  if not (GetInboxInvoiceInfo and index) then return end
  local ok, kind, _, _, bid, buyout, deposit, consignment = pcall(GetInboxInvoiceInfo, index)
  if not ok or kind ~= "seller" then return end
  local sale = (bid and bid > 0) and bid or (buyout or 0)
  deposit, consignment = deposit or 0, consignment or 0
  local net = sale + deposit - consignment
  if net <= 0 then return end
  -- the same open mailbox can fire both hooks for one mail; ignore an identical entry added a moment ago
  local t = Now()
  for _, p in ipairs(pending) do
    if p.sale == sale and p.cut == consignment and p.deposit == deposit and t - p.t < 1 then return end
  end
  pending[#pending + 1] = { sale = sale, deposit = deposit, cut = consignment, net = net, t = t }
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
      lines[#lines + 1] = ("  %-24s %s"):format(r[2], CP.MoneyPlain(math.abs(v)))
      sum = sum + v
    end
  end
  return sum
end

function L.Lines(period)
  local db = CP.db
  local ledger = db and db.ledger or {}
  local days, label = {}, "all time"
  if period == "all" or not PERIODS[period] then
    days = ledger
  else
    local cutoff = DayKey(time() - PERIODS[period] * 86400)
    for k, d in pairs(ledger) do if k >= cutoff then days[k] = d end end
    label = period == "today" and "today" or period == "week" and "last 7 days" or "last 30 days"
  end
  local tot = Sum(days)
  local lines = { ("Gold ledger, %s (all your characters)"):format(label), "" }
  local income = Block(lines, "COMING IN", L.INCOME, tot)
  lines[#lines + 1] = ("  %-24s %s"):format("Total in", CP.MoneyPlain(income))
  lines[#lines + 1] = ""
  local spent = Block(lines, "GOING OUT", L.COSTS, tot)
  lines[#lines + 1] = ("  %-24s %s"):format("Total out", CP.MoneyPlain(-spent))
  lines[#lines + 1] = ""
  local net = income + spent
  lines[#lines + 1] = ("NET  %s"):format(CP.MoneyPlain(net))
  -- overhead = what it costs to run the business: deposits kept after refunds, sale fees, repairs, travel, training
  local overhead = -((tot.deposits or 0) + (tot.depositBack or 0) + (tot.cut or 0) + (tot.repairs or 0) + (tot.flights or 0) + (tot.training or 0))
  lines[#lines + 1] = ("OVERHEAD (deposits kept, sale fees, repairs, flights, training)  %s"):format(CP.MoneyPlain(overhead))
  if tot.sales and tot.sales > 0 then
    lines[#lines + 1] = ("AH net after fees and deposits: %s"):format(CP.MoneyPlain(tot.sales + (tot.cut or 0) + (tot.deposits or 0) + (tot.depositBack or 0)))
  end
  -- per day
  local keys = {}
  for k in pairs(days) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return a > b end)
  if #keys > 1 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BY DAY (net)"
    for i = 1, math.min(#keys, 30) do
      local n = 0
      for _, v in pairs(days[keys[i]]) do n = n + v end
      lines[#lines + 1] = ("  %s  %s"):format(keys[i], CP.MoneyPlain(n))
    end
  end
  if period == "all" and db and db.ledgerChars then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BY CHARACTER (net, all time)"
    for ck, c in pairs(db.ledgerChars) do
      local n = 0
      for _, v in pairs(c) do n = n + v end
      lines[#lines + 1] = ("  %-20s %s"):format(CP.ShortName(ck), CP.MoneyPlain(n))
    end
  end
  if next(ledger) == nil then
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
  if CP.db then CP.db.ledger, CP.db.ledgerChars = {}, {} end
end
