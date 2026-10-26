-- Pure money ledger. No GMod calls.
-- Per id: { balance, pending }. Spend draws on balance only (never negative).
-- Earn adds to pending. Commit (each BUY) folds pending into balance.
-- Reset (match start) sets balance to StartMoney and clears pending.
-- MaxMoney 0 means no cap. A positive cap clamps balance on commit, reset, and refund.

BALLISTICS = BALLISTICS or {}

local Ledger = {}
Ledger.__index = Ledger

local function whole(n)
	n = tonumber(n)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return math.floor(n)
end

local function startMoney(self)
	local n = whole(self.cfg.StartMoney) or 0
	if n < 0 then n = 0 end
	return n
end

local function maxMoney(self)
	local n = whole(self.cfg.MaxMoney) or 0
	if n < 0 then n = 0 end
	return n
end

local function cap(self, balance)
	local max = maxMoney(self)
	if max > 0 and balance > max then return max end
	return balance
end

function Ledger.new(cfg)
	if type(cfg) ~= "table" then cfg = {} end
	return setmetatable({ cfg = cfg, accounts = {} }, Ledger)
end

function Ledger:Ensure(id)
	if id == nil then return nil end
	id = tostring(id)
	if id == "" then return nil end
	local account = self.accounts[id]
	if not account then
		account = { balance = cap(self, startMoney(self)), pending = 0 }
		self.accounts[id] = account
	end
	return account
end

function Ledger:Get(id)
	local account = self:Ensure(id)
	if not account then return 0, 0 end
	return account.balance, account.pending
end

function Ledger:Ids()
	local list = {}
	for id in pairs(self.accounts) do
		list[#list + 1] = id
	end
	return list
end

function Ledger:Spend(id, price)
	local n = whole(price)
	if n == nil or n < 0 then return false, "invalid" end
	local account = self:Ensure(id)
	if not account then return false, "player" end
	if account.balance < n then return false, "insufficient" end
	account.balance = account.balance - n
	return true, account.balance
end

-- amount nil → look up cfg.Gains[key]. Explicit amount skips the lookup.
function Ledger:Earn(id, key, amount)
	local n = amount
	if n == nil then
		local gains = self.cfg.Gains
		if type(gains) ~= "table" then return false, "unknown" end
		n = gains[key]
	end
	n = whole(n)
	if n == nil then return false, "unknown" end
	if n < 0 then return false, "invalid" end
	local account = self:Ensure(id)
	if not account then return false, "player" end
	account.pending = account.pending + n
	return true, account.pending
end

function Ledger:Refund(id, amount)
	local n = whole(amount)
	if n == nil or n < 0 then return false, "invalid" end
	local account = self:Ensure(id)
	if not account then return false, "player" end
	account.balance = cap(self, account.balance + n)
	return true, account.balance
end

function Ledger:Commit(id)
	if id == nil then
		for existing in pairs(self.accounts) do
			self:Commit(existing)
		end
		return true
	end
	local account = self:Ensure(id)
	if not account then return false, "player" end
	account.balance = cap(self, account.balance + account.pending)
	account.pending = 0
	return true, account.balance
end

function Ledger:Reset(id)
	if id == nil then
		for existing in pairs(self.accounts) do
			self:Reset(existing)
		end
		return true
	end
	local account = self:Ensure(id)
	if not account then return false, "player" end
	account.balance = cap(self, startMoney(self))
	account.pending = 0
	return true, account.balance
end

BALLISTICS.Ledger = Ledger
