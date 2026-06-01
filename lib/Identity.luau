--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "TrustSDKIdentityRemotes"
local SYNC_EVENT_NAME = "IdentitySync"
local SNAPSHOT_FUNCTION_NAME = "GetIdentitySnapshot"
local TOKEN_REFRESH_INTERVAL_SECONDS = 300
local REQUEST_TIMEOUT_SECONDS = 15

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

export type RequestOptions = {
	Url: string,
	Method: string,
	Headers: {[string]: string},
	Body: string,
}

export type RequestAsync = (request: RequestOptions) -> (boolean, string)

export type ServerConfig = {
	IdentityServerUrl: string,
	SessionEndpointPath: string?,
	RefreshEndpointPath: string?,
	RemoteParent: Instance?,
	DefaultHeaders: {[string]: string}?,
	SessionRefreshIntervalSeconds: number?,
	RequestTimeoutSeconds: number?,
	RequestAsync: RequestAsync?,
	OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?,
	OnIdentityFailed: ((Player, string) -> ())?,
}

export type ClientConfig = {
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
	RemoteFolder: Folder,
	SyncEvent: RemoteEvent,
	SnapshotFunction: RemoteFunction,
	IdentityServerUrl: string,
	SessionEndpointPath: string,
	RefreshEndpointPath: string,
	DefaultHeaders: {[string]: string},
	SessionRefreshIntervalSeconds: number,
	RequestTimeoutSeconds: number,
	RequestAsync: RequestAsync,
	IdentitiesByPlayer: {[Player]: IdentityRecord},
	RefreshGenerationByPlayer: {[Player]: number},
	OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?,
	OnIdentityFailed: ((Player, string) -> ())?,
}

type ClientState = {
	RemoteFolder: Folder,
	SyncEvent: RemoteEvent,
	SnapshotFunction: RemoteFunction,
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

local function requestIdentityFromServer(state: ServerState, player: Player, endpointPath: string): IdentityRecord
	local robloxIdentity = collectRobloxIdentity(player)
	local payload = {
		robloxIdentity = robloxIdentity,
	}

	local headers = table.clone(state.DefaultHeaders)
	headers["Content-Type"] = "application/json"

	local success, responseOrError = state.RequestAsync({
		Url = buildUrl(state.IdentityServerUrl, endpointPath),
		Method = "POST",
		Headers = headers,
		Body = HttpService:JSONEncode(payload),
	})

	assert(success, string.format("IdentityServer request failed: %s", tostring(responseOrError)))

	local response = decodeIdentityServerResponse(responseOrError)
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

local function pushIdentityToClient(state: ServerState, player: Player, record: IdentityRecord)
	state.SyncEvent:FireClient(player, clonePlayerIdentity(record))
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

	local remoteParent = getRemoteParent(config)
	local remoteFolder = getOrCreateRemoteFolder(remoteParent)

	local state: ServerState = {
		RemoteFolder = remoteFolder,
		SyncEvent = getOrCreateRemoteEvent(remoteFolder, SYNC_EVENT_NAME),
		SnapshotFunction = getOrCreateRemoteFunction(remoteFolder, SNAPSHOT_FUNCTION_NAME),
		IdentityServerUrl = config.IdentityServerUrl,
		SessionEndpointPath = config.SessionEndpointPath or "/identity/session",
		RefreshEndpointPath = config.RefreshEndpointPath or "/identity/refresh",
		DefaultHeaders = table.clone(config.DefaultHeaders or {}),
		SessionRefreshIntervalSeconds = math.max(60, config.SessionRefreshIntervalSeconds or TOKEN_REFRESH_INTERVAL_SECONDS),
		RequestTimeoutSeconds = math.max(1, config.RequestTimeoutSeconds or REQUEST_TIMEOUT_SECONDS),
		RequestAsync = config.RequestAsync or defaultRequestAsync,
		IdentitiesByPlayer = {},
		RefreshGenerationByPlayer = {},
		OnIdentityUpdated = config.OnIdentityUpdated,
		OnIdentityFailed = config.OnIdentityFailed,
	}

	state.SnapshotFunction.OnServerInvoke = function(player: Player)
		local record = state.IdentitiesByPlayer[player]
		if record then
			return clonePlayerIdentity(record)
		end

		return nil
	end

	state.SyncEvent.OnServerEvent:Connect(function()
		-- One-way server-to-client channel.
	end)

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
	local remoteParent = getRemoteParent(config)
	local remoteFolder = getRemoteFolder(remoteParent)

	local state: ClientState = {
		RemoteFolder = remoteFolder,
		SyncEvent = getRemoteEvent(remoteFolder, SYNC_EVENT_NAME),
		SnapshotFunction = getRemoteFunction(remoteFolder, SNAPSHOT_FUNCTION_NAME),
		LocalIdentity = nil,
		IdentityListeners = {},
		OnIdentityUpdated = if config then config.OnIdentityUpdated else nil,
	}

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
