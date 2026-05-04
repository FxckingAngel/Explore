--[[
	Dex Loader
	FxckingAngel/Explore
	
	Usage:
	  loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/loader.lua"))()
]]

local BASE_URL = "https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/Modules/"

local function fetch(module)
	local ok, src = pcall(function()
		return game:HttpGet(BASE_URL .. module .. ".lua")
	end)
	if not ok or not src or #src == 0 then
		error(("[Dex] Failed to fetch '"..module.."': "..tostring(src)), 2)
	end
	local fn, err = loadstring(src)
	if not fn then
		error(("[Dex] Compile error in '"..module.."': "..tostring(err)), 2)
	end
	local ok2, result = pcall(fn)
	if not ok2 then
		error(("[Dex] Runtime error in '"..module.."': "..tostring(result)), 2)
	end
	return result
end

print("[Dex] Fetching modules...")

-- Fetch all module control tables
local LibControl        = fetch("Lib")
local ExplorerControl   = fetch("Explorer")
local PropertiesControl = fetch("Properties")
local SVControl         = fetch("ScriptViewer")

print("[Dex] Initializing...")

-- Mirrors what Main does in the original Dex source

local service = setmetatable({}, {__index = function(self, name)
	local s = game:GetService(name)
	self[name] = s
	return s
end})

local plr = service.Players.LocalPlayer
	or service.Players.PlayerAdded:Wait()

local Settings = {}

-- Apply default settings (mirrors DefaultSettings in main script)
local function applyDefaults(defaults, target)
	for k, v in pairs(defaults) do
		if type(v) == "table" and v._Recurse then
			target[k] = target[k] or {}
			applyDefaults(v, target[k])
		else
			target[k] = v
		end
	end
end

applyDefaults({
	Explorer = {
		_Recurse = true,
		Sorting = true,
		TeleportToOffset = Vector3.new(0,0,0),
		ClickToRename = true,
		AutoUpdateSearch = true,
		AutoUpdateMode = 0,
		LiveEditMode = true,
		PartSelectionBox = true,
		GuiSelectionBox = true,
		CopyPathUseGetChildren = true,
		UseNameWidth = false,
	},
	Properties = {
		_Recurse = true,
		MaxConflictCheck = 50,
		ShowDeprecated = false,
		ShowHidden = false,
		ClearOnFocus = false,
		LoadstringInput = true,
		NumberRounding = 3,
		ShowAttributes = false,
		LiveEditMode = true,
		MaxAttributes = 50,
		ScaleType = 1,
	},
	Theme = {
		_Recurse = true,
		Main1 = Color3.fromRGB(52,52,52),
		Main2 = Color3.fromRGB(45,45,45),
		Outline1 = Color3.fromRGB(33,33,33),
		Outline2 = Color3.fromRGB(55,55,55),
		Outline3 = Color3.fromRGB(30,30,30),
		TextBox = Color3.fromRGB(38,38,38),
		Menu = Color3.fromRGB(32,32,32),
		ListSelection = Color3.fromRGB(11,90,175),
		Button = Color3.fromRGB(60,60,60),
		ButtonHover = Color3.fromRGB(68,68,68),
		ButtonPress = Color3.fromRGB(40,40,40),
		Highlight = Color3.fromRGB(75,75,75),
		Text = Color3.fromRGB(255,255,255),
		PlaceholderText = Color3.fromRGB(100,100,100),
		Important = Color3.fromRGB(255,0,0),
		ExplorerIconMap = "",
		MiscIconMap = "",
		Syntax = {
			Text = Color3.fromRGB(204,204,204),
			Background = Color3.fromRGB(36,36,36),
			Selection = Color3.fromRGB(255,255,255),
			SelectionBack = Color3.fromRGB(11,90,175),
			Operator = Color3.fromRGB(204,204,204),
			Number = Color3.fromRGB(255,198,0),
			String = Color3.fromRGB(173,241,149),
			Comment = Color3.fromRGB(102,102,102),
			Keyword = Color3.fromRGB(248,109,124),
			Error = Color3.fromRGB(255,0,0),
			FindBackground = Color3.fromRGB(141,118,0),
			MatchingWord = Color3.fromRGB(85,85,85),
			BuiltIn = Color3.fromRGB(132,214,247),
			CurrentLine = Color3.fromRGB(45,50,65),
			LocalMethod = Color3.fromRGB(253,251,172),
			LocalProperty = Color3.fromRGB(97,161,241),
			Nil = Color3.fromRGB(255,198,0),
			Bool = Color3.fromRGB(255,198,0),
			Function = Color3.fromRGB(248,109,124),
			Local = Color3.fromRGB(248,109,124),
			Self = Color3.fromRGB(248,109,124),
			FunctionName = Color3.fromRGB(253,251,172),
			Bracket = Color3.fromRGB(204,204,204),
		},
	},
}, Settings)

-- Determine gui holder
local elevated = pcall(function() game:GetService("CoreGui"):GetFullName() end)
local GuiHolder = elevated and game:GetService("CoreGui") or plr:FindFirstChildOfClass("PlayerGui")

local create = function(data)
	local insts = {}
	for i,v in pairs(data) do insts[v[1]] = Instance.new(v[2]) end
	for _,v in pairs(data) do
		for prop,val in pairs(v[3]) do
			if type(val) == "table" then insts[v[1]][prop] = insts[val[1]]
			else insts[v[1]][prop] = val end
		end
	end
	return insts[1]
end

local createSimple = function(class, props)
	local inst = Instance.new(class)
	for i,v in next, props do inst[i] = v end
	return inst
end

-- Stub Main table that modules need
local Main = {
	Elevated = elevated,
	GuiHolder = GuiHolder,
	Mouse = plr:GetMouse(),
	DisplayOrders = {SideWindow=8, Window=10, Menu=100000, Core=101000},
	MiscIcons = nil,
	LargeIcons = nil,
	Apps = {},
	AppControls = {},
	MenuApps = {},
}

-- Wire up deps for all controls
local env = {}
local Apps = Main.Apps

local deps = {
	Main=Main, Lib=nil, Apps=Apps, Settings=Settings,
	API=nil, RMD=nil, env=env, service=service, plr=plr,
	create=create, createSimple=createSimple,
}

-- Lib needs deps before Main() so service/plr/create helpers exist
LibControl.InitDeps(deps)
local Lib = LibControl.Main()
deps.Lib = Lib
Main.MiscIcons = Lib.IconMap.new("rbxassetid://6511490623",256,256,16,16)
Main.LargeIcons = Lib.IconMap.new("rbxassetid://6579106223",256,256,32,32)

Main.MiscIcons:SetDict({
	Reference=0, Cut=1, Cut_Disabled=2, Copy=3, Copy_Disabled=4, Paste=5, Paste_Disabled=6,
	Delete=7, Delete_Disabled=8, Group=9, Group_Disabled=10, Ungroup=11, Ungroup_Disabled=12,
	TeleportTo=13, Rename=14, JumpToParent=15, ExploreData=16, Save=17, CallFunction=18,
	CallRemote=19, Undo=20, Undo_Disabled=21, Redo=22, Redo_Disabled=23,
	Expand_Over=24, Expand=25, Collapse_Over=26, Collapse=27,
	SelectChildren=28, SelectChildren_Disabled=29, InsertObject=30, ViewScript=31,
	AddStar=32, RemoveStar=33, Script_Disabled=34, LocalScript_Disabled=35,
	Play=36, Pause=37, Rename_Disabled=38,
})
Main.LargeIcons:SetDict({Explorer=0, Properties=1, Script_Viewer=2})

Main.ShowGui = function(gui)
	gui.Parent = GuiHolder
end

-- Fetch API + RMD (needed by Explorer & Properties)
print("[Dex] Fetching API...")
local env = (type(getfenv) == "function" and getfenv()) or _G
local getVersion = env.Version or env.version or _G.Version or _G.version
if type(getVersion) ~= "function" then
	error("[Dex] Could not resolve Roblox version function (Version/version)")
end

local okVersion, versionId = pcall(getVersion)
if not okVersion or type(versionId) ~= "string" or #versionId == 0 then
	error("[Dex] Failed to read Roblox version id: "..tostring(versionId))
end

local apiUrls = {
	"https://setup.roblox.com/"..versionId.."-API-Dump.json",
	"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json",
}

local rawAPI, lastApiErr, usedApiUrl
for i = 1, #apiUrls do
	local url = apiUrls[i]
	local okApiFetch, data = pcall(function()
		return game:HttpGet(url)
	end)
	if okApiFetch and type(data) == "string" and #data > 0 then
		rawAPI = data
		usedApiUrl = url
		break
	end
	lastApiErr = tostring(data)
end
if not rawAPI then
	error("[Dex] Failed to fetch API dump. Last error: "..tostring(lastApiErr))
end

local okApiDecode, apiData = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), rawAPI)
if not okApiDecode or type(apiData) ~= "table" then
	error("[Dex] Failed to decode API dump JSON from "..tostring(usedApiUrl)..": "..tostring(apiData))
end

local API = {Classes={}, Enums={}, CategoryOrder={}, GetMember=function() return {} end}
local seenCats = {}

for _, class in pairs(apiData.Classes) do
	local nc = {Name=class.Name, Superclass=class.Superclass, Properties={}, Functions={}, Events={}, Callbacks={}, Tags={}}
	if class.Tags then for _,t in pairs(class.Tags) do nc.Tags[t]=true end end
	for _, member in pairs(class.Members) do
		local nm = {Name=member.Name, Class=class.Name, Security=member.Security, Tags={}}
		if member.Tags then for _,t in pairs(member.Tags) do nm.Tags[t]=true end end
		if member.MemberType == "Property" then
			local cat = (member.Category or "Other"):match("^%s*(.-)%s*$")
			if not seenCats[cat] then API.CategoryOrder[cat]=#API.CategoryOrder+1 seenCats[cat]=true end
			nm.ValueType = member.ValueType nm.Category = cat nm.Serialization = member.Serialization
			table.insert(nc.Properties, nm)
		elseif member.MemberType == "Function" then
			nm.Parameters={} nm.ReturnType = member.ReturnType.Name
			for _,p in pairs(member.Parameters) do table.insert(nm.Parameters,{Name=p.Name,Type=p.Type.Name}) end
			table.insert(nc.Functions, nm)
		elseif member.MemberType == "Event" then
			nm.Parameters={}
			for _,p in pairs(member.Parameters) do table.insert(nm.Parameters,{Name=p.Name,Type=p.Type.Name}) end
			table.insert(nc.Events, nm)
		end
	end
	API.Classes[class.Name] = nc
end
for _, class in pairs(API.Classes) do
	class.Superclass = API.Classes[class.Superclass]
end
for _, enum in pairs(apiData.Enums) do
	local ne = {Name=enum.Name, Items={}, Tags={}}
	if enum.Tags then for _,t in pairs(enum.Tags) do ne.Tags[t]=true end end
	for _,item in pairs(enum.Items) do table.insert(ne.Items,{Name=item.Name,Value=item.Value}) end
	API.Enums[enum.Name] = ne
end

-- Minimal RMD
local RMD = {Classes={}, Enums={}, PropertyOrders={}}
pcall(function()
	print("[Dex] Fetching RMD...")
	local rawXML = game:HttpGet("https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml")
	local parsed = Lib.ParseXML(rawXML)
	local classList = parsed.children[1].children[1].children
	for _, class in pairs(classList) do
		local className = ""
		for _, child in pairs(class.children) do
			if child.tag == "Properties" then
				local data = {Properties={}, Functions={}}
				for _, prop in pairs(child.children) do
					local name = prop.attrs.name
					name = name:sub(1,1):upper()..name:sub(2)
					data[name] = prop.children[1].text
				end
				className = data.Name
				RMD.Classes[className] = data
			elseif child.attrs and child.attrs.class == "ReflectionMetadataProperties" then
				for _, member in pairs(child.children) do
					if member.attrs and member.attrs.class == "ReflectionMetadataMember" then
						local data = {}
						if member.children[1] and member.children[1].tag == "Properties" then
							for _, prop in pairs(member.children[1].children) do
								if prop.attrs then
									local name = prop.attrs.name
									name = name:sub(1,1):upper()..name:sub(2)
									data[name] = prop.children[1].text
								end
							end
							if data.PropertyOrder then
								RMD.PropertyOrders[className] = RMD.PropertyOrders[className] or {}
								RMD.PropertyOrders[className][data.Name] = tonumber(data.PropertyOrder)
							end
							if RMD.Classes[className] then
								RMD.Classes[className].Properties[data.Name] = data
							end
						end
					end
				end
			end
		end
	end
end)

deps.API = API
deps.RMD = RMD

LibControl.InitDeps(deps)
ExplorerControl.InitDeps(deps)
PropertiesControl.InitDeps(deps)
SVControl.InitDeps(deps)

-- Run each module's Main() to get the app table
local Explorer    = ExplorerControl.Main()
local Properties  = PropertiesControl.Main()
local ScriptViewer = SVControl.Main()

Apps.Explorer    = Explorer
Apps.Properties  = Properties
Apps.ScriptViewer = ScriptViewer

local appTable = {Explorer=Explorer, Properties=Properties, ScriptViewer=ScriptViewer}

-- InitAfterMain so modules can cross-reference each other
LibControl.InitAfterMain(appTable)
ExplorerControl.InitAfterMain(appTable)
PropertiesControl.InitAfterMain(appTable)
SVControl.InitAfterMain(appTable)

-- Init window system then each app
print("[Dex] Building UI...")
if not game:FindFirstChild("ServerScriptService") then
	local sssMirror = Instance.new("Folder")
	sssMirror.Name = "ServerScriptService"
	local marker = Instance.new("StringValue")
	marker.Name = "__BridgeMirror"
	marker.Value = "Client-side mirror for bridge editing"
	marker.Parent = sssMirror

	local rs = game:GetService("ReplicatedStorage")
	if not rs:FindFirstChild("DexBridge") then
		local bridge = Instance.new("RemoteEvent")
		bridge.Name = "DexBridge"
		bridge.Parent = rs
		print("[DexBridge] connected UWU (created)")
	else
		print("[DexBridge] connected UWU")
	end
	if not rs:FindFirstChild("DexBridgeList") then
		local listFn = Instance.new("RemoteFunction")
		listFn.Name = "DexBridgeList"
		listFn.Parent = rs
	end
	local listFn = rs:FindFirstChild("DexBridgeList")
	if listFn and listFn:IsA("RemoteFunction") then
		local ok, entries = pcall(function()
			return listFn:InvokeServer()
		end)
		if ok and type(entries) == "table" then
			for i = 1, #entries do
				local entry = entries[i]
				if type(entry) == "table" and type(entry.Name) == "string" then
					local node = Instance.new("StringValue")
					node.Name = entry.Name
					node.Value = entry.Path or entry.Name
					node.Parent = sssMirror
				end
			end
		end
	end

	sssMirror.Parent = game
end
Lib.Window.Init()
Explorer.Init()
Properties.Init()
	local okSV, svErr = pcall(function()
		ScriptViewer.Init()
	end)
	if not okSV then
		warn("[Dex] ScriptViewer failed to initialize: "..tostring(svErr))
	end

-- Show Explorer + Properties docked to the right side by default
Explorer.Window:Show({Align="right", Pos=1, Size=0.5, Silent=true})
Properties.Window:Show({Align="right", Pos=2, Size=0.5, Silent=true})

-- Slight defer so side-panel tween plays correctly
task.defer(function()
	Lib.Window.ToggleSide("right")
end)

print("[Dex] Ready.")
