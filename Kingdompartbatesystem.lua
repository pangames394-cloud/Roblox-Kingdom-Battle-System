-- Connected Discord-GitHub
-- Made By It_Ramfis239 | Discord: pangamesdev

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local BEACON_HEIGHT = 150
local TroopData = require(ReplicatedStorage:WaitForChild("TroopData"))
local EFFECT_DURATION = 3
local BATTLE_SPACING = 8

local BattleResultEvent = ReplicatedStorage:WaitForChild("BattleResultEvent")
local BATTLE_SOUND_ID = "rbxassetid://1836334472"
local AnnexRemote = ReplicatedStorage:WaitForChild("AnnexTerritoryEvent")
local SelectTroopEvent = ReplicatedStorage:WaitForChild("SelectTroopEvent")
local EnterSelectionModeEvent = ReplicatedStorage:WaitForChild("EnterSelectionModeEvent")
local ClearTroopSelectionEvent = ReplicatedStorage:WaitForChild("ClearTroopSelectionEvent")
local BattleMusicDuckEvent = ReplicatedStorage:WaitForChild("BattleMusicDuckEvent")

local Territories = Workspace:WaitForChild("Territories")
local PathFolder = Workspace:WaitForChild("Path")

local UpdateTroopInfoEvent = ReplicatedStorage:WaitForChild("UpdateTroopInfoEvent")
local BattleLoopSoundEvent = ReplicatedStorage:WaitForChild("BattleLoopSoundEvent")
local PlayGlobalSoundEvent = ReplicatedStorage:WaitForChild("PlayGlobalSoundEvent")

local function playOneShot(position, soundId, volume, targetPlayers)
	if targetPlayers then
		for _, plr in ipairs(targetPlayers) do
			if plr then
				PlayGlobalSoundEvent:FireClient(plr, soundId, volume or 1)
			end
		end
	else
		PlayGlobalSoundEvent:FireAllClients(soundId, volume or 1)
	end
end

local function fireToPlayers(remoteEvent, players, ...)
	for _, plr in ipairs(players) do
		if plr then
			remoteEvent:FireClient(plr, ...)
		end
	end
end

local RETREAT_SOUND_ID = "rbxassetid://6875748361"
local REGEN_SOUND_ID = "rbxassetid://134410911353980"
local CHARGE_SOUND_ID = "rbxassetid://6875748361"
local FOOTSTEP_SOUND_ID = "rbxassetid://130977158423885"

local WALK_SPEED = 4
local DEFAULT_KINGDOM_COLOR = Color3.fromRGB(255, 0, 0)
local DEFAULT_GARRISON = 50
local DEFAULT_GOLD_INCOME = 15
local PATH_USE_THRESHOLD = 0.5
local BORDER_DISTANCE = 20

local PlayerEliminatedEvent = ReplicatedStorage:FindFirstChild("PlayerEliminatedEvent")

if not PlayerEliminatedEvent then
	PlayerEliminatedEvent = Instance.new("RemoteEvent")
	PlayerEliminatedEvent.Name = "PlayerEliminatedEvent"
	PlayerEliminatedEvent.Parent = ReplicatedStorage
end

local WALK_ANIMATION_IDS = {
	"rbxassetid://85255213067811",
	"rbxassetid://74742643272249",
	"rbxassetid://120151422990004",
}

local IDLE_ANIMATION_ID = "rbxassetid://109442557992825"

local SLASH_ANIMATION_ID = "rbxassetid://96423019110698"
local THRUST_ANIMATION_ID = "rbxassetid://130389329494334"
local FLINCH_ANIMATION_ID = "rbxassetid://101319515652327"
local DEATH_ANIMATION_ID = "rbxassetid://93548936792512"
local VICTORY_ANIMATION_ID = "rbxassetid://82991368584640"

local ATTACK_LUNGE_DISTANCE = 3
local ATTACK_SWING_TIME = 0.88
local FLINCH_DISTANCE = 1.4
local FLINCH_TIME = 3
local DEATH_COLLAPSE_TIME = 3.6
local VICTORY_HOP_HEIGHT = 2.5
local VICTORY_HOP_TIME = 0.25
local CHARGE_TIME = 0.35
local POST_VICTORY_HOLD = 3.5
local FACE_TURN_TIME = 0.2

local function countPlayerTerritory(playerName)
	local count = 0
	
	for _, territory in ipairs(Territories:GetChildren()) do
		if territory:GetAttribute("Owner") == playerName then
			count += 1
		end
	end
	
	return count
end

local function syncTerritoryCount(playerName)
	local plr = Players:FindFirstChild(playerName)
	
	if plr then
		plr:SetAttribute("TerritoryCount", countPlayerTerritory(playerName))
	end
end

local MODEL_FRONT_IS_NEGATIVE_Z = false

local function facingRotation(from, to, fallbackRotation)
	local flatFrom = Vector3.new(from.X, 0, from.Z)
	local flatTo = Vector3.new(to.X, 0, to.Z)

	if (flatTo - flatFrom).Magnitude < 0.01 then
		return fallbackRotation or CFrame.new()
	end

	local direction = (flatTo - flatFrom).Unit

	if not MODEL_FRONT_IS_NEGATIVE_Z then
		direction = -direction
	end

	return CFrame.lookAt(Vector3.zero, direction)
end

local function playDefenseAttack(defenseModel, targetPosition)
	if not defenseModel or not defenseModel.Parent then
		return
	end

	local origin = defenseModel:GetPivot()

	local direction = Vector3.new(
		targetPosition.X - origin.Position.X,
		0,
		targetPosition.Z - origin.Position.Z
	)

	if direction.Magnitude > 0.01 then
		local rotation = CFrame.lookAt(
			origin.Position,
			origin.Position + direction
		)

		defenseModel:PivotTo(rotation)
	end
end

local WaitingForSelect = {}
local WaitingAction = {}

print("")

local function getAnimator(troopModel)
	local humanoid = troopModel:FindFirstChildWhichIsA("Humanoid", true)

	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator
end

local function loadTrack(troopModel, animationId, priority)
	local animator = getAnimator(troopModel)

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn("Failed to load animation", animationId, "on", troopModel.Name)
		return nil
	end

	track.Looped = true
	track.Priority = priority

	return track
end

local function startWalkAnimation(troopModel)
	local animationId = WALK_ANIMATION_IDS[math.random(1, #WALK_ANIMATION_IDS)]

	local track = loadTrack(troopModel, animationId, Enum.AnimationPriority.Movement)

	if not track then
		return nil
	end

	track:Play()

	local root = troopModel:FindFirstChild("HumanoidRootPart", true)

	if root and not root:FindFirstChild("FootstepSound") then
		local footstepSound = Instance.new("Sound")
		footstepSound.Name = "FootstepSound"
		footstepSound.SoundId = FOOTSTEP_SOUND_ID
		footstepSound.Volume = 0.4
		footstepSound.RollOffMaxDistance = 60
		footstepSound.Looped = true
		footstepSound.Parent = root
		footstepSound:Play()
	end

	return track
end

local function waitForAnimator(troopModel, timeout)
	local animator = getAnimator(troopModel)

	if animator then
		return animator
	end

	local start = os.clock()

	while troopModel and troopModel.Parent and not animator and (os.clock() - start) < (timeout or 5) do
		task.wait(0.1)
		animator = getAnimator(troopModel)
	end

	return animator
end

local function startIdleAnimation(troopModel)
	if not troopModel or not troopModel.Parent then
		return
	end

	task.spawn(function()
		local animator = waitForAnimator(troopModel, 5)

		if not animator or not troopModel.Parent then
			return
		end

		local animation = Instance.new("Animation")
		animation.AnimationId = IDLE_ANIMATION_ID

		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if not ok or not track then
			warn("Failed to load idle animation on", troopModel.Name)
			return
		end

		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end)
end

local function stopAnimation(track, fadeTime, troopModel)
	if track then
		pcall(function()
			track:Stop(fadeTime or 0.15)
		end)
	end

	if troopModel then
		local root = troopModel:FindFirstChild("HumanoidRootPart", true)
		local footstepSound = root and root:FindFirstChild("FootstepSound")

		if footstepSound then
			footstepSound:Stop()
			footstepSound:Destroy()
		end
	end
end
