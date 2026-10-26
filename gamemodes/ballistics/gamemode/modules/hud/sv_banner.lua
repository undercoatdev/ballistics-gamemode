-- Tells every client which end banner to show. The text is chosen on the client.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}

local function send(kind, winner)
	if winner ~= "good" and winner ~= "bad" and not (kind == "round" and winner == "draw") then
		return
	end
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_banner", nil, { kind = kind, winner = winner })
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_banner", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteString(payload.kind or "")
			net.WriteString(payload.winner or "")
		end,
	})
end

if hook and hook.Add then
	hook.Add("Ballistics_RoundEnd", "Ballistics_Banner", function(winner)
		send("round", winner)
	end)
	hook.Add("Ballistics_MatchEnd", "Ballistics_Banner", function(winner)
		send("game", winner)
	end)
end
