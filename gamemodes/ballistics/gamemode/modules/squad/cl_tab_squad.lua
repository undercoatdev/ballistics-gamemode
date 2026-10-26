-- Firing Squad admin tab. Rows and blurbs come from the squad view.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

if BALLISTICS.Admin and BALLISTICS.Admin.Register then
	BALLISTICS.Admin.Register("firing_squad", function(parent)
		if BALLISTICS.Admin.BuildRules then
			BALLISTICS.Admin.BuildRules(parent, "firing_squad", BALLISTICS.SquadView)
		end
	end)
end
