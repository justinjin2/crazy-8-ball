--!strict
-- Super Bounce (docs/prompts/ABILITIES_PROMPT.md 7.3): the cue ball keeps bouncing. No hooks:
-- it is only the cue ball's own material for the shot's first Config.Ults.SuperBounce.Seconds
-- (Arming.extras puts CueRailRestitution, CueRailFriction, CueBallRestitution,
-- CueSlidingFriction, CueRollingFriction and CueUntil in the overrides; Simulation applies
-- them to the cue ball alone, and normal friction returns after CueUntil). The entry marks the
-- shot as an ult shot for the replay's look (the boings come from its rail and ball hits).
local SuperBounce = {}

return SuperBounce
