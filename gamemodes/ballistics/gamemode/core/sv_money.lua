-- Ledger glue. NW2 ints bal_money and bal_pending, commit at BUY, reset at match start.
-- Round win/loss lands in pending here. A draw pays Gains.draw to everyone slotted.
-- An enemy player kill during LIVE pays Gains.kill. Teamkills, suicides, and world deaths do not.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Money = {}

local ledger = BALLISTICS.Ledger.new(BALLISTICS.Config or {})
local plyById = {}

local function playerId(ply)
	if BALLISTICS.PlayerId then return BALLISTICS.PlayerId(ply) end
	if type(ply) == "string" and ply ~= "" then return ply end
	if type(ply) == "number" then return tostring(ply) end
	return nil
end

local function remember(ply, id)
	if id and BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply) then plyById[id] = ply end
end

local function resolve(ply, id)
	if BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply) and type(ply.SetNW2Int) == "function" then return ply end
	if id and BALLISTICS.Slots and BALLISTICS.Slots.Player then
		local found = BALLISTICS.Slots.Player(id)
		if found then return found end
	end
	return plyById[id]
end

local function sync(ply, id)
	id = id or playerId(ply)
	if not id then return end
	remember(ply, id)
	local target = resolve(ply, id)
	-- Real players are userdata, so only check for the method.
	if target == nil or type(target.SetNW2Int) ~= "function" then return end
	local balance, pending = ledger:Get(id)
	target:SetNW2Int("bal_money", balance)
	target:SetNW2Int("bal_pending", pending)
	if hook and hook.Run then hook.Run("Ballistics_MoneyChanged", target) end
end

local function syncAll()
	for _, id in ipairs(ledger:Ids()) do
		sync(nil, id)
	end
end

function BALLISTICS.Money.Get(ply)
	local id = playerId(ply)
	if not id then return 0, 0 end
	return ledger:Get(id)
end

function BALLISTICS.Money.Spend(ply, price)
	local id = playerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local ok, err = ledger:Spend(id, price)
	if ok then sync(ply, id) end
	return ok, err
end

function BALLISTICS.Money.Earn(ply, key, amount)
	local id = playerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local ok, err = ledger:Earn(id, key, amount)
	if ok then sync(ply, id) end
	return ok, err
end

function BALLISTICS.Money.Refund(ply, amount)
	local id = playerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local ok, err = ledger:Refund(id, amount)
	if ok then sync(ply, id) end
	return ok, err
end

function BALLISTICS.Money.Commit(ply)
	local id = playerId(ply)
	if not id then return false, "player" end
	local ok, err = ledger:Commit(id)
	if ok then sync(ply, id) end
	return ok, err
end

function BALLISTICS.Money.CommitAll()
	ledger:Commit()
	syncAll()
	return true
end

local function ensureKnown()
	local good = TEAM_GOOD or 1
	local bad = TEAM_BAD or 2
	if BALLISTICS.Slots and BALLISTICS.Slots.Members then
		for _, teamId in ipairs({ good, bad }) do
			local members = BALLISTICS.Slots.Members(teamId)
			for i = 1, #members do
				ledger:Ensure(members[i])
			end
		end
	end
	if BALLISTICS.Player and BALLISTICS.Player.Each then
		BALLISTICS.Player.Each(function(ply)
			local id = playerId(ply)
			if id then
				remember(ply, id)
				ledger:Ensure(id)
			end
		end)
	end
end

function BALLISTICS.Money.Reset()
	ensureKnown()
	ledger:Reset()
	syncAll()
	return true
end

function BALLISTICS.Money.Sync(ply)
	sync(ply, playerId(ply))
end

local function phaseOf()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		local phase = BALLISTICS.Round.Phase()
		if type(phase) == "string" and phase ~= "" then return phase end
	end
	return "lobby"
end

-- World and weapon entities are userdata too. Only a real player method counts.
local function entityPlayer(ent)
	if ent == nil or ent == false then return false end
	if type(ent.IsPlayer) ~= "function" then return false end
	return ent:IsPlayer() == true
end

local function teamOf(ply)
	if ply == nil then return nil end
	if not (BALLISTICS.Slots and type(BALLISTICS.Slots.TeamOf) == "function") then return nil end
	local teamId = BALLISTICS.Slots.TeamOf(ply)
	local good = TEAM_GOOD or 1
	local bad = TEAM_BAD or 2
	if teamId == good or teamId == bad then return teamId end
	return nil
end

-- Pays Gains.kill into pending, or returns false and leaves the ledger alone.
function BALLISTICS.Money.OnDeath(victim, attacker)
	local reward = nil
	if BALLISTICS.Gains and type(BALLISTICS.Gains.KillReward) == "function" then
		reward = BALLISTICS.Gains.KillReward({
			phase = phaseOf(),
			suicide = victim ~= nil and attacker == victim,
			attackerIsPlayer = entityPlayer(attacker),
			victimTeam = teamOf(victim),
			attackerTeam = teamOf(attacker),
		})
	end
	if reward ~= "kill" then return false end
	local ok = BALLISTICS.Money.Earn(attacker, "kill")
	return ok == true
end

local function payTeam(teamId, key)
	if not (BALLISTICS.Slots and BALLISTICS.Slots.Members) then return end
	local members = BALLISTICS.Slots.Members(teamId)
	for i = 1, #members do
		BALLISTICS.Money.Earn(members[i], key)
	end
end

if hook and hook.Add then
	hook.Add("Ballistics_RoundEnd", "Ballistics_MoneyRound", function(winner)
		if winner == "draw" then
			payTeam(TEAM_GOOD or 1, "draw")
			payTeam(TEAM_BAD or 2, "draw")
			return
		end
		if winner ~= "good" and winner ~= "bad" then return end
		local good = TEAM_GOOD or 1
		local bad = TEAM_BAD or 2
		if winner == "good" then
			payTeam(good, "round_win")
			payTeam(bad, "round_loss")
		else
			payTeam(bad, "round_win")
			payTeam(good, "round_loss")
		end
	end)

	hook.Add("PlayerInitialSpawn", "Ballistics_MoneyInit", function(ply)
		local id = playerId(ply)
		if not id then return end
		remember(ply, id)
		ledger:Ensure(id)
		sync(ply, id)
	end)

	-- PlayerDeath is (victim, inflictor, attacker). The inflictor is ignored:
	-- only an enemy player attacker during LIVE is paid.
	hook.Add("PlayerDeath", "Ballistics_MoneyKill", function(victim, _, attacker)
		BALLISTICS.Money.OnDeath(victim, attacker)
	end)
end
