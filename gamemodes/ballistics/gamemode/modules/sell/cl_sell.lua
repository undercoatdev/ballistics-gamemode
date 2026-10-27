if not CLIENT then return end
local S = BALLISTICS.Sell
local pops = {}

function S.Send(item)
	if type(item) ~= "table" or not item.key then return end
	net.Start("bal_sell")
	net.WriteString(item.key)
	net.SendToServer()
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_sell_ok", function(amount)
		if surface and surface.PlaySound then surface.PlaySound(S.SOUND) end
		pops[#pops + 1] = { text = S.Label(amount), at = RealTime() }
	end, { read = function() return net.ReadUInt(16) end })
end

hook.Add("PostRenderVGUI", "Ballistics_SellPop", function()
	local now = RealTime()
	for i = #pops, 1, -1 do
		local p = pops[i]
		local age = now - p.at
		if age > 1.5 then
			table.remove(pops, i)
		else
			local a = math.floor(255 * (1 - age / 1.5))
			draw.SimpleText(p.text, "DermaLarge", ScrW() / 2, ScrH() * 0.3 - age * 40, Color(120, 230, 120, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end)
