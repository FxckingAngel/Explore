--[[
	AutoDeflect v39 — Back to basics
	Ring detection that WORKED in v20 + instant fire on entry
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/Load.lua"))()
]]

if _G._AutoDeflectCleanup then pcall(_G._AutoDeflectCleanup) _G._AutoDeflectCleanup = nil end
do
	local old = workspace:FindFirstChild("_AutoDeflect")
	if old then old:Destroy() end
	for _, h in pairs({game:GetService("CoreGui"), game:GetService("Players").LocalPlayer.PlayerGui}) do
		local g = h:FindFirstChild("AutoDeflectUI")
		if g then g:Destroy() end
	end
end
task.wait(0.1)

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local VIM              = game:GetService("VirtualInputManager")
local plr              = Players.LocalPlayer

local RADIUS    = 30
local SEGMENTS  = 48
local REFIRE_CD = 0.8
local RING_IDLE = Color3.fromRGB(0, 180, 255)
local RING_HOT  = Color3.fromRGB(255, 50, 50)
local BALL_COL  = Color3.fromRGB(255, 200, 0)

local active     = false
local myRing     = {}
local ballRing   = {}
local cachedBall = nil
local lastFired  = 0
local lastLogTime = 0
local lastLogTime = 0
local deflectBtn = nil
local renderConn = nil

local ringFolder = Instance.new("Folder")
ringFolder.Name  = "_AutoDeflect"
ringFolder.Parent = workspace

local function makeRing(radius, color)
	local parts = {}
	local step = (2*math.pi)/SEGMENTS
	for i = 0, SEGMENTS-1 do
		local a=i*step local b=(i+1)*step
		local ax,az=math.cos(a),math.sin(a)
		local bx,bz=math.cos(b),math.sin(b)
		local len=Vector3.new((bx-ax)*radius,0,(bz-az)*radius).Magnitude
		local p=Instance.new("Part")
		p.Anchored=true p.CanCollide=false p.CanQuery=false p.CanTouch=false p.CastShadow=false
		p.Size=Vector3.new(len+0.05,0.3,0.3) p.Color=color
		p.Material=Enum.Material.Neon p.Transparency=0.2 p.Parent=ringFolder
		parts[i+1]=p
	end
	return parts
end

local function posRing(parts, origin, radius)
	local step=(2*math.pi)/SEGMENTS
	for i,p in pairs(parts) do
		local a=(i-1)*step local b=i*step
		local ax,az=math.cos(a),math.sin(a)
		local bx,bz=math.cos(b),math.sin(b)
		local cx,cz=(ax+bx)/2,(az+bz)/2
		p.CFrame=CFrame.new(origin.X+cx*radius,origin.Y,origin.Z+cz*radius)
			*CFrame.Angles(0,-math.atan2(bz-az,bx-ax),0)
	end
end

local function colorRing(parts,col) for _,p in pairs(parts) do p.Color=col end end
local function destroyRing(parts) for _,p in pairs(parts) do pcall(p.Destroy,p) end end
local function getRoot() local c=plr.Character return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart")) end

-- Ball detection
local function watchFX(fx)
	local rock=fx:FindFirstChild("RockTemplate")
	if rock then cachedBall=rock end
	fx.ChildAdded:Connect(function(c) if c.Name=="RockTemplate" then cachedBall=c end end)
	fx.ChildRemoved:Connect(function(c) if c.Name=="RockTemplate" and cachedBall==c then cachedBall=nil end end)
end
local _fx=workspace:FindFirstChild("FX")
if _fx then watchFX(_fx) end
workspace.ChildAdded:Connect(function(c) if c.Name=="FX" then watchFX(c) end end)

-- Deflect button — exact method from v20 that worked
local function getDeflectButton()
	for _,v in pairs(plr.PlayerGui:GetDescendants()) do
		if v.Name=="DeflectButton" and v:IsA("GuiButton") then return v end
	end
	return nil
end

-- Ready = lighter color (R > 0.2), Cooldown = dark (R ~ 0.09)
local function isReady()
	if not deflectBtn or not deflectBtn.Parent then return true end
	return deflectBtn.BackgroundColor3.R > 0.2
end

local function fireDeflect()
	if not deflectBtn or not deflectBtn.Parent then
		deflectBtn = getDeflectButton()
	end
	-- F key
	pcall(VIM.SendKeyEvent, VIM, true,  Enum.KeyCode.F, false, game)
	task.wait(0.05)
	pcall(VIM.SendKeyEvent, VIM, false, Enum.KeyCode.F, false, game)
	-- Button click
	if deflectBtn then
		pcall(function()
			local conn=deflectBtn.MouseButton1Click:Connect(function() end)
			conn:Disconnect()
			deflectBtn.MouseButton1Click:Fire()
		end)
	end
end

-- Main update
local function update()
	local root=getRoot()
	if not root then return end
	local origin=root.Position
	posRing(myRing, origin, RADIUS)

	-- Fallback search
	if not cachedBall or not cachedBall.Parent then
		local fx=workspace:FindFirstChild("FX")
		if fx then local r=fx:FindFirstChild("RockTemplate") if r then cachedBall=r end end
	end

	local ball=cachedBall
	if ball and ball.Parent then
		if #ballRing==0 then ballRing=makeRing(3,BALL_COL) end
		posRing(ballRing, Vector3.new(ball.Position.X,origin.Y,ball.Position.Z), 3)
	elseif #ballRing>0 then
		destroyRing(ballRing) ballRing={}
	end

	if not ball or not ball.Parent then
		colorRing(myRing, RING_IDLE) return
	end

	local dist=Vector3.new(ball.Position.X-origin.X, 0, ball.Position.Z-origin.Z).Magnitude

	-- Log distance every 2 seconds
	local now2 = tick()
	if now2 - (lastLogTime or 0) > 2 then
		lastLogTime = now2
		print("[AD] dist="..math.floor(dist).." speed="..math.floor(ball.AssemblyLinearVelocity.Magnitude).." radius="..RADIUS)
	end

	local speed = ball.AssemblyLinearVelocity.Magnitude

	-- Fire when ball is in sweet spot: 3-9 studs away
	-- Too close (0-2) = already hit, Too far (10+) = animation ends before ball arrives
	local shouldFire = dist <= 9 and dist >= 2 and speed > 3

	if shouldFire then
		colorRing(myRing, RING_HOT)
		local now=tick()
		if now-lastFired >= REFIRE_CD then
			lastFired=now
			print("[AD] FIRE dist="..math.floor(dist).." spd="..math.floor(speed))
			task.spawn(function()
				fireDeflect()
				task.wait(0.05)
				fireDeflect()
			end)
		end
	else
		colorRing(myRing, RING_IDLE)
	end
end

local function enable()
	if active then return end
	active=true
	myRing=makeRing(RADIUS, RING_IDLE)
	deflectBtn=getDeflectButton()
	renderConn=RunService.Heartbeat:Connect(update)
end

local function disable()
	if not active then return end
	active=false
	if renderConn then renderConn:Disconnect() renderConn=nil end
	destroyRing(myRing) myRing={}
	destroyRing(ballRing) ballRing={}
	colorRing(myRing, RING_IDLE)
end

-- UI
local gui=Instance.new("ScreenGui")
gui.Name="AutoDeflectUI" gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.DisplayOrder=9999

local frame=Instance.new("Frame",gui)
frame.Size=UDim2.new(0,210,0,70) frame.Position=UDim2.new(0.5,-105,0,20)
frame.BackgroundColor3=Color3.fromRGB(12,12,12) frame.BorderSizePixel=0 frame.Active=true
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local stroke=Instance.new("UIStroke",frame)
stroke.Color=RING_IDLE stroke.Thickness=1.5

local title=Instance.new("TextLabel",frame)
title.Text="⬤  AUTO-DEFLECT  v51"title.Font=Enum.Font.GothamBold title.TextSize=12 title.TextColor3=RING_IDLE
title.BackgroundTransparency=1 title.Position=UDim2.new(0,12,0,8)
title.Size=UDim2.new(1,-80,0,16) title.TextXAlignment=Enum.TextXAlignment.Left

local status=Instance.new("TextLabel",frame)
status.Font=Enum.Font.Gotham status.TextSize=10
status.BackgroundTransparency=1 status.Position=UDim2.new(0,12,0,28)
status.Size=UDim2.new(1,-24,0,14) status.TextXAlignment=Enum.TextXAlignment.Left

local status2=Instance.new("TextLabel",frame)
status2.Font=Enum.Font.Gotham status2.TextSize=10
status2.BackgroundTransparency=1 status2.Position=UDim2.new(0,12,0,44)
status2.Size=UDim2.new(1,-24,0,14) status2.TextXAlignment=Enum.TextXAlignment.Left

local btn=Instance.new("TextButton",frame)
btn.Text="OFF" btn.Font=Enum.Font.GothamBold btn.TextSize=13
btn.TextColor3=Color3.fromRGB(255,255,255) btn.BackgroundColor3=Color3.fromRGB(45,45,45)
btn.BorderSizePixel=0 btn.AutoButtonColor=false
btn.Position=UDim2.new(1,-66,0,8) btn.Size=UDim2.new(0,54,0,26)
Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)

local ti=TweenInfo.new(0.15,Enum.EasingStyle.Quad)
local function updateBtn()
	if active then
		TweenService:Create(btn,ti,{BackgroundColor3=Color3.fromRGB(0,160,80)}):Play()
		TweenService:Create(stroke,ti,{Color=RING_HOT}):Play()
		btn.Text="ON"
	else
		TweenService:Create(btn,ti,{BackgroundColor3=Color3.fromRGB(45,45,45)}):Play()
		TweenService:Create(stroke,ti,{Color=RING_IDLE}):Play()
		btn.Text="OFF"
	end
end
btn.MouseButton1Click:Connect(function()
	if active then disable() else enable() end
	updateBtn()
end)

RunService.Heartbeat:Connect(function()
	if not active then
		status.Text="Off" status.TextColor3=Color3.fromRGB(80,80,80)
		status2.Text="" return
	end
	local ball=cachedBall
	local root=getRoot()
	if ball and ball.Parent and root then
		local dist=math.floor(Vector3.new(ball.Position.X-root.Position.X,0,ball.Position.Z-root.Position.Z).Magnitude)
		local spd=math.floor(ball.AssemblyLinearVelocity.Magnitude)
		status.Text="Ball: "..dist.."s  "..spd.."v"
		status.TextColor3=dist<=RADIUS and RING_HOT or Color3.fromRGB(0,200,100)
		status2.Text=tick()-lastFired<0.3 and ">>> DEFLECT FIRED <<<" or "Ring: "..RADIUS.."s"
		status2.TextColor3=tick()-lastFired<0.3 and RING_HOT or Color3.fromRGB(80,80,80)
	else
		status.Text="Searching for ball..." status.TextColor3=Color3.fromRGB(180,100,0)
		status2.Text="Ring: "..RADIUS.."s" status2.TextColor3=Color3.fromRGB(80,80,80)
	end
end)

-- Drag
local drag,ds,sp
frame.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true ds=i.Position sp=frame.Position end
end)
UserInputService.InputChanged:Connect(function(i)
	if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
		local d=i.Position-ds
		frame.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
end)

plr.CharacterAdded:Connect(function()
	if active then disable() task.wait(1) enable() updateBtn() end
end)

_G._AutoDeflectCleanup=function()
	disable() pcall(gui.Destroy,gui) pcall(ringFolder.Destroy,ringFolder)
end

local ok=pcall(function() game:GetService("CoreGui"):GetFullName() end)
gui.Parent=ok and game:GetService("CoreGui") or plr.PlayerGui
print("[AutoDeflect] v50 - sweet spot dist 2-9
