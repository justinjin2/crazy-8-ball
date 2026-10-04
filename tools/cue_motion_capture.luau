--!nocheck
-- Transient Studio Client helper: record actual gameplay, no saved Script instances.
-- Edit NAME/SECONDS before execute_luau. Wait for the callback before another recording.
-- CaptureService records up to 30 seconds and mutes voices. The local MP4 is retained in
-- ~/Library/Roblox/tmp-capture-storage as an extensionless wob-* file (identify MP4 magic).
-- Copy only the newly created MP4 into ignored assets/cue/renders/vfx-upgrade for review.
local NAME = "cue_motion"
local SECONDS = 16
local capture = game:GetService("CaptureService")
_G.CueMotionCaptures = _G.CueMotionCaptures or {}
local result = capture:StartVideoCaptureAsync(function(status, video)
	_G.CueMotionCaptures[NAME] = { status = status, video = video }
	print("Cue motion recording", NAME, status, video and video.TimeLength)
end, {})
if result == Enum.VideoCaptureStartedResult.Success then
	task.delay(SECONDS, function()
		capture:StopVideoCapture()
	end)
end
return tostring(result)
