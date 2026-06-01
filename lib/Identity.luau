--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DefaultTransport = require(script.Parent.Transport)

local REMOTE_FOLDER_NAME = "TrustSDKIdentityRemotes"
local SYNC_EVENT_NAME = "IdentitySync"
local SNAPSHOT_FUNCTION_NAME = "GetIdentitySnapshot"
local TOKEN_REFRESH_INTERVAL_SECONDS = 300
local REQUEST_TIMEOUT_SECONDS = 15
local TRANSPORT_SNAPSHOT_TIMEOUT_SECONDS = 15
local TRANSPORT_LISTENER_ID = "TrustSDK.Identity"
local TRANSPORT_MESSAGE_PREFIX = "__TrustSDK_Identity__:"
local PLAYER_IDENTITY_CAPABILITY = "PlayerIdentity"
local PLAYER_STORAGE_CAPABILITY = "PlayerStorage"

export type RobloxIdentity = {
	UserId: number,
	Username: string,
	DisplayName: string,
	AccountAge: number,
	MembershipType: string,
	HasVerifiedBadge: boolean?,
	Team: string?,
	LocaleId: string?,
	PlaceId: number,
	GameId: string,
	JobId: string,
}

export type PlayerIdentity = {
	PlayerIdentityId: string?,
	PublicKey: string,
	SessionToken: string,
	SessionExpiresAt: number?,
	IsNewRegistration: boolean,
	RobloxIdentity: RobloxIdentity,
	LastUpdatedAt: number,
}

export type IdentityServerResponse = {
	PlayerIdentityId: string?,
	PublicKey: string,
	SessionToken: string,
	SessionExpiresAt: number?,
	ExpiresInSeconds: number?,
	IsNewRegistration: boolean?,
}

export type IdentityServerCapabilitiesResponse = {
	Capabilities: {string}?,
	capabilities: {string}?,
}

export type PlayerStorageItem = {
	Key: string,
	Value: any,
	GameId: number,
	JobId: string,
	CreatedAt: number,
	UpdatedAt: number,
}

export type PlayerStorageKeysResponse = {
	Keys: {string},
}

export type RequestOptions = {
	Url: string,
	Method: string,
	Headers: {[string]: string},
	Body: string,
}

export type RequestAsync = (request: RequestOptions) -> (boolean, string)
export type TransportModule = {
	AddServerMessageListener: (self: any, listenerId: string, listener: (Player, buffer) -> boolean?) -> (),
	RemoveServerMessageListener: (self: any, listenerId: string) -> (),
	AddClientMessageListener: (self: any, listenerId: string, listener: (buffer) -> boolean?) -> (),
	RemoveClientMessageListener: (self: any, listenerId: string) -> (),
	SendToClient: (self: any, player: Player, payload: buffer | string) -> (),
	SendToServer: (self: any, payload: buffer | string) -> (),
}

export type ServerConfig = {
	IdentityServerUrl: string,
	CapabilitiesEndpointPath: string?,
	SessionEndpointPath: string?,
	RefreshEndpointPath: string?,
	PlayerStorageEndpointPath: string?,
	Transport: TransportModule?,
	UseTransport: boolean?,
	RemoteParent: Instance?,
	DefaultHeaders: {[string]: string}?,
	SessionRefreshIntervalSeconds: number?,
	RequestTimeoutSeconds: number?,
	RequestAsync: RequestAsync?,
	OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?,
	OnIdentityFailed: ((Player, string) -> ())?,
}

export type ClientConfig = {
	Transport: TransportModule?,
	UseTransport: boolean?,
	RemoteParent: Instance?,
	OnIdentityUpdated: ((PlayerIdentity) -> ())?,
}

type IdentityRecord = {
	PublicKey: string,
	SessionToken: string,
	PlayerIdentityId: string?,
	SessionExpiresAt: number?,
	IsNewRegistration: boolean,
	LastUpdatedAt: number,
	RobloxIdentity: RobloxIdentity,
}

type ServerState = {
	RemoteFolder: Folder?,
	SyncEvent: RemoteEvent?,
	SnapshotFunction: RemoteFunction?,
	Transport: TransportModule?,
	UseTransport: boolean,
	IdentityServerUrl: string,
	CapabilitiesEndpointPath: string,
	SessionEndpointPath: string,
	RefreshEndpointPath: string,
	PlayerStorageEndpointPath: string,
	DefaultHeaders: {[string]: string},
	SessionRefreshIntervalSeconds: number,
	RequestTimeoutSeconds: number,
	RequestAsync: RequestAsync,
	CapabilitySet: {[string]: boolean},
	IdentitiesByPlayer: {[Player]: IdentityRecord},
	RefreshGenerationByPlayer: {[Player]: number},
	OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?,
	OnIdentityFailed: ((Player, string) -> ())?,
}

type ClientState = {
	RemoteFolder: Folder?,
	SyncEvent: RemoteEvent?,
	SnapshotFunction: RemoteFunction?,
	Transport: TransportModule?,
	UseTransport: boolean,
	LocalIdentity: PlayerIdentity?,
	IdentityListeners: {[string]: (PlayerIdentity) -> boolean?},
	OnIdentityUpdated: ((PlayerIdentity) -> ())?,
}

local Identity = {}
Identity.__index = Identity

local serverState: ServerState? = nil
local clientState: ClientState? = nil

local function getRemoteParent(config: {RemoteParent: Instance?}?): Instance
	return if config and config.RemoteParent then config.RemoteParent else ReplicatedStorage
end

local function getOrCreateRemoteFolder(parent: Instance): Folder
	local existing = parent:FindFirstChild(REMOTE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTE_FOLDER_NAME
	folder.Parent = parent
	return folder
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getRemoteFolder(parent: Instance): Folder
	local folder = if RunService:IsClient()
		then parent:WaitForChild(REMOTE_FOLDER_NAME, REQUEST_TIMEOUT_SECONDS)
		else parent:FindFirstChild(REMOTE_FOLDER_NAME)
	assert(folder and folder:IsA("Folder"), string.format("Expected %s folder under %s", REMOTE_FOLDER_NAME, parent:GetFullName()))
	return folder
end

local function getRemoteEvent(parent: Instance, name: string): RemoteEvent
	local remote = if RunService:IsClient()
		then parent:WaitForChild(name, REQUEST_TIMEOUT_SECONDS)
		else parent:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteEvent"), string.format("Expected RemoteEvent %s", name))
	return remote
end

local function getRemoteFunction(parent: Instance, name: string): RemoteFunction
	local remote = if RunService:IsClient()
		then parent:WaitForChild(name, REQUEST_TIMEOUT_SECONDS)
		else parent:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteFunction"), string.format("Expected RemoteFunction %s", name))
	return remote
end

local function cloneRobloxIdentity(identity: RobloxIdentity): RobloxIdentity
	return table.clone(identity) :: RobloxIdentity
end

local function clonePlayerIdentityValue(identity: PlayerIdentity): PlayerIdentity
	return {
		PlayerIdentityId = identity.PlayerIdentityId,
		PublicKey = identity.PublicKey,
		SessionToken = identity.SessionToken,
		SessionExpiresAt = identity.SessionExpiresAt,
		IsNewRegistration = identity.IsNewRegistration,
		RobloxIdentity = cloneRobloxIdentity(identity.RobloxIdentity),
		LastUpdatedAt = identity.LastUpdatedAt,
	}
end

local function clonePlayerIdentity(record: IdentityRecord): PlayerIdentity
	return {
		PlayerIdentityId = record.PlayerIdentityId,
		PublicKey = record.PublicKey,
		SessionToken = record.SessionToken,
		SessionExpiresAt = record.SessionExpiresAt,
		IsNewRegistration = record.IsNewRegistration,
		RobloxIdentity = cloneRobloxIdentity(record.RobloxIdentity),
		LastUpdatedAt = record.LastUpdatedAt,
	}
end

local function encodeTransportPacket(payload: {[string]: any}): string
	return TRANSPORT_MESSAGE_PREFIX .. HttpService:JSONEncode(payload)
end

local function decodeTransportPacket(payload: buffer): {[string]: any}?
	local decodedString = buffer.tostring(payload)
	if string.sub(decodedString, 1, #TRANSPORT_MESSAGE_PREFIX) ~= TRANSPORT_MESSAGE_PREFIX then
		return nil
	end

	local rawJson = string.sub(decodedString, #TRANSPORT_MESSAGE_PREFIX + 1)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawJson)
	end)

	if not ok or type(decoded) ~= "table" then
		return nil
	end

	return decoded
end

local function notifyClientListeners(state: ClientState, identity: PlayerIdentity)
	local handled = false
	for _, listener in state.IdentityListeners do
		if listener(identity) == true then
			handled = true
		end
	end

	if not handled and state.OnIdentityUpdated then
		state.OnIdentityUpdated(identity)
	end
end

local function resolveTransportModule(config: {Transport: TransportModule?, UseTransport: boolean?}?): (TransportModule?, boolean)
	local transportModule = if config and config.Transport then config.Transport else DefaultTransport
	local useTransport = if config and config.UseTransport == true then true else false
	return transportModule, useTransport
end

local function getMembershipTypeName(player: Player): string
	local membership = tostring(player.MembershipType)
	local split = string.split(membership, ".")
	return split[#split] or membership
end

local function collectRobloxIdentity(player: Player): RobloxIdentity
	local teamName: string? = nil
	if player.Team then
		teamName = player.Team.Name
	end

	local hasVerifiedBadge: boolean? = nil
	local success, result = pcall(function()
		return (player :: any).HasVerifiedBadge
	end)
	if success and type(result) == "boolean" then
		hasVerifiedBadge = result
	end

	local localeId: string? = nil
	local localeSuccess, localeResult = pcall(function()
		return (player :: any).LocaleId
	end)
	if localeSuccess and type(localeResult) == "string" then
		localeId = localeResult
	end

	return {
		UserId = player.UserId,
		Username = player.Name,
		DisplayName = player.DisplayName,
		AccountAge = player.AccountAge,
		MembershipType = getMembershipTypeName(player),
		HasVerifiedBadge = hasVerifiedBadge,
		Team = teamName,
		LocaleId = localeId,
		PlaceId = game.PlaceId,
		GameId = tostring(game.GameId),
		JobId = game.JobId,
	}
end

local function buildUrl(baseUrl: string, path: string): string
	local trimmedBase = string.gsub(baseUrl, "/+$", "")
	local trimmedPath = if string.sub(path, 1, 1) == "/" then path else "/" .. path
	return trimmedBase .. trimmedPath
end

local function defaultRequestAsync(request: RequestOptions): (boolean, string)
	local response = HttpService:RequestAsync({
		Url = request.Url,
		Method = request.Method,
		Headers = request.Headers,
		Body = request.Body,
	})

	if not response.Success then
		local detail = response.StatusMessage
		if type(response.Body) == "string" and response.Body ~= "" then
			detail = string.format("%s (%s)", response.StatusMessage, response.Body)
		end
		return false, detail
	end

	return true, response.Body
end

local function decodeIdentityServerResponse(rawBody: string): IdentityServerResponse
	local decoded = HttpService:JSONDecode(rawBody)
	assert(type(decoded) == "table", "IdentityServer response must be a JSON object")
	assert(type(decoded.PublicKey) == "string" and decoded.PublicKey ~= "", "IdentityServer response missing PublicKey")
	assert(type(decoded.SessionToken) == "string" and decoded.SessionToken ~= "", "IdentityServer response missing SessionToken")

	return decoded :: IdentityServerResponse
end

local function decodeCapabilitiesResponse(rawBody: string): {[string]: boolean}
	local decoded = HttpService:JSONDecode(rawBody)
	assert(type(decoded) == "table", "IdentityServer capabilities response must be a JSON object")

	local list = (decoded :: IdentityServerCapabilitiesResponse).Capabilities or (decoded :: IdentityServerCapabilitiesResponse).capabilities
	assert(type(list) == "table", "IdentityServer capabilities response missing Capabilities array")

	local capabilitySet = {}
	for _, capability in list do
		assert(type(capability) == "string", "IdentityServer capability entries must be strings")
		capabilitySet[capability] = true
	end

	return capabilitySet
end

local function decodePlayerStorageItem(rawBody: string): PlayerStorageItem?
	local decoded = HttpService:JSONDecode(rawBody)
	if decoded == nil then
		return nil
	end

	assert(type(decoded) == "table", "PlayerStorage response must be a JSON object")
	assert(type(decoded.Key) == "string" and decoded.Key ~= "", "PlayerStorage response missing Key")
	assert(decoded.Value ~= nil, "PlayerStorage response missing Value")
	assert(type(decoded.GameId) == "number", "PlayerStorage response missing GameId")
	assert(type(decoded.JobId) == "string", "PlayerStorage response missing JobId")
	assert(type(decoded.CreatedAt) == "number", "PlayerStorage response missing CreatedAt")
	assert(type(decoded.UpdatedAt) == "number", "PlayerStorage response missing UpdatedAt")

	return decoded :: PlayerStorageItem
end

local function decodePlayerStorageKeys(rawBody: string): {string}
	local decoded = HttpService:JSONDecode(rawBody)
	assert(type(decoded) == "table", "PlayerStorage keys response must be a JSON object")
	assert(type(decoded.Keys) == "table", "PlayerStorage keys response missing Keys")

	local keys = {}
	for _, key in decoded.Keys do
		assert(type(key) == "string", "PlayerStorage key entries must be strings")
		table.insert(keys, key)
	end

	return keys
end

local function requestJson(state: ServerState, method: string, endpointPath: string, bodyTable: {[string]: any}?, extraHeaders: {[string]: string}?): string
	local headers = table.clone(state.DefaultHeaders)
	if extraHeaders then
		for key, value in extraHeaders do
			headers[key] = value
		end
	end

	local body = ""
	if bodyTable ~= nil then
		headers["Content-Type"] = "application/json"
		body = HttpService:JSONEncode(bodyTable)
	end

	local success, responseOrError = state.RequestAsync({
		Url = buildUrl(state.IdentityServerUrl, endpointPath),
		Method = method,
		Headers = headers,
		Body = body,
	})

	assert(success, string.format("IdentityServer request failed: %s", tostring(responseOrError)))
	return responseOrError
end

local function requestCapabilities(state: ServerState): {[string]: boolean}
	local rawBody = requestJson(state, "GET", state.CapabilitiesEndpointPath, nil, nil)
	return decodeCapabilitiesResponse(rawBody)
end

local function ensureCapability(state: ServerState, capabilityName: string)
	assert(state.CapabilitySet[capabilityName] == true, string.format("IdentityServer does not advertise capability %q", capabilityName))
end

local function requestIdentityFromServer(state: ServerState, player: Player, endpointPath: string): IdentityRecord
	local robloxIdentity = collectRobloxIdentity(player)
	local payload = {
		robloxIdentity = robloxIdentity,
	}
	local response = decodeIdentityServerResponse(requestJson(state, "POST", endpointPath, payload, nil))
	local now = os.time()
	local expiresAt = response.SessionExpiresAt
	if expiresAt == nil and type(response.ExpiresInSeconds) == "number" then
		expiresAt = now + response.ExpiresInSeconds
	end

	return {
		PublicKey = response.PublicKey,
		SessionToken = response.SessionToken,
		PlayerIdentityId = response.PlayerIdentityId,
		SessionExpiresAt = expiresAt,
		IsNewRegistration = response.IsNewRegistration == true,
		LastUpdatedAt = now,
		RobloxIdentity = robloxIdentity,
	}
end

local function buildPlayerStorageHeaders(identity: IdentityRecord): {[string]: string}
	return {
		["Authorization"] = string.format("Bearer %s", identity.SessionToken),
		["X-TrustSDK-PlayerIdentityId"] = identity.PlayerIdentityId or "",
	}
end

local function buildPlayerStoragePayload(player: Player, identity: IdentityRecord, value: any?): {[string]: any}
	return {
		Value = value,
		GameId = game.GameId,
		JobId = game.JobId,
		PlayerIdentityId = identity.PlayerIdentityId,
		RobloxIdentity = collectRobloxIdentity(player),
	}
end

local function buildPlayerStorageItemPath(state: ServerState, key: string): string
	return buildUrl(state.PlayerStorageEndpointPath, HttpService:UrlEncode(key))
end

local function requestPlayerStorage(state: ServerState, player: Player, method: string, key: string, value: any?): PlayerStorageItem?
	ensureCapability(state, PLAYER_STORAGE_CAPABILITY)

	local identity = state.IdentitiesByPlayer[player]
	assert(identity, string.format("No Identity session is available for player %s", player.Name))

	local payload = if method == "POST"
		then buildPlayerStoragePayload(player, identity, value)
		else nil
	local rawBody = requestJson(state, method, buildPlayerStorageItemPath(state, key), payload, buildPlayerStorageHeaders(identity))
	if rawBody == "" then
		return nil
	end

	return decodePlayerStorageItem(rawBody)
end

local function requestPlayerStorageKeys(state: ServerState, player: Player): {string}
	ensureCapability(state, PLAYER_STORAGE_CAPABILITY)

	local identity = state.IdentitiesByPlayer[player]
	assert(identity, string.format("No Identity session is available for player %s", player.Name))

	local rawBody = requestJson(state, "GET", buildUrl(state.PlayerStorageEndpointPath, "keys"), nil, buildPlayerStorageHeaders(identity))
	return decodePlayerStorageKeys(rawBody)
end

local function pushIdentityToClient(state: ServerState, player: Player, record: IdentityRecord)
	local clonedIdentity = clonePlayerIdentity(record)
	if state.UseTransport then
		assert(state.Transport, "Identity transport mode requires a Transport module")
		local ok = pcall(function()
			state.Transport:SendToClient(player, encodeTransportPacket({
				Action = "sync",
				Identity = clonedIdentity,
			}))
		end)

		if not ok then
			-- The secure session may not exist yet. The client will request a snapshot once Transport is ready.
		end
		return
	end

	assert(state.SyncEvent, "Identity remote sync event is not initialized")
	state.SyncEvent:FireClient(player, clonedIdentity)
end

local function storeIdentity(state: ServerState, player: Player, record: IdentityRecord)
	state.IdentitiesByPlayer[player] = record
	pushIdentityToClient(state, player, record)

	if state.OnIdentityUpdated then
		state.OnIdentityUpdated(player, clonePlayerIdentity(record))
	end
end

local function syncPlayerIdentity(state: ServerState, player: Player, endpointPath: string)
	local ok, result = pcall(function()
		return requestIdentityFromServer(state, player, endpointPath)
	end)

	if not ok then
		if state.OnIdentityFailed then
			state.OnIdentityFailed(player, tostring(result))
		else
			warn(string.format("[TrustSDK.Identity] %s", tostring(result)))
		end
		return
	end

	storeIdentity(state, player, result :: IdentityRecord)
end

local function startRefreshLoop(state: ServerState, player: Player)
	local nextGeneration = (state.RefreshGenerationByPlayer[player] or 0) + 1
	state.RefreshGenerationByPlayer[player] = nextGeneration

	task.spawn(function()
		while serverState == state and player.Parent == Players and state.RefreshGenerationByPlayer[player] == nextGeneration do
			task.wait(state.SessionRefreshIntervalSeconds)

			if serverState ~= state or player.Parent ~= Players or state.RefreshGenerationByPlayer[player] ~= nextGeneration then
				break
			end

			syncPlayerIdentity(state, player, state.RefreshEndpointPath)
		end
	end)
end

local function buildServerState(config: ServerConfig): ServerState
	assert(type(config.IdentityServerUrl) == "string" and config.IdentityServerUrl ~= "", "IdentityServerUrl is required")
	assert(HttpService.HttpEnabled == true, "Identity.Initialize requires HttpService.HttpEnabled on the server")

	local transportModule, useTransport = resolveTransportModule(config)
	local remoteFolder: Folder? = nil
	local syncEvent: RemoteEvent? = nil
	local snapshotFunction: RemoteFunction? = nil

	if not useTransport then
		local remoteParent = getRemoteParent(config)
		remoteFolder = getOrCreateRemoteFolder(remoteParent)
		syncEvent = getOrCreateRemoteEvent(remoteFolder, SYNC_EVENT_NAME)
		snapshotFunction = getOrCreateRemoteFunction(remoteFolder, SNAPSHOT_FUNCTION_NAME)
	end

	local state: ServerState = {
		RemoteFolder = remoteFolder,
		SyncEvent = syncEvent,
		SnapshotFunction = snapshotFunction,
		Transport = transportModule,
		UseTransport = useTransport,
		IdentityServerUrl = config.IdentityServerUrl,
		CapabilitiesEndpointPath = config.CapabilitiesEndpointPath or "/",
		SessionEndpointPath = config.SessionEndpointPath or "/identity/session",
		RefreshEndpointPath = config.RefreshEndpointPath or "/identity/refresh",
		PlayerStorageEndpointPath = config.PlayerStorageEndpointPath or "/storage",
		DefaultHeaders = table.clone(config.DefaultHeaders or {}),
		SessionRefreshIntervalSeconds = math.max(60, config.SessionRefreshIntervalSeconds or TOKEN_REFRESH_INTERVAL_SECONDS),
		RequestTimeoutSeconds = math.max(1, config.RequestTimeoutSeconds or REQUEST_TIMEOUT_SECONDS),
		RequestAsync = config.RequestAsync or defaultRequestAsync,
		CapabilitySet = {},
		IdentitiesByPlayer = {},
		RefreshGenerationByPlayer = {},
		OnIdentityUpdated = config.OnIdentityUpdated,
		OnIdentityFailed = config.OnIdentityFailed,
	}

	state.CapabilitySet = requestCapabilities(state)
	ensureCapability(state, PLAYER_IDENTITY_CAPABILITY)

	if state.SnapshotFunction then
		state.SnapshotFunction.OnServerInvoke = function(player: Player)
			local record = state.IdentitiesByPlayer[player]
			if record then
				return clonePlayerIdentity(record)
			end

			return nil
		end
	end

	if state.SyncEvent then
		state.SyncEvent.OnServerEvent:Connect(function()
			-- One-way server-to-client channel.
		end)
	end

	if state.UseTransport then
		assert(state.Transport, "Identity transport mode requires a Transport module")
		state.Transport:AddServerMessageListener(TRANSPORT_LISTENER_ID, function(player: Player, plaintext: buffer)
			local packet = decodeTransportPacket(plaintext)
			if not packet then
				return false
			end

			if packet.Action == "request_snapshot" then
				local record = state.IdentitiesByPlayer[player]
				if record then
					pushIdentityToClient(state, player, record)
				end
				return true
			end

			return true
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			syncPlayerIdentity(state, player, state.SessionEndpointPath)
			startRefreshLoop(state, player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		state.IdentitiesByPlayer[player] = nil
		state.RefreshGenerationByPlayer[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			syncPlayerIdentity(state, player, state.SessionEndpointPath)
			startRefreshLoop(state, player)
		end)
	end

	return state
end

local function buildClientState(config: ClientConfig?): ClientState
	local transportModule, useTransport = resolveTransportModule(config)
	local remoteFolder: Folder? = nil
	local syncEvent: RemoteEvent? = nil
	local snapshotFunction: RemoteFunction? = nil

	if not useTransport then
		local remoteParent = getRemoteParent(config)
		remoteFolder = getRemoteFolder(remoteParent)
		syncEvent = getRemoteEvent(remoteFolder, SYNC_EVENT_NAME)
		snapshotFunction = getRemoteFunction(remoteFolder, SNAPSHOT_FUNCTION_NAME)
	end

	local state: ClientState = {
		RemoteFolder = remoteFolder,
		SyncEvent = syncEvent,
		SnapshotFunction = snapshotFunction,
		Transport = transportModule,
		UseTransport = useTransport,
		LocalIdentity = nil,
		IdentityListeners = {},
		OnIdentityUpdated = if config then config.OnIdentityUpdated else nil,
	}

	if state.UseTransport then
		assert(state.Transport, "Identity transport mode requires a Transport module")
		state.Transport:AddClientMessageListener(TRANSPORT_LISTENER_ID, function(plaintext: buffer)
			local packet = decodeTransportPacket(plaintext)
			if not packet then
				return false
			end

			if packet.Action == "sync" and type(packet.Identity) == "table" then
				local clonedIdentity = clonePlayerIdentityValue(packet.Identity :: PlayerIdentity)
				state.LocalIdentity = clonedIdentity
				notifyClientListeners(state, clonePlayerIdentityValue(clonedIdentity))
			end

			return true
		end)

		task.spawn(function()
			local deadline = os.clock() + TRANSPORT_SNAPSHOT_TIMEOUT_SECONDS
			while os.clock() < deadline do
				local ok = pcall(function()
					state.Transport:SendToServer(encodeTransportPacket({
						Action = "request_snapshot",
					}))
				end)

				if ok then
					return
				end

				task.wait(0.25)
			end

			warn("[TrustSDK.Identity] Timed out waiting for Transport handshake before requesting identity snapshot")
		end)
	else
		assert(state.SyncEvent and state.SnapshotFunction, "Identity remote mode is not initialized")

		state.SyncEvent.OnClientEvent:Connect(function(identity: PlayerIdentity)
			if type(identity) ~= "table" then
				return
			end

			local clonedIdentity = clonePlayerIdentityValue(identity)
			state.LocalIdentity = clonedIdentity
			notifyClientListeners(state, clonePlayerIdentityValue(clonedIdentity))
		end)

		local snapshot = state.SnapshotFunction:InvokeServer()
		if type(snapshot) == "table" then
			local clonedSnapshot = clonePlayerIdentityValue(snapshot)
			state.LocalIdentity = clonedSnapshot
			notifyClientListeners(state, clonePlayerIdentityValue(clonedSnapshot))
		end
	end

	return state
end

function Identity:Initialize(config: ServerConfig | ClientConfig?)
	if RunService:IsServer() then
		if serverState then
			return
		end

		assert(type(config) == "table", "Identity.Initialize on the server requires configuration")
		serverState = buildServerState(config :: ServerConfig)
		return
	end

	if clientState then
		return
	end

	clientState = buildClientState(config :: ClientConfig?)
end

function Identity:GetPlayerIdentity(player: Player): PlayerIdentity?
	assert(RunService:IsServer(), "GetPlayerIdentity can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")

	local record = serverState.IdentitiesByPlayer[player]
	if not record then
		return nil
	end

	return clonePlayerIdentity(record)
end

function Identity:GetCapabilities(): {[string]: boolean}
	assert(RunService:IsServer(), "GetCapabilities can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")

	return table.clone(serverState.CapabilitySet)
end

function Identity:HasCapability(capabilityName: string): boolean
	assert(RunService:IsServer(), "HasCapability can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")

	return serverState.CapabilitySet[capabilityName] == true
end

function Identity:GetLocalIdentity(): PlayerIdentity?
	assert(not RunService:IsServer(), "GetLocalIdentity can only be called on the client")
	assert(clientState, "Identity.Initialize must be called on the client first")

	local identity = clientState.LocalIdentity
	return if identity then clonePlayerIdentityValue(identity) else nil
end

function Identity:GetPlayerPublicKey(player: Player): string?
	assert(RunService:IsServer(), "GetPlayerPublicKey can only be called on the server")

	local identity = self:GetPlayerIdentity(player)
	return if identity then identity.PublicKey else nil
end

function Identity:GetLocalPublicKey(): string?
	assert(not RunService:IsServer(), "GetLocalPublicKey can only be called on the client")

	local identity = self:GetLocalIdentity()
	return if identity then identity.PublicKey else nil
end

function Identity:GetPlayerSessionToken(player: Player): string?
	assert(RunService:IsServer(), "GetPlayerSessionToken can only be called on the server")

	local identity = self:GetPlayerIdentity(player)
	return if identity then identity.SessionToken else nil
end

function Identity:GetLocalSessionToken(): string?
	assert(not RunService:IsServer(), "GetLocalSessionToken can only be called on the client")

	local identity = self:GetLocalIdentity()
	return if identity then identity.SessionToken else nil
end

function Identity:RefreshPlayerSession(player: Player)
	assert(RunService:IsServer(), "RefreshPlayerSession can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")

	syncPlayerIdentity(serverState, player, serverState.RefreshEndpointPath)
end

function Identity:GetPlayerStorageItem(player: Player, key: string): PlayerStorageItem?
	assert(RunService:IsServer(), "GetPlayerStorageItem can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")
	assert(type(key) == "string" and key ~= "", "PlayerStorage key must be a non-empty string")

	return requestPlayerStorage(serverState, player, "GET", key, nil)
end

function Identity:GetPlayerStorageKeys(player: Player): {string}
	assert(RunService:IsServer(), "GetPlayerStorageKeys can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")

	return requestPlayerStorageKeys(serverState, player)
end

function Identity:SetPlayerStorageItem(player: Player, key: string, value: any): PlayerStorageItem?
	assert(RunService:IsServer(), "SetPlayerStorageItem can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")
	assert(type(key) == "string" and key ~= "", "PlayerStorage key must be a non-empty string")
	assert(value ~= nil, "PlayerStorage value must not be nil")

	return requestPlayerStorage(serverState, player, "POST", key, value)
end

function Identity:DeletePlayerStorageItem(player: Player, key: string): PlayerStorageItem?
	assert(RunService:IsServer(), "DeletePlayerStorageItem can only be called on the server")
	assert(serverState, "Identity.Initialize must be called on the server first")
	assert(type(key) == "string" and key ~= "", "PlayerStorage key must be a non-empty string")

	return requestPlayerStorage(serverState, player, "DELETE", key, nil)
end

function Identity:AddClientIdentityListener(listenerId: string, listener: (PlayerIdentity) -> boolean?)
	assert(not RunService:IsServer(), "AddClientIdentityListener can only be called on the client")
	assert(clientState, "Identity.Initialize must be called on the client first")

	clientState.IdentityListeners[listenerId] = listener
end

function Identity:RemoveClientIdentityListener(listenerId: string)
	assert(not RunService:IsServer(), "RemoveClientIdentityListener can only be called on the client")
	assert(clientState, "Identity.Initialize must be called on the client first")

	clientState.IdentityListeners[listenerId] = nil
end

return Identity
