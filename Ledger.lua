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

local function ContextName()
  for _, k in ipairs({ "ah", "merchant", "mail", "trade", "bank", "guild", "trainer", "taxi" }) do
    if L.ctx and L.ctx[k] then return k end
  end
  return "-"
end

function L.Record(cat, copper)
  if not CP.db or not copper or copper == 0 then return end
  -- the last 80 entries, so /pf ledger log can show where a number came from
  local log = CP.db.ledgerLog
  if not log then log = {} CP.db.ledgerLog = log end
  log[#log + 1] = { t = time(), c = cat, v = copper, w = ContextName(), who = CP.charKey and CP.ShortName(CP.charKey) or "?" }
  while #log > 80 do table.remove(log, 1) end
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
L.ctx = ctx
local postedAt, repairAt, questAt, questMoney = -10, -10, -10, 0
local posting, depositGrace = 0, -10   -- auctions being created right now (their deposit is taken as they are created)
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
      -- gold another of your characters mailed (it left a note when it sent it)
      if delta > 0 and CP.db and CP.db.transit and CP.charKey then
        local me = CP.ShortName(CP.charKey):lower()
        local list = CP.db.transit[me]
        if list then
          for i = #list, 1, -1 do if time() - (list[i].t or 0) > 14 * 86400 then table.remove(list, i) end end
          table.sort(list, function(a, b) return a.amt > b.amt end)
          local i = 1
          while i <= #list and delta > 0 do
            if list[i].amt <= delta then
              L.Record("transferIn", list[i].amt)
              delta = delta - list[i].amt
              table.remove(list, i)
            else
              i = i + 1
            end
          end
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
      if posting > 0 or t - postedAt < 4 or t < depositGrace then L.Record("deposits", -c) else L.Record("ahBuys", -c) end
    elseif ctx.merchant then
      if t - repairAt < 2 then L.Record("repairs", -c) else L.Record("vendorBuys", -c) end
    elseif ctx.guild then L.Record("guildOut", -c)
    elseif ctx.trade then L.Record("tradeOut", -c)
    elseif ctx.mail then
      local xfer = sendMoney
      -- if the game call that sets the gold wasn't seen, everything above the 30c postage is the gold sent
      if xfer <= 0 and sendTo and c > 30 and IsMine(sendTo) then xfer = c - 30 end
      if xfer > 0 and sendTo and IsMine(sendTo) and c >= xfer then
        L.Record("transferOut", -xfer)
        -- let the receiving character know, so it books the gold as a transfer too
        if CP.db then
          CP.db.transit = CP.db.transit or {}
          local who = (sendTo:match("^([^%-]+)") or sendTo):lower()
          CP.db.transit[who] = CP.db.transit[who] or {}
          table.insert(CP.db.transit[who], { amt = xfer, t = time() })
        end
        c = c - xfer
        if c > 0 then L.Record("mailOut", -c) end
      else
        L.Record("mailOut", -c)
      end
      sendMoney, sendTo = 0, nil
    elseif ctx.bank then L.Record("bank", -c)
    elseif ctx.trainer then L.Record("training", -c)
    elseif ctx.taxi then L.Record("flights", -c)
    else L.Record("otherOut", -c) end
  end
end

-- Snapshot of what this character has up on the auction house, so the ledger can show gold that is
-- listed but not sold yet. The game only reports this while the auction house is open.
local function ItemName(link)
  if type(link) ~= "string" then return nil end
  return link:match("%[(.-)%]") or link
end
local function NameFromInfo(info)
  local n = ItemName(info.itemLink)
  if n then return n end
  local id = info.itemKey and info.itemKey.itemID
  if id then
    local gi = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = gi and gi(id)
    if type(name) == "string" then return name end
  end
  return nil
end
local function MaxStack(link)
  local gi = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not gi or not link then return 1 end
  local _, _, _, _, _, _, _, stack = gi(link)
  return tonumber(stack) or 1
end

function L.SnapshotListings()
  if not (CP.db and CP.charKey) then return end
  local items = {}
  local ok = false
  local AH = C_AuctionHouse
  if AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo then
    ok = true
    for i = 1, AH.GetNumOwnedAuctions() or 0 do
      local info = AH.GetOwnedAuctionInfo(i)
      if info then
        local qty = info.quantity or 1
        local ask = info.buyoutAmount or 0
        if ask == 0 then ask = info.bidAmount or 0 end
        -- stacks are listed per unit (only single items have a whole-item price): the asking price is for one
        if qty > 1 then ask = ask * qty end
        items[#items + 1] = { name = NameFromInfo(info) or "?", n = qty, ask = ask, sold = (info.status == 1) and true or nil }
      end
    end
  elseif GetNumAuctionItems and GetAuctionItemInfo then
    ok = true
    local n = GetNumAuctionItems("owner")
    for i = 1, tonumber(n) or 0 do
      local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, _, _, saleStatus = GetAuctionItemInfo("owner", i)
      if name then
        local ask = (buyout and buyout > 0) and buyout or (minBid or 0)
        items[#items + 1] = { name = name, n = count or 1, ask = ask, sold = (saleStatus == 1) and true or nil }
      end
    end
  end
  if not ok then return end
  CP.db.myAuctions = CP.db.myAuctions or {}
  CP.db.myAuctions[CP.charKey] = { t = time(), v = 2, items = items }
  L.dirty = true
end

-- Earlier versions booked gold mailed between your own characters as ordinary mail in and out. Pair them up
-- (one character's mail out matches another's mail in, the difference being postage) and book them as transfers.
function L.RepairTransfers()
  local db = CP.db
  if not db or db.transferFix == 2 then return end
  db.transferFix = 2
  local function Move(tbl, key, cat, amt, sign)
    tbl[key] = (tbl[key] or 0) - amt * sign     -- take it out of mailIn / mailOut
    tbl[cat] = (tbl[cat] or 0) + amt * sign
  end
  -- first day (in order) whose numbers can give up that amount
  local function Days(tbl, fn)
    local days = {}
    for day in pairs(tbl or {}) do days[#days + 1] = day end
    table.sort(days)
    for _, day in ipairs(days) do if fn(tbl[day], day) then return end end
  end
  local totals = db.ledgerChars or {}
  local ins, outs = {}, {}
  for ck, c in pairs(totals) do
    if (c.mailIn or 0) > 0 then ins[#ins + 1] = { ck = ck, amt = c.mailIn } end
    if (c.mailOut or 0) < 0 then outs[#outs + 1] = { ck = ck, amt = -c.mailOut } end
  end
  table.sort(ins, function(a, b) return a.amt > b.amt end)
  for _, i in ipairs(ins) do
    local best
    for _, o in ipairs(outs) do
      local diff = o.amt - i.amt
      if o.ck ~= i.ck and not o.used and diff >= 0 and diff <= 3000 and (not best or diff < best.amt - i.amt) then best = o end
    end
    if best then
      best.used = true
      local amt = i.amt
      Move(totals[i.ck], "mailIn", "transferIn", amt, 1)
      Move(totals[best.ck], "mailOut", "transferOut", amt, -1)
      Days(db.ledger, function(d)
        if (d.mailIn or 0) >= amt and (d.mailOut or 0) <= -amt then
          Move(d, "mailIn", "transferIn", amt, 1)
          Move(d, "mailOut", "transferOut", amt, -1)
          return true
        end
      end)
      Days(db.ledgerDC, function(chars)
        local a, b = chars[i.ck], chars[best.ck]
        if a and (a.mailIn or 0) >= amt then Move(a, "mailIn", "transferIn", amt, 1) end
        if b and (b.mailOut or 0) <= -amt then Move(b, "mailOut", "transferOut", amt, -1) end
        return (a and true) or (b and true) or false
      end)
    end
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_OWNED_LIST_UPDATE", "PLAYER_LOGIN", "PLAYER_MONEY", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
  "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "PLAYER_LOGOUT", "TRADE_SHOW", "TRADE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "QUEST_TURNED_IN" }) do
  CP.Register(f, e)
end
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_AUCTION_CREATED")
f:SetScript("OnEvent", CP.Safe("ledger", function(_, event, a1, a2, a3)
  if event == "PLAYER_LOGIN" then
    -- 0.8.2 briefly saved my own auctions inside db.listings, which belongs to the price tracker: move them out
    if CP.db and CP.db.listings then
      for k, v in pairs(CP.db.listings) do
        if type(k) == "string" and type(v) == "table" and v.items then
          CP.db.myAuctions = CP.db.myAuctions or {}
          CP.db.myAuctions[k] = v
          CP.db.listings[k] = nil
        end
      end
    end
    L.RepairTransfers()
    lastMoney = GetMoney()
    sessionStart, sessionMoney = time(), lastMoney
    -- earlier versions saved a bogus 0 at logout: repair those entries
    for _, d in pairs((CP.db and CP.db.worth) or {}) do
      for _, e in pairs(d) do if e.e == 0 and (e.s or 0) > 0 then e.e = e.s end end
    end
    Worth()
  elseif event == "PLAYER_LOGOUT" then
    -- GetMoney() reads 0 while logging out, so nothing is recorded here
  elseif event == "PLAYER_MONEY" then
    local now = GetMoney()
    local delta = now - (lastMoney or now)
    if delta ~= 0 then Classify(delta) end
    lastMoney = now
    Worth()
  elseif event == "MAIL_INBOX_UPDATE" then
    snap = {}
    local num = GetInboxNumItems or (C_Mail and C_Mail.GetInboxNumItems)
    local hdr = GetInboxHeaderInfo or (C_Mail and C_Mail.GetInboxHeaderInfo)
    if num and hdr then
      local sum, n = 0, 0
      for i = 1, num() or 0 do
        local _, _, sender, _, money = hdr(i)
        snap[i] = { sender = sender, money = money or 0 }
        if (money or 0) > 0 then sum, n = sum + money, n + 1 end
      end
      if CP.db and CP.charKey then
        CP.db.mailGold = CP.db.mailGold or {}
        CP.db.mailGold[CP.charKey] = { money = sum, n = n, t = time() }
      end
    end
  elseif event == "TRADE_SHOW" then ctx.trade = true
  elseif event == "TRADE_CLOSED" then ctx.trade = false
  elseif event == "BANKFRAME_OPENED" then ctx.bank = true
  elseif event == "BANKFRAME_CLOSED" then ctx.bank = false
  elseif event == "GUILDBANKFRAME_OPENED" then ctx.guild = true
  elseif event == "GUILDBANKFRAME_CLOSED" then ctx.guild = false
  elseif event == "OWNED_AUCTIONS_UPDATED" or event == "AUCTION_OWNED_LIST_UPDATE" then
    L.SnapshotListings()
  elseif event == "AUCTION_HOUSE_SHOW" then
    ctx.ah = true
    posting = 0
    -- ask for our own listings; the answer arrives as an update event
    if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
    if C_Timer then C_Timer.After(2, function() pcall(L.SnapshotListings) end) end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    posting = math.max(0, posting - 1)
    depositGrace = Now() + 2
  elseif event == "AUCTION_HOUSE_CLOSED" then ctx.ah = false posting = 0
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
local function Posted() postedAt = Now() posting = posting + 1 end
Hook(_G.C_AuctionHouse, "PostItem", Posted)
Hook(_G.C_AuctionHouse, "PostCommodity", Posted)
Hook(_G, "StartAuction", Posted)
Hook(_G, "RepairAllItems", function() repairAt = Now() end)

-- gold you attach to mail, and who it goes to (mail to your own characters is a transfer, not spending)
Hook(_G, "SetSendMailMoney", function(amount) sendMoney = tonumber(amount) or 0 end)
Hook(_G.C_Mail, "SetSendMailMoney", function(amount) sendMoney = tonumber(amount) or 0 end)
Hook(_G, "SendMail", function(recipient) sendTo = recipient end)
Hook(_G.C_Mail, "SendMail", function(recipient) sendTo = recipient end)

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
Hook(_G.C_Mail, "TakeInboxMoney", TookMail)
Hook(_G.C_Mail, "AutoLootMailItem", TookMail)

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
  lines[#lines + 1] = ("NET CASH FLOW  %s   (everything in minus everything out, including buying stock)"):format(CP.MoneyPlain(net))
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
  do
    -- gold on its way: sold auctions whose money has not been collected, plus coin sitting in mailboxes
    local lst, soldNet, inbox, boxN = db.myAuctions or {}, 0, 0, 0
    local allSales, allCut = 0, 0
    for _, d in pairs(db.ledger or {}) do allSales, allCut = allSales + (d.sales or 0), allCut + (d.cut or 0) end
    local rate = (allSales > 0) and math.min(0.15, math.max(0, -allCut / allSales)) or 0.05
    for c, e in pairs(lst) do
      if not ck or c == ck then
        for _, it in ipairs(e.items or {}) do if it.sold then soldNet = soldNet + math.floor(it.ask * (1 - rate)) end end
      end
    end
    for c, m in pairs(db.mailGold or {}) do
      if not ck or c == ck then inbox, boxN = inbox + (m.money or 0), boxN + (m.n or 0) end
    end
    local waiting = soldNet + inbox
    if waiting > 0 then
      row("|cffffd100Waiting for you in the mail|r", "|cffffd100" .. M(waiting) .. "|r",
        (soldNet > 0 and ("sold auctions about " .. M(soldNet)) or "") .. ((soldNet > 0 and inbox > 0) and ", " or "") ..
        (inbox > 0 and ("coin in mailboxes " .. M(inbox)) or ""))
    else
      row("Waiting for you in the mail", "|cff9d9d9dnothing known|r", "open the auction house and your mailbox once on each character")
    end
  end
  row("Days with activity", #keys)
  row("Net cash flow (everything in minus everything out)", Signed(net))
  row("Net before buying stock", Signed(net - (-(tot.ahBuys or 0)) - (-(tot.vendorBuys or 0))), "buying is stock, not loss")
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
    row("Deposits not returned yet", M(math.max(0, dep - depBack)), "unsold, expired or cancelled")
    row("Spent buying on the AH", M(-(tot.ahBuys or 0)))
    row("|cffffd100AH result (after fees, deposits, buys)|r", Signed(sales - fees - (dep - depBack) + (tot.ahBuys or 0)))
    row("|cff9d9d9dA deposit comes back only when the item sells. Listings still up for sale look like a loss until they do.|r")
    gap()
  end

  -- listed but not sold yet (current, so not limited to the chosen period)
  do
    local lst = db.myAuctions or {}
    local per, names = {}, {}
    local allSales, allCut = 0, 0
    for _, d in pairs(db.ledger or {}) do allSales, allCut = allSales + (d.sales or 0), allCut + (d.cut or 0) end
    local rate = (allSales > 0) and math.min(0.15, math.max(0, -allCut / allSales)) or 0.05
    local totN, totAsk, soldAsk, big = 0, 0, 0, {}
    for c, e in pairs(lst) do
      if not ck or c == ck then
        local n, ask = 0, 0
        for _, it in ipairs(e.items or {}) do
          -- snapshots from before 0.8.2 stored a stack's per-unit price when the item name was unknown
          if e.v ~= 2 and (it.n or 1) > 1 and it.name == "?" and not it.fixed then it.ask = it.ask * it.n it.fixed = true end
          if it.sold then soldAsk = soldAsk + it.ask
          else
            n, ask = n + 1, ask + it.ask
            big[#big + 1] = it
          end
        end
        per[c] = { n = n, ask = ask, t = e.t }
        names[#names + 1] = c
        totN, totAsk = totN + n, totAsk + ask
      end
    end
    table.sort(names)
    head("UNREALIZED: LISTED, NOT SOLD YET", "Listings", "Asking price", "After fees (est.)", "Updated")
    if #names == 0 then
      row("|cff9d9d9dOpen the auction house once on each character to record what you have listed.|r")
    else
      for _, c in ipairs(names) do
        local p = per[c]
        row(CP.ShortName(c), p.n, M(p.ask), M(math.floor(p.ask * (1 - rate))), date("%m-%d %H:%M", p.t))
      end
      row("|cffffd100Total unrealized|r", totN, M(totAsk), M(math.floor(totAsk * (1 - rate))))
      if soldAsk > 0 then row("Sold, gold waiting in the mail", "", M(soldAsk), M(math.floor(soldAsk * (1 - rate)))) end
      table.sort(big, function(a, b) return a.ask > b.ask end)
      for i = 1, math.min(#big, 8) do
        row("   " .. big[i].name .. (big[i].n > 1 and (" x" .. big[i].n) or ""), "", M(big[i].ask))
      end
      row("|cff9d9d9dAsking price is what you listed it for.|r")
      row(("|cff9d9d9dFees estimated at %d%% from your sales so far.|r"):format(math.floor(rate * 100 + 0.5)))
      row("|cff9d9d9dUpdated each time you open the auction house.|r")
    end
    gap()
    L.unrealized = totAsk
    L.unrealizedNet = math.floor(totAsk * (1 - rate))
  end

  -- overhead
  local overhead = fees + (dep - depBack) + -(tot.repairs or 0) + -(tot.flights or 0) + -(tot.training or 0) + -(tot.bank or 0)
  head("OVERHEAD (cost of doing business)", "Amount", "% of sales")
  row("AH fees", M(fees), Pct(fees, sales))
  row("Deposits not returned", M(math.max(0, dep - depBack)), Pct(math.max(0, dep - depBack), sales))
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
      row("Not explained by the ledger", Signed(unexplained))
    else
      row("|cff40ff40The ledger accounts for all of it|r")
    end
  end
  if #rows == 0 or next(days) == nil then
    rows = { { k = "row", "Nothing recorded for this period yet. The ledger counts every gold change from now on." } }
  end
  return rows, { inn = inn, out = out, net = net, overhead = overhead, unrealized = L.unrealizedNet or 0 }
end

-- "Name-Realm" shown as "Name - Realm" so same-named characters on different realms are told apart
local function FullName(k) return (tostring(k):gsub("%-", " - ", 1)) end

local PERIOD_LABELS = { { "today", "Today" }, { "week", "7 days" }, { "month", "30 days" }, { "all", "All time" } }
local COLW = { 290, 110, 130, 100, 100 }
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
  -- character dropdown (own small menu, so it never depends on Blizzard's dropdown templates)
  local cb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  cb:SetSize(260, 22)
  cb:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  local menu = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", 0, 0)
  if menu.SetBackdrop then
    menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    menu:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    menu:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
  end
  menu:Hide()
  menu.items = {}
  L.menu = menu
  local function Pick(ck) L.char = ck menu:Hide() L.Refresh() end
  local function OpenMenu()
    local names = {}
    for c in pairs((CP.db and CP.db.ledgerChars) or {}) do names[#names + 1] = c end
    table.sort(names)
    table.insert(names, 1, false)
    for i, c in ipairs(names) do
      local it = menu.items[i]
      if not it then
        it = CreateFrame("Button", nil, menu)
        it:SetSize(256, 20)
        it:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 20)
        it.t = it:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        it.t:SetPoint("LEFT", it, "LEFT", 8, 0)
        local hl = it:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        menu.items[i] = it
      end
      local sel = (c or nil) == L.char
      it.t:SetText((sel and "|cff40ff40> " or "   ") .. (c and FullName(c) or "All characters") .. (sel and "|r" or ""))
      it:SetScript("OnClick", function() Pick(c or nil) end)
      it:Show()
    end
    for i = #names + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(260, #names * 20 + 4)
    menu:Show()
  end
  cb:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else OpenMenu() end end)
  p:HookScript("OnHide", function() menu:Hide() end)
  L.charBtn = cb

  -- four headline numbers
  L.tiles = {}
  local tw = math.floor((width - 4 * 8) / 5)
  local tiles = { { "net", "NET CASH FLOW" }, { "inn", "TOTAL IN" }, { "out", "TOTAL OUT" }, { "overhead", "OVERHEAD" }, { "unrealized", "UNREALIZED" } }
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

  L.info = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  L.info:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -72)

  -- the scrolling table
  local scroll = CreateFrame("ScrollFrame", nil, p)
  scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -90)
  scroll:SetSize(width - 4, height - 90)
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
  for key, b in pairs(L.pbtn) do
    local fsx = b:GetFontString()
    if key == L.period then
      b:LockHighlight()
      if fsx then fsx:SetTextColor(0.25, 1, 0.25) end
    else
      b:UnlockHighlight()
      if fsx then fsx:SetTextColor(1, 0.82, 0) end
    end
  end
  L.charBtn:SetText((L.char and FullName(L.char) or "All characters") .. "  v")
  do
    local lbl = { today = "Today", week = "Last 7 days", month = "Last 30 days", all = "All time" }
    local first
    for k in pairs(CP.db.ledger or {}) do if not first or k < first then first = k end end
    L.info:SetText(("Showing: |cff40ff40%s|r  -  %s  -  data recorded since %s"):format(
      lbl[L.period] or L.period, L.char and FullName(L.char) or "all characters", first or "(nothing yet)"))
  end
  local rows, t = L.Rows(L.period, L.char)
  L.tiles.net:SetText(Signed(t.net))
  L.tiles.inn:SetText(M(t.inn))
  L.tiles.out:SetText(M(t.out))
  L.tiles.overhead:SetText(M(t.overhead))
  L.tiles.unrealized:SetText(M(t.unrealized or 0))
  for i, r in ipairs(rows) do
    local ln = Line(i)
    for c = 1, 5 do
      local v = r[c]
      if r.k == "head" and v ~= nil then v = "|cffffd100" .. tostring(v) .. "|r" end
      if r.k == "gap" then v = nil end
      local fs = ln.fs[c]
      fs:SetWidth(COLW[c])
      fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
      fs:SetText(v ~= nil and tostring(v) or "")
      fs:Show()
    end
    -- text wider than its column takes over the empty columns after it (left aligned) instead of being cut off
    for c = 1, 4 do
      local fs = ln.fs[c]
      if fs:GetText() and fs:GetText() ~= "" and (fs:GetStringWidth() or 0) > COLW[c] - 1 then
        local span, n = COLW[c], c + 1
        while n <= 5 and (r[n] == nil or r[n] == "") do span = span + 4 + COLW[n] n = n + 1 end
        if span > COLW[c] then
          fs:SetWidth(span)
          fs:SetJustifyH("LEFT")
          for m = c + 1, n - 1 do ln.fs[m]:SetText("") end
        end
      end
    end
  end
  for i = #rows + 1, #L.lines do
    for c = 1, 5 do L.lines[i].fs[c]:Hide() end
  end
  L.content:SetHeight(math.max(10, #rows * ROWH + 8))
end

-- the most recent entries, newest last: where each number came from
function L.LogLines()
  local lines = { "Last gold changes Profiteer recorded (newest at the bottom):", "" }
  for _, e in ipairs((CP.db and CP.db.ledgerLog) or {}) do
    lines[#lines + 1] = ("%s  %-10s %-14s %-12s %s"):format(date("%H:%M:%S", e.t), e.who or "?", e.c, e.w or "-", CP.MoneyPlain(e.v))
  end
  if #lines == 2 then lines[3] = "Nothing recorded yet." end
  return lines
end
