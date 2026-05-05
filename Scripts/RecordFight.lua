--[[
	RecordFight — Deathball Data Recorder
	Logs ball distance, speed, hit events during a real game
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/RecordFight.lua"))()
]]

local Players   = game:GetService("Players")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer

local events = {}
local startTime = tick()
local lastHealth = nil
local lastLogTime = 0
local cachedBall = nil
local recording = false

-- Track ball
local function watchFX(fx)
	local rock = fx:FindFirstChild("RockTemplate")
	if rock then cachedBall = rock end
	fx.ChildAdded:Connect(function(c)
		if c.Name == "RockTemplate" then
			cachedBall = c
			if recording then
				table.insert(events, {t=tick()-startTime, e="BALL_APPEAR"})
			end
		end
	end)
	fx.ChildRemoved:Connect(function(c)
		if c.Name == "RockTemplate" and cachedBall == c then
			cachedBall = nil
		end
	end)
end
local _fx = workspace:FindFirstChild("FX")
if _fx then watchFX(_fx) end
workspace.ChildAdded:Connect(function(c) if c.Name == "FX" then watchFX(c) end end)

-- Log function
local function log(event, data)
	local entry = {t = math.floor((tick()-startTime)*100)/100, e = event}
	for k,v in pairs(data or {}) do entry[k] = v end
	table.insert(events, entry)
	print(string.format("[REC] t=%.1f %s %s", entry.t, event,
		data and ("dist="..tostring(data.dist or "").." spd="..tostring(data.spd or "").." hp="..tostring(data.hp or "")) or ""))
end

-- Main loop
RunService.Heartbeat:Connect(function()
	if not recording then return end

	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
	if not root or not hum then return end

	local hp = math.floor(hum.Health)

	-- Detect getting hit (health drop)
	if lastHealth and hp < lastHealth - 1 then
		local dmg = lastHealth - hp
		log("GOT_HIT", {hp=hp, dmg=dmg,
			dist = cachedBall and math.floor(Vector3.new(
				cachedBall.Position.X-root.Position.X,0,
				cachedBall.Position.Z-root.Position.Z).Magnitude) or -1,
			spd = cachedBall and math.floor(cachedBall.AssemblyLinearVelocity.Magnitude) or -1
		})
	end
	lastHealth = hp

	-- Log ball data every 0.5s
	local now = tick()
	if cachedBall and cachedBall.Parent and now - lastLogTime > 0.5 then
		lastLogTime = now
		local dist = math.floor(Vector3.new(
			cachedBall.Position.X-root.Position.X,0,
			cachedBall.Position.Z-root.Position.Z).Magnitude)
		local spd = math.floor(cachedBall.AssemblyLinearVelocity.Magnitude)
		-- Only log when ball is moving or close
		if spd > 5 or dist < 30 then
			log("BALL", {dist=dist, spd=spd, hp=hp})
		end
	end
end)

-- Commands
local function startRec()
	events = {}
	startTime = tick()
	lastHealth = nil
	lastLogTime = 0
	recording = true
	print("[REC] ======= RECORDING STARTED =======")
	print("[REC] Play normally. Run stopRec() when done.")
end

local function stopRec()
	recording = false
	print("\n[REC] ======= RECORDING STOPPED =======")
	print("[REC] Total events: "..#events)
	print("[REC] Duration: "..math.floor(tick()-startTime).."s")
	print("\n[REC] ===== FULL LOG =====")
	-- Print summary of hits
	local hits = 0
	for _, e in pairs(events) do
		if e.e == "GOT_HIT" then
			hits = hits + 1
			print(string.format("[REC] HIT #%d at t=%.1f | dist=%d spd=%d dmg=%d hp=%d",
				hits, e.t, e.dist or -1, e.spd or -1, e.dmg or 0, e.hp or 0))
		end
	end
	print("[REC] Total hits taken: "..hits)
	print("\n[REC] ===== BALL POSITIONS WHEN HIT =====")
	print("[REC] dist=how far ball was | spd=ball speed")
	print("[REC] Copy this output and share it!")
end

_G.startRec = startRec
_G.stopRec  = stopRec

print("[RecordFight] Loaded!")
print("[RecordFight] Run: _G.startRec() to start recording")
print("[RecordFight] Run: _G.stopRec()  to stop and see results")
print("[RecordFight] Join a game, start recording, play a full round, then stop")
