--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Identity = TrustSDK("Identity")
local Transport = TrustSDK("Transport")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local RoactCompat = require(ReplicatedStorage.Packages.RoactCompat)

local SCREEN_GUI_NAME = "TrustSDKIdentityTestGui"
local IDENTITY_LISTENER_ID = "TrustSDK.IdentityTest"
local TRANSPORT_LISTENER_ID = "TrustSDK.IdentityTest.Client"
local MESSAGE_PREFIX = "__TrustSDK_IdentityTest__:"
local REQUEST_TIMEOUT_SECONDS = 10
local REQUEST_RETRY_INTERVAL_SECONDS = 0.25

local Event = RoactCompat.Event
local e = React.createElement

local localPlayer = Players.LocalPlayer
assert(localPlayer, "IdentityTest requires LocalPlayer")

print("[TrustSDK Identity Test][Client] Booting identity test client harness")

local pendingRequests: {[string]: {
	Resolve: (any) -> (),
	Reject: (string) -> (),
}} = {}

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

local function initializeIdentityClient()
	local ok, errorMessage = pcall(function()
		Transport:Initialize()
		print("[TrustSDK Identity Test][Client] Transport initialized")
		Identity:Initialize({
			Transport = Transport,
			UseTransport = true,
		})
		print("[TrustSDK Identity Test][Client] Identity initialized in transport mode")
	end)

	if not ok then
		warn("[TrustSDK Identity UI] Failed to initialize Identity client:", errorMessage)
	end
end

initializeIdentityClient()

Transport:AddClientMessageListener(TRANSPORT_LISTENER_ID, function(plaintext: buffer)
	local packet = decodePacket(plaintext)
	if not packet then
		return false
	end

	print(string.format(
		"[TrustSDK Identity Test][Client] Received packet action=%s requestId=%s",
		tostring(packet.Action),
		tostring(packet.RequestId)
	))

	if packet.Action ~= "response" then
		return true
	end

	local requestId = tostring(packet.RequestId or "")
	local pending = pendingRequests[requestId]
	if pending then
		pendingRequests[requestId] = nil
		print(string.format("[TrustSDK Identity Test][Client] Resolving requestId=%s", requestId))
		pending.Resolve(packet.Payload)
	else
		warn(string.format("[TrustSDK Identity Test][Client] No pending request for requestId=%s", requestId))
	end

	return true
end)

local screenGui: ScreenGui? = nil
local reactRoot = nil

type StatusResponse = {
	Ok: boolean,
	Error: string?,
	Capabilities: {string}?,
	HasPlayerStorage: boolean?,
	PlayerIdentity: {
		PlayerIdentityId: string?,
		PublicKey: string,
		SessionExpiresAt: number?,
		IsNewRegistration: boolean,
		LastUpdatedAt: number,
	}?,
}

type StorageTestResponse = {
	Ok: boolean,
	Error: string?,
	TestId: string?,
	Key: string?,
	Written: {[string]: any}?,
	Fetched: {[string]: any}?,
	KeysAfterWrite: {string}?,
	Deleted: {[string]: any}?,
}

local function invokeServer(payload: {[string]: any})
	local requestId = HttpService:GenerateGUID(false)
	print(string.format(
		"[TrustSDK Identity Test][Client] Starting request action=%s requestId=%s",
		tostring(payload.Action),
		requestId
	))

	local bindable = Instance.new("BindableEvent")
	local resolved = false
	local responsePayload = nil

	pendingRequests[requestId] = {
		Resolve = function(response)
			if resolved then
				return
			end

			resolved = true
			responsePayload = response
			print(string.format("[TrustSDK Identity Test][Client] Request resolved requestId=%s ok=%s", requestId, tostring(response and response.Ok)))
			bindable:Fire()
		end,
		Reject = function(errorMessage: string)
			if resolved then
				return
			end

			resolved = true
			responsePayload = {
				Ok = false,
				Error = errorMessage,
			}
			warn(string.format("[TrustSDK Identity Test][Client] Request rejected requestId=%s error=%s", requestId, errorMessage))
			bindable:Fire()
		end,
	}

	task.spawn(function()
		local deadline = os.clock() + REQUEST_TIMEOUT_SECONDS
		local attempt = 0

		while os.clock() < deadline do
			attempt += 1
			local ok, errorMessage = pcall(function()
				Transport:SendToServer(encodePacket({
					Action = payload.Action,
					RequestId = requestId,
				}))
			end)

			if ok then
				print(string.format(
					"[TrustSDK Identity Test][Client] Sent request action=%s requestId=%s attempt=%d",
					tostring(payload.Action),
					requestId,
					attempt
				))
				return
			end

			warn(string.format(
				"[TrustSDK Identity Test][Client] Send attempt failed action=%s requestId=%s attempt=%d error=%s",
				tostring(payload.Action),
				requestId,
				attempt,
				tostring(errorMessage)
			))

			task.wait(REQUEST_RETRY_INTERVAL_SECONDS)
		end

		local pending = pendingRequests[requestId]
		if pending then
			pendingRequests[requestId] = nil
			pending.Reject("Timed out waiting for Transport to become ready for the identity test request")
		end
	end)

	task.delay(REQUEST_TIMEOUT_SECONDS, function()
		local pending = pendingRequests[requestId]
		if pending then
			warn(string.format(
				"[TrustSDK Identity Test][Client] Response wait timeout action=%s requestId=%s",
				tostring(payload.Action),
				requestId
			))
			pendingRequests[requestId] = nil
			pending.Reject("Timed out waiting for identity test response")
		end
	end)

	bindable.Event:Wait()
	bindable:Destroy()

	return responsePayload
end

local function truncate(value: string?, maxLength: number): string
	if type(value) ~= "string" or value == "" then
		return "n/a"
	end

	if #value <= maxLength then
		return value
	end

	return string.sub(value, 1, maxLength) .. "..."
end

local function formatTimestamp(value: number?): string
	if type(value) ~= "number" then
		return "n/a"
	end

	return os.date("!%Y-%m-%d %H:%M:%S", value)
end

local function statusLines(status: StatusResponse?, localIdentity): {string}
	local lines = {}

	if not status then
		table.insert(lines, "Server status: loading...")
	else
		table.insert(lines, "Capabilities: " .. table.concat(status.Capabilities or {}, ", "))
		table.insert(lines, "PlayerStorage: " .. tostring(status.HasPlayerStorage == true))

		if status.PlayerIdentity then
			table.insert(lines, "Server public key: " .. truncate(status.PlayerIdentity.PublicKey, 18))
			table.insert(lines, "Server identity id: " .. truncate(status.PlayerIdentity.PlayerIdentityId, 18))
			table.insert(lines, "Session expires: " .. formatTimestamp(status.PlayerIdentity.SessionExpiresAt))
		end
	end

	if localIdentity then
		table.insert(lines, "Local public key: " .. truncate(localIdentity.PublicKey, 18))
		table.insert(lines, "Local token: " .. truncate(localIdentity.SessionToken, 18))
	end

	return lines
end

local function storageResultLines(result: StorageTestResponse?): {string}
	if not result then
		return {
			"No PlayerStorage test has been run yet.",
		}
	end

	if result.Ok ~= true then
		return {
			"PlayerStorage test failed: " .. tostring(result.Error or "unknown error"),
		}
	end

	local lines = {
		"PlayerStorage test passed.",
		"Key: " .. tostring(result.Key or "n/a"),
	}

	if result.KeysAfterWrite then
		table.insert(lines, "Keys after write: " .. table.concat(result.KeysAfterWrite, ", "))
	end

	local function appendStep(stepName: string, stepValue: {[string]: any}?)
		if not stepValue then
			table.insert(lines, stepName .. ": no payload")
			return
		end

		table.insert(lines, string.format(
			"%s: GameId=%s JobId=%s CreatedAt=%s UpdatedAt=%s",
			stepName,
			tostring(stepValue.GameId),
			tostring(stepValue.JobId),
			formatTimestamp(stepValue.CreatedAt),
			formatTimestamp(stepValue.UpdatedAt)
		))
	end

	appendStep("Written", result.Written)
	appendStep("Fetched", result.Fetched)
	appendStep("Deleted", result.Deleted)

	return lines
end

local function IdentityPanel()
	local localIdentity, setLocalIdentity = React.useState(Identity:GetLocalIdentity())
	local status, setStatus = React.useState(nil :: StatusResponse?)
	local storageResult, setStorageResult = React.useState(nil :: StorageTestResponse?)
	local busy, setBusy = React.useState(false)
	local errorText, setErrorText = React.useState(nil :: string?)

	React.useEffect(function()
		local active = true

		Identity:AddClientIdentityListener(IDENTITY_LISTENER_ID, function(identity)
			if active then
				setLocalIdentity(identity)
			end
			return true
		end)

		task.spawn(function()
			local response = invokeServer({
				Action = "status",
			}) :: StatusResponse

			if not active then
				return
			end

			if response.Ok == true then
				setStatus(response)
				setErrorText(nil)
			else
				setErrorText(tostring(response.Error or "Failed to fetch status"))
			end
		end)

		return function()
			active = false
			Identity:RemoveClientIdentityListener(IDENTITY_LISTENER_ID)
		end
	end, {})

	local function closePanel()
		if reactRoot and screenGui then
			reactRoot:unmount()
			screenGui:Destroy()
			reactRoot = nil
			screenGui = nil
		end
	end

	local function runPlayerStorageTest()
		setBusy(true)
		setErrorText(nil)

		task.spawn(function()
			local response = invokeServer({
				Action = "run_player_storage_test",
			}) :: StorageTestResponse

			setBusy(false)

			if response.Ok == true then
				setStorageResult(response)
			else
				setStorageResult(response)
				setErrorText(tostring(response.Error or "PlayerStorage test failed"))
			end
		end)
	end

	local infoLines = statusLines(status, localIdentity)
	local resultLines = storageResultLines(storageResult)

	local infoChildren = {}
	for index, line in infoLines do
		infoChildren["Info" .. tostring(index)] = e("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = index,
			Font = Enum.Font.Gotham,
			Text = line,
			TextColor3 = Color3.fromRGB(222, 226, 255),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	infoChildren.Layout = e("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local resultChildren = {}
	for index, line in resultLines do
		resultChildren["Result" .. tostring(index)] = e("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = index,
			Font = Enum.Font.Gotham,
			Text = line,
			TextColor3 = Color3.fromRGB(201, 255, 217),
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	resultChildren.Layout = e("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 13, 25),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(640, 470),
			BackgroundColor3 = Color3.fromRGB(15, 23, 42),
			BorderSizePixel = 0,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
			Header = e("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(24, 18),
				Size = UDim2.new(1, -100, 0, 32),
				Font = Enum.Font.GothamBold,
				Text = "Identity Test Console",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Close = e("TextButton", {
				Position = UDim2.new(1, -58, 0, 16),
				Size = UDim2.fromOffset(38, 38),
				BackgroundColor3 = Color3.fromRGB(30, 41, 59),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Text = "X",
				TextColor3 = Color3.fromRGB(226, 232, 240),
				TextSize = 18,
				[Event.Activated] = closePanel,
			}, {
				UICorner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			Instructions = e("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(24, 56),
				Size = UDim2.new(1, -48, 0, 24),
				Font = Enum.Font.Gotham,
				Text = "Open this panel by typing !identity in chat. The identity test UI and PlayerStorage checks use Transport.",
				TextColor3 = Color3.fromRGB(148, 163, 184),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			InfoCard = e("Frame", {
				Position = UDim2.fromOffset(24, 96),
				Size = UDim2.new(1, -48, 0, 144),
				BackgroundColor3 = Color3.fromRGB(30, 41, 59),
				BorderSizePixel = 0,
			}, {
				UICorner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
				}),
				Content = e("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}, infoChildren),
			}),
			RunButton = e("TextButton", {
				Position = UDim2.fromOffset(24, 260),
				Size = UDim2.fromOffset(220, 44),
				BackgroundColor3 = if busy then Color3.fromRGB(71, 85, 105) else Color3.fromRGB(34, 197, 94),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Text = if busy then "Running..." else "Run PlayerStorage Test",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 16,
				AutoButtonColor = not busy,
				[Event.Activated] = function()
					if not busy then
						runPlayerStorageTest()
					end
				end,
			}, {
				UICorner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
			}),
			Error = if errorText then e("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(260, 268),
				Size = UDim2.new(1, -284, 0, 28),
				Font = Enum.Font.Gotham,
				Text = errorText,
				TextColor3 = Color3.fromRGB(248, 113, 113),
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}) else nil,
			ResultCard = e("Frame", {
				Position = UDim2.fromOffset(24, 320),
				Size = UDim2.new(1, -48, 0, 126),
				BackgroundColor3 = Color3.fromRGB(22, 101, 52),
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}, {
				UICorner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
				}),
				Content = e("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}, resultChildren),
			}),
		}),
	})
end

local function openIdentityPanel()
	if screenGui or reactRoot then
		print("[TrustSDK Identity Test][Client] Identity panel already open")
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10050
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	reactRoot = ReactRoblox.createRoot(screenGui)
	reactRoot:render(e(IdentityPanel))
	print("[TrustSDK Identity Test][Client] Identity panel opened")
end

localPlayer.Chatted:Connect(function(message)
	if string.lower(message) == "!identity" then
		print("[TrustSDK Identity Test][Client] Chat trigger received: !identity")
		openIdentityPanel()
	end
end)
