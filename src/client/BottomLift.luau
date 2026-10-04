--!strict
-- BottomLift: how far the bottom-centre prompts (OpponentPrompt, Reminders) sit over their usual
-- place, so they clear the lucky block hotbar while it shows (LuckyHotbar sets it; 0 when it is
-- hidden). Read when they lay out.
local BottomLift = {}

local px = 0

--- Pixels to add to a bottom-centre prompt's gap from the bottom of the screen.
function BottomLift.get(): number
	return px
end

function BottomLift.set(value: number)
	px = math.max(0, value)
end

return BottomLift
