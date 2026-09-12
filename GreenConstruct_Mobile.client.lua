local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local RNG = Random.new()

local TOUCH_PRIMARY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local CONFIG = {
	Visual = {
		FolderName = "GreenConstructFX",
		Core = Color3.fromRGB(165, 255, 195),
		Mid = Color3.fromRGB(45, 255, 105),
		Deep = Color3.fromRGB(14, 115, 48),
		Transparency = 0.08,
	},
	Quality = {
		Scale = TOUCH_PRIMARY and 0.62 or 1,
		MaxFragments = TOUCH_PRIMARY and 12 or 22,
		MaxScanParts = 48,
		HighlightTime = 0.7,
	},
	Energy = {
		Max = 100,
		Regen = 11,
		Smooth = 9,
	},
	Camera = {
		MaxIntensity = 0.42,
		Decay = 2.6,
	},
	Combo = {
		Sequence = { "Fist", "Cage", "Hammer" },
		Window = 7,
		Radius = 30,
		Reward = 35,
	},
	Fist = {
		Cost = 20,
		Cooldown = 3.2,
		Size = 1,
		Form = 0.5,
		Charge = 0.32,
		Thrust = 0.34,
		Rest = 0.16,
		Dissipate = 0.45,
		HoldDistance = 6,
		Reach = 42,
		HitRadius = 12,
		ArmAngle = 78,
	},
	Cage = {
		Cost = 28,
		Cooldown = 5.5,
		Radius = 12,
		Height = 15,
		Bars = 14,
		Build = 0.9,
		Life = 4.5,
		Dissipate = 0.9,
		MaxDistance = 85,
		ScanInterval = 0.15,
		AimTimeout = 6,
	},
	Hammer = {
		Cost = 40,
		Cooldown = 7,
		Size = 1,
		Form = 0.85,
		Lift = 0.45,
		Hold = 0.28,
		Slam = 0.4,
		Rest = 0.3,
		Dissipate = 0.7,
		Reach = 9,
		HitRadius = 20,
		ArmAngle = 120,
	},
}

local character = nil
local humanoid = nil
local rootPart = nil
local rightHand = nil
local rightShoulder = nil
local shoulderBaseC0 = nil

local scopes = {}
local energy = CONFIG.Energy.Max
local energyShown = CONFIG.Energy.Max
local energyWarnUntil = 0
local exclusiveBusy = false
local comboHistory = {}
local shakes = {}
local hud = {}
local placement = nil
local targetReport = { Count = 0, Until = 0 }
local characterConnections = {}
local fxFolder = nil

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = CONFIG.Quality.MaxScanParts

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function clock()
	return os.clock()
end

local function clamp01(value)
	return value < 0 and 0 or (value > 1 and 1 or value)
end

local function lerp(a, b, alpha)
	return a + (b - a) * alpha
end

local function easeOut(alpha)
	alpha = clamp01(alpha)
	return 1 - (1 - alpha) ^ 3
end

local function easeIn(alpha)
	return clamp01(alpha) ^ 3
end

local function easeInOut(alpha)
	alpha = clamp01(alpha)
	return alpha * alpha * (3 - 2 * alpha)
end

local function randomUnit()
	local vector = Vector3.new(RNG:NextNumber(-1, 1), RNG:NextNumber(-1, 1), RNG:NextNumber(-1, 1))
	return vector.Magnitude > 0.05 and vector.Unit or Vector3.yAxis
end

local function scaled(count)
	return math.max(1, math.floor(count * CONFIG.Quality.Scale + 0.5))
end

local function getCamera()
	return Workspace.CurrentCamera
end

local function getFXFolder()
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = CONFIG.Visual.FolderName
	fxFolder.Parent = Workspace
	return fxFolder
end

local Scope = {}
Scope.__index = Scope

function Scope.new(name)
	local self = setmetatable({
		Name = name,
		Alive = true,
		Objects = {},
		Connections = {},
		Finalizers = {},
		Update = nil,
	}, Scope)
	table.insert(scopes, self)
	return self
end

function Scope:Track(object)
	if not self.Alive then
		if typeof(object) == "Instance" then
			object:Destroy()
		end
		return object
	end
	table.insert(self.Objects, object)
	return object
end

function Scope:Bind(connection)
	if not self.Alive then
		connection:Disconnect()
		return connection
	end
	table.insert(self.Connections, connection)
	return connection
end

function Scope:OnFinish(callback)
	table.insert(self.Finalizers, callback)
end

function Scope:Destroy()
	if not self.Alive then
		return
	end
	self.Alive = false
	self.Update = nil
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for index = #self.Objects, 1, -1 do
		local object = self.Objects[index]
		if typeof(object) == "Instance" and object.Parent then
			object:Destroy()
		end
	end
	table.clear(self.Objects)
	for _, finalizer in ipairs(self.Finalizers) do
		local ok, err = pcall(finalizer)
		if not ok then
			warn("[GreenConstruct] finalizer error: " .. tostring(err))
		end
	end
	table.clear(self.Finalizers)
	local index = table.find(scopes, self)
	if index then
		table.remove(scopes, index)
	end
end

local function destroyAllScopes()
	for index = #scopes, 1, -1 do
		scopes[index]:Destroy()
	end
end

local function makeEnergyPart(scope, name, shape, size, cframe, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color or CONFIG.Visual.Mid
	part.Material = Enum.Material.Neon
	part.Transparency = transparency or CONFIG.Visual.Transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = getFXFolder()
	return scope:Track(part)
end

local function addGlow(scope, host, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = CONFIG.Visual.Mid
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = host
	return scope:Track(light)
end

local function addSparks(scope, host, rate, speed, size, lifetime)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EnergySparks"
	emitter.Color = ColorSequence.new(CONFIG.Visual.Core, CONFIG.Visual.Mid)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = rate * CONFIG.Quality.Scale
	emitter.Lifetime = lifetime or NumberRange.new(0.35, 0.8)
	emitter.Speed = speed
	emitter.Size = size
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Drag = 1.5
	emitter.Parent = host
	return scope:Track(emitter)
end

local function tweenTo(instance, duration, goal, style, direction)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local animation = TweenService:Create(instance, info, goal)
	animation:Play()
	return animation
end

local function facing(position, direction)
	local unit = direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(position, position + unit, math.abs(unit.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis)
end

local function addShake(intensity, duration)
	table.insert(shakes, {
		Start = clock(),
		Duration = duration,
		Intensity = math.min(CONFIG.Camera.MaxIntensity, intensity),
	})
end

local function refreshCollisionFilters()
	local filter = { getFXFolder() }
	if character then
		table.insert(filter, character)
	end
	overlapParams.FilterDescendantsInstances = filter
	rayParams.FilterDescendantsInstances = filter
end

local function isAlive()
	return character ~= nil
		and character.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and rootPart ~= nil
		and rootPart.Parent ~= nil
end

local function getHumanoid(model)
	return model and model:FindFirstChildOfClass("Humanoid") or nil
end

local function getCharacterRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart") or nil
end

local function getCharacterHand(model)
	if not model then
		return nil
	end
	return model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or getCharacterRoot(model)
end

local function getRightShoulder(model)
	if not model then
		return nil
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and (descendant.Name == "RightShoulder" or descendant.Name == "Right Shoulder") then
			return descendant
		end
	end
	return nil
end

local function handCFrame()
	if rightHand and rightHand.Parent then
		return rightHand.CFrame
	end
	if rootPart then
		return rootPart.CFrame * CFrame.new(1.6, 1.4, -0.6)
	end
	return CFrame.identity
end

local function poseArm(scope, angleProvider)
	if not rightShoulder or not shoulderBaseC0 then
		return
	end
	local joint = rightShoulder
	local base = shoulderBaseC0
	scope:OnFinish(function()
		if joint and joint.Parent then
			joint.C0 = base
		end
	end)
	return function(elapsed)
		if joint and joint.Parent then
			joint.C0 = CFrame.Angles(-math.rad(angleProvider(elapsed)), 0, 0) * base
		end
	end
end

local function groundBelow(position, distance)
	local result = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -(distance or 200), 0), rayParams)
	if result then
		return result.Position, result.Normal
	end
	return position, Vector3.yAxis
end

local function scanCharacters(position, radius, seen, output)
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(position, radius, overlapParams)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local targetHumanoid = getHumanoid(model)
		if model and targetHumanoid and targetHumanoid.Health > 0 and not seen[model] then
			seen[model] = true
			table.insert(output, model)
			local highlight = Instance.new("Highlight")
			highlight.Name = "LocalHitPreview"
			highlight.FillColor = CONFIG.Visual.Mid
			highlight.OutlineColor = CONFIG.Visual.Core
			highlight.FillTransparency = 0.55
			highlight.OutlineTransparency = 0
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = model
			highlight.Parent = getFXFolder()
			Debris:AddItem(highlight, CONFIG.Quality.HighlightTime)
			targetReport.Count = #output
			targetReport.Until = clock() + 1.4
		end
	end
	return output
end

local function spawnImpact(position, normal, radius, power)
	local scope = Scope.new("Impact")
	local up = normal.Magnitude > 0.01 and normal.Unit or Vector3.yAxis
	local orientation = facing(position, up)

	local core = makeEnergyPart(scope, "ImpactCore", Enum.PartType.Ball, Vector3.one * 2, CFrame.new(position), CONFIG.Visual.Core, 0.05)
	addGlow(scope, core, power * 2, radius * 2.4)
	local burst = addSparks(scope, core, 0, NumberRange.new(radius * 0.4, radius * 1.1), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	}))
	burst:Emit(scaled(math.clamp(radius * 2, 14, 48)))
	tweenTo(core, 0.3, { Size = Vector3.one * radius * 0.8, Transparency = 1 }, Enum.EasingStyle.Quad)

	for index = 1, scaled(3) do
		local ring = makeEnergyPart(scope, "Shockwave", Enum.PartType.Cylinder, Vector3.new(0.3, 2, 2), orientation * CFrame.Angles(0, math.pi / 2, 0), index == 1 and CONFIG.Visual.Core or CONFIG.Visual.Mid, 0.1)
		local delay = (index - 1) * 0.09
		task.delay(delay, function()
			if ring.Parent then
				tweenTo(ring, 0.42, {
					Size = Vector3.new(0.3, radius * (2 + index * 0.5), radius * (2 + index * 0.5)),
					Transparency = 1,
				}, Enum.EasingStyle.Quart)
			end
		end)
	end

	local column = makeEnergyPart(scope, "ImpactColumn", Enum.PartType.Cylinder, Vector3.new(1, radius * 0.5, radius * 0.5), CFrame.new(position + up * 1) * CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Mid, 0.55)
	tweenTo(column, 0.5, { Size = Vector3.new(radius * 2.2, radius * 0.15, radius * 0.15), Transparency = 1 }, Enum.EasingStyle.Quint)

	local lines = scaled(8)
	for index = 1, lines do
		local angle = (index / lines) * math.pi * 2
		local direction = (orientation * CFrame.Angles(0, 0, angle)).RightVector
		local flat = (direction - up * direction:Dot(up))
		flat = flat.Magnitude > 0.01 and flat.Unit or orientation.RightVector
		local line = makeEnergyPart(scope, "RadialLine", Enum.PartType.Block, Vector3.new(0.25, 0.25, 2), facing(position + flat * 2 + up * 0.2, flat), CONFIG.Visual.Core, 0.1)
		tweenTo(line, 0.38, {
			Size = Vector3.new(0.08, 0.08, radius * 1.5),
			CFrame = facing(position + flat * radius * 0.75 + up * 0.2, flat),
			Transparency = 1,
		}, Enum.EasingStyle.Quart)
	end

	for _ = 1, math.min(CONFIG.Quality.MaxFragments, scaled(radius)) do
		local direction = (randomUnit() + up * 0.8).Unit
		local length = RNG:NextNumber(0.6, 1.8)
		local shard = makeEnergyPart(scope, "Fragment", Enum.PartType.Block, Vector3.new(0.18, 0.18, length), facing(position, direction), CONFIG.Visual.Core, 0.05)
		local target = position + direction * RNG:NextNumber(radius * 0.5, radius * 1.4)
		tweenTo(shard, RNG:NextNumber(0.4, 0.8), {
			CFrame = facing(target, direction) * CFrame.Angles(RNG:NextNumber(0, 3), RNG:NextNumber(0, 3), 0),
			Size = Vector3.new(0.05, 0.05, length * 0.4),
			Transparency = 1,
		}, Enum.EasingStyle.Quad)
	end

	for _ = 1, scaled(5) do
		local orb = makeEnergyPart(scope, "ImpactOrb", Enum.PartType.Ball, Vector3.one * RNG:NextNumber(0.5, 1.3), CFrame.new(position + randomUnit() * 2), CONFIG.Visual.Mid, 0.15)
		tweenTo(orb, RNG:NextNumber(0.45, 0.9), {
			CFrame = CFrame.new(position + randomUnit() * radius * 0.9 + up * RNG:NextNumber(2, 8)),
			Size = Vector3.one * 0.1,
			Transparency = 1,
		}, Enum.EasingStyle.Sine)
	end

	addShake(power * 0.09, 0.3)
	task.delay(1.1, function()
		scope:Destroy()
	end)
end

local function buildFist(scope)
	local pieces = {}
	local function piece(name, shape, size, offset, rotation, color)
		local relative = CFrame.new(offset) * (rotation or CFrame.identity)
		local part = makeEnergyPart(scope, name, shape, size, CFrame.new(offset), color)
		table.insert(pieces, { Part = part, Offset = relative, BaseSize = size })
		return part
	end

	piece("Palm", Enum.PartType.Block, Vector3.new(5.6, 6.1, 3.1), Vector3.new(0, 0, 0), nil, CONFIG.Visual.Mid)
	piece("PalmCore", Enum.PartType.Block, Vector3.new(4.4, 4.6, 0.9), Vector3.new(0, 0, -1.7), nil, CONFIG.Visual.Core)
	piece("Wrist", Enum.PartType.Block, Vector3.new(3.5, 2.7, 2.7), Vector3.new(0, -4.1, 0.1), nil, CONFIG.Visual.Deep)
	piece("WristRing", Enum.PartType.Cylinder, Vector3.new(0.5, 4.2, 4.2), Vector3.new(0, -3.1, 0.1), CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Core)

	for index = -2, 2 do
		local x = index * 1.18
		piece("Knuckle", Enum.PartType.Ball, Vector3.new(1.5, 1.5, 1.5), Vector3.new(x, 3.15, -0.3), nil, CONFIG.Visual.Core)
		piece("FingerUpper", Enum.PartType.Block, Vector3.new(1.1, 2, 1.35), Vector3.new(x, 1.7, 0.4), CFrame.Angles(math.rad(-14), 0, 0), CONFIG.Visual.Mid)
		piece("FingerJoint", Enum.PartType.Ball, Vector3.new(1.2, 1.2, 1.2), Vector3.new(x, 0.75, 0.55), nil, CONFIG.Visual.Core)
		piece("FingerTip", Enum.PartType.Block, Vector3.new(1.05, 1.9, 1.3), Vector3.new(x, -0.1, -0.05), CFrame.Angles(math.rad(20), 0, 0), CONFIG.Visual.Mid)
	end

	piece("ThumbBase", Enum.PartType.Block, Vector3.new(1.7, 2.4, 1.6), Vector3.new(-3, 0.3, -0.5), CFrame.Angles(0, 0, math.rad(-35)), CONFIG.Visual.Mid)
	piece("ThumbJoint", Enum.PartType.Ball, Vector3.new(1.5, 1.5, 1.5), Vector3.new(-2.7, 1.2, -0.9), nil, CONFIG.Visual.Core)
	piece("ThumbTip", Enum.PartType.Block, Vector3.new(1.55, 2.7, 1.5), Vector3.new(-2.4, 1.5, -1.3), CFrame.Angles(math.rad(-22), 0, math.rad(-40)), CONFIG.Visual.Core)

	local shards = scaled(6)
	for index = 1, shards do
		local angle = (index / shards) * math.pi * 2
		piece("Contour", Enum.PartType.Block, Vector3.new(0.22, 0.22, 2.4), Vector3.new(math.cos(angle) * 3.2, math.sin(angle) * 3.3, -2), CFrame.Angles(0, angle, 0), CONFIG.Visual.Core)
	end

	return pieces
end

local function buildHammer(scope)
	local pieces = {}
	local function piece(name, shape, size, offset, rotation, color)
		local relative = CFrame.new(offset) * (rotation or CFrame.identity)
		local part = makeEnergyPart(scope, name, shape, size, CFrame.new(offset), color)
		table.insert(pieces, { Part = part, Offset = relative, BaseSize = size })
		return part
	end

	piece("Handle", Enum.PartType.Block, Vector3.new(1.25, 11, 1.25), Vector3.new(0, 0, 0), nil, CONFIG.Visual.Mid)
	piece("HandleCore", Enum.PartType.Cylinder, Vector3.new(11.2, 0.6, 0.6), Vector3.new(0, 0, 0), CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Core)
	piece("Pommel", Enum.PartType.Ball, Vector3.new(2.3, 2.3, 2.3), Vector3.new(0, -5.6, 0), nil, CONFIG.Visual.Core)
	piece("Head", Enum.PartType.Block, Vector3.new(8.6, 4.8, 4.3), Vector3.new(0, 6.4, 0), nil, CONFIG.Visual.Mid)
	piece("HeadTopPlate", Enum.PartType.Block, Vector3.new(9.3, 0.6, 4.9), Vector3.new(0, 8.6, 0), nil, CONFIG.Visual.Core)
	piece("HeadBottomPlate", Enum.PartType.Block, Vector3.new(9.3, 0.6, 4.9), Vector3.new(0, 4.2, 0), nil, CONFIG.Visual.Core)
	piece("FaceLeft", Enum.PartType.Block, Vector3.new(1.6, 3.2, 4.9), Vector3.new(-5.1, 6.4, 0), nil, CONFIG.Visual.Core)
	piece("FaceRight", Enum.PartType.Block, Vector3.new(1.6, 3.2, 4.9), Vector3.new(5.1, 6.4, 0), nil, CONFIG.Visual.Core)
	piece("Nucleus", Enum.PartType.Ball, Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 6.4, 0), nil, CONFIG.Visual.Core)

	for y = -3.6, 3.6, 1.8 do
		piece("HandleBand", Enum.PartType.Cylinder, Vector3.new(1.7, 0.35, 1.7), Vector3.new(0, y, 0), CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Deep)
	end

	local orbiters = scaled(8)
	for index = 1, orbiters do
		local angle = (index / orbiters) * math.pi * 2
		piece("Orbiter", Enum.PartType.Block, Vector3.new(0.35, 0.35, 1.3), Vector3.new(math.cos(angle) * 5.6, 6.4 + math.sin(angle) * 2.8, math.sin(angle) * 2.3), CFrame.Angles(0, angle, 0), CONFIG.Visual.Core)
		pieces[#pieces].Orbit = { Angle = angle, Radius = 5.6, Height = 6.4 }
	end

	return pieces
end

local function buildCage(scope, basePosition)
	local pieces = {}
	local radius = CONFIG.Cage.Radius
	local height = CONFIG.Cage.Height
	local bars = math.max(8, scaled(CONFIG.Cage.Bars))

	local function piece(name, shape, size, cframe, color, delay, spin)
		local part = makeEnergyPart(scope, name, shape, size, cframe, color, 1)
		table.insert(pieces, {
			Part = part,
			BaseSize = size,
			BaseCFrame = cframe,
			Delay = delay,
			Spin = spin,
		})
		return part
	end

	local function ring(name, ringRadius, y, thickness, segments, color, delay, spin)
		for index = 1, segments do
			local angle = (index / segments) * math.pi * 2
			local position = basePosition + Vector3.new(math.cos(angle) * ringRadius, y, math.sin(angle) * ringRadius)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			local length = (2 * math.pi * ringRadius / segments) * 1.14
			piece(name, Enum.PartType.Block, Vector3.new(thickness, thickness, length), facing(position, tangent), color, delay + (index / segments) * 0.18, spin)
		end
	end

	ring("BaseRing", radius, 0.15, 0.55, bars, CONFIG.Visual.Core, 0)
	for index = 1, bars do
		local angle = (index / bars) * math.pi * 2
		local position = basePosition + Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius)
		piece("VerticalBar", Enum.PartType.Block, Vector3.new(0.45, height, 0.45), CFrame.new(position), CONFIG.Visual.Mid, 0.2 + (index / bars) * 0.24)
	end
	ring("TopRing", radius, height, 0.55, bars, CONFIG.Visual.Core, 0.5)
	ring("InnerRingLow", radius * 0.9, height * 0.32, 0.28, math.max(8, scaled(10)), CONFIG.Visual.Core, 0.62, 0.55)
	ring("InnerRingHigh", radius * 0.9, height * 0.7, 0.28, math.max(8, scaled(10)), CONFIG.Visual.Core, 0.7, -0.45)

	local domeSegments = math.max(4, scaled(6))
	for index = 1, domeSegments do
		local angle = (index / domeSegments) * math.pi * 2
		local position = basePosition + Vector3.new(math.cos(angle) * radius * 0.55, height + 1.6, math.sin(angle) * radius * 0.55)
		piece("DomeStrut", Enum.PartType.Block, Vector3.new(0.32, 0.32, radius * 0.75), facing(position, (basePosition + Vector3.new(0, height + 3.4, 0) - position)), CONFIG.Visual.Mid, 0.55 + index * 0.03)
	end

	local core = piece("CageCore", Enum.PartType.Ball, Vector3.new(1.6, 1.6, 1.6), CFrame.new(basePosition + Vector3.new(0, height * 0.5, 0)), CONFIG.Visual.Core, 0.75)
	addGlow(scope, core, 2.2, radius * 2)
	addSparks(scope, core, 22, NumberRange.new(2, 7), NumberSequence.new(0.3, 0), NumberRange.new(0.5, 1.2))

	return pieces, core
end

local Skills = {}

local function registerCombo(name)
	local timestamp = clock()
	table.insert(comboHistory, { Name = name, Time = timestamp })
	while #comboHistory > 0 and timestamp - comboHistory[1].Time > CONFIG.Combo.Window do
		table.remove(comboHistory, 1)
	end
end

local function superConstruct(origin, direction)
	local scope = Scope.new("SuperConstruct")
	local center = origin + direction * 8 + Vector3.new(0, 4, 0)
	spawnImpact(center, Vector3.yAxis, CONFIG.Combo.Radius, 6)

	local motifs = {
		{ Shape = Enum.PartType.Block, Size = Vector3.new(5, 5, 5), Offset = Vector3.new(-6, 0, 0) },
		{ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 8, 8), Offset = Vector3.new(0, 0, 0) },
		{ Shape = Enum.PartType.Ball, Size = Vector3.new(5.5, 5.5, 5.5), Offset = Vector3.new(6, 0, 0) },
	}
	for index, motif in ipairs(motifs) do
		local part = makeEnergyPart(scope, "SuperMotif", motif.Shape, motif.Size * 0.2, CFrame.new(center + motif.Offset), index == 2 and CONFIG.Visual.Core or CONFIG.Visual.Mid, 0.25)
		tweenTo(part, 0.9, { Size = motif.Size, Transparency = 1, CFrame = CFrame.new(center + motif.Offset + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.pi, 0) }, Enum.EasingStyle.Back)
	end

	local halo = makeEnergyPart(scope, "SuperHalo", Enum.PartType.Cylinder, Vector3.new(0.6, 4, 4), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Core, 0.1)
	tweenTo(halo, 0.8, { Size = Vector3.new(0.6, CONFIG.Combo.Radius * 2.4, CONFIG.Combo.Radius * 2.4), Transparency = 1 }, Enum.EasingStyle.Quint)
	addShake(0.3, 0.5)
	energy = math.min(CONFIG.Energy.Max, energy + CONFIG.Combo.Reward)
	if hud.Bar then
		hud.Bar.BackgroundColor3 = CONFIG.Visual.Core
		tweenTo(hud.Bar, 1.2, { BackgroundColor3 = CONFIG.Visual.Mid })
	end
	task.delay(1.4, function()
		scope:Destroy()
	end)
end

local function checkCombo()
	local sequence = CONFIG.Combo.Sequence
	if #comboHistory < #sequence then
		return
	end
	local offset = #comboHistory - #sequence
	for index, name in ipairs(sequence) do
		if comboHistory[offset + index].Name ~= name then
			return
		end
	end
	if comboHistory[#comboHistory].Time - comboHistory[offset + 1].Time > CONFIG.Combo.Window then
		return
	end
	table.clear(comboHistory)
	if rootPart then
		superConstruct(rootPart.Position, rootPart.CFrame.LookVector)
	end
end

local function finishSkill(name)
	local skill = Skills[name]
	skill.State = "Idle"
	if skill.Exclusive then
		exclusiveBusy = false
	end
end

local function runFist()
	local settings = CONFIG.Fist
	local skill = Skills.Fist
	local scope = Scope.new("Fist")
	scope:OnFinish(function()
		finishSkill("Fist")
	end)

	local pieces = buildFist(scope)
	local armPose = poseArm(scope, function(elapsed)
		if elapsed < settings.Form then
			return settings.ArmAngle * easeOut(elapsed / settings.Form)
		elseif elapsed < settings.Form + settings.Charge then
			return settings.ArmAngle * (1 - 0.45 * easeInOut((elapsed - settings.Form) / settings.Charge))
		elseif elapsed < settings.Form + settings.Charge + settings.Thrust then
			return settings.ArmAngle * (0.55 + 0.55 * easeIn((elapsed - settings.Form - settings.Charge) / settings.Thrust))
		end
		local fade = clamp01((elapsed - settings.Form - settings.Charge - settings.Thrust) / (settings.Rest + settings.Dissipate))
		return settings.ArmAngle * (1.1 * (1 - fade))
	end)

	local emitterHost = pieces[1].Part
	addGlow(scope, emitterHost, 3, 26)
	addSparks(scope, emitterHost, 45, NumberRange.new(4, 12), NumberSequence.new(0.6, 0))

	local total = settings.Form + settings.Charge + settings.Thrust + settings.Rest + settings.Dissipate
	local impactAt = settings.Form + settings.Charge + settings.Thrust * 0.82
	local startTime = clock()
	local impacted = false
	local seen = {}
	local targets = {}
	local lockedDirection = nil
	local lockedOrigin = nil

	scope.Update = function(currentTime)
		if not isAlive() then
			scope:Destroy()
			return
		end
		local elapsed = currentTime - startTime
		local direction = rootPart.CFrame.LookVector
		local origin = handCFrame().Position + Vector3.new(0, 0.5, 0)

		local distance
		if elapsed < settings.Form then
			skill.State = "Casting"
			distance = lerp(2, settings.HoldDistance, easeOut(elapsed / settings.Form))
		elseif elapsed < settings.Form + settings.Charge then
			skill.State = "Charging"
			distance = lerp(settings.HoldDistance, settings.HoldDistance - 3, easeInOut((elapsed - settings.Form) / settings.Charge))
		elseif elapsed < settings.Form + settings.Charge + settings.Thrust then
			skill.State = "Attacking"
			if not lockedDirection then
				lockedDirection = direction
				lockedOrigin = origin
			end
			local progress = (elapsed - settings.Form - settings.Charge) / settings.Thrust
			distance = lerp(settings.HoldDistance - 3, settings.Reach, easeIn(progress))
		elseif elapsed < settings.Form + settings.Charge + settings.Thrust + settings.Rest then
			skill.State = "Impact"
			distance = settings.Reach + (elapsed - settings.Form - settings.Charge - settings.Thrust) * 4
		else
			skill.State = "Destroying"
			distance = settings.Reach + settings.Rest * 4
		end

		local activeDirection = lockedDirection or direction
		local activeOrigin = lockedOrigin or origin
		local center = activeOrigin + activeDirection * distance
		local pivot = facing(center, activeDirection)
		local formProgress = clamp01(elapsed / settings.Form)
		local scale = settings.Size * lerp(0.12, 1, easeOut(formProgress))
		local fade = elapsed > total - settings.Dissipate
			and clamp01((elapsed - (total - settings.Dissipate)) / settings.Dissipate)
			or 0
		local pulse = 1 + math.sin(currentTime * 12) * 0.02

		for index, item in ipairs(pieces) do
			local part = item.Part
			if part.Parent then
				part.CFrame = pivot * item.Offset
				part.Size = item.BaseSize * scale * (index % 3 == 0 and pulse or 1)
				part.Transparency = CONFIG.Visual.Transparency + fade * (1 - CONFIG.Visual.Transparency)
			end
		end

		if armPose then
			armPose(elapsed)
		end

		if not impacted and elapsed >= impactAt then
			impacted = true
			scanCharacters(center, settings.HitRadius, seen, targets)
			spawnImpact(center + activeDirection * 2, -activeDirection, settings.HitRadius, 3.4)
		end

		if elapsed >= total then
			scope:Destroy()
		end
	end
end

local function startCage(basePosition)
	local settings = CONFIG.Cage
	local skill = Skills.Cage
	local scope = Scope.new("Cage")
	scope:OnFinish(function()
		finishSkill("Cage")
	end)

	local pieces, core = buildCage(scope, basePosition)
	local startTime = clock()
	local total = settings.Build + settings.Life + settings.Dissipate
	local lastScan = -math.huge
	local seen = {}
	local targets = {}
	local flickerSeeds = {}
	for index = 1, #pieces do
		flickerSeeds[index] = RNG:NextNumber(0, settings.Dissipate * 0.7)
	end

	spawnImpact(basePosition, Vector3.yAxis, settings.Radius * 0.6, 1.6)

	scope.Update = function(currentTime)
		local elapsed = currentTime - startTime
		local dissipating = elapsed > settings.Build + settings.Life
		local dissipateProgress = dissipating and clamp01((elapsed - settings.Build - settings.Life) / settings.Dissipate) or 0

		if elapsed < settings.Build then
			skill.State = "Casting"
		elseif not dissipating then
			skill.State = "Active"
		else
			skill.State = "Destroying"
		end

		for index, item in ipairs(pieces) do
			local part = item.Part
			if part.Parent then
				local appear = clamp01((elapsed - item.Delay) / 0.28)
				local pulse = 1 + math.sin(currentTime * 6 + index * 0.7) * 0.07
				local visible = easeOut(appear)
				local transparency = 1 - visible * (1 - CONFIG.Visual.Transparency)

				if dissipating then
					local localFade = clamp01((dissipateProgress * settings.Dissipate - flickerSeeds[index]) / (settings.Dissipate * 0.4))
					local flicker = math.sin(currentTime * 40 + index) > 0 and 0.25 or 0
					transparency = math.min(1, CONFIG.Visual.Transparency + localFade + flicker * (1 - localFade))
					visible = 1 - localFade
				end

				part.Transparency = transparency
				part.Size = item.BaseSize * math.max(0.05, visible) * pulse
				if item.Spin then
					part.CFrame = CFrame.new(basePosition)
						* CFrame.Angles(0, currentTime * item.Spin, 0)
						* CFrame.new(basePosition):Inverse()
						* item.BaseCFrame
				end
			end
		end

		if core.Parent then
			core.Size = Vector3.one * (1.6 + math.sin(currentTime * 8) * 0.35) * (1 - dissipateProgress)
		end

		if not dissipating and elapsed >= settings.Build and currentTime - lastScan >= settings.ScanInterval then
			lastScan = currentTime
			scanCharacters(basePosition + Vector3.new(0, CONFIG.Cage.Height * 0.5, 0), settings.Radius, seen, targets)
		end

		if elapsed >= total then
			scope:Destroy()
		end
	end
end

local function runHammer()
	local settings = CONFIG.Hammer
	local skill = Skills.Hammer
	local scope = Scope.new("Hammer")
	scope:OnFinish(function()
		finishSkill("Hammer")
	end)

	local pieces = buildHammer(scope)
	local armPose = poseArm(scope, function(elapsed)
		if elapsed < settings.Form then
			return 25 * easeOut(elapsed / settings.Form)
		elseif elapsed < settings.Form + settings.Lift then
			return lerp(25, settings.ArmAngle, easeInOut((elapsed - settings.Form) / settings.Lift))
		elseif elapsed < settings.Form + settings.Lift + settings.Hold then
			return settings.ArmAngle
		elseif elapsed < settings.Form + settings.Lift + settings.Hold + settings.Slam then
			return lerp(settings.ArmAngle, -20, easeIn((elapsed - settings.Form - settings.Lift - settings.Hold) / settings.Slam))
		end
		local fade = clamp01((elapsed - settings.Form - settings.Lift - settings.Hold - settings.Slam) / (settings.Rest + settings.Dissipate))
		return lerp(-20, 0, fade)
	end)

	local head = pieces[4].Part
	addGlow(scope, head, 3, 30)
	addSparks(scope, head, 30, NumberRange.new(3, 9), NumberSequence.new(0.5, 0))

	local startTime = clock()
	local total = settings.Form + settings.Lift + settings.Hold + settings.Slam + settings.Rest + settings.Dissipate
	local slamStart = settings.Form + settings.Lift + settings.Hold
	local impacted = false
	local seen = {}
	local targets = {}
	local impactPoint = nil

	scope.Update = function(currentTime)
		if not isAlive() then
			scope:Destroy()
			return
		end
		local elapsed = currentTime - startTime
		local hand = handCFrame()
		local look = rootPart.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local pivot
		local fade = 0

		if elapsed < settings.Form then
			skill.State = "Casting"
			pivot = hand * CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(-25), 0, 0)
		elseif elapsed < slamStart then
			skill.State = "Charging"
			local progress = easeInOut((elapsed - settings.Form) / (settings.Lift + settings.Hold))
			pivot = hand * CFrame.new(0, lerp(-0.6, 2.2, progress), 0) * CFrame.Angles(math.rad(lerp(-25, -135, progress)), 0, 0)
		elseif elapsed < slamStart + settings.Slam then
			skill.State = "Attacking"
			local progress = easeIn((elapsed - slamStart) / settings.Slam)
			if not impactPoint then
				local ground = groundBelow(rootPart.Position + flat * settings.Reach, 250)
				impactPoint = ground
			end
			local high = rootPart.Position + flat * (settings.Reach * 0.45) + Vector3.new(0, 11, 0)
			local low = impactPoint + Vector3.new(0, 1.4, 0)
			local position = high:Lerp(low, progress)
			pivot = CFrame.lookAt(position, position + flat, Vector3.yAxis) * CFrame.Angles(math.rad(lerp(-140, 92, progress)), 0, 0)
			if not impacted and progress > 0.93 then
				impacted = true
				local point, normal = groundBelow(impactPoint, 40)
				scanCharacters(point, settings.HitRadius, seen, targets)
				spawnImpact(point, normal, settings.HitRadius, 6)
			end
		elseif elapsed < total - settings.Dissipate then
			skill.State = "Impact"
			local point = (impactPoint or rootPart.Position + flat * settings.Reach) + Vector3.new(0, 1.4, 0)
			pivot = CFrame.lookAt(point, point + flat, Vector3.yAxis) * CFrame.Angles(math.rad(92), 0, 0)
		else
			skill.State = "Destroying"
			fade = clamp01((elapsed - (total - settings.Dissipate)) / settings.Dissipate)
			local point = (impactPoint or rootPart.Position + flat * settings.Reach) + Vector3.new(0, 1.4 + fade * 2, 0)
			pivot = CFrame.lookAt(point, point + flat, Vector3.yAxis) * CFrame.Angles(math.rad(92), 0, 0)
		end

		local formProgress = clamp01(elapsed / settings.Form)
		local scale = settings.Size * lerp(0.08, 1, easeOut(formProgress))

		for _, item in ipairs(pieces) do
			local part = item.Part
			if part.Parent then
				local offset = item.Offset
				if item.Orbit then
					local angle = item.Orbit.Angle + currentTime * 2.2
					offset = CFrame.new(math.cos(angle) * item.Orbit.Radius, item.Orbit.Height + math.sin(angle * 1.4) * 2.6, math.sin(angle) * 2.3)
						* CFrame.Angles(0, angle, 0)
				end
				part.CFrame = pivot * offset
				part.Size = item.BaseSize * scale
				part.Transparency = CONFIG.Visual.Transparency + fade * (1 - CONFIG.Visual.Transparency)
			end
		end

		if armPose then
			armPose(elapsed)
		end

		if elapsed >= total then
			scope:Destroy()
		end
	end
end

local function aimPointFromScreen(screenPoint, maxDistance)
	local camera = getCamera()
	if not camera or not rootPart then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	local ray = camera:ViewportPointToRay(screenPoint.X - inset.X, screenPoint.Y - inset.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * (maxDistance * 3 + 100), rayParams)
	local point = result and result.Position or (ray.Origin + ray.Direction * maxDistance)
	local offset = point - rootPart.Position
	if offset.Magnitude > maxDistance then
		point = rootPart.Position + offset.Unit * maxDistance
	end
	local grounded = groundBelow(point, 200)
	local groundedOffset = grounded - rootPart.Position
	if groundedOffset.Magnitude > maxDistance then
		grounded = rootPart.Position + groundedOffset.Unit * maxDistance
	end
	return grounded
end

local function cancelPlacement()
	if placement then
		placement.Scope:Destroy()
		placement = nil
	end
	if hud.Hint then
		hud.Hint.Visible = false
	end
	if hud.Buttons and hud.Buttons.Cage then
		hud.Buttons.Cage.Armed = false
	end
end

local function abortCage(refund)
	local skill = Skills.Cage
	cancelPlacement()
	skill.State = "Idle"
	skill.ReadyAt = 0
	if refund then
		energy = math.min(CONFIG.Energy.Max, energy + CONFIG.Cage.Cost)
	end
end

local function beginPlacement()
	cancelPlacement()
	local scope = Scope.new("CagePlacement")
	local marker = makeEnergyPart(scope, "PlacementMarker", Enum.PartType.Cylinder, Vector3.new(0.4, CONFIG.Cage.Radius * 2, CONFIG.Cage.Radius * 2), CFrame.new(rootPart and rootPart.Position or Vector3.zero) * CFrame.Angles(0, 0, math.pi / 2), CONFIG.Visual.Mid, 0.55)
	placement = { Scope = scope, Marker = marker, Expires = clock() + CONFIG.Cage.AimTimeout }
	if hud.Hint then
		hud.Hint.Text = "TOQUE NO CHÃO PARA PRENDER"
		hud.Hint.Visible = true
	end
	if hud.Buttons and hud.Buttons.Cage then
		hud.Buttons.Cage.Armed = true
	end

	scope.Update = function(currentTime)
		if not isAlive() or currentTime > placement.Expires then
			abortCage(true)
			return
		end
		local camera = getCamera()
		if camera and marker.Parent then
			local center = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.55)
			local point = aimPointFromScreen(center, CONFIG.Cage.MaxDistance)
			if point then
				marker.CFrame = CFrame.new(point + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				marker.Transparency = 0.45 + math.sin(currentTime * 8) * 0.12
			end
		end
	end

	scope:Bind(UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if processedByUI or not placement then
			return
		end
		local point = aimPointFromScreen(position, CONFIG.Cage.MaxDistance)
		cancelPlacement()
		if point then
			startCage(point)
		else
			finishSkill("Cage")
		end
	end))
end

local function runCage()
	if TOUCH_PRIMARY then
		Skills.Cage.State = "Aiming"
		beginPlacement()
		return
	end
	local point = aimPointFromScreen(UserInputService:GetMouseLocation(), CONFIG.Cage.MaxDistance)
	if not point then
		finishSkill("Cage")
		return
	end
	startCage(point)
end

Skills.Fist = { Name = "Fist", Config = CONFIG.Fist, State = "Idle", ReadyAt = 0, Exclusive = true, Run = runFist, Label = "PUNHO", Key = "Z" }
Skills.Cage = { Name = "Cage", Config = CONFIG.Cage, State = "Idle", ReadyAt = 0, Exclusive = false, Run = runCage, Label = "PRISÃO", Key = "X" }
Skills.Hammer = { Name = "Hammer", Config = CONFIG.Hammer, State = "Idle", ReadyAt = 0, Exclusive = true, Run = runHammer, Label = "MARTELO", Key = "C" }

local function warnEnergy()
	energyWarnUntil = clock() + 0.45
end

local function activate(name)
	local skill = Skills[name]
	if not skill then
		return false
	end
	if placement and name == "Cage" then
		abortCage(true)
		return false
	end
	if not isAlive() or skill.State ~= "Idle" then
		return false
	end
	if skill.Exclusive and exclusiveBusy then
		return false
	end
	local currentTime = clock()
	if currentTime < skill.ReadyAt then
		return false
	end
	if energy < skill.Config.Cost then
		warnEnergy()
		return false
	end

	energy -= skill.Config.Cost
	skill.ReadyAt = currentTime + skill.Config.Cooldown
	skill.State = "Casting"
	if skill.Exclusive then
		exclusiveBusy = true
	end
	registerCombo(name)
	checkCombo()

	local ok, err = pcall(skill.Run)
	if not ok then
		warn("[GreenConstruct] " .. name .. " failed: " .. tostring(err))
		skill.State = "Idle"
		if skill.Exclusive then
			exclusiveBusy = false
		end
		return false
	end
	return true
end

local function makeSkillButton(parent, skill, order)
	local button = Instance.new("TextButton")
	button.Name = skill.Name .. "Button"
	button.Size = UDim2.fromOffset(84, 84)
	button.BackgroundColor3 = Color3.fromRGB(8, 26, 15)
	button.BackgroundTransparency = 0.12
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = order
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.Visual.Mid
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = button

	local fill = Instance.new("Frame")
	fill.Name = "Cooldown"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = button

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.44)
	label.Position = UDim2.fromScale(0, 0.16)
	label.BackgroundTransparency = 1
	label.Text = skill.Label
	label.TextColor3 = CONFIG.Visual.Core
	label.TextScaled = false
	label.TextSize = 13
	label.Font = Enum.Font.GothamBold
	label.ZIndex = 3
	label.Parent = button

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 0.34)
	hint.Position = UDim2.fromScale(0, 0.54)
	hint.BackgroundTransparency = 1
	hint.Text = TOUCH_PRIMARY and "TOQUE" or skill.Key
	hint.TextColor3 = Color3.fromRGB(150, 200, 165)
	hint.TextSize = 12
	hint.Font = Enum.Font.GothamMedium
	hint.ZIndex = 3
	hint.Parent = button

	local lastFire = 0
	local function fire()
		local currentTime = clock()
		if currentTime - lastFire < 0.15 then
			return
		end
		lastFire = currentTime
		activate(skill.Name)
	end

	button.Activated:Connect(fire)
	button.MouseButton1Click:Connect(fire)

	return { Button = button, Fill = fill, Stroke = stroke, Armed = false }
end

local function buildInterface()
	local existing = PlayerGui:FindFirstChild("GreenConstructHUD")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "GreenConstructHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "EnergyPanel"
	panel.AnchorPoint = Vector2.new(0, TOUCH_PRIMARY and 0 or 1)
	panel.Position = TOUCH_PRIMARY and UDim2.new(0, 18, 0, 52) or UDim2.new(0, 24, 1, -26)
	panel.Size = UDim2.fromOffset(268, 62)
	panel.BackgroundColor3 = Color3.fromRGB(6, 22, 13)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CONFIG.Visual.Mid
	panelStroke.Transparency = 0.4
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromOffset(180, 18)
	title.Position = UDim2.fromOffset(14, 8)
	title.BackgroundTransparency = 1
	title.Text = "ENERGIA DE CONSTRUCT"
	title.TextColor3 = CONFIG.Visual.Core
	title.TextSize = 12
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local value = Instance.new("TextLabel")
	value.Size = UDim2.fromOffset(60, 18)
	value.Position = UDim2.fromOffset(194, 8)
	value.BackgroundTransparency = 1
	value.Text = "100%"
	value.TextColor3 = Color3.new(1, 1, 1)
	value.TextSize = 12
	value.Font = Enum.Font.GothamBold
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = panel

	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(240, 14)
	track.Position = UDim2.fromOffset(14, 32)
	track.BackgroundColor3 = Color3.fromRGB(18, 52, 28)
	track.BorderSizePixel = 0
	track.Parent = panel

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = CONFIG.Visual.Mid
	bar.BorderSizePixel = 0
	bar.Parent = track

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 90)
	hint.Size = UDim2.fromOffset(320, 26)
	hint.BackgroundColor3 = Color3.fromRGB(6, 22, 13)
	hint.BackgroundTransparency = 0.25
	hint.Text = ""
	hint.TextColor3 = CONFIG.Visual.Core
	hint.TextSize = 14
	hint.Font = Enum.Font.GothamBold
	hint.Visible = false
	hint.Parent = gui

	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 8)
	hintCorner.Parent = hint

	local report = Instance.new("TextLabel")
	report.Name = "TargetReport"
	report.AnchorPoint = Vector2.new(0.5, 0)
	report.Position = UDim2.new(0.5, 0, 0, 124)
	report.Size = UDim2.fromOffset(320, 22)
	report.BackgroundTransparency = 1
	report.Text = ""
	report.TextColor3 = CONFIG.Visual.Core
	report.TextSize = 13
	report.Font = Enum.Font.GothamMedium
	report.TextTransparency = 0.1
	report.Parent = gui

	local pad = Instance.new("Frame")
	pad.Name = "SkillPad"
	pad.AnchorPoint = Vector2.new(1, 1)
	pad.Position = TOUCH_PRIMARY and UDim2.new(1, -22, 1, -168) or UDim2.new(1, -26, 1, -26)
	pad.Size = UDim2.fromOffset(280, 92)
	pad.BackgroundTransparency = 1
	pad.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = pad

	hud = {
		Gui = gui,
		Scale = scale,
		Panel = panel,
		PanelStroke = panelStroke,
		Bar = bar,
		Value = value,
		Hint = hint,
		Report = report,
		Buttons = {
			Fist = makeSkillButton(pad, Skills.Fist, 1),
			Cage = makeSkillButton(pad, Skills.Cage, 2),
			Hammer = makeSkillButton(pad, Skills.Hammer, 3),
		},
	}

	local function resize()
		local camera = getCamera()
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		local factor = math.clamp(math.min(viewport.X, viewport.Y) / 720, 0.75, 1.35)
		scale.Scale = factor
	end

	resize()
	local camera = getCamera()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local nextCamera = getCamera()
		if nextCamera then
			nextCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
			resize()
		end
	end)
end

local function updateInterface(deltaTime, currentTime)
	energyShown = lerp(energyShown, energy, math.min(1, deltaTime * CONFIG.Energy.Smooth))
	if hud.Bar then
		hud.Bar.Size = UDim2.fromScale(math.max(0, energyShown / CONFIG.Energy.Max), 1)
		hud.Value.Text = string.format("%d%%", math.floor(energyShown + 0.5))
	end
	if hud.PanelStroke then
		local warning = currentTime < energyWarnUntil
		hud.PanelStroke.Color = warning and Color3.fromRGB(255, 90, 90) or CONFIG.Visual.Mid
		hud.PanelStroke.Transparency = warning and 0 or 0.4
	end
	if hud.Report then
		if currentTime < targetReport.Until and targetReport.Count > 0 then
			hud.Report.Text = string.format("ALVOS DETECTADOS LOCALMENTE: %d", targetReport.Count)
			hud.Report.TextTransparency = clamp01(1 - (targetReport.Until - currentTime) / 0.6) * 0.9
		elseif hud.Report.Text ~= "" then
			hud.Report.Text = ""
		end
	end
	if not hud.Buttons then
		return
	end
	for name, entry in pairs(hud.Buttons) do
		local skill = Skills[name]
		local remaining = math.max(0, skill.ReadyAt - currentTime)
		local ratio = skill.Config.Cooldown > 0 and remaining / skill.Config.Cooldown or 0
		entry.Fill.Size = UDim2.fromScale(1, ratio)
		local usable = remaining <= 0 and energy >= skill.Config.Cost and skill.State == "Idle"
		if entry.Armed then
			entry.Stroke.Color = CONFIG.Visual.Core
			entry.Stroke.Thickness = 3
		else
			entry.Stroke.Color = usable and CONFIG.Visual.Mid or Color3.fromRGB(90, 110, 95)
			entry.Stroke.Thickness = 2
		end
	end
end

local function updateCamera(currentTime)
	local camera = getCamera()
	if not camera or #shakes == 0 then
		return
	end
	local offset = Vector3.zero
	for index = #shakes, 1, -1 do
		local shake = shakes[index]
		local progress = clamp01((currentTime - shake.Start) / shake.Duration)
		if progress >= 1 then
			table.remove(shakes, index)
		else
			local strength = shake.Intensity * (1 - progress) ^ CONFIG.Camera.Decay
			offset += Vector3.new(
				math.noise(currentTime * 38, index * 4.3),
				math.noise(index * 7.1, currentTime * 41),
				math.noise(currentTime * 35, index * 2.7)
			) * strength * 2
		end
	end
	if offset.Magnitude > 0.0001 then
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end
end

local function step(deltaTime)
	local currentTime = clock()
	energy = math.min(CONFIG.Energy.Max, energy + CONFIG.Energy.Regen * deltaTime)

	for index = #scopes, 1, -1 do
		local scope = scopes[index]
		if scope.Alive and scope.Update then
			local ok, err = pcall(scope.Update, currentTime, deltaTime)
			if not ok then
				warn("[GreenConstruct] update error in " .. scope.Name .. ": " .. tostring(err))
				scope:Destroy()
			end
		end
	end

	updateInterface(deltaTime, currentTime)
	updateCamera(currentTime)
end

local function detachCharacter()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	cancelPlacement()
	destroyAllScopes()
	exclusiveBusy = false
	for _, skill in pairs(Skills) do
		skill.State = "Idle"
	end
	character = nil
	humanoid = nil
	rootPart = nil
	rightHand = nil
	rightShoulder = nil
	shoulderBaseC0 = nil
	refreshCollisionFilters()
end

local function attachCharacter(model)
	detachCharacter()
	character = model
	humanoid = getHumanoid(model)
	rootPart = getCharacterRoot(model) or model:WaitForChild("HumanoidRootPart", 5)
	rightHand = getCharacterHand(model)
	rightShoulder = getRightShoulder(model)
	shoulderBaseC0 = rightShoulder and rightShoulder.C0 or nil
	refreshCollisionFilters()

	if humanoid then
		table.insert(characterConnections, humanoid.Died:Connect(function()
			cancelPlacement()
			destroyAllScopes()
			exclusiveBusy = false
			for _, skill in pairs(Skills) do
				skill.State = "Idle"
			end
		end))
		table.insert(characterConnections, humanoid:GetPropertyChangedSignal("RigType"):Connect(function()
			rightHand = getCharacterHand(character)
			rightShoulder = getRightShoulder(character)
			shoulderBaseC0 = rightShoulder and rightShoulder.C0 or nil
		end))
	end

	table.insert(characterConnections, model.ChildRemoved:Connect(function(child)
		if child == rightHand then
			rightHand = getCharacterHand(character)
		end
	end))
end

local function onInput(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Z then
			activate("Fist")
		elseif input.KeyCode == Enum.KeyCode.X then
			activate("Cage")
		elseif input.KeyCode == Enum.KeyCode.C then
			activate("Hammer")
		end
	end
end

buildInterface()
refreshCollisionFilters()
RunService:BindToRenderStep("GreenConstructUpdate", Enum.RenderPriority.Camera.Value + 2, step)
UserInputService.InputBegan:Connect(onInput)
LocalPlayer.CharacterAdded:Connect(attachCharacter)
LocalPlayer.CharacterRemoving:Connect(detachCharacter)
if LocalPlayer.Character then
	attachCharacter(LocalPlayer.Character)
end
