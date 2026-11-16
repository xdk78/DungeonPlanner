-- The accept / decline prompt for plans other players offer. Shown out of combat only (Comm defers it), one at a time
-- (Widgets' dialog queue). Closing the dialog with Escape declines.

local _, ns = ...
local W, L = ns.Widgets, ns.L

local Prompts = ns:NewModule("Prompts")

function Prompts.Init()
	ns:On("SHARE_PROMPT", Prompts, function(t)
		local size = string.format("%.1f KB", t.bytes / 1024)
		local answered = false
		W.ShowDialog({
			title = L["Plan offered"],
			text = string.format(L["%s wants to send you the plan \"%s\" (%s). Accepted plans are added as new plans; nothing is overwritten."],
				t.sender, t.name ~= "" and t.name or "?", size),
			buttons = {
				{
					L["Accept"],
					function()
						answered = true
						ns.Comm.Respond(t, true)
					end,
					true,
				},
				{
					L["Decline"],
					function()
						answered = true
						ns.Comm.Respond(t, false)
					end,
				},
			},
			onDismiss = function()
				if not answered then
					ns.Comm.Respond(t, false)
				end
			end,
		})
	end)
end
