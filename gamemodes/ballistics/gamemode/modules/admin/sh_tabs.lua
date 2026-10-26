-- Admin tab tree. Pure data: which sub-tabs exist and whether Reset is live.
-- Rules stays a placeholder until its phase. Spawns and Teams are live.

BALLISTICS = BALLISTICS or {}
BALLISTICS.AdminTabs = BALLISTICS.AdminTabs or {}

local TREE = {
	{
		id = "spawns",
		title = "Spawns",
		implemented = true,
		reset = { enabled = true, kind = "spawns" },
	},
	{
		id = "teams",
		title = "Teams",
		implemented = true,
		reset = { enabled = true, section = "teams" },
	},
	{
		id = "rules",
		title = "Rules",
		implemented = false,
		reset = { enabled = false },
		children = {
			{
				id = "costs",
				title = "Costs",
				implemented = false,
				reset = { enabled = false, section = "costs" },
				children = {
					{ id = "weapons", title = "Weapons", implemented = false, reset = { enabled = false, section = "weapons" } },
					{ id = "throwables", title = "Throwables", implemented = false, reset = { enabled = false, section = "throwables" } },
					{ id = "meds", title = "Meds", implemented = false, reset = { enabled = false, section = "meds" } },
					{ id = "attachments", title = "Attachments", implemented = false, reset = { enabled = false, section = "attachments" } },
				},
			},
			{ id = "gains", title = "Gains", implemented = false, reset = { enabled = false, section = "gains" } },
			{ id = "general", title = "General", implemented = false, reset = { enabled = false, section = "general" } },
		},
	},
}

local function copyNode(node)
	local reset = node.reset or {}
	local out = {
		id = node.id,
		title = node.title,
		implemented = node.implemented == true,
		reset = {
			enabled = reset.enabled == true,
			section = reset.section,
			kind = reset.kind,
		},
	}
	if node.children then
		out.children = {}
		for i = 1, #node.children do
			out.children[i] = copyNode(node.children[i])
		end
	end
	return out
end

function BALLISTICS.AdminTabs.Tree()
	local out = {}
	for i = 1, #TREE do
		out[i] = copyNode(TREE[i])
	end
	return out
end

function BALLISTICS.AdminTabs.Walk(tree, fn)
	tree = tree or BALLISTICS.AdminTabs.Tree()
	for i = 1, #tree do
		local node = tree[i]
		fn(node)
		if node.children then BALLISTICS.AdminTabs.Walk(node.children, fn) end
	end
end

function BALLISTICS.AdminTabs.Find(id, tree)
	if type(id) ~= "string" then return nil end
	local found = nil
	BALLISTICS.AdminTabs.Walk(tree, function(node)
		if not found and node.id == id then found = node end
	end)
	return found
end

-- Payload for a Reset button. Config tabs send bal_config_set. Spawns resets
-- this map's flag file and does not touch Config. Disabled tabs return nil.
function BALLISTICS.AdminTabs.ResetRequest(node)
	if type(node) ~= "table" or type(node.reset) ~= "table" then return nil, "disabled" end
	if node.reset.enabled ~= true then return nil, "disabled" end
	if node.reset.kind == "spawns" then
		return { reset = true, kind = "spawns" }
	end
	if type(node.reset.section) ~= "string" or node.reset.section == "" then
		return nil, "section"
	end
	return { reset = true, section = node.reset.section }
end

function BALLISTICS.AdminTabs.ButtonVisible(isAdmin)
	return isAdmin == true
end
