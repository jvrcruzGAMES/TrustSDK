--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cryptography = require(ReplicatedStorage.Packages.cryptography)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RoactCompat = require(ReplicatedStorage.Packages.RoactCompat)
local Transport = require(script.Parent.Transport)

local CSPRNG = Cryptography.Utilities.CSPRNG

local MESSAGE_PREFIX = "__TrustSDK_Robots__:"
local TRANSPORT_LISTENER_ID = "TrustSDK.Robots"
local SCREEN_GUI_NAME = "TrustSDKRobotsCaptcha"

local DEFAULT_CODE_LENGTH = 6
local DEFAULT_MAX_ATTEMPTS = 3
local DEFAULT_TIMEOUT_SECONDS = 90

type TransportModule = typeof(Transport)

export type CaptchaTheme = {
	OverlayColor: string?,
	CardColor: string?,
	AccentColor: string?,
	TextColor: string?,
	MutedTextColor: string?,
	ErrorColor: string?,
}

export type CaptchaOptions = {
	Title: string?,
	Prompt: string?,
	CodeLength: number?,
	MaxAttempts: number?,
	TimeoutSeconds: number?,
	LockMovement: boolean?,
	FailOnMovement: boolean?,
	AllowClose: boolean?,
	Theme: CaptchaTheme?,
	OnShown: ((Player, string) -> ())?,
	OnSolved: ((Player, string, string) -> ())?,
	OnFailed: ((Player, string, string?) -> ())?,
	OnTampered: ((Player, string, string) -> ())?,
	OnClosed: ((Player, string) -> ())?,
	OnTimeout: ((Player, string) -> ())?,
	OnMoveWhileLocked: ((Player, string) -> ())?,
}

type ActiveChallenge = {
	Id: string,
	Answer: string,
	Attempts: number,
	MaxAttempts: number,
	ExpiresAt: number,
	LockMovement: boolean,
	FailOnMovement: boolean,
	AllowClose: boolean,
	Options: CaptchaOptions,
}

type ServerState = {
	Transport: TransportModule,
	ActiveChallengesByPlayer: {[Player]: ActiveChallenge},
}

type ClientActiveChallenge = {
	Id: string,
	Title: string,
	Prompt: string,
	DisplayCode: string,
	MaxAttempts: number,
	RemainingAttempts: number,
	TimeoutSeconds: number,
	LockMovement: boolean,
	AllowClose: boolean,
	Theme: CaptchaTheme?,
	Feedback: string?,
	FeedbackIsError: boolean,
	ScreenGui: ScreenGui,
	RootFrameRef: {current: Frame?},
	ReactRoot: any,
	Connections: {RBXScriptConnection},
	RestoreHumanoidState: {WalkSpeed: number, JumpPower: number, JumpHeight: number, AutoRotate: boolean}?,
	TamperReported: boolean,
}

type ClientState = {
	Transport: TransportModule,
	ActiveChallenge: ClientActiveChallenge?,
}

local Event = RoactCompat.Event
local Change = RoactCompat.Change
local e = React.createElement

local Robots = {}
Robots.__index = Robots

local serverState: ServerState? = nil
local clientState: ClientState? = nil

local function encodePacket(payload: {[string]: any}): string
	return MESSAGE_PREFIX .. HttpService:JSONEncode(payload)
end

local function decodePacket(payload: buffer): {[string]: any}?
	local decodedString = buffer.tostring(payload)
	if string.sub(decodedString, 1, #MESSAGE_PREFIX) ~= MESSAGE_PREFIX then
		return nil
	end

	local rawJson = string.sub(decodedString, #MESSAGE_PREFIX + 1)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawJson)
	end)

	if not ok or type(decoded) ~= "table" then
		return nil
	end

	return decoded
end

local function randomCaptchaCode(length: number): string
	return string.upper(CSPRNG.RandomHex(length))
end

local function parseHexColor(value: string?, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end

	local hex = value:gsub("#", "")
	if #hex ~= 6 then
		return fallback
	end

	local red = tonumber(string.sub(hex, 1, 2), 16)
	local green = tonumber(string.sub(hex, 3, 4), 16)
	local blue = tonumber(string.sub(hex, 5, 6), 16)

	if not red or not green or not blue then
		return fallback
	end

	return Color3.fromRGB(red, green, blue)
end

local function sendServerPacket(player: Player, payload: {[string]: any})
	assert(serverState, "Robots server state is not initialized")
	serverState.Transport:SendToClient(player, encodePacket(payload))
end

local function sendClientPacket(payload: {[string]: any})
	assert(clientState, "Robots client state is not initialized")
	clientState.Transport:SendToServer(encodePacket(payload))
end

local function resolveHumanoid()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local character = localPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function restoreMovement(active: ClientActiveChallenge)
	local humanoid = resolveHumanoid()
	if humanoid and active.RestoreHumanoidState then
		humanoid.WalkSpeed = active.RestoreHumanoidState.WalkSpeed
		humanoid.JumpPower = active.RestoreHumanoidState.JumpPower
		humanoid.JumpHeight = active.RestoreHumanoidState.JumpHeight
		humanoid.AutoRotate = active.RestoreHumanoidState.AutoRotate
	end

	active.RestoreHumanoidState = nil
end

local function applyMovementLock(active: ClientActiveChallenge)
	if not active.LockMovement then
		return
	end

	local humanoid = resolveHumanoid()
	if not humanoid then
		return
	end

	active.RestoreHumanoidState = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
end

local function reportTamper(active: ClientActiveChallenge, reason: string)
	if active.TamperReported then
		return
	end

	active.TamperReported = true
	sendClientPacket({
		Action = "tamper",
		ChallengeId = active.Id,
		Reason = reason,
	})
end

local function unmountActiveChallenge(silent: boolean?)
	if not clientState then
		return
	end

	local active = clientState.ActiveChallenge
	if not active then
		return
	end

	clientState.ActiveChallenge = nil

	for _, connection in active.Connections do
		connection:Disconnect()
	end

	restoreMovement(active)

	active.ReactRoot:unmount()
	active.ScreenGui:Destroy()

	if not silent then
		active.Connections = {}
	end
end

local function CaptchaApp(props)
	local input, setInput = React.useState("")

	React.useEffect(function()
		setInput("")
	end, {props.ChallengeId})

	local theme = props.Theme or {}
	local overlayColor = parseHexColor(theme.OverlayColor, Color3.fromRGB(15, 23, 42))
	local cardColor = parseHexColor(theme.CardColor, Color3.fromRGB(255, 255, 255))
	local accentColor = parseHexColor(theme.AccentColor, Color3.fromRGB(16, 185, 129))
	local textColor = parseHexColor(theme.TextColor, Color3.fromRGB(15, 23, 42))
	local mutedTextColor = parseHexColor(theme.MutedTextColor, Color3.fromRGB(100, 116, 139))
	local errorColor = parseHexColor(theme.ErrorColor, Color3.fromRGB(220, 38, 38))

	return e("Frame", {
		ref = props.RootFrameRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 320),
		BackgroundColor3 = cardColor,
		BorderSizePixel = 0,
	}, {
		UICorner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 22),
			Size = UDim2.new(1, -56, 0, 32),
			Font = Enum.Font.GothamBold,
			Text = props.Title,
			TextColor3 = textColor,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Prompt = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 62),
			Size = UDim2.new(1, -56, 0, 44),
			Font = Enum.Font.Gotham,
			Text = props.Prompt,
			TextWrapped = true,
			TextColor3 = mutedTextColor,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		CodeCard = e("Frame", {
			Position = UDim2.fromOffset(28, 118),
			Size = UDim2.new(1, -56, 0, 56),
			BackgroundColor3 = overlayColor,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			CodeText = e("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.RobotoMono,
				Text = props.DisplayCode,
				TextColor3 = accentColor,
				TextSize = 28,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		}),
		Input = e("TextBox", {
			Position = UDim2.fromOffset(28, 190),
			Size = UDim2.new(1, -156, 0, 48),
			BackgroundColor3 = Color3.fromRGB(248, 250, 252),
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			PlaceholderText = "Enter the code above",
			Text = input,
			TextColor3 = textColor,
			TextSize = 18,
			ClearTextOnFocus = false,
			[Change.Text] = function(textBox)
				setInput(string.upper(textBox.Text))
			end,
			[Event.FocusLost] = function(_, enterPressed)
				if enterPressed and #input > 0 then
					props.OnSubmit(input)
				end
			end,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			UIPadding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			}),
		}),
		Submit = e("TextButton", {
			Position = UDim2.new(1, -116, 0, 190),
			Size = UDim2.fromOffset(88, 48),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = "Submit",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 18,
			AutoButtonColor = true,
			[Event.Activated] = function()
				if #input > 0 then
					props.OnSubmit(input)
				end
			end,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		}),
		Status = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 250),
			Size = UDim2.new(1, -56, 0, 24),
			Font = Enum.Font.Gotham,
			Text = string.format("Attempts remaining: %d", props.RemainingAttempts),
			TextColor3 = mutedTextColor,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Feedback = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 274),
			Size = UDim2.new(1, -56, 0, 24),
			Font = Enum.Font.Gotham,
			Text = props.Feedback or "",
			TextColor3 = if props.FeedbackIsError then errorColor else accentColor,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Close = if props.AllowClose then e("TextButton", {
			Position = UDim2.new(1, -52, 0, 18),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = Color3.fromRGB(241, 245, 249),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = "X",
			TextColor3 = mutedTextColor,
			TextSize = 18,
			[Event.Activated] = function()
				props.OnClose()
			end,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}) else nil,
	})
end

local function renderActiveChallenge(active: ClientActiveChallenge)
	active.ReactRoot:render(e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = parseHexColor(active.Theme and active.Theme.OverlayColor, Color3.fromRGB(15, 23, 42)),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Card = e(CaptchaApp, {
			ChallengeId = active.Id,
			Title = active.Title,
			Prompt = active.Prompt,
			DisplayCode = active.DisplayCode,
			RemainingAttempts = active.RemainingAttempts,
			AllowClose = active.AllowClose,
			Feedback = active.Feedback,
			FeedbackIsError = active.FeedbackIsError,
			Theme = active.Theme,
			RootFrameRef = active.RootFrameRef,
			OnSubmit = function(input: string)
				sendClientPacket({
					Action = "submit",
					ChallengeId = active.Id,
					Response = string.upper(input),
				})
			end,
			OnClose = function()
				sendClientPacket({
					Action = "closed",
					ChallengeId = active.Id,
				})
			end,
		}),
	}))
end

local function mountChallenge(packet: {[string]: any})
	assert(clientState, "Robots client state is not initialized")

	unmountActiveChallenge(true)

	local localPlayer = Players.LocalPlayer
	assert(localPlayer, "LocalPlayer is required for Robots client state")

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local active: ClientActiveChallenge = {
		Id = packet.ChallengeId,
		Title = packet.Title,
		Prompt = packet.Prompt,
		DisplayCode = packet.DisplayCode,
		MaxAttempts = packet.MaxAttempts,
		RemainingAttempts = packet.MaxAttempts,
		TimeoutSeconds = packet.TimeoutSeconds,
		LockMovement = packet.LockMovement == true,
		AllowClose = packet.AllowClose == true,
		Theme = packet.Theme,
		Feedback = nil,
		FeedbackIsError = false,
		ScreenGui = screenGui,
		RootFrameRef = React.createRef(),
		ReactRoot = ReactRoblox.createRoot(screenGui),
		Connections = {},
		RestoreHumanoidState = nil,
		TamperReported = false,
	}

	clientState.ActiveChallenge = active
	renderActiveChallenge(active)
	applyMovementLock(active)

	table.insert(active.Connections, screenGui.AncestryChanged:Connect(function()
		if screenGui.Parent == nil or not screenGui:IsDescendantOf(playerGui) then
			reportTamper(active, "gui_removed")
		end
	end))

	table.insert(active.Connections, screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screenGui.Enabled == false then
			reportTamper(active, "gui_disabled")
		end
	end))

	table.insert(active.Connections, RunService.Heartbeat:Connect(function()
		local current = clientState and clientState.ActiveChallenge
		if current ~= active then
			return
		end

		local frame = active.RootFrameRef.current
		if not frame then
			return
		end

		if frame.Visible == false then
			reportTamper(active, "frame_hidden")
			return
		end

		if frame.AbsoluteSize.X < 250 or frame.AbsoluteSize.Y < 180 then
			reportTamper(active, "frame_obscured")
		end
	end))

	sendClientPacket({
		Action = "shown",
		ChallengeId = active.Id,
	})
end

local function sendFeedback(challenge: ActiveChallenge, player: Player, feedback: string, isError: boolean)
	sendServerPacket(player, {
		Action = "feedback",
		ChallengeId = challenge.Id,
		Feedback = feedback,
		FeedbackIsError = isError,
		RemainingAttempts = challenge.MaxAttempts - challenge.Attempts,
	})
end

local function dismissChallenge(player: Player, challenge: ActiveChallenge, reason: string)
	sendServerPacket(player, {
		Action = "dismiss",
		ChallengeId = challenge.Id,
		Reason = reason,
	})
end

local function failChallenge(player: Player, challenge: ActiveChallenge, reason: string, detail: string?)
	assert(serverState, "Robots server state is not initialized")

	if serverState.ActiveChallengesByPlayer[player] ~= challenge then
		return
	end

	serverState.ActiveChallengesByPlayer[player] = nil
	dismissChallenge(player, challenge, reason)

	if reason == "tampered" and challenge.Options.OnTampered then
		challenge.Options.OnTampered(player, challenge.Id, detail or reason)
	end

	if reason == "closed" and challenge.Options.OnClosed then
		challenge.Options.OnClosed(player, challenge.Id)
	end

	if reason == "timeout" and challenge.Options.OnTimeout then
		challenge.Options.OnTimeout(player, challenge.Id)
	end

	if reason == "move_while_locked" and challenge.Options.OnMoveWhileLocked then
		challenge.Options.OnMoveWhileLocked(player, challenge.Id)
	end

	if challenge.Options.OnFailed then
		challenge.Options.OnFailed(player, challenge.Id, reason)
	end
end

local function startMovementMonitor(player: Player, challenge: ActiveChallenge)
	if not challenge.LockMovement then
		return
	end

	task.spawn(function()
		local rootPart: BasePart? = nil
		local lastPosition: Vector3? = nil

		while serverState and serverState.ActiveChallengesByPlayer[player] == challenge do
			local character = player.Character
			if character then
				rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rootPart then
					local currentPosition = rootPart.Position
					if lastPosition and (currentPosition - lastPosition).Magnitude > 1.5 then
						if challenge.FailOnMovement then
							failChallenge(player, challenge, "move_while_locked")
							return
						elseif challenge.Options.OnMoveWhileLocked then
							challenge.Options.OnMoveWhileLocked(player, challenge.Id)
						end
					end
					lastPosition = currentPosition
				end
			end

			task.wait(0.25)
		end
	end)
end

local function handleServerPacket(player: Player, packet: {[string]: any}): boolean
	assert(serverState, "Robots server state is not initialized")

	local challenge = serverState.ActiveChallengesByPlayer[player]
	if not challenge or packet.ChallengeId ~= challenge.Id then
		return true
	end

	local action = packet.Action
	if action == "shown" then
		if challenge.Options.OnShown then
			challenge.Options.OnShown(player, challenge.Id)
		end
		return true
	end

	if action == "tamper" then
		failChallenge(player, challenge, "tampered", tostring(packet.Reason or "unknown"))
		return true
	end

	if action == "closed" then
		failChallenge(player, challenge, "closed")
		return true
	end

	if action == "submit" then
		local response = tostring(packet.Response or "")
		if response == challenge.Answer then
			serverState.ActiveChallengesByPlayer[player] = nil
			dismissChallenge(player, challenge, "solved")
			if challenge.Options.OnSolved then
				challenge.Options.OnSolved(player, challenge.Id, response)
			end
		else
			challenge.Attempts += 1
			if challenge.Attempts >= challenge.MaxAttempts then
				failChallenge(player, challenge, "attempts_exhausted")
			else
				sendFeedback(challenge, player, "That code was incorrect. Please try again.", true)
			end
		end
		return true
	end

	return true
end

local function handleClientPacket(packet: {[string]: any}): boolean
	assert(clientState, "Robots client state is not initialized")

	local action = packet.Action
	if action == "show" then
		mountChallenge(packet)
		return true
	end

	local active = clientState.ActiveChallenge
	if not active or packet.ChallengeId ~= active.Id then
		return true
	end

	if action == "feedback" then
		active.Feedback = tostring(packet.Feedback or "")
		active.FeedbackIsError = packet.FeedbackIsError == true
		active.RemainingAttempts = tonumber(packet.RemainingAttempts) or active.RemainingAttempts
		renderActiveChallenge(active)
		return true
	end

	if action == "dismiss" then
		unmountActiveChallenge(true)
		return true
	end

	return true
end

function Robots:Initialize(config: {Transport: TransportModule?}?)
	local transportModule = if config and config.Transport then config.Transport else Transport

	if RunService:IsServer() then
		if serverState then
			return
		end

		serverState = {
			Transport = transportModule,
			ActiveChallengesByPlayer = {},
		}

		transportModule:AddServerMessageListener(TRANSPORT_LISTENER_ID, function(player: Player, plaintext: buffer)
			local packet = decodePacket(plaintext)
			if not packet then
				return false
			end

			return handleServerPacket(player, packet)
		end)

		Players.PlayerRemoving:Connect(function(player)
			if serverState then
				serverState.ActiveChallengesByPlayer[player] = nil
			end
		end)

		return
	end

	if clientState then
		return
	end

	clientState = {
		Transport = transportModule,
		ActiveChallenge = nil,
	}

	transportModule:AddClientMessageListener(TRANSPORT_LISTENER_ID, function(plaintext: buffer)
		local packet = decodePacket(plaintext)
		if not packet then
			return false
		end

		return handleClientPacket(packet)
	end)
end

function Robots:SummonCaptcha(player: Player, options: CaptchaOptions?): string
	assert(RunService:IsServer(), "SummonCaptcha can only be called on the server")
	assert(serverState, "Robots:Initialize must be called on the server first")

	local existing = serverState.ActiveChallengesByPlayer[player]
	if existing then
		failChallenge(player, existing, "replaced")
	end

	local challengeId = HttpService:GenerateGUID(false)
	local codeLength = math.max(4, options and options.CodeLength or DEFAULT_CODE_LENGTH)
	local timeoutSeconds = math.max(10, options and options.TimeoutSeconds or DEFAULT_TIMEOUT_SECONDS)
	local challenge: ActiveChallenge = {
		Id = challengeId,
		Answer = randomCaptchaCode(codeLength),
		Attempts = 0,
		MaxAttempts = math.max(1, options and options.MaxAttempts or DEFAULT_MAX_ATTEMPTS),
		ExpiresAt = os.clock() + timeoutSeconds,
		LockMovement = if options and options.LockMovement == false then false else options ~= nil and options.LockMovement == true,
		FailOnMovement = if options and options.FailOnMovement ~= nil then options.FailOnMovement else true,
		AllowClose = if options and options.AllowClose ~= nil then options.AllowClose else false,
		Options = options or {},
	}

	serverState.ActiveChallengesByPlayer[player] = challenge

	sendServerPacket(player, {
		Action = "show",
		ChallengeId = challenge.Id,
		Title = if options and options.Title then options.Title else "Verification Required",
		Prompt = if options and options.Prompt then options.Prompt else "Enter the verification code below to continue.",
		DisplayCode = challenge.Answer,
		MaxAttempts = challenge.MaxAttempts,
		TimeoutSeconds = timeoutSeconds,
		LockMovement = challenge.LockMovement,
		AllowClose = challenge.AllowClose,
		Theme = if options then options.Theme else nil,
	})

	startMovementMonitor(player, challenge)

	task.delay(timeoutSeconds, function()
		if serverState and serverState.ActiveChallengesByPlayer[player] == challenge then
			failChallenge(player, challenge, "timeout")
		end
	end)

	return challenge.Id
end

function Robots:DismissCaptcha(player: Player, reason: string?)
	assert(RunService:IsServer(), "DismissCaptcha can only be called on the server")
	assert(serverState, "Robots:Initialize must be called on the server first")

	local challenge = serverState.ActiveChallengesByPlayer[player]
	if not challenge then
		return
	end

	serverState.ActiveChallengesByPlayer[player] = nil
	dismissChallenge(player, challenge, reason or "dismissed")
end

function Robots:GetActiveCaptcha(player: Player): string?
	assert(RunService:IsServer(), "GetActiveCaptcha can only be called on the server")
	assert(serverState, "Robots:Initialize must be called on the server first")

	local challenge = serverState.ActiveChallengesByPlayer[player]
	return if challenge then challenge.Id else nil
end

return Robots
