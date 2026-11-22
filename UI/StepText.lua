-- How steps read in the side panel, run mode and tooltips: a step's title and caption (its floor, where stairs lead),
-- and a pull's plan marks. Split from UI/MainFrame.lua.

local _, ns = ...
local UI = ns.UI
local L = ns.L

-- A step's title and caption for lists and run mode, whether its spot is an estimate (the plan says "(approx.)": shown
-- as a small mark, Style.WithApprox), and its note without that mark.
function UI.StepText(plan, step)
	if not (plan and step) then
		return "", "", false, nil
	end
	local note, approx = ns.Util.SplitApprox(step.note)
	local stepMarker = step.marker and ns.Util.FindById(plan.markers, step.marker)
	if stepMarker and not approx then
		approx = select(2, ns.Util.SplitApprox(stepMarker.note))
	end
	local title, caption
	if step.kind == "marker" then
		title = stepMarker and (stepMarker.label ~= "" and stepMarker.label or L[stepMarker.kind]) or L["Move on"]
		-- A quest item: the item's name as the client has it (in the player's language), the label until it loads.
		if stepMarker and stepMarker.kind == "quest_item" and stepMarker.itemID then
			title = ns.Names.Item(stepMarker.itemID) or title
		end
		caption = stepMarker and L[stepMarker.kind] or L["Move"]
	elseif step.kind == "boss" then
		local enc = step.encounter and ns.Util.FindById(plan.encounters, step.encounter)
		local marker = step.marker and ns.Util.FindById(plan.markers, step.marker)
		title = enc and ns.Names.Encounter(enc) or (marker and marker.label ~= "" and marker.label) or L["Boss"]
		caption = L["Boss"]
	elseif step.kind == "pull" then
		local pull, index = ns.Util.FindById(plan.pulls, step.pull)
		title = pull and pull.name or L["Pull"]
		caption = index and string.format(L["Pull %d"], index) or L["Pull"]
	elseif step.kind == "entrance" then
		local marker = step.marker and ns.Util.FindById(plan.markers, step.marker)
		title = marker and marker.label ~= "" and marker.label or L.entrance
		caption = L.entrance
	elseif step.kind == "objective" then
		title = note or ""
		caption = L["Objective"]
	else
		title = note and note ~= "" and note or L["Move on"]
		caption = L["Move"]
	end
	-- Where the plan has several floors, the step's, unless it is named as the instance (the Deadmines' first floor is
	-- "The Deadmines": every step there would repeat what the header says). The other floors keep their names.
	if step.floor and #plan.floors > 1 and plan.floors[step.floor] then
		local floorName = ns.Names.Floor(plan.floors[step.floor], step.floor)
		if floorName ~= ns.Names.Instance(plan.instance) and floorName ~= plan.instance.name then
			caption = caption .. "  •  " .. floorName
		end
	end
	-- Stairs or a portal on the way: where it leads (a second click on the step goes there, UI/SidePanel.lua).
	local link = UI.StepLink(plan, step)
	if link then
		caption = caption .. "  •  " .. string.format(L["to %s"], ns.Names.Floor(plan.floors[link], link))
	end
	return title, caption, approx, note
end

-- The floor a step's marker leads to (stairs, a portal: marker.toFloor), or nil.
function UI.StepLink(plan, step)
	local m = plan and step and step.marker and ns.Util.FindById(plan.markers, step.marker)
	return m and m.toFloor and m.toFloor ~= step.floor and plan.floors[m.toFloor] and m.toFloor or nil
end

-- A pull's plan marks as one short line: its tags, planned cooldowns and Bloodlust ("Interrupt • CC • CDs • Lust"),
-- and with opts.progress its planned forces ("34%"). "" when it has none. opts.long uses the full names.
function UI.PullMarks(pull, opts)
	opts = opts or {}
	if not pull then
		return ""
	end
	local prefix = opts.long and "tag:" or "tagShort:"
	local parts = {}
	for _, tag in ipairs(pull.tags or {}) do
		parts[#parts + 1] = L[prefix .. tag]
	end
	if pull.cd then
		parts[#parts + 1] = L[prefix .. "cd"]
	end
	if pull.lust then
		parts[#parts + 1] = L[prefix .. "lust"]
	end
	if opts.progress and pull.progress then
		parts[#parts + 1] = string.format(L["%d%%"], pull.progress)
	end
	return table.concat(parts, "  •  ")
end

