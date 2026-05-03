--[[
	Lib Module
	
	Container for functions and classes
]]

-- Common Locals
local Main,Lib,Apps,Settings -- Main Containers
local Explorer, Properties, ScriptViewer, Notebook -- Major Apps
local API,RMD,env,service,plr,create,createSimple -- Main Locals

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local Lib = {}

	local runService = (service and service.RunService) or game:GetService("RunService")
	local renderStepped = runService.RenderStepped
	local signalWait = renderStepped.wait
	local PH = newproxy() -- Placeholder, must be replaced in constructor
	local SIGNAL = newproxy()

	-- Usually for classes that work with a Roblox Object
	local function initObj(props,mt)
		local type = type
		local function copy(t)
			local res = {}
			for i,v in pairs(t) do
				if v == SIGNAL then
					res[i] = Lib.Signal.new()
				elseif type(v) == "table" then
					res[i] = copy(v)
				else
					res[i] = v
				end
			end		
			return res
		end

		local newObj = copy(props)
		return setmetatable(newObj,mt)
	end

	local function getGuiMT(props,funcs)
		return {__index = function(self,ind) if not props[ind] then return funcs[ind] or self.Gui[ind] end end,
		__newindex = function(self,ind,val) if not props[ind] then self.Gui[ind] = val else rawset(self,ind,val) end end}
	end

	-- Functions

	Lib.FormatLuaString = (function()
		local string = string
		local gsub = string.gsub
		local format = string.format
		local char = string.char
		local cleanTable = {['"'] = '\\"', ['\\'] = '\\\\'}
		for i = 0,31 do
			cleanTable[char(i)] = "\\"..format("%03d",i)
		end
		for i = 127,255 do
			cleanTable[char(i)] = "\\"..format("%03d",i)
		end

		return function(str)
			return gsub(str,"[\"\\\0-\31\127-\255]",cleanTable)
		end
	end)()

	Lib.CheckMouseInGui = function(gui)
		if gui == nil then return false end
		local mouse = Main.Mouse
		local guiPosition = gui.AbsolutePosition
		local guiSize = gui.AbsoluteSize	
		return mouse.X >= guiPosition.X and mouse.X < guiPosition.X + guiSize.X and mouse.Y >= guiPosition.Y and mouse.Y < guiPosition.Y + guiSize.Y
	end

	Lib.IsShiftDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or service.UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	Lib.IsCtrlDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or service.UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	Lib.CreateArrow = function(size,num,dir)
		local max = num
		local arrowFrame = createSimple("Frame",{
			BackgroundTransparency = 1,
			Name = "Arrow",
			Size = UDim2.new(0,size,0,size)
		})
		if dir == "up" then
			for i = 1,num do
				createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-(i-1),0,math.floor(size/2)+i-math.floor(max/2)-1),
					Size = UDim2.new(0,i+(i-1),0,1),
					Parent = arrowFrame
				})
			end
		elseif dir == "down" then
			for i = 1,num do
				createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-(i-1),0,math.floor(size/2)-i+math.floor(max/2)+1),
					Size = UDim2.new(0,i+(i-1),0,1),
					Parent = arrowFrame
				})
			end
		elseif dir == "left" then
			for i = 1,num do
				createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)+i-math.floor(max/2)-1,0,math.floor(size/2)-(i-1)),
					Size = UDim2.new(0,1,0,i+(i-1)),
					Parent = arrowFrame
				})
			end
		elseif dir == "right" then
			for i = 1,num do
				createSimple("Frame",{
					BackgroundColor3 = Color3.new(220/255,220/255,220/255),
					BorderSizePixel = 0,
					Position = UDim2.new(0,math.floor(size/2)-i+math.floor(max/2)+1,0,math.floor(size/2)-(i-1)),
					Size = UDim2.new(0,1,0,i+(i-1)),
					Parent = arrowFrame
				})
			end
		end
		return arrowFrame
	end

	Lib.ParseXML = (function()
		local func = function()
			local string, print, pairs = string, print, pairs

			local trim = function(s)
				local from = s:match"^%s*()"
				return from > #s and "" or s:match(".*%S", from)
			end

			local gtchar = string.byte('>', 1)
			local slashchar = string.byte('/', 1)
			local D = string.byte('D', 1)
			local E = string.byte('E', 1)

			function parse(s, evalEntities)
				s = s:gsub('<!%-%-(.-)%-%->', '')
				local entities, tentities = {}

				if evalEntities then
					local pos = s:find('<[_%w]')
					if pos then
						s:sub(1, pos):gsub('<!ENTITY%s+([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
							entities[#entities+1] = {name=name, value=entity}
						end)
						tentities = createEntityTable(entities)
						s = replaceEntities(s:sub(pos), tentities)
					end
				end

				local t, l = {}, {}

				local addtext = function(txt)
					txt = txt:match'^%s*(.*%S)' or ''
					if #txt ~= 0 then
						t[#t+1] = {text=txt}
					end    
				end

				s:gsub('<([?!/]?)([-:_%w]+)%s*(/?>?)([^<]*)', function(type, name, closed, txt)
					if #type == 0 then
						local a = {}
						if #closed == 0 then
							local len = 0
							for all,aname,_,value,starttxt in string.gmatch(txt, "(.-([-_%w]+)%s*=%s*(.)(.-)%3%s*(/?>?))") do
								len = len + #all
								a[aname] = value
								if #starttxt ~= 0 then
									txt = txt:sub(len+1)
									closed = starttxt
									break
								end
							end
						end
						t[#t+1] = {tag=name, attrs=a, children={}}

						if closed:byte(1) ~= slashchar then
							l[#l+1] = t
							t = t[#t].children
						end

						addtext(txt)
					elseif '/' == type then
						t = l[#l]
						l[#l] = nil
						addtext(txt)
					elseif '!' == type then
						if E == name:byte(1) then
							txt:gsub('([_%w]+)%s+(.)(.-)%2', function(name, q, entity)
								entities[#entities+1] = {name=name, value=entity}
							end, 1)
						end
					end
				end)

				return {children=t, entities=entities, tentities=tentities}
			end

			function parseText(txt)
				return parse(txt)
			end

			function defaultEntityTable()
				return { quot='"', apos="'", lt='<', gt='>', amp='&', tab='\t', nbsp=' ', }
			end

			function replaceEntities(s, entities)
				return s:gsub('&([^;]+);', entities)
			end

			function createEntityTable(docEntities, resultEntities)
				entities = resultEntities or defaultEntityTable()
				for _,e in pairs(docEntities) do
					e.value = replaceEntities(e.value, entities)
					entities[e.name] = e.value
				end
				return entities
			end

			return parseText
		end
		local newEnv = setmetatable({},{__index = getfenv()})
		setfenv(func,newEnv)
		return func()
	end)()

	Lib.FastWait = function(s)
		if not s then return signalWait(renderStepped) end
		local start = tick()
		while tick() - start < s do signalWait(renderStepped) end
	end

	Lib.ButtonAnim = function(button,data)
		local holding = false
		local disabled = false
		local mode = data and data.Mode or 1
		local control = {}

		if mode == 2 then
			local lerpTo = data.LerpTo or Color3.new(0,0,0)
			local delta = data.LerpDelta or 0.2
			control.StartColor = data.StartColor or button.BackgroundColor3
			control.PressColor = data.PressColor or control.StartColor:lerp(lerpTo,delta)
			control.HoverColor = data.HoverColor or control.StartColor:lerp(control.PressColor,0.6)
			control.OutlineColor = data.OutlineColor
		end

		button.InputBegan:Connect(function(input)
			if disabled then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement and not holding then
				if mode == 1 then button.BackgroundTransparency = 0.4
				elseif mode == 2 then button.BackgroundColor3 = control.HoverColor end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = true
				if mode == 1 then button.BackgroundTransparency = 0
				elseif mode == 2 then
					button.BackgroundColor3 = control.PressColor
					if control.OutlineColor then button.BorderColor3 = control.PressColor end
				end
			end
		end)

		button.InputEnded:Connect(function(input)
			if disabled then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement and not holding then
				if mode == 1 then button.BackgroundTransparency = 1
				elseif mode == 2 then button.BackgroundColor3 = control.StartColor end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = false
				if mode == 1 then
					button.BackgroundTransparency = Lib.CheckMouseInGui(button) and 0.4 or 1
				elseif mode == 2 then
					button.BackgroundColor3 = Lib.CheckMouseInGui(button) and control.HoverColor or control.StartColor
					if control.OutlineColor then button.BorderColor3 = control.OutlineColor end
				end
			end
		end)

		control.Disable = function()
			disabled = true
			holding = false
			if mode == 1 then button.BackgroundTransparency = 1
			elseif mode == 2 then button.BackgroundColor3 = control.StartColor end
		end

		control.Enable = function() disabled = false end

		return control
	end

	Lib.FindAndRemove = function(t,item)
		local pos = table.find(t,item)
		if pos then table.remove(t,pos) end
	end

	Lib.AttachTo = function(obj,data)
		local target,posOffX,posOffY,sizeOffX,sizeOffY,resize,con
		local disabled = false

		local function update()
			if not obj or not target then return end
			local targetPos = target.AbsolutePosition
			local targetSize = target.AbsoluteSize
			obj.Position = UDim2.new(0,targetPos.X + posOffX,0,targetPos.Y + posOffY)
			if resize then obj.Size = UDim2.new(0,targetSize.X + sizeOffX,0,targetSize.Y + sizeOffY) end
		end

		local function setup(o,data)
			obj = o
			data = data or {}
			target = data.Target
			posOffX = data.PosOffX or 0
			posOffY = data.PosOffY or 0
			sizeOffX = data.SizeOffX or 0
			sizeOffY = data.SizeOffY or 0
			resize = data.Resize or false

			if con then con:Disconnect() con = nil end
			if target then
				con = target.Changed:Connect(function(prop)
					if not disabled and prop == "AbsolutePosition" or prop == "AbsoluteSize" then
						update()
					end
				end)
			end
			update()
		end
		setup(obj,data)

		return {
			SetData = function(obj,data) setup(obj,data) end,
			Enable = function() disabled = false update() end,
			Disable = function() disabled = true end,
			Destroy = function() con:Disconnect() con = nil end,
		}
	end

	Lib.ProtectedGuis = {}

	Lib.ShowGui = function(gui)
		if env.protectgui then env.protectgui(gui) end
		gui.Parent = Main.GuiHolder
	end

	Lib.ColorToBytes = function(col)
		local round = math.round
		return string.format("%d, %d, %d",round(col.r*255),round(col.g*255),round(col.b*255))
	end

	Lib.ReadFile = function(filename)
		if not env.readfile then return end
		local s,contents = pcall(env.readfile,filename)
		if s and contents then return contents end
	end

	Lib.DeferFunc = function(f,...)
		signalWait(renderStepped)
		return f(...)
	end

	Lib.LoadCustomAsset = function(filepath)
		if not env.getcustomasset or not env.isfile or not env.isfile(filepath) then return end
		return env.getcustomasset(filepath)
	end

	Lib.FetchCustomAsset = function(url,filepath)
		if not env.writefile then return end
		local s,data = pcall(function()
			return game:HttpGet(url)
		end)
		if not s or type(data) ~= "string" or #data == 0 then return end
		local lowerData = string.lower(data)
		if lowerData:find("<html",1,true) or lowerData:find("<!doctype html",1,true) then
			return
		end
		env.writefile(filepath,data)
		return Lib.LoadCustomAsset(filepath)
	end

	-- Classes

	Lib.Signal = (function()
		local funcs = {}

		local disconnect = function(con)
			local pos = table.find(con.Signal.Connections,con)
			if pos then table.remove(con.Signal.Connections,pos) end
		end

		funcs.Connect = function(self,func)
			if type(func) ~= "function" then error("Attempt to connect a non-function") end		
			local con = {Signal = self, Func = func, Disconnect = disconnect}
			self.Connections[#self.Connections+1] = con
			return con
		end

		funcs.Fire = function(self,...)
			for i,v in next,self.Connections do
				xpcall(coroutine.wrap(v.Func),function(e) warn(e.."\n"..debug.traceback()) end,...)
			end
		end

		local mt = {
			__index = funcs,
			__tostring = function(self) return "Signal: " .. tostring(#self.Connections) .. " Connections" end
		}

		local function new()
			local obj = {}
			obj.Connections = {}
			return setmetatable(obj,mt)
		end

		return {new = new}
	end)()

	Lib.Set = (function()
		local funcs = {}

		funcs.Add = function(self,obj)
			if self.Map[obj] then return end
			local list = self.List
			list[#list+1] = obj
			self.Map[obj] = true
			self.Changed:Fire()
		end

		funcs.AddTable = function(self,t)
			local changed
			local list,map = self.List,self.Map
			for i = 1,#t do
				local elem = t[i]
				if not map[elem] then
					list[#list+1] = elem
					map[elem] = true
					changed = true
				end
			end
			if changed then self.Changed:Fire() end
		end

		funcs.Remove = function(self,obj)
			if not self.Map[obj] then return end
			local list = self.List
			local pos = table.find(list,obj)
			if pos then table.remove(list,pos) end
			self.Map[obj] = nil
			self.Changed:Fire()
		end

		funcs.RemoveTable = function(self,t)
			local changed
			local list,map = self.List,self.Map
			local removeSet = {}
			for i = 1,#t do
				local elem = t[i]
				map[elem] = nil
				removeSet[elem] = true
			end
			for i = #list,1,-1 do
				local elem = list[i]
				if removeSet[elem] then table.remove(list,i) changed = true end
			end
			if changed then self.Changed:Fire() end
		end

		funcs.Set = function(self,obj)
			if #self.List == 1 and self.List[1] == obj then return end
			self.List = {obj}
			self.Map = {[obj] = true}
			self.Changed:Fire()
		end

		funcs.SetTable = function(self,t)
			local newList,newMap = {},{}
			self.List,self.Map = newList,newMap
			table.move(t,1,#t,1,newList)
			for i = 1,#t do newMap[t[i]] = true end
			self.Changed:Fire()
		end

		funcs.Clear = function(self)
			if #self.List == 0 then return end
			self.List = {}
			self.Map = {}
			self.Changed:Fire()
		end

		local mt = {__index = funcs}

		local function new()
			local obj = setmetatable({
				List = {},
				Map = {},
				Changed = Lib.Signal.new()
			},mt)
			return obj
		end

		return {new = new}
	end)()

	Lib.IconMap = (function()
		local funcs = {}

		funcs.GetLabel = function(self)
			local label = Instance.new("ImageLabel")
			self:SetupLabel(label)
			return label
		end

		funcs.SetupLabel = function(self,obj)
			obj.BackgroundTransparency = 1
			obj.ImageRectOffset = Vector2.new(0,0)
			obj.ImageRectSize = Vector2.new(self.IconSizeX,self.IconSizeY)
			obj.ScaleType = Enum.ScaleType.Crop
			obj.Size = UDim2.new(0,self.IconSizeX,0,self.IconSizeY)
		end

		funcs.Display = function(self,obj,index)
			obj.Image = self.MapId
			if not self.NumX then
				obj.ImageRectOffset = Vector2.new(self.IconSizeX*index, 0)
			else
				obj.ImageRectOffset = Vector2.new(self.IconSizeX*(index % self.NumX), self.IconSizeY*math.floor(index / self.NumX))
			end
		end

		funcs.DisplayByKey = function(self,obj,key)
			if self.IndexDict[key] then self:Display(obj,self.IndexDict[key]) end
		end

		funcs.SetDict = function(self,dict)
			self.IndexDict = dict
		end

		local mt = {}
		mt.__index = funcs

		local function new(mapId,mapSizeX,mapSizeY,iconSizeX,iconSizeY)
			local obj = setmetatable({
				MapId = mapId, MapSizeX = mapSizeX, MapSizeY = mapSizeY,
				IconSizeX = iconSizeX, IconSizeY = iconSizeY,
				NumX = mapSizeX/iconSizeX, IndexDict = {}
			},mt)
			return obj
		end

		local function newLinear(mapId,iconSizeX,iconSizeY)
			local obj = setmetatable({
				MapId = mapId, IconSizeX = iconSizeX, IconSizeY = iconSizeY, IndexDict = {}
			},mt)
			return obj
		end

		return {new = new, newLinear = newLinear}
	end)()

	Lib.ScrollBar = (function()
		local funcs = {}
		local user = service.UserInputService
		local mouse = plr:GetMouse()
		local checkMouseInGui = Lib.CheckMouseInGui
		local createArrow = Lib.CreateArrow

		local function drawThumb(self)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local scrollThumb = self.GuiElems.ScrollThumb
			local scrollThumbFrame = self.GuiElems.ScrollThumbFrame

			if not (self:CanScrollUp() or self:CanScrollDown()) then
				scrollThumb.Visible = false
			else
				scrollThumb.Visible = true
			end

			if self.Horizontal then
				scrollThumb.Size = UDim2.new(visible/total,0,1,0)
				if scrollThumb.AbsoluteSize.X < 16 then scrollThumb.Size = UDim2.new(0,16,1,0) end
				local fs = scrollThumbFrame.AbsoluteSize.X
				local bs = scrollThumb.AbsoluteSize.X
				scrollThumb.Position = UDim2.new(self:GetScrollPercent()*(fs-bs)/fs,0,0,0)
			else
				scrollThumb.Size = UDim2.new(1,0,visible/total,0)
				if scrollThumb.AbsoluteSize.Y < 16 then scrollThumb.Size = UDim2.new(1,0,0,16) end
				local fs = scrollThumbFrame.AbsoluteSize.Y
				local bs = scrollThumb.AbsoluteSize.Y
				scrollThumb.Position = UDim2.new(0,0,self:GetScrollPercent()*(fs-bs)/fs,0)
			end
		end

		local function createFrame(self)
			local newFrame = createSimple("Frame",{Style=0,Active=true,AnchorPoint=Vector2.new(0,0),BackgroundColor3=Color3.new(0.35294118523598,0.35294118523598,0.35294118523598),BackgroundTransparency=0,BorderColor3=Color3.new(0.10588236153126,0.16470588743687,0.20784315466881),BorderSizePixel=0,ClipsDescendants=false,Draggable=false,Position=UDim2.new(1,-16,0,0),Rotation=0,Selectable=false,Size=UDim2.new(0,16,1,0),SizeConstraint=0,Visible=true,ZIndex=1,Name="ScrollBar",})
			local button1,button2

			if self.Horizontal then
				newFrame.Size = UDim2.new(1,0,0,16)
				button1 = createSimple("ImageButton",{Parent=newFrame,Name="Left",Size=UDim2.new(0,16,0,16),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false})
				createArrow(16,4,"left").Parent = button1
				button2 = createSimple("ImageButton",{Parent=newFrame,Name="Right",Position=UDim2.new(1,-16,0,0),Size=UDim2.new(0,16,0,16),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false})
				createArrow(16,4,"right").Parent = button2
			else
				newFrame.Size = UDim2.new(0,16,1,0)
				button1 = createSimple("ImageButton",{Parent=newFrame,Name="Up",Size=UDim2.new(0,16,0,16),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false})
				createArrow(16,4,"up").Parent = button1
				button2 = createSimple("ImageButton",{Parent=newFrame,Name="Down",Position=UDim2.new(0,0,1,-16),Size=UDim2.new(0,16,0,16),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false})
				createArrow(16,4,"down").Parent = button2
			end

			local scrollThumbFrame = createSimple("Frame",{BackgroundTransparency=1,Parent=newFrame})
			if self.Horizontal then
				scrollThumbFrame.Position = UDim2.new(0,16,0,0)
				scrollThumbFrame.Size = UDim2.new(1,-32,1,0)
			else
				scrollThumbFrame.Position = UDim2.new(0,0,0,16)
				scrollThumbFrame.Size = UDim2.new(1,0,1,-32)
			end

			local scrollThumb = createSimple("Frame",{BackgroundColor3=Color3.new(120/255,120/255,120/255),BorderSizePixel=0,Parent=scrollThumbFrame})
			local markerFrame = createSimple("Frame",{BackgroundTransparency=1,Name="Markers",Size=UDim2.new(1,0,1,0),Parent=scrollThumbFrame})

			local buttonPress = false
			local thumbPress = false
			local thumbFramePress = false

			button1.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not buttonPress and self:CanScrollUp() then button1.BackgroundTransparency = 0.8 end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not self:CanScrollUp() then return end
				buttonPress = true
				button1.BackgroundTransparency = 0.5
				if self:CanScrollUp() then self:ScrollUp() self.Scrolled:Fire() end
				local buttonTick = tick()
				local releaseEvent
				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
					releaseEvent:Disconnect()
					if checkMouseInGui(button1) and self:CanScrollUp() then button1.BackgroundTransparency = 0.8 else button1.BackgroundTransparency = 1 end
					buttonPress = false
				end)
				while buttonPress do
					if tick() - buttonTick >= 0.3 and self:CanScrollUp() then self:ScrollUp() self.Scrolled:Fire() end
					wait()
				end
			end)
			button1.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not buttonPress then button1.BackgroundTransparency = 1 end
			end)

			button2.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not buttonPress and self:CanScrollDown() then button2.BackgroundTransparency = 0.8 end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not self:CanScrollDown() then return end
				buttonPress = true
				button2.BackgroundTransparency = 0.5
				if self:CanScrollDown() then self:ScrollDown() self.Scrolled:Fire() end
				local buttonTick = tick()
				local releaseEvent
				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
					releaseEvent:Disconnect()
					if checkMouseInGui(button2) and self:CanScrollDown() then button2.BackgroundTransparency = 0.8 else button2.BackgroundTransparency = 1 end
					buttonPress = false
				end)
				while buttonPress do
					if tick() - buttonTick >= 0.3 and self:CanScrollDown() then self:ScrollDown() self.Scrolled:Fire() end
					wait()
				end
			end)
			button2.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not buttonPress then button2.BackgroundTransparency = 1 end
			end)

			scrollThumb.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not thumbPress then scrollThumb.BackgroundTransparency = 0.2 scrollThumb.BackgroundColor3 = self.ThumbSelectColor end
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

				local dir = self.Horizontal and "X" or "Y"
				local lastThumbPos = nil
				buttonPress = false thumbFramePress = false thumbPress = true
				scrollThumb.BackgroundTransparency = 0
				local mouseOffset = mouse[dir] - scrollThumb.AbsolutePosition[dir]
				local releaseEvent,mouseEvent

				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
					releaseEvent:Disconnect()
					if mouseEvent then mouseEvent:Disconnect() end
					if checkMouseInGui(scrollThumb) then scrollThumb.BackgroundTransparency = 0.2 else scrollThumb.BackgroundTransparency = 0 scrollThumb.BackgroundColor3 = self.ThumbColor end
					thumbPress = false
				end)
				self:Update()

				mouseEvent = user.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement and thumbPress and releaseEvent.Connected then
						local thumbFrameSize = scrollThumbFrame.AbsoluteSize[dir]-scrollThumb.AbsoluteSize[dir]
						local pos = mouse[dir] - scrollThumbFrame.AbsolutePosition[dir] - mouseOffset
						if pos > thumbFrameSize then pos = thumbFrameSize elseif pos < 0 then pos = 0 end
						if lastThumbPos ~= pos then
							lastThumbPos = pos
							self:ScrollTo(math.floor(0.5+pos/thumbFrameSize*(self.TotalSpace-self.VisibleSpace)))
						end
						wait()
					end
				end)
			end)
			scrollThumb.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and not thumbPress then scrollThumb.BackgroundTransparency = 0 scrollThumb.BackgroundColor3 = self.ThumbColor end
			end)

			scrollThumbFrame.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 or checkMouseInGui(scrollThumb) then return end
				local dir = self.Horizontal and "X" or "Y"
				local scrollDir = 0
				if mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir] then scrollDir = 1 end

				local function doTick()
					local scrollSize = self.VisibleSpace - 1
					if scrollDir == 0 and mouse[dir] < scrollThumb.AbsolutePosition[dir] then
						self:ScrollTo(self.Index - scrollSize)
					elseif scrollDir == 1 and mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir] then
						self:ScrollTo(self.Index + scrollSize)
					end
				end

				thumbPress = false thumbFramePress = true
				doTick()
				local thumbFrameTick = tick()
				local releaseEvent
				releaseEvent = user.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
					releaseEvent:Disconnect()
					thumbFramePress = false
				end)
				while thumbFramePress do
					if tick() - thumbFrameTick >= 0.3 and checkMouseInGui(scrollThumbFrame) then doTick() end
					wait()
				end
			end)

			newFrame.MouseWheelForward:Connect(function() self:ScrollTo(self.Index - self.WheelIncrement) end)
			newFrame.MouseWheelBackward:Connect(function() self:ScrollTo(self.Index + self.WheelIncrement) end)

			self.GuiElems.ScrollThumb = scrollThumb
			self.GuiElems.ScrollThumbFrame = scrollThumbFrame
			self.GuiElems.Button1 = button1
			self.GuiElems.Button2 = button2
			self.GuiElems.MarkerFrame = markerFrame

			return newFrame
		end

		funcs.Update = function(self,nocallback)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local button1 = self.GuiElems.Button1
			local button2 = self.GuiElems.Button2

			self.Index = math.clamp(self.Index,0,math.max(0,total-visible))

			if self.LastTotalSpace ~= self.TotalSpace then
				self.LastTotalSpace = self.TotalSpace
				self:UpdateMarkers()
			end

			if self:CanScrollUp() then
				for i,v in pairs(button1.Arrow:GetChildren()) do v.BackgroundTransparency = 0 end
			else
				button1.BackgroundTransparency = 1
				for i,v in pairs(button1.Arrow:GetChildren()) do v.BackgroundTransparency = 0.5 end
			end
			if self:CanScrollDown() then
				for i,v in pairs(button2.Arrow:GetChildren()) do v.BackgroundTransparency = 0 end
			else
				button2.BackgroundTransparency = 1
				for i,v in pairs(button2.Arrow:GetChildren()) do v.BackgroundTransparency = 0.5 end
			end

			drawThumb(self)
		end

		funcs.UpdateMarkers = function(self)
			local markerFrame = self.GuiElems.MarkerFrame
			markerFrame:ClearAllChildren()
			for i,v in pairs(self.Markers) do
				if i < self.TotalSpace then
					createSimple("Frame",{
						BackgroundTransparency = 0, BackgroundColor3 = v, BorderSizePixel = 0,
						Position = self.Horizontal and UDim2.new(i/self.TotalSpace,0,1,-6) or UDim2.new(1,-6,i/self.TotalSpace,0),
						Size = self.Horizontal and UDim2.new(0,1,0,6) or UDim2.new(0,6,0,1),
						Name = "Marker"..tostring(i), Parent = markerFrame
					})
				end
			end
		end

		funcs.AddMarker = function(self,ind,color) self.Markers[ind] = color or Color3.new(0,0,0) end
		funcs.ScrollTo = function(self,ind,nocallback) self.Index = ind self:Update() if not nocallback then self.Scrolled:Fire() end end
		funcs.ScrollUp = function(self) self.Index = self.Index - self.Increment self:Update() end
		funcs.ScrollDown = function(self) self.Index = self.Index + self.Increment self:Update() end
		funcs.CanScrollUp = function(self) return self.Index > 0 end
		funcs.CanScrollDown = function(self) return self.Index + self.VisibleSpace < self.TotalSpace end
		funcs.GetScrollPercent = function(self) return self.Index/(self.TotalSpace-self.VisibleSpace) end
		funcs.SetScrollPercent = function(self,perc) self.Index = math.floor(perc*(self.TotalSpace-self.VisibleSpace)) self:Update() end

		funcs.Texture = function(self,data)
			self.ThumbColor = data.ThumbColor or Color3.new(0,0,0)
			self.ThumbSelectColor = data.ThumbSelectColor or Color3.new(0,0,0)
			self.GuiElems.ScrollThumb.BackgroundColor3 = data.ThumbColor or Color3.new(0,0,0)
			self.Gui.BackgroundColor3 = data.FrameColor or Color3.new(0,0,0)
			self.GuiElems.Button1.BackgroundColor3 = data.ButtonColor or Color3.new(0,0,0)
			self.GuiElems.Button2.BackgroundColor3 = data.ButtonColor or Color3.new(0,0,0)
			for i,v in pairs(self.GuiElems.Button1.Arrow:GetChildren()) do v.BackgroundColor3 = data.ArrowColor or Color3.new(0,0,0) end
			for i,v in pairs(self.GuiElems.Button2.Arrow:GetChildren()) do v.BackgroundColor3 = data.ArrowColor or Color3.new(0,0,0) end
		end

		funcs.SetScrollFrame = function(self,frame)
			if self.ScrollUpEvent then self.ScrollUpEvent:Disconnect() self.ScrollUpEvent = nil end
			if self.ScrollDownEvent then self.ScrollDownEvent:Disconnect() self.ScrollDownEvent = nil end
			self.ScrollUpEvent = frame.MouseWheelForward:Connect(function() self:ScrollTo(self.Index - self.WheelIncrement) end)
			self.ScrollDownEvent = frame.MouseWheelBackward:Connect(function() self:ScrollTo(self.Index + self.WheelIncrement) end)
		end

		local mt = {}
		mt.__index = funcs

		local function new(hor)
			local obj = setmetatable({
				Index = 0, VisibleSpace = 0, TotalSpace = 0,
				Increment = 1, WheelIncrement = 1,
				Markers = {}, GuiElems = {}, Horizontal = hor,
				LastTotalSpace = 0, Scrolled = Lib.Signal.new()
			},mt)
			obj.Gui = createFrame(obj)
			obj:Texture({
				ThumbColor = Color3.fromRGB(60,60,60),
				ThumbSelectColor = Color3.fromRGB(75,75,75),
				ArrowColor = Color3.new(1,1,1),
				FrameColor = Color3.fromRGB(40,40,40),
				ButtonColor = Color3.fromRGB(75,75,75)
			})
			return obj
		end

		return {new = new}
	end)()

	Lib.Window = (function()
		local funcs = {}
		local static = {MinWidth = 200, FreeWidth = 200}
		local mouse = plr:GetMouse()
		local sidesGui,alignIndicator
		local visibleWindows = {}
		local leftSide = {Width = 300, Windows = {}, ResizeCons = {}, Hidden = true}
		local rightSide = {Width = 300, Windows = {}, ResizeCons = {}, Hidden = true}
		local displayOrderStart
		local sideDisplayOrder
		local sideTweenInfo = TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
		local tweens = {}
		local isA = game.IsA

		local theme = {
			MainColor1 = Color3.fromRGB(52,52,52),
			MainColor2 = Color3.fromRGB(45,45,45),
			Button = Color3.fromRGB(60,60,60)
		}

		local function stopTweens()
			for i = 1,#tweens do tweens[i]:Cancel() end
			tweens = {}
		end

		local function resizeHook(self,resizer,dir)
			local guiMain = self.GuiElems.Main
			resizer.InputBegan:Connect(function(input)
				if not self.Dragging and not self.Resizing and self.Resizable and self.ResizableInternal then
					local isH = dir:find("[WE]") and true
					local isV = dir:find("[NS]") and true
					local signX = dir:find("W",1,true) and -1 or 1
					local signY = dir:find("N",1,true) and -1 or 1

					if self.Minimized and isV then return end

					if input.UserInputType == Enum.UserInputType.MouseMovement then
						resizer.BackgroundTransparency = 0.5
					elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
						local releaseEvent,mouseEvent
						local offX = mouse.X - resizer.AbsolutePosition.X
						local offY = mouse.Y - resizer.AbsolutePosition.Y
						self.Resizing = resizer
						resizer.BackgroundTransparency = 1

						releaseEvent = service.UserInputService.InputEnded:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1 then
								releaseEvent:Disconnect() mouseEvent:Disconnect()
								self.Resizing = false resizer.BackgroundTransparency = 1
							end
						end)

						mouseEvent = service.UserInputService.InputChanged:Connect(function(input)
							if self.Resizable and self.ResizableInternal and input.UserInputType == Enum.UserInputType.MouseMovement then
								self:StopTweens()
								local deltaX = input.Position.X - resizer.AbsolutePosition.X - offX
								local deltaY = input.Position.Y - resizer.AbsolutePosition.Y - offY
								if guiMain.AbsoluteSize.X + deltaX*signX < self.MinX then deltaX = signX*(self.MinX - guiMain.AbsoluteSize.X) end
								if guiMain.AbsoluteSize.Y + deltaY*signY < self.MinY then deltaY = signY*(self.MinY - guiMain.AbsoluteSize.Y) end
								if signY < 0 and guiMain.AbsolutePosition.Y + deltaY < 0 then deltaY = -guiMain.AbsolutePosition.Y end
								guiMain.Position = guiMain.Position + UDim2.new(0,(signX < 0 and deltaX or 0),0,(signY < 0 and deltaY or 0))
								self.SizeX = self.SizeX + (isH and deltaX*signX or 0)
								self.SizeY = self.SizeY + (isV and deltaY*signY or 0)
								guiMain.Size = UDim2.new(0,self.SizeX,0,self.Minimized and 20 or self.SizeY)
							end
						end)
					end
				end
			end)

			resizer.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and self.Resizing ~= resizer then
					resizer.BackgroundTransparency = 1
				end
			end)
		end

		local updateWindows

		local function moveToTop(window)
			local found = table.find(visibleWindows,window)
			if found then
				table.remove(visibleWindows,found)
				table.insert(visibleWindows,1,window)
				updateWindows()
			end
		end

		local function sideHasRoom(side,neededSize)
			local maxY = sidesGui.AbsoluteSize.Y - (math.max(0,#side.Windows - 1) * 4)
			local inc = 0
			for i,v in pairs(side.Windows) do
				inc = inc + (v.MinY or 100)
				if inc > maxY - neededSize then return false end
			end
			return true
		end

		local function getSideInsertPos(side,curY)
			local pos = #side.Windows + 1
			local range = {0,sidesGui.AbsoluteSize.Y}
			for i,v in pairs(side.Windows) do
				local midPos = v.PosY + v.SizeY/2
				if curY <= midPos then pos = i range[2] = midPos break
				else range[1] = midPos end
			end
			return pos,range
		end

		local function focusInput(self,obj)
			if isA(obj,"GuiButton") then
				obj.MouseButton1Down:Connect(function() moveToTop(self) end)
			elseif isA(obj,"TextBox") then
				obj.Focused:Connect(function() moveToTop(self) end)
			end
		end

		local createGui = function(self)
			local gui = create({
				{1,"ScreenGui",{Name="Window",}},
				{2,"Frame",{Active=true,BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="Main",Parent={1},Position=UDim2.new(0.40000000596046,0,0.40000000596046,0),Size=UDim2.new(0,300,0,300),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,Name="Content",Parent={2},Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,1,-20),ClipsDescendants=true}},
				{4,"Frame",{BackgroundColor3=Color3.fromRGB(33,33,33),BorderSizePixel=0,Name="Line",Parent={3},Size=UDim2.new(1,0,0,1),}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="TopBar",Parent={2},Size=UDim2.new(1,0,0,20),}},
				{6,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Title",Parent={5},Position=UDim2.new(0,5,0,0),Size=UDim2.new(1,-10,0,20),Text="Window",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,}},
				{7,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Close",Parent={5},Position=UDim2.new(1,-18,0,2),Size=UDim2.new(0,16,0,16),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
				{8,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5054663650",Parent={7},Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,10,0,10),}},
				{9,"UICorner",{CornerRadius=UDim.new(0,4),Parent={7},}},
				{10,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.12549020349979,0.12549020349979,0.12549020349979),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="Minimize",Parent={5},Position=UDim2.new(1,-36,0,2),Size=UDim2.new(0,16,0,16),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,}},
				{11,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://5034768003",Parent={10},Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,10,0,10),}},
				{12,"UICorner",{CornerRadius=UDim.new(0,4),Parent={10},}},
				{13,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Image="rbxassetid://1427967925",Name="Outlines",Parent={2},Position=UDim2.new(0,-5,0,-5),ScaleType=1,Size=UDim2.new(1,10,1,10),SliceCenter=Rect.new(6,6,25,25),TileSize=UDim2.new(0,20,0,20),}},
				{14,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Name="ResizeControls",Parent={2},Position=UDim2.new(0,-5,0,-5),Size=UDim2.new(1,10,1,10),}},
				{15,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="North",Parent={14},Position=UDim2.new(0,5,0,0),Size=UDim2.new(1,-10,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{16,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="South",Parent={14},Position=UDim2.new(0,5,1,-5),Size=UDim2.new(1,-10,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{17,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="NorthEast",Parent={14},Position=UDim2.new(1,-5,0,0),Size=UDim2.new(0,5,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{18,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="East",Parent={14},Position=UDim2.new(1,-5,0,5),Size=UDim2.new(0,5,1,-10),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{19,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="West",Parent={14},Position=UDim2.new(0,0,0,5),Size=UDim2.new(0,5,1,-10),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{20,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="SouthEast",Parent={14},Position=UDim2.new(1,-5,1,-5),Size=UDim2.new(0,5,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{21,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="NorthWest",Parent={14},Size=UDim2.new(0,5,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{22,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.27450981736183,0.27450981736183,0.27450981736183),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="SouthWest",Parent={14},Position=UDim2.new(0,0,1,-5),Size=UDim2.new(0,5,0,5),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
			})

			local guiMain = gui.Main
			local guiTopBar = guiMain.TopBar
			local guiResizeControls = guiMain.ResizeControls

			self.GuiElems.Main = guiMain
			self.GuiElems.TopBar = guiMain.TopBar
			self.GuiElems.Content = guiMain.Content
			self.GuiElems.Line = guiMain.Content.Line
			self.GuiElems.Outlines = guiMain.Outlines
			self.GuiElems.Title = guiTopBar.Title
			self.GuiElems.Close = guiTopBar.Close
			self.GuiElems.Minimize = guiTopBar.Minimize
			self.GuiElems.ResizeControls = guiResizeControls
			self.ContentPane = guiMain.Content

			guiTopBar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and self.Draggable then
					local releaseEvent,mouseEvent
					local maxX = sidesGui.AbsoluteSize.X
					local initX = guiMain.AbsolutePosition.X
					local initY = guiMain.AbsolutePosition.Y
					local offX = mouse.X - initX
					local offY = mouse.Y - initY
					local alignInsertPos,alignInsertSide
					guiDragging = true

					releaseEvent = game:GetService("UserInputService").InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							releaseEvent:Disconnect() mouseEvent:Disconnect()
							guiDragging = false alignIndicator.Parent = nil
							if alignInsertSide then
								local targetSide = (alignInsertSide == "left" and leftSide) or (alignInsertSide == "right" and rightSide)
								self:AlignTo(targetSide,alignInsertPos)
							end
						end
					end)

					mouseEvent = game:GetService("UserInputService").InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement and self.Draggable and not self.Closed then
							if self.Aligned then
								if leftSide.Resizing or rightSide.Resizing then return end
								local posX,posY = input.Position.X-offX,input.Position.Y-offY
								local delta = math.sqrt((posX-initX)^2 + (posY-initY)^2)
								if delta >= 5 then self:SetAligned(false) end
							else
								local inputX,inputY = input.Position.X,input.Position.Y
								local posX,posY = inputX-offX,inputY-offY
								if posY < 0 then posY = 0 end
								guiMain.Position = UDim2.new(0,posX,0,posY)

								if self.Resizable and self.Alignable then
									if inputX < 25 then
										if sideHasRoom(leftSide,self.MinY or 100) then
											local insertPos,range = getSideInsertPos(leftSide,inputY)
											alignIndicator.Indicator.Position = UDim2.new(0,-15,0,range[1])
											alignIndicator.Indicator.Size = UDim2.new(0,40,0,range[2]-range[1])
											Lib.ShowGui(alignIndicator)
											alignInsertPos = insertPos alignInsertSide = "left" return
										end
									elseif inputX >= maxX - 25 then
										if sideHasRoom(rightSide,self.MinY or 100) then
											local insertPos,range = getSideInsertPos(rightSide,inputY)
											alignIndicator.Indicator.Position = UDim2.new(0,maxX-25,0,range[1])
											alignIndicator.Indicator.Size = UDim2.new(0,40,0,range[2]-range[1])
											Lib.ShowGui(alignIndicator)
											alignInsertPos = insertPos alignInsertSide = "right" return
										end
									end
								end
								alignIndicator.Parent = nil alignInsertPos = nil alignInsertSide = nil
							end
						end
					end)
				end
			end)

			guiTopBar.Close.MouseButton1Click:Connect(function()
				if self.Closed then return end
				self:Close()
			end)

			guiTopBar.Minimize.MouseButton1Click:Connect(function()
				if self.Closed then return end
				if self.Aligned then self:SetAligned(false)
				else self:SetMinimized() end
			end)

			guiTopBar.Minimize.MouseButton2Click:Connect(function()
				if self.Closed then return end
				if not self.Aligned then
					self:SetMinimized(nil,2)
					guiTopBar.Minimize.BackgroundTransparency = 1
				end
			end)

			guiMain.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and not self.Aligned and not self.Closed then
					moveToTop(self)
				end
			end)

			guiMain:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				local absPos = guiMain.AbsolutePosition
				self.PosX = absPos.X self.PosY = absPos.Y
			end)

			resizeHook(self,guiResizeControls.North,"N")
			resizeHook(self,guiResizeControls.NorthEast,"NE")
			resizeHook(self,guiResizeControls.East,"E")
			resizeHook(self,guiResizeControls.SouthEast,"SE")
			resizeHook(self,guiResizeControls.South,"S")
			resizeHook(self,guiResizeControls.SouthWest,"SW")
			resizeHook(self,guiResizeControls.West,"W")
			resizeHook(self,guiResizeControls.NorthWest,"NW")

			guiMain.Size = UDim2.new(0,self.SizeX,0,self.SizeY)

			gui.DescendantAdded:Connect(function(obj) focusInput(self,obj) end)
			local descs = gui:GetDescendants()
			for i = 1,#descs do focusInput(self,descs[i]) end

			self.MinimizeAnim = Lib.ButtonAnim(guiTopBar.Minimize)
			self.CloseAnim = Lib.ButtonAnim(guiTopBar.Close)

			return gui
		end

		local function updateSideFrames(noTween)
			stopTweens()
			leftSide.Frame.Size = UDim2.new(0,leftSide.Width,1,0)
			rightSide.Frame.Size = UDim2.new(0,rightSide.Width,1,0)
			leftSide.Frame.Resizer.Position = UDim2.new(0,leftSide.Width,0,0)
			rightSide.Frame.Resizer.Position = UDim2.new(0,-5,0,0)

			local leftHidden = #leftSide.Windows == 0 or leftSide.Hidden
			local rightHidden = #rightSide.Windows == 0 or rightSide.Hidden
			local leftPos = (leftHidden and UDim2.new(0,-leftSide.Width-10,0,0) or UDim2.new(0,0,0,0))
			local rightPos = (rightHidden and UDim2.new(1,10,0,0) or UDim2.new(1,-rightSide.Width,0,0))

			sidesGui.LeftToggle.Text = leftHidden and ">" or "<"
			sidesGui.RightToggle.Text = rightHidden and "<" or ">"

			if not noTween then
				local function insertTween(...)
					local tween = service.TweenService:Create(...)
					tweens[#tweens+1] = tween tween:Play()
				end
				insertTween(leftSide.Frame,sideTweenInfo,{Position = leftPos})
				insertTween(rightSide.Frame,sideTweenInfo,{Position = rightPos})
				insertTween(sidesGui.LeftToggle,sideTweenInfo,{Position = UDim2.new(0,#leftSide.Windows == 0 and -16 or 0,0,-36)})
				insertTween(sidesGui.RightToggle,sideTweenInfo,{Position = UDim2.new(1,#rightSide.Windows == 0 and 0 or -16,0,-36)})
			else
				leftSide.Frame.Position = leftPos
				rightSide.Frame.Position = rightPos
				sidesGui.LeftToggle.Position = UDim2.new(0,#leftSide.Windows == 0 and -16 or 0,0,-36)
				sidesGui.RightToggle.Position = UDim2.new(1,#rightSide.Windows == 0 and 0 or -16,0,-36)
			end
		end

		local function getSideFramePos(side)
			local leftHidden = #leftSide.Windows == 0 or leftSide.Hidden
			local rightHidden = #rightSide.Windows == 0 or rightSide.Hidden
			if side == leftSide then
				return (leftHidden and UDim2.new(0,-leftSide.Width-10,0,0) or UDim2.new(0,0,0,0))
			else
				return (rightHidden and UDim2.new(1,10,0,0) or UDim2.new(1,-rightSide.Width,0,0))
			end
		end

		local function sideResized(side)
			local currentPos = 0
			local sideFramePos = getSideFramePos(side)
			for i,v in pairs(side.Windows) do
				v.SizeX = side.Width
				v.GuiElems.Main.Size = UDim2.new(0,side.Width,0,v.SizeY)
				v.GuiElems.Main.Position = UDim2.new(sideFramePos.X.Scale,sideFramePos.X.Offset,0,currentPos)
				currentPos = currentPos + v.SizeY+4
			end
		end

		local function sideResizerHook(resizer,dir,side,pos)
			local mouse = Main.Mouse
			local windows = side.Windows

			resizer.InputBegan:Connect(function(input)
				if not side.Resizing then
					if input.UserInputType == Enum.UserInputType.MouseMovement then
						resizer.BackgroundColor3 = theme.MainColor2
					elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
						local releaseEvent,mouseEvent
						local offX = mouse.X - resizer.AbsolutePosition.X
						local offY = mouse.Y - resizer.AbsolutePosition.Y
						side.Resizing = resizer
						resizer.BackgroundColor3 = theme.MainColor2

						releaseEvent = service.UserInputService.InputEnded:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1 then
								releaseEvent:Disconnect() mouseEvent:Disconnect()
								side.Resizing = false resizer.BackgroundColor3 = theme.Button
							end
						end)

						mouseEvent = service.UserInputService.InputChanged:Connect(function(input)
							if not resizer.Parent then
								releaseEvent:Disconnect() mouseEvent:Disconnect() side.Resizing = false return
							end
							if input.UserInputType == Enum.UserInputType.MouseMovement then
								if dir == "V" then
									local delta = input.Position.Y - resizer.AbsolutePosition.Y - offY
									if delta > 0 then
										local neededSize = delta
										for i = pos+1,#windows do
											local window = windows[i]
											local newSize = math.max(window.SizeY-neededSize,(window.MinY or 100))
											neededSize = neededSize - (window.SizeY - newSize)
											window.SizeY = newSize
										end
										windows[pos].SizeY = windows[pos].SizeY + math.max(0,delta-neededSize)
									else
										local neededSize = -delta
										for i = pos,1,-1 do
											local window = windows[i]
											local newSize = math.max(window.SizeY-neededSize,(window.MinY or 100))
											neededSize = neededSize - (window.SizeY - newSize)
											window.SizeY = newSize
										end
										windows[pos+1].SizeY = windows[pos+1].SizeY + math.max(0,-delta-neededSize)
									end
									updateSideFrames() sideResized(side)
								elseif dir == "H" then
									local maxWidth = math.max(300,sidesGui.AbsoluteSize.X-static.FreeWidth)
									local otherSide = (side == leftSide and rightSide or leftSide)
									local delta = input.Position.X - resizer.AbsolutePosition.X - offX
									delta = (side == leftSide and delta or -delta)
									local proposedSize = math.max(static.MinWidth,side.Width + delta)
									if proposedSize + otherSide.Width <= maxWidth then
										side.Width = proposedSize
									else
										local newOtherSize = maxWidth - proposedSize
										if newOtherSize >= static.MinWidth then
											side.Width = proposedSize otherSide.Width = newOtherSize
										else
											side.Width = maxWidth - static.MinWidth otherSide.Width = static.MinWidth
										end
									end
									updateSideFrames(true) sideResized(side) sideResized(otherSide)
								end
							end
						end)
					end
				end
			end)

			resizer.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and side.Resizing ~= resizer then
					resizer.BackgroundColor3 = theme.Button
				end
			end)
		end

		local function renderSide(side,noTween)
			local currentPos = 0
			local sideFramePos = getSideFramePos(side)
			local template = side.WindowResizer:Clone()
			for i,v in pairs(side.ResizeCons) do v:Disconnect() end
			for i,v in pairs(side.Frame:GetChildren()) do if v.Name == "WindowResizer" then v:Destroy() end end
			side.ResizeCons = {} side.Resizing = nil

			for i,v in pairs(side.Windows) do
				v.SidePos = i
				local isEnd = i == #side.Windows
				local size = UDim2.new(0,side.Width,0,v.SizeY)
				local pos = UDim2.new(sideFramePos.X.Scale,sideFramePos.X.Offset,0,currentPos)
				Lib.ShowGui(v.Gui)
				if noTween then
					v.GuiElems.Main.Size = size v.GuiElems.Main.Position = pos
				else
					local tween = service.TweenService:Create(v.GuiElems.Main,sideTweenInfo,{Size=size,Position=pos})
					tweens[#tweens+1] = tween tween:Play()
				end
				currentPos = currentPos + v.SizeY+4

				if not isEnd then
					local newTemplate = template:Clone()
					newTemplate.Position = UDim2.new(1,-side.Width,0,currentPos-4)
					side.ResizeCons[#side.ResizeCons+1] = v.Gui.Main:GetPropertyChangedSignal("Size"):Connect(function()
						newTemplate.Position = UDim2.new(1,-side.Width,0,v.GuiElems.Main.Position.Y.Offset+v.GuiElems.Main.Size.Y.Offset)
					end)
					side.ResizeCons[#side.ResizeCons+1] = v.Gui.Main:GetPropertyChangedSignal("Position"):Connect(function()
						newTemplate.Position = UDim2.new(1,-side.Width,0,v.GuiElems.Main.Position.Y.Offset+v.GuiElems.Main.Size.Y.Offset)
					end)
					sideResizerHook(newTemplate,"V",side,i)
					newTemplate.Parent = side.Frame
				end
			end
		end

		local function updateSide(side,noTween)
			local oldHeight = 0
			local currentPos = 0
			local neededSize = 0
			local windows = side.Windows
			local height = sidesGui.AbsoluteSize.Y - (math.max(0,#windows-1)*4)
			for i,v in pairs(windows) do oldHeight = oldHeight + v.SizeY end
			for i,v in pairs(windows) do
				if i == #windows then
					v.SizeY = height-currentPos
					neededSize = math.max(0,(v.MinY or 100)-v.SizeY)
				else
					v.SizeY = math.max(math.floor(v.SizeY/oldHeight*height),v.MinY or 100)
				end
				currentPos = currentPos + v.SizeY
			end
			if neededSize > 0 then
				for i = #windows-1,1,-1 do
					local window = windows[i]
					local newSize = math.max(window.SizeY-neededSize,(window.MinY or 100))
					neededSize = neededSize - (window.SizeY - newSize)
					window.SizeY = newSize
				end
				local lastWindow = windows[#windows]
				lastWindow.SizeY = (lastWindow.MinY or 100)-neededSize
			end
			renderSide(side,noTween)
		end

		updateWindows = function(noTween)
			updateSideFrames(noTween)
			updateSide(leftSide,noTween)
			updateSide(rightSide,noTween)
			local count = 0
			for i = #visibleWindows,1,-1 do
				visibleWindows[i].Gui.DisplayOrder = displayOrderStart + count
				Lib.ShowGui(visibleWindows[i].Gui)
				count = count + 1
			end
		end

		funcs.SetMinimized = function(self,set,mode)
			local oldVal = self.Minimized
			local newVal
			if set == nil then newVal = not self.Minimized else newVal = set end
			self.Minimized = newVal
			if not mode then mode = 1 end

			local resizeControls = self.GuiElems.ResizeControls
			local minimizeControls = {"North","NorthEast","NorthWest","South","SouthEast","SouthWest"}
			for i = 1,#minimizeControls do
				local control = resizeControls:FindFirstChild(minimizeControls[i])
				if control then control.Visible = not newVal end
			end

			if mode == 1 or mode == 2 then
				self:StopTweens()
				if mode == 1 then
					self.GuiElems.Main:TweenSize(UDim2.new(0,self.SizeX,0,newVal and 20 or self.SizeY),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.25,true)
				else
					local maxY = sidesGui.AbsoluteSize.Y
					local newPos = UDim2.new(0,self.PosX,0,newVal and math.min(maxY-20,self.PosY+self.SizeY-20) or math.max(0,self.PosY-self.SizeY+20))
					self.GuiElems.Main:TweenPosition(newPos,Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.25,true)
					self.GuiElems.Main:TweenSize(UDim2.new(0,self.SizeX,0,newVal and 20 or self.SizeY),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.25,true)
				end
				self.GuiElems.Minimize.ImageLabel.Image = newVal and "rbxassetid://5060023708" or "rbxassetid://5034768003"
			end

			if oldVal ~= newVal then
				if newVal then self.OnMinimize:Fire() else self.OnRestore:Fire() end
			end
		end

		funcs.Resize = function(self,sizeX,sizeY)
			self.SizeX = sizeX or self.SizeX self.SizeY = sizeY or self.SizeY
			self.GuiElems.Main.Size = UDim2.new(0,self.SizeX,0,self.SizeY)
		end
		funcs.SetSize = funcs.Resize
		funcs.SetTitle = function(self,title) self.GuiElems.Title.Text = title end
		funcs.SetResizable = function(self,val) self.Resizable = val self.GuiElems.ResizeControls.Visible = self.Resizable and self.ResizableInternal end
		funcs.SetResizableInternal = function(self,val) self.ResizableInternal = val self.GuiElems.ResizeControls.Visible = self.Resizable and self.ResizableInternal end

		funcs.SetAligned = function(self,val)
			self.Aligned = val
			self:SetResizableInternal(not val)
			self.GuiElems.Main.Active = not val
			self.GuiElems.Main.Outlines.Visible = not val
			if not val then
				for i,v in pairs(leftSide.Windows) do if v == self then table.remove(leftSide.Windows,i) break end end
				for i,v in pairs(rightSide.Windows) do if v == self then table.remove(rightSide.Windows,i) break end end
				if not table.find(visibleWindows,self) then table.insert(visibleWindows,1,self) end
				self.GuiElems.Minimize.ImageLabel.Image = "rbxassetid://5034768003"
				self.Side = nil updateWindows()
			else
				self:SetMinimized(false,3)
				for i,v in pairs(visibleWindows) do if v == self then table.remove(visibleWindows,i) break end end
				self.GuiElems.Minimize.ImageLabel.Image = "rbxassetid://5448127505"
			end
		end

		funcs.Add = function(self,obj,name)
			if type(obj) == "table" and obj.Gui and obj.Gui:IsA("GuiObject") then
				obj.Gui.Parent = self.ContentPane
			else obj.Parent = self.ContentPane end
			if name then self.Elements[name] = obj end
		end

		funcs.GetElement = function(self,obj,name) return self.Elements[name] end

		funcs.AlignTo = function(self,side,pos,size,silent)
			if table.find(side.Windows,self) or self.Closed then return end
			size = size or self.SizeY
			if size > 0 and size <= 1 then
				local totalSideHeight = 0
				for i,v in pairs(side.Windows) do totalSideHeight = totalSideHeight + v.SizeY end
				self.SizeY = (totalSideHeight > 0 and totalSideHeight * size * 2) or size
			else self.SizeY = (size > 0 and size or 100) end
			self:SetAligned(true)
			self.Side = side self.SizeX = side.Width
			self.Gui.DisplayOrder = sideDisplayOrder + 1
			for i,v in pairs(side.Windows) do v.Gui.DisplayOrder = sideDisplayOrder end
			pos = math.min(#side.Windows+1,pos or 1)
			self.SidePos = pos
			table.insert(side.Windows,pos,self)
			if not silent then side.Hidden = false end
			updateWindows(silent)
		end

		funcs.Close = function(self)
			self.Closed = true self:SetResizableInternal(false)
			Lib.FindAndRemove(leftSide.Windows,self)
			Lib.FindAndRemove(rightSide.Windows,self)
			Lib.FindAndRemove(visibleWindows,self)
			self.MinimizeAnim.Disable() self.CloseAnim.Disable()
			self.ClosedSide = self.Side self.Side = nil
			self.OnDeactivate:Fire()

			if not self.Aligned then
				self:StopTweens()
				local ti = TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
				local closeTime = tick() self.LastClose = closeTime
				self:DoTween(self.GuiElems.Main,ti,{Size=UDim2.new(0,self.SizeX,0,20)})
				self:DoTween(self.GuiElems.Title,ti,{TextTransparency=1})
				self:DoTween(self.GuiElems.Minimize.ImageLabel,ti,{ImageTransparency=1})
				self:DoTween(self.GuiElems.Close.ImageLabel,ti,{ImageTransparency=1})
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then return end
				self:DoTween(self.GuiElems.TopBar,ti,{BackgroundTransparency=1})
				self:DoTween(self.GuiElems.Outlines,ti,{ImageTransparency=1})
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then return end
			end

			self.Aligned = false self.Gui.Parent = nil
			updateWindows(true)
		end

		funcs.Hide = funcs.Close
		funcs.IsVisible = function(self) return not self.Closed and ((self.Side and not self.Side.Hidden) or not self.Side) end
		funcs.IsContentVisible = function(self) return self:IsVisible() and not self.Minimized end
		funcs.Focus = function(self) moveToTop(self) end

		funcs.MoveInBoundary = function(self)
			local posX,posY = self.PosX,self.PosY
			local maxX,maxY = sidesGui.AbsoluteSize.X,sidesGui.AbsoluteSize.Y
			posX = math.min(posX,maxX-self.SizeX) posY = math.min(posY,maxY-20)
			self.GuiElems.Main.Position = UDim2.new(0,posX,0,posY)
		end

		funcs.DoTween = function(self,...)
			local tween = service.TweenService:Create(...)
			self.Tweens[#self.Tweens+1] = tween tween:Play()
		end

		funcs.StopTweens = function(self)
			for i,v in pairs(self.Tweens) do v:Cancel() end
			self.Tweens = {}
		end

		funcs.Show = function(self,data) return static.ShowWindow(self,data) end
		funcs.ShowAndFocus = function(self,data)
			static.ShowWindow(self,data)
			service.RunService.RenderStepped:wait()
			self:Focus()
		end

		static.ShowWindow = function(window,data)
			data = data or {}
			local align = data.Align
			local pos = data.Pos
			local size = data.Size
			local targetSide = (align == "left" and leftSide) or (align == "right" and rightSide)

			if not window.Closed then
				if not window.Aligned then window:SetMinimized(false)
				elseif window.Side and not data.Silent then static.SetSideVisible(window.Side,true) end
				return
			end

			window.Closed = false window.LastClose = tick()
			window.GuiElems.Title.TextTransparency = 0
			window.GuiElems.Minimize.ImageLabel.ImageTransparency = 0
			window.GuiElems.Close.ImageLabel.ImageTransparency = 0
			window.GuiElems.TopBar.BackgroundTransparency = 0
			window.GuiElems.Outlines.ImageTransparency = 0
			window.GuiElems.Minimize.ImageLabel.Image = "rbxassetid://5034768003"
			window.GuiElems.Main.Active = true
			window.GuiElems.Main.Outlines.Visible = true
			window:SetMinimized(false,3) window:SetResizableInternal(true)
			window.MinimizeAnim.Enable() window.CloseAnim.Enable()

			if align then
				window:AlignTo(targetSide,pos,size,data.Silent)
			else
				if align == nil and window.ClosedSide then
					window:AlignTo(window.ClosedSide,window.SidePos,size,true)
					static.SetSideVisible(window.ClosedSide,true)
				else
					if table.find(visibleWindows,window) then return end
					window.GuiElems.Main.Size = UDim2.new(0,window.SizeX,0,20)
					local ti = TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
					window:StopTweens()
					window:DoTween(window.GuiElems.Main,ti,{Size=UDim2.new(0,window.SizeX,0,window.SizeY)})
					window.SizeY = size or window.SizeY
					table.insert(visibleWindows,1,window)
					updateWindows()
				end
			end

			window.ClosedSide = nil
			window.OnActivate:Fire()
		end

		static.ToggleSide = function(name)
			local side = (name == "left" and leftSide or rightSide)
			side.Hidden = not side.Hidden
			for i,v in pairs(side.Windows) do
				if side.Hidden then v.OnDeactivate:Fire() else v.OnActivate:Fire() end
			end
			updateWindows()
		end

		static.SetSideVisible = function(s,vis)
			local side = (type(s) == "table" and s) or (s == "left" and leftSide or rightSide)
			side.Hidden = not vis
			for i,v in pairs(side.Windows) do
				if side.Hidden then v.OnDeactivate:Fire() else v.OnActivate:Fire() end
			end
			updateWindows()
		end

		static.Init = function()
			displayOrderStart = Main.DisplayOrders.Window
			sideDisplayOrder = Main.DisplayOrders.SideWindow

			sidesGui = Instance.new("ScreenGui")
			local leftFrame = create({
				{1,"Frame",{Active=true,Name="LeftSide",BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,}},
				{2,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2549019753933,0.2549019753933,0.2549019753933),BorderSizePixel=0,Font=3,Name="Resizer",Parent={1},Size=UDim2.new(0,5,1,0),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={2},Position=UDim2.new(0,0,0,0),Size=UDim2.new(0,1,1,0),}},
				{4,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2549019753933,0.2549019753933,0.2549019753933),BorderSizePixel=0,Font=3,Name="WindowResizer",Parent={1},Position=UDim2.new(1,-300,0,0),Size=UDim2.new(1,0,0,4),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={4},Size=UDim2.new(1,0,0,1),}},
			})
			leftSide.Frame = leftFrame
			leftFrame.Position = UDim2.new(0,-leftSide.Width-10,0,0)
			leftSide.WindowResizer = leftFrame.WindowResizer
			leftFrame.WindowResizer.Parent = nil
			leftFrame.Parent = sidesGui

			local rightFrame = create({
				{1,"Frame",{Active=true,Name="RightSide",BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),BorderSizePixel=0,}},
				{2,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2549019753933,0.2549019753933,0.2549019753933),BorderSizePixel=0,Font=3,Name="Resizer",Parent={1},Size=UDim2.new(0,5,1,0),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={2},Position=UDim2.new(0,4,0,0),Size=UDim2.new(0,1,1,0),}},
				{4,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.2549019753933,0.2549019753933,0.2549019753933),BorderSizePixel=0,Font=3,Name="WindowResizer",Parent={1},Position=UDim2.new(1,-300,0,0),Size=UDim2.new(1,0,0,4),Text="",TextColor3=Color3.new(0,0,0),TextSize=14,}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={4},Size=UDim2.new(1,0,0,1),}},
			})
			rightSide.Frame = rightFrame
			rightFrame.Position = UDim2.new(1,10,0,0)
			rightSide.WindowResizer = rightFrame.WindowResizer
			rightFrame.WindowResizer.Parent = nil
			rightFrame.Parent = sidesGui

			sideResizerHook(leftFrame.Resizer,"H",leftSide)
			sideResizerHook(rightFrame.Resizer,"H",rightSide)

			alignIndicator = Instance.new("ScreenGui")
			alignIndicator.DisplayOrder = Main.DisplayOrders.Core
			local indicator = Instance.new("Frame",alignIndicator)
			indicator.BackgroundColor3 = Color3.fromRGB(0,170,255)
			indicator.BorderSizePixel = 0 indicator.BackgroundTransparency = 0.8
			indicator.Name = "Indicator"
			local corner = Instance.new("UICorner",indicator)
			corner.CornerRadius = UDim.new(0,10)

			local leftToggle = create({{1,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderMode=2,Font=10,Name="LeftToggle",Position=UDim2.new(0,0,0,-36),Size=UDim2.new(0,16,0,36),Text="<",TextColor3=Color3.new(1,1,1),TextSize=14,}}})
			local rightToggle = leftToggle:Clone()
			rightToggle.Name = "RightToggle"
			rightToggle.Position = UDim2.new(1,-16,0,-36)
			Lib.ButtonAnim(leftToggle,{Mode=2,PressColor=Color3.fromRGB(32,32,32)})
			Lib.ButtonAnim(rightToggle,{Mode=2,PressColor=Color3.fromRGB(32,32,32)})

			leftToggle.MouseButton1Click:Connect(function() static.ToggleSide("left") end)
			rightToggle.MouseButton1Click:Connect(function() static.ToggleSide("right") end)
			leftToggle.Parent = sidesGui rightToggle.Parent = sidesGui

			sidesGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				local maxWidth = math.max(300,sidesGui.AbsoluteSize.X-static.FreeWidth)
				leftSide.Width = math.max(static.MinWidth,math.min(leftSide.Width,maxWidth-rightSide.Width))
				rightSide.Width = math.max(static.MinWidth,math.min(rightSide.Width,maxWidth-leftSide.Width))
				for i = 1,#visibleWindows do visibleWindows[i]:MoveInBoundary() end
				updateWindows(true)
			end)

			sidesGui.DisplayOrder = sideDisplayOrder - 1
			Lib.ShowGui(sidesGui)
			updateSideFrames()
		end

		local mt = {__index = funcs}
		static.new = function()
			local obj = setmetatable({
				Minimized=false,Dragging=false,Resizing=false,Aligned=false,
				Draggable=true,Resizable=true,ResizableInternal=true,Alignable=true,
				Closed=true,SizeX=300,SizeY=300,MinX=200,MinY=200,PosX=0,PosY=0,
				GuiElems={},Tweens={},Elements={},
				OnActivate=Lib.Signal.new(),OnDeactivate=Lib.Signal.new(),
				OnMinimize=Lib.Signal.new(),OnRestore=Lib.Signal.new()
			},mt)
			obj.Gui = createGui(obj)
			return obj
		end

		return static
	end)()

	Lib.ContextMenu = (function()
		local funcs = {}
		local mouse

		local function createGui(self)
			local contextGui = create({
				{1,"ScreenGui",{DisplayOrder=1000000,Name="Context",ZIndexBehavior=1,}},
				{2,"Frame",{Active=true,BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),Name="Main",Parent={1},Position=UDim2.new(0.5,-100,0.5,-150),Size=UDim2.new(0,200,0,100),}},
				{3,"UICorner",{CornerRadius=UDim.new(0,4),Parent={2},}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.17647059261799,0.17647059261799,0.17647059261799),Name="Container",Parent={2},Position=UDim2.new(0,1,0,1),Size=UDim2.new(1,-2,1,-2),}},
				{5,"UICorner",{CornerRadius=UDim.new(0,4),Parent={4},}},
				{6,"ScrollingFrame",{Active=true,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(0,0,0,0),Name="List",Parent={4},Position=UDim2.new(0,2,0,2),ScrollBarImageColor3=Color3.new(0,0,0),ScrollBarThickness=4,Size=UDim2.new(1,-4,1,-4),VerticalScrollBarInset=1,}},
				{7,"UIListLayout",{Parent={6},SortOrder=2,}},
				{8,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="SearchFrame",Parent={4},Size=UDim2.new(1,0,0,24),Visible=false,}},
				{9,"Frame",{BackgroundColor3=Color3.new(0.14901961386204,0.14901961386204,0.14901961386204),BorderColor3=Color3.new(0.1176470592618,0.1176470592618,0.1176470592618),BorderSizePixel=0,Name="SearchContainer",Parent={8},Position=UDim2.new(0,3,0,3),Size=UDim2.new(1,-6,0,18),}},
				{10,"TextBox",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="SearchBox",Parent={9},PlaceholderColor3=Color3.new(0.39215689897537,0.39215689897537,0.39215689897537),PlaceholderText="Search",Position=UDim2.new(0,4,0,0),Size=UDim2.new(1,-8,0,18),Text="",TextColor3=Color3.new(1,1,1),TextSize=14,TextXAlignment=0,}},
				{11,"UICorner",{CornerRadius=UDim.new(0,2),Parent={9},}},
				{12,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="Line",Parent={8},Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,1),}},
				{13,"TextButton",{AutoButtonColor=false,BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BackgroundTransparency=1,BorderColor3=Color3.new(0.33725491166115,0.49019610881805,0.73725491762161),BorderSizePixel=0,Font=3,Name="Entry",Parent={1},Size=UDim2.new(1,0,0,22),Text="",TextSize=14,Visible=false,}},
				{14,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="EntryName",Parent={13},Position=UDim2.new(0,24,0,0),Size=UDim2.new(1,-24,1,0),Text="Duplicate",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=0,}},
				{15,"TextLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Font=3,Name="Shortcut",Parent={13},Position=UDim2.new(0,24,0,0),Size=UDim2.new(1,-30,1,0),Text="Ctrl+D",TextColor3=Color3.new(0.86274516582489,0.86274516582489,0.86274516582489),TextSize=14,TextXAlignment=1,}},
				{16,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ImageRectOffset=Vector2.new(304,0),ImageRectSize=Vector2.new(16,16),Name="Icon",Parent={13},Position=UDim2.new(0,2,0,3),ScaleType=4,Size=UDim2.new(0,16,0,16),}},
				{17,"UICorner",{CornerRadius=UDim.new(0,4),Parent={13},}},
				{18,"Frame",{BackgroundColor3=Color3.new(0.21568629145622,0.21568629145622,0.21568629145622),BackgroundTransparency=1,BorderSizePixel=0,Name="Divider",Parent={1},Position=UDim2.new(0,0,0,20),Size=UDim2.new(1,0,0,7),Visible=false,}},
				{19,"Frame",{BackgroundColor3=Color3.new(0.20392157137394,0.20392157137394,0.20392157137394),BorderSizePixel=0,Name="Line",Parent={18},Position=UDim2.new(0,0,0.5,0),Size=UDim2.new(1,0,0,1),}},
				{20,"TextLabel",{AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Font=3,Name="DividerName",Parent={18},Position=UDim2.new(0,2,0.5,0),Size=UDim2.new(1,-4,1,0),Text="Objects",TextColor3=Color3.new(1,1,1),TextSize=14,TextTransparency=0.60000002384186,TextXAlignment=0,Visible=false,}},
			})
			self.GuiElems.Main = contextGui.Main
			self.GuiElems.List = contextGui.Main.Container.List
			self.GuiElems.Entry = contextGui.Entry
			self.GuiElems.Divider = contextGui.Divider
			self.GuiElems.SearchFrame = contextGui.Main.Container.SearchFrame
			self.GuiElems.SearchBar = self.GuiElems.SearchFrame.SearchContainer.SearchBox
			Lib.ViewportTextBox.convert(self.GuiElems.SearchBar)

			self.GuiElems.SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
				local lower,find = string.lower,string.find
				local searchText = lower(self.GuiElems.SearchBar.Text)
				local items = self.Items
				local map = self.ItemToEntryMap

				if searchText ~= "" then
					local results = {}
					local count = 1
					for i = 1,#items do
						local item = items[i]
						local entry = map[item]
						if entry then
							if not item.Divider and find(lower(item.Name),searchText,1,true) then
								results[count] = item count = count + 1
							else entry.Visible = false end
						end
					end
					table.sort(results,function(a,b) return a.Name < b.Name end)
					for i = 1,#results do
						local entry = map[results[i]]
						entry.LayoutOrder = i entry.Visible = true
					end
				else
					for i = 1,#items do
						local entry = map[items[i]]
						if entry then entry.LayoutOrder = i entry.Visible = true end
					end
				end

				local toSize = self.GuiElems.List.UIListLayout.AbsoluteContentSize.Y + 6
				self.GuiElems.List.CanvasSize = UDim2.new(0,0,0,toSize-6)
			end)

			return contextGui
		end

		funcs.Add = function(self,item)
			local newItem = {
				Name=item.Name or "Item",Icon=item.Icon or "",Shortcut=item.Shortcut or "",
				OnClick=item.OnClick,OnHover=item.OnHover,Disabled=item.Disabled or false,
				DisabledIcon=item.DisabledIcon or "",IconMap=item.IconMap,OnRightClick=item.OnRightClick
			}
			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Items[#self.Items+1] = newItem self.Updated = nil
		end

		funcs.AddRegistered = function(self,name,disabled)
			if not self.Registered[name] then error(name.." is not registered") end
			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Registered[name].Disabled = disabled
			self.Items[#self.Items+1] = self.Registered[name] self.Updated = nil
		end

		funcs.Register = function(self,name,item)
			self.Registered[name] = {
				Name=item.Name or "Item",Icon=item.Icon or "",Shortcut=item.Shortcut or "",
				OnClick=item.OnClick,OnHover=item.OnHover,DisabledIcon=item.DisabledIcon or "",
				IconMap=item.IconMap,OnRightClick=item.OnRightClick
			}
		end

		funcs.UnRegister = function(self,name) self.Registered[name] = nil end

		funcs.AddDivider = function(self,text)
			self.QueuedDivider = false
			local textWidth = text and service.TextService:GetTextSize(text,14,Enum.Font.SourceSans,Vector2.new(999999999,20)).X or nil
			table.insert(self.Items,{Divider=true,Text=text,TextSize=textWidth and textWidth+4})
			self.Updated = nil
		end

		funcs.QueueDivider = function(self,text) self.QueuedDivider = true self.QueuedDividerText = text or "" end
		funcs.Clear = function(self) self.Items = {} self.Updated = nil end

		funcs.Refresh = function(self)
			for i,v in pairs(self.GuiElems.List:GetChildren()) do
				if not v:IsA("UIListLayout") then v:Destroy() end
			end
			local map = {} self.ItemToEntryMap = map
			local dividerFrame = self.GuiElems.Divider
			local contextList = self.GuiElems.List
			local entryFrame = self.GuiElems.Entry
			local items = self.Items

			for i = 1,#items do
				local item = items[i]
				if item.Divider then
					local newDivider = dividerFrame:Clone()
					newDivider.Line.BackgroundColor3 = self.Theme.DividerColor
					if item.Text then
						newDivider.Size = UDim2.new(1,0,0,20)
						newDivider.Line.Position = UDim2.new(0,item.TextSize,0.5,0)
						newDivider.Line.Size = UDim2.new(1,-item.TextSize,0,1)
						newDivider.DividerName.TextColor3 = self.Theme.TextColor
						newDivider.DividerName.Text = item.Text
						newDivider.DividerName.Visible = true
					end
					newDivider.Visible = true map[item] = newDivider newDivider.Parent = contextList
				else
					local newEntry = entryFrame:Clone()
					newEntry.BackgroundColor3 = self.Theme.HighlightColor
					newEntry.EntryName.TextColor3 = self.Theme.TextColor
					newEntry.EntryName.Text = item.Name
					newEntry.Shortcut.Text = item.Shortcut
					if item.Disabled then
						newEntry.EntryName.TextColor3 = Color3.new(150/255,150/255,150/255)
						newEntry.Shortcut.TextColor3 = Color3.new(150/255,150/255,150/255)
					end

					if self.Iconless then
						newEntry.EntryName.Position = UDim2.new(0,2,0,0)
						newEntry.EntryName.Size = UDim2.new(1,-4,0,20)
						newEntry.Icon.Visible = false
					else
						local iconIndex = item.Disabled and item.DisabledIcon or item.Icon
						if item.IconMap then
							if type(iconIndex) == "number" then item.IconMap:Display(newEntry.Icon,iconIndex)
							elseif type(iconIndex) == "string" then item.IconMap:DisplayByKey(newEntry.Icon,iconIndex) end
						elseif type(iconIndex) == "string" then newEntry.Icon.Image = iconIndex end
					end

					if not item.Disabled then
						if item.OnClick then
							newEntry.MouseButton1Click:Connect(function()
								item.OnClick(item.Name)
								if not item.NoHide then self:Hide() end
							end)
						end
						if item.OnRightClick then
							newEntry.MouseButton2Click:Connect(function()
								item.OnRightClick(item.Name)
								if not item.NoHide then self:Hide() end
							end)
						end
					end

					newEntry.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement then newEntry.BackgroundTransparency = 0 end
					end)
					newEntry.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement then newEntry.BackgroundTransparency = 1 end
					end)

					newEntry.Visible = true map[item] = newEntry newEntry.Parent = contextList
				end
			end
			self.Updated = true
		end

		funcs.Show = function(self,x,y)
			local elems = self.GuiElems
			elems.SearchFrame.Visible = self.SearchEnabled
			elems.List.Position = UDim2.new(0,2,0,2+(self.SearchEnabled and 24 or 0))
			elems.List.Size = UDim2.new(1,-4,1,-4-(self.SearchEnabled and 24 or 0))
			if self.SearchEnabled and self.ClearSearchOnShow then elems.SearchBar.Text = "" end
			self.GuiElems.List.CanvasPosition = Vector2.new(0,0)

			if not self.Updated then self:Refresh() end

			local reverseY = false
			local x,y = x or mouse.X, y or mouse.Y
			local maxX,maxY = mouse.ViewSizeX,mouse.ViewSizeY

			if x + self.Width > maxX then x = self.ReverseX and x - self.Width or maxX - self.Width end
			elems.Main.Position = UDim2.new(0,x,0,y)
			elems.Main.Size = UDim2.new(0,self.Width,0,0)
			self.Gui.DisplayOrder = Main.DisplayOrders.Menu
			Lib.ShowGui(self.Gui)

			local toSize = elems.List.UIListLayout.AbsoluteContentSize.Y + 6
			if self.MaxHeight and toSize > self.MaxHeight then
				elems.List.CanvasSize = UDim2.new(0,0,0,toSize-6) toSize = self.MaxHeight
			else elems.List.CanvasSize = UDim2.new(0,0,0,0) end
			if y + toSize > maxY then reverseY = true end

			local closable
			if self.CloseEvent then self.CloseEvent:Disconnect() end
			self.CloseEvent = service.UserInputService.InputBegan:Connect(function(input)
				if not closable or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				if not Lib.CheckMouseInGui(elems.Main) then self.CloseEvent:Disconnect() self:Hide() end
			end)

			if reverseY then
				elems.Main.Position = UDim2.new(0,x,0,y-(self.ReverseYOffset or 0))
				local newY = y - toSize - (self.ReverseYOffset or 0)
				y = newY >= 0 and newY or 0
				elems.Main:TweenSizeAndPosition(UDim2.new(0,self.Width,0,toSize),UDim2.new(0,x,0,y),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.2,true)
			else
				elems.Main:TweenSize(UDim2.new(0,self.Width,0,toSize),Enum.EasingDirection.Out,Enum.EasingStyle.Quart,0.2,true)
			end

			Lib.FastWait()
			if self.SearchEnabled and self.FocusSearchOnShow then elems.SearchBar:CaptureFocus() end
			closable = true
		end

		funcs.Hide = function(self) self.Gui.Parent = nil end

		funcs.ApplyTheme = function(self,data)
			local theme = self.Theme
			theme.ContentColor = data.ContentColor or Settings.Theme.Menu
			theme.OutlineColor = data.OutlineColor or Settings.Theme.Menu
			theme.DividerColor = data.DividerColor or Settings.Theme.Outline2
			theme.TextColor = data.TextColor or Settings.Theme.Text
			theme.HighlightColor = data.HighlightColor or Settings.Theme.Main1
			self.GuiElems.Main.BackgroundColor3 = theme.OutlineColor
			self.GuiElems.Main.Container.BackgroundColor3 = theme.ContentColor
		end

		local mt = {__index = funcs}
		local function new()
			if not mouse then mouse = Main.Mouse or service.Players.LocalPlayer:GetMouse() end
			local obj = setmetatable({
				Width=200,MaxHeight=nil,Iconless=false,SearchEnabled=false,
				ClearSearchOnShow=true,FocusSearchOnShow=true,Updated=false,
				QueuedDivider=false,QueuedDividerText="",Items={},Registered={},
				GuiElems={},Theme={}
			},mt)
			obj.Gui = createGui(obj)
			obj:ApplyTheme({})
			return obj
		end

		return {new = new}
	end)()

	Lib.ViewportTextBox = (function()
		local textService = game:GetService("TextService")
		local props = {OffsetX=0,TextBox=PH,CursorPos=-1,Gui=PH,View=PH}
		local funcs = {}

		funcs.Update = function(self)
			local cursorPos = self.CursorPos or -1
			local text = self.TextBox.Text
			if text == "" then self.TextBox.Position = UDim2.new(0,0,0,0) return end
			if cursorPos == -1 then return end

			local cursorText = text:sub(1,cursorPos-1)
			local leftEnd = -self.TextBox.Position.X.Offset
			local rightEnd = leftEnd + self.View.AbsoluteSize.X
			local totalTextSize = textService:GetTextSize(text,self.TextBox.TextSize,self.TextBox.Font,Vector2.new(999999999,100)).X
			local cursorTextSize = textService:GetTextSize(cursorText,self.TextBox.TextSize,self.TextBox.Font,Vector2.new(999999999,100)).X
			local pos = nil

			if cursorTextSize > rightEnd then
				pos = math.max(-1,cursorTextSize - self.View.AbsoluteSize.X + 2)
			elseif cursorTextSize < leftEnd then
				pos = math.max(-1,cursorTextSize-2)
			elseif totalTextSize < rightEnd then
				pos = math.max(-1,totalTextSize - self.View.AbsoluteSize.X + 2)
			end

			if pos then
				self.TextBox.Position = UDim2.new(0,-pos,0,0)
				self.TextBox.Size = UDim2.new(1,pos,1,0)
			end
		end

		funcs.GetText = function(self) return self.TextBox.Text end
		funcs.SetText = function(self,text) self.TextBox.Text = text end

		local mt = getGuiMT(props,funcs)

		local function convert(textbox)
			local obj = initObj(props,mt)
			local view = Instance.new("Frame")
			view.BackgroundTransparency = textbox.BackgroundTransparency
			view.BackgroundColor3 = textbox.BackgroundColor3
			view.BorderSizePixel = textbox.BorderSizePixel
			view.BorderColor3 = textbox.BorderColor3
			view.Position = textbox.Position
			view.Size = textbox.Size
			view.ClipsDescendants = true
			view.Name = textbox.Name
			textbox.BackgroundTransparency = 1
			textbox.Position = UDim2.new(0,0,0,0)
			textbox.Size = UDim2.new(1,0,1,0)
			textbox.TextXAlignment = Enum.TextXAlignment.Left
			textbox.Name = "Input"

			obj.TextBox = textbox obj.View = view obj.Gui = view

			textbox.Changed:Connect(function(prop)
				if prop == "Text" or prop == "CursorPosition" or prop == "AbsoluteSize" then
					local cursorPos = obj.TextBox.CursorPosition
					if cursorPos ~= -1 then obj.CursorPos = cursorPos end
					obj:Update()
				end
			end)

			obj:Update()
			view.Parent = textbox.Parent
			textbox.Parent = view
			return obj
		end

		local function new()
			local textBox = Instance.new("TextBox")
			textBox.Size = UDim2.new(0,100,0,20)
			textBox.BackgroundColor3 = Settings.Theme.TextBox
			textBox.BorderColor3 = Settings.Theme.Outline3
			textBox.ClearTextOnFocus = false
			textBox.TextColor3 = Settings.Theme.Text
			textBox.Font = Enum.Font.SourceSans
			textBox.TextSize = 14 textBox.Text = ""
			return convert(textBox)
		end

		return {new = new, convert = convert}
	end)()

	Lib.Label = (function()
		local props,funcs = {},{}
		local mt = getGuiMT(props,funcs)
		local function new()
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Settings.Theme.Text
			label.TextTransparency = 0.1
			label.Size = UDim2.new(0,100,0,20)
			label.Font = Enum.Font.SourceSans
			label.TextSize = 14
			local obj = setmetatable({Gui=label},mt)
			return obj
		end
		return {new = new}
	end)()

	Lib.Frame = (function()
		local props,funcs = {},{}
		local mt = getGuiMT(props,funcs)
		local function new()
			local fr = Instance.new("Frame")
			fr.BackgroundColor3 = Settings.Theme.Main1
			fr.BorderColor3 = Settings.Theme.Outline1
			fr.Size = UDim2.new(0,50,0,50)
			local obj = setmetatable({Gui=fr},mt)
			return obj
		end
		return {new = new}
	end)()

	Lib.Button = (function()
		local props = {
			Gui=PH,Anim=PH,Disabled=false,
			OnClick=SIGNAL,OnDown=SIGNAL,OnUp=SIGNAL,AllowedButtons={1}
		}
		local funcs = {}
		local tableFind = table.find

		funcs.Trigger = function(self,event,button)
			if not self.Disabled and tableFind(self.AllowedButtons,button) then
				self["On"..event]:Fire(button)
			end
		end

		funcs.SetDisabled = function(self,dis)
			self.Disabled = dis
			if dis then self.Anim:Disable() self.Gui.TextTransparency = 0.5
			else self.Anim.Enable() self.Gui.TextTransparency = 0 end
		end

		local mt = getGuiMT(props,funcs)

		local function new()
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.TextColor3 = Settings.Theme.Text b.TextTransparency = 0.1
			b.Size = UDim2.new(0,100,0,20)
			b.Font = Enum.Font.SourceSans b.TextSize = 14
			b.BackgroundColor3 = Settings.Theme.Button
			b.BorderColor3 = Settings.Theme.Outline2

			local obj = initObj(props,mt)
			obj.Gui = b
			obj.Anim = Lib.ButtonAnim(b,{Mode=2,StartColor=Settings.Theme.Button,HoverColor=Settings.Theme.ButtonHover,PressColor=Settings.Theme.ButtonPress,OutlineColor=Settings.Theme.Outline2})

			b.MouseButton1Click:Connect(function() obj:Trigger("Click",1) end)
			b.MouseButton1Down:Connect(function() obj:Trigger("Down",1) end)
			b.MouseButton1Up:Connect(function() obj:Trigger("Up",1) end)
			b.MouseButton2Click:Connect(function() obj:Trigger("Click",2) end)
			b.MouseButton2Down:Connect(function() obj:Trigger("Down",2) end)
			b.MouseButton2Up:Connect(function() obj:Trigger("Up",2) end)

			return obj
		end

		return {new = new}
	end)()

	Lib.DropDown = (function()
		local props = {
			Gui=PH,Anim=PH,Context=PH,Selected=PH,Disabled=false,
			CanBeEmpty=true,Options={},GuiElems={},OnSelect=SIGNAL
		}
		local funcs = {}

		funcs.Update = function(self)
			local options = self.Options
			if #options > 0 then
				if not self.Selected then
					if not self.CanBeEmpty then self.Selected = options[1] self.GuiElems.Label.Text = options[1]
					else self.GuiElems.Label.Text = "- Select -" end
				else self.GuiElems.Label.Text = self.Selected end
			else self.GuiElems.Label.Text = "- Select -" end
		end

		funcs.ShowOptions = function(self)
			local context = self.Context
			context.Width = self.Gui.AbsoluteSize.X
			context.ReverseYOffset = self.Gui.AbsoluteSize.Y
			context:Show(self.Gui.AbsolutePosition.X,self.Gui.AbsolutePosition.Y+context.ReverseYOffset)
		end

		funcs.SetOptions = function(self,opts)
			self.Options = opts
			local context = self.Context
			local options = self.Options
			context:Clear()
			local onClick = function(option) self.Selected = option self.OnSelect:Fire(option) self:Update() end
			if self.CanBeEmpty then
				context:Add({Name="- Select -",OnClick=function() self.Selected=nil self.OnSelect:Fire(nil) self:Update() end})
			end
			for i = 1,#options do context:Add({Name=options[i],OnClick=onClick}) end
			self:Update()
		end

		funcs.SetSelected = function(self,opt)
			self.Selected = type(opt) == "number" and self.Options[opt] or opt
			self:Update()
		end

		local mt = getGuiMT(props,funcs)

		local function new()
			local f = Instance.new("TextButton")
			f.AutoButtonColor = false f.Text = ""
			f.Size = UDim2.new(0,100,0,20)
			f.BackgroundColor3 = Settings.Theme.TextBox
			f.BorderColor3 = Settings.Theme.Outline3

			local label = Lib.Label.new()
			label.Position = UDim2.new(0,2,0,0)
			label.Size = UDim2.new(1,-22,1,0)
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Parent = f
			local arrow = create({
				{1,"Frame",{BackgroundTransparency=1,Name="EnumArrow",Position=UDim2.new(1,-16,0,2),Size=UDim2.new(0,16,0,16),}},
				{2,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,8,0,9),Size=UDim2.new(0,1,0,1),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,7,0,8),Size=UDim2.new(0,3,0,1),}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.86274510622025,0.86274510622025,0.86274510622025),BorderSizePixel=0,Parent={1},Position=UDim2.new(0,6,0,7),Size=UDim2.new(0,5,0,1),}},
			})
			arrow.Parent = f

			local obj = initObj(props,mt)
			obj.Gui = f
			obj.Anim = Lib.ButtonAnim(f,{Mode=2,StartColor=Settings.Theme.TextBox,LerpTo=Settings.Theme.Button,LerpDelta=0.15})
			obj.Context = Lib.ContextMenu.new()
			obj.Context.Iconless = true obj.Context.MaxHeight = 200
			obj.Selected = nil obj.GuiElems = {Label=label}
			f.MouseButton1Down:Connect(function() obj:ShowOptions() end)
			obj:Update()
			return obj
		end

		return {new = new}
	end)()

	Lib.ClickSystem = (function()
		local props = {
			LastItem=PH,OnDown=SIGNAL,OnRelease=SIGNAL,AllowedButtons={1},
			Combo=0,MaxCombo=2,ComboTime=0.5,Items={},ItemCons={},
			ClickId=-1,LastButton=""
		}
		local funcs = {}

		funcs.Trigger = function(self,item,button)
			if table.find(self.AllowedButtons,button) then
				if self.LastButton ~= button or self.LastItem ~= item or self.Combo == self.MaxCombo or tick() - self.ClickId > self.ComboTime then
					self.Combo = 0 self.LastButton = button self.LastItem = item
				end
				self.Combo = self.Combo + 1
				self.ClickId = tick()

				local release
				release = service.UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType["MouseButton"..button] then
						release:Disconnect()
						if Lib.CheckMouseInGui(item) and self.LastButton == button and self.LastItem == item then
							self["OnRelease"]:Fire(item,self.Combo,button)
						end
					end
				end)

				self["OnDown"]:Fire(item,self.Combo,button)
			end
		end

		funcs.Add = function(self,item)
			if table.find(self.Items,item) then return end
			local cons = {}
			cons[1] = item.MouseButton1Down:Connect(function() self:Trigger(item,1) end)
			cons[2] = item.MouseButton2Down:Connect(function() self:Trigger(item,2) end)
			self.ItemCons[item] = cons self.Items[#self.Items+1] = item
		end

		funcs.Remove = function(self,item)
			local ind = table.find(self.Items,item)
			if not ind then return end
			for i,v in pairs(self.ItemCons[item]) do v:Disconnect() end
			self.ItemCons[item] = nil table.remove(self.Items,ind)
		end

		local mt = {__index = funcs}
		local function new()
			local obj = initObj(props,mt)
			return obj
		end

		return {new = new}
	end)()

	Lib.Checkbox = (function()
		local funcs = {}
		local c3 = Color3.fromRGB
		local v2 = Vector2.new
		local ud2s = UDim2.fromScale
		local ud2o = UDim2.fromOffset
		local ud = UDim.new
		local max = math.max
		local new = Instance.new
		local TweenSize = new("Frame").TweenSize
		local ti = TweenInfo.new
		local delay = delay

		local function ripple(object,color)
			local circle = new("Frame")
			circle.BackgroundColor3 = color circle.BackgroundTransparency = 0.75
			circle.BorderSizePixel = 0 circle.AnchorPoint = v2(0.5,0.5)
			circle.Size = ud2o() circle.Position = ud2s(0.5,0.5)
			circle.Parent = object
			local rounding = new("UICorner")
			rounding.CornerRadius = ud(1) rounding.Parent = circle
			local abssz = object.AbsoluteSize
			local size = max(abssz.X,abssz.Y) * 5/3
			TweenSize(circle,ud2o(size,size),"Out","Quart",0.4)
			service.TweenService:Create(circle,ti(0.4,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{BackgroundTransparency=1}):Play()
			service.Debris:AddItem(circle,0.4)
		end

		local function initGui(self,frame)
			local checkbox = frame or create({
				{1,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="Checkbox",Position=UDim2.new(0,3,0,3),Size=UDim2.new(0,16,0,16),}},
				{2,"Frame",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Name="ripples",Parent={1},Size=UDim2.new(1,0,1,0),}},
				{3,"Frame",{BackgroundColor3=Color3.new(0.10196078568697,0.10196078568697,0.10196078568697),BorderSizePixel=0,Name="outline",Parent={1},Size=UDim2.new(0,16,0,16),}},
				{4,"Frame",{BackgroundColor3=Color3.new(0.14117647707462,0.14117647707462,0.14117647707462),BorderSizePixel=0,Name="filler",Parent={3},Position=UDim2.new(0,1,0,1),Size=UDim2.new(0,14,0,14),}},
				{5,"Frame",{BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="top",Parent={4},Size=UDim2.new(0,16,0,0),}},
				{6,"Frame",{AnchorPoint=Vector2.new(0,1),BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="bottom",Parent={4},Position=UDim2.new(0,0,0,14),Size=UDim2.new(0,16,0,0),}},
				{7,"Frame",{BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="left",Parent={4},Size=UDim2.new(0,0,0,16),}},
				{8,"Frame",{AnchorPoint=Vector2.new(1,0),BackgroundColor3=Color3.new(0.90196084976196,0.90196084976196,0.90196084976196),BorderSizePixel=0,Name="right",Parent={4},Position=UDim2.new(0,14,0,0),Size=UDim2.new(0,0,0,16),}},
				{9,"Frame",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,ClipsDescendants=true,Name="checkmark",Parent={4},Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,0,0,20),}},
				{10,"ImageLabel",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,Image="rbxassetid://6234266378",Parent={9},Position=UDim2.new(0.5,0,0.5,0),ScaleType=3,Size=UDim2.new(0,15,0,11),}},
				{11,"ImageLabel",{AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://6401617475",ImageColor3=Color3.new(0.20784313976765,0.69803923368454,0.98431372642517),Name="checkmark2",Parent={4},Position=UDim2.new(0.5,0,0.5,0),Size=UDim2.new(0,12,0,12),Visible=false,}},
				{12,"ImageLabel",{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,Image="rbxassetid://6425281788",ImageTransparency=0.20000000298023,Name="middle",Parent={4},ScaleType=2,Size=UDim2.new(1,0,1,0),TileSize=UDim2.new(0,2,0,2),Visible=false,}},
				{13,"UICorner",{CornerRadius=UDim.new(0,2),Parent={3},}},
			})
			local outline = checkbox.outline
			local filler = outline.filler
			local checkmark = filler.checkmark
			local ripples_container = checkbox.ripples
			local top,bottom,left,right = filler.top,filler.bottom,filler.left,filler.right

			self.Gui = checkbox
			self.GuiElems = {
				Top=top,Bottom=bottom,Left=left,Right=right,
				Outline=outline,Filler=filler,Checkmark=checkmark,
				Checkmark2=filler.checkmark2,Middle=filler.middle
			}

			checkbox.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 then
					local release
					release = service.UserInputService.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							release:Disconnect()
							if Lib.CheckMouseInGui(checkbox) then
								if self.Style == 0 then ripple(ripples_container,self.Disabled and self.Colors.Disabled or self.Colors.Primary) end
								if not self.Disabled then self:SetState(not self.Toggled,true)
								else self:Paint() end
								self.OnInput:Fire()
							end
						end
					end)
				end
			end)

			self:Paint()
		end

		funcs.Collapse = function(self,anim)
			local g = self.GuiElems
			if anim then
				TweenSize(g.Top,ud2o(14,14),"In","Quart",4/15,true)
				TweenSize(g.Bottom,ud2o(14,14),"In","Quart",4/15,true)
				TweenSize(g.Left,ud2o(14,14),"In","Quart",4/15,true)
				TweenSize(g.Right,ud2o(14,14),"In","Quart",4/15,true)
			else
				g.Top.Size=ud2o(14,14) g.Bottom.Size=ud2o(14,14)
				g.Left.Size=ud2o(14,14) g.Right.Size=ud2o(14,14)
			end
		end

		funcs.Expand = function(self,anim)
			local g = self.GuiElems
			if anim then
				TweenSize(g.Top,ud2o(14,0),"InOut","Quart",4/15,true)
				TweenSize(g.Bottom,ud2o(14,0),"InOut","Quart",4/15,true)
				TweenSize(g.Left,ud2o(0,14),"InOut","Quart",4/15,true)
				TweenSize(g.Right,ud2o(0,14),"InOut","Quart",4/15,true)
			else
				g.Top.Size=ud2o(14,0) g.Bottom.Size=ud2o(14,0)
				g.Left.Size=ud2o(0,14) g.Right.Size=ud2o(0,14)
			end
		end

		funcs.Paint = function(self)
			local g = self.GuiElems
			if self.Style == 0 then
				local color_base = self.Disabled and self.Colors.Disabled
				g.Outline.BackgroundColor3 = color_base or (self.Toggled and self.Colors.Primary) or self.Colors.Secondary
				local walls_color = color_base or self.Colors.Primary
				g.Top.BackgroundColor3=walls_color g.Bottom.BackgroundColor3=walls_color
				g.Left.BackgroundColor3=walls_color g.Right.BackgroundColor3=walls_color
			else
				g.Outline.BackgroundColor3 = self.Disabled and self.Colors.Disabled or self.Colors.Secondary
				g.Filler.BackgroundColor3 = self.Disabled and self.Colors.DisabledBackground or self.Colors.Background
				g.Checkmark2.ImageColor3 = self.Disabled and self.Colors.DisabledCheck or self.Colors.Primary
			end
		end

		funcs.SetState = function(self,val,anim)
			self.Toggled = val
			if self.OutlineColorTween then self.OutlineColorTween:Cancel() end
			local setStateTime = tick() self.LastSetStateTime = setStateTime

			if self.Toggled then
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(self.GuiElems.Outline,ti(4/15,Enum.EasingStyle.Circular,Enum.EasingDirection.Out),{BackgroundColor3=self.Colors.Primary})
						self.OutlineColorTween:Play()
						delay(0.15,function()
							if setStateTime ~= self.LastSetStateTime then return end
							self:Paint() TweenSize(self.GuiElems.Checkmark,ud2o(14,20),"Out","Bounce",2/15,true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Primary
						self:Paint() self.GuiElems.Checkmark.Size = ud2o(14,20)
					end
					self:Collapse(anim)
				else
					self:Paint() self.GuiElems.Checkmark2.Visible=true self.GuiElems.Middle.Visible=false
				end
			else
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(self.GuiElems.Outline,ti(4/15,Enum.EasingStyle.Circular,Enum.EasingDirection.In),{BackgroundColor3=self.Colors.Secondary})
						self.OutlineColorTween:Play()
						delay(0.15,function()
							if setStateTime ~= self.LastSetStateTime then return end
							self:Paint() TweenSize(self.GuiElems.Checkmark,ud2o(0,20),"Out","Quad",1/15,true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Secondary
						self:Paint() self.GuiElems.Checkmark.Size = ud2o(0,20)
					end
					self:Expand(anim)
				else
					self:Paint() self.GuiElems.Checkmark2.Visible=false
					self.GuiElems.Middle.Visible=(self.Toggled==nil)
				end
			end
		end

		local mt = {__index = funcs}

		local function new(style)
			local obj = setmetatable({
				Toggled=false,Disabled=false,OnInput=Lib.Signal.new(),Style=style or 0,
				Colors={
					Background=c3(36,36,36),Primary=c3(49,176,230),Secondary=c3(25,25,25),
					Disabled=c3(64,64,64),DisabledBackground=c3(52,52,52),DisabledCheck=c3(80,80,80)
				}
			},mt)
			initGui(obj)
			return obj
		end

		return {new = new}
	end)()

	return Lib
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
