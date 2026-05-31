--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cryptography = require(ReplicatedStorage.Packages.cryptography)

local EdDSA = Cryptography.Verification.EdDSA
local X25519 = EdDSA.X25519
local AEAD = Cryptography.Encryption.AEAD
local HKDF = Cryptography.Hashing.HKDF
local SHA256 = Cryptography.Hashing.SHA2.SHA256
local CSPRNG = Cryptography.Utilities.CSPRNG
local Conversions = Cryptography.Utilities.Conversions

local REMOTE_FOLDER_NAME = "TrustSDKRemotes"
local HANDSHAKE_REQUEST_NAME = "HandshakeRequest"
local HANDSHAKE_COMPLETE_NAME = "HandshakeComplete"
local SECURE_MESSAGE_NAME = "SecureMessage"
local REKEY_REQUEST_NAME = "RekeyRequest"
local REKEY_SIGNAL_NAME = "RekeySignal"

local SERVER_PUBLIC_KEY_ATTRIBUTE = "ServerEd25519PublicKeyHex"
local SERVER_STATIC_PUBLIC_KEY_ATTRIBUTE = "ServerStaticX25519PublicKeyHex"
local PLAYER_IDENTITY_STORE_NAME = "TrustSDK.PlayerIdentities"
local REKEY_INTERVAL_SECONDS = 300
local REPLICATION_TIMEOUT_SECONDS = 15

local HKDF_INFO = buffer.fromstring("TrustSDK.SessionKey.v2")
local MESSAGE_AAD = buffer.fromstring("TrustSDK.ChaCha20Poly1305.v2")
local CLIENT_TO_SERVER_CONTEXT = buffer.fromstring("c2s")
local SERVER_TO_CLIENT_CONTEXT = buffer.fromstring("s2c")
local IDENTITY_BOOTSTRAP_AAD = buffer.fromstring("TrustSDK.IdentityBootstrap.v1")
local REKEY_CONTEXT = buffer.fromstring("rekey")

export type ServerConfig = {
	ServerIdentitySecretKey: buffer | string?,
	ServerStaticSecretKey: buffer | string?,
	ServerEd25519PublicKey: buffer | string?,
	OnServerMessage: ((Player, buffer) -> ())?,
	RemoteParent: Instance?,
	PlayerIdentityStoreName: string?,
	Debug: boolean?,
}

export type ClientConfig = {
	ServerEd25519PublicKey: buffer | string?,
	OnClientMessage: ((buffer) -> ())?,
	RemoteParent: Instance?,
	Debug: boolean?,
}

type PlayerIdentityRecord = {
	Version: number,
	SecretKeyHex: string,
	PublicKeyHex: string,
}

type Session = {
	Key: buffer,
	PlayerIdentitySecretKey: buffer,
	PlayerIdentityPublicKey: buffer,
	ServerIdentityPublicKey: buffer,
	NextOutboundSequence: number,
	LastInboundSequence: number,
}

type ServerHandshakeState = {
	ServerEphemeralMasked: buffer,
	ServerEphemeralPublic: buffer,
}

type ServerState = {
	HandshakeFolder: Folder,
	HandshakeRequest: RemoteFunction,
	HandshakeComplete: RemoteFunction,
	RekeyRequest: RemoteFunction,
	SecureMessage: RemoteEvent,
	RekeySignal: RemoteEvent,
	IdentitySecretKey: buffer,
	IdentityPublicKey: buffer,
	StaticSecretKey: buffer?,
	StaticPublicKey: buffer?,
	PlayerIdentityStore: GlobalDataStore,
	PlayerIdentitiesByUserId: {[number]: {
		SecretKey: buffer,
		PublicKey: buffer,
	}},
	HandshakeStateByPlayer: {[Player]: ServerHandshakeState},
	RekeyStateByPlayer: {[Player]: {
		RequestId: string,
		ServerEphemeralMasked: buffer,
		ServerEphemeralPublic: buffer,
	}},
	SessionsByPlayer: {[Player]: Session},
	ServerMessageListeners: {[string]: (Player, buffer) -> boolean?},
	OnServerMessage: ((Player, buffer) -> ())?,
	Debug: boolean,
}

type ClientState = {
	HandshakeFolder: Folder,
	HandshakeRequest: RemoteFunction,
	HandshakeComplete: RemoteFunction,
	RekeyRequest: RemoteFunction,
	SecureMessage: RemoteEvent,
	RekeySignal: RemoteEvent,
	ServerEd25519PublicKey: buffer,
	Session: Session?,
	ClientMessageListeners: {[string]: (buffer) -> boolean?},
	OnClientMessage: ((buffer) -> ())?,
	Debug: boolean,
}

local Transport = {}
Transport.__index = Transport

local serverState: ServerState? = nil
local clientState: ClientState? = nil

local function concatBuffers(...: buffer): buffer
	local buffers = {...}
	local totalLength = 0

	for _, currentBuffer in buffers do
		totalLength += buffer.len(currentBuffer)
	end

	local result = buffer.create(totalLength)
	local offset = 0

	for _, currentBuffer in buffers do
		local currentLength = buffer.len(currentBuffer)
		buffer.copy(result, offset, currentBuffer, 0, currentLength)
		offset += currentLength
	end

	return result
end

local function toBuffer(value: buffer | string, fieldName: string): buffer
	if typeof(value) == "buffer" then
		return value :: buffer
	end

	if type(value) == "string" then
		return Conversions.FromHex(value)
	end

	error(string.format("%s must be a buffer or hex string", fieldName), 3)
end

local function normalizeOptionalBuffer(value: buffer | string?, fieldName: string): buffer?
	if value == nil then
		return nil
	end

	return toBuffer(value, fieldName)
end

local function randomSecretKey(): buffer
	return CSPRNG.Ed25519Random()
end

local function randomNonce(): buffer
	local nonce = buffer.create(12)
	local source = CSPRNG.RandomBytes(12)
	buffer.copy(nonce, 0, source, 0, 12)
	return nonce
end

local function encodeSequence(sequence: number): buffer
	local encoded = buffer.create(4)
	buffer.writeu32(encoded, 0, sequence)
	return encoded
end

local function deriveSessionKey(sharedSecret: buffer, serverEphemeralPublic: buffer, clientEphemeralPublic: buffer): buffer
	local salt = concatBuffers(serverEphemeralPublic, clientEphemeralPublic)
	return HKDF(sharedSecret, salt, HKDF_INFO, 32, SHA256, 64, 32)
end

local function encryptPayload(sessionKey: buffer, plaintext: buffer, additionalAuthData: buffer): (buffer, buffer, buffer)
	local nonce = randomNonce()
	local ciphertext, tag = AEAD.Encrypt(plaintext, sessionKey, nonce, additionalAuthData)
	return nonce, ciphertext, tag
end

local function decryptPayload(sessionKey: buffer, nonce: buffer, ciphertext: buffer, tag: buffer, additionalAuthData: buffer): buffer?
	return AEAD.Decrypt(ciphertext, sessionKey, nonce, tag, additionalAuthData)
end

local function coercePlaintext(payload: buffer | string): buffer
	if typeof(payload) == "buffer" then
		return payload :: buffer
	end

	if type(payload) == "string" then
		return buffer.fromstring(payload)
	end

	error("Payload must be a buffer or string", 3)
end

local function encodeIdentityPayload(identitySecretKey: buffer, identityPublicKey: buffer): buffer
	local payload = {
		identitySecretKeyHex = Conversions.ToHex(identitySecretKey),
		identityPublicKeyHex = Conversions.ToHex(identityPublicKey),
	}

	return buffer.fromstring(HttpService:JSONEncode(payload))
end

local function decodeIdentityPayload(payload: buffer): (buffer, buffer)
	local decoded = HttpService:JSONDecode(buffer.tostring(payload))
	assert(type(decoded) == "table", "Identity bootstrap payload must be a JSON object")
	assert(type(decoded.identitySecretKeyHex) == "string", "Identity bootstrap payload missing identitySecretKeyHex")
	assert(type(decoded.identityPublicKeyHex) == "string", "Identity bootstrap payload missing identityPublicKeyHex")

	return Conversions.FromHex(decoded.identitySecretKeyHex), Conversions.FromHex(decoded.identityPublicKeyHex)
end

local function buildSignatureInput(context: buffer, sequence: number, nonce: buffer, ciphertext: buffer, tag: buffer): buffer
	return concatBuffers(context, encodeSequence(sequence), nonce, ciphertext, tag)
end

local function buildRekeySignatureInput(requestId: string, serverEphemeralPublic: buffer): buffer
	return concatBuffers(REKEY_CONTEXT, buffer.fromstring(requestId), serverEphemeralPublic)
end

local function debugPayloadString(payload: buffer): string
	local ok, result = pcall(function()
		return buffer.tostring(payload)
	end)

	if ok then
		return result
	end

	return string.format("<buffer:%d bytes>", buffer.len(payload))
end

local function debugLogPacket(scope: string, direction: string, sequence: number, nonce: buffer, ciphertext: buffer, tag: buffer, signature: buffer, plaintext: buffer)
	print(string.format(
		"[TrustSDK Debug][%s][%s] seq=%d nonce=%s ciphertext=%s tag=%s signature=%s",
		scope,
		direction,
		sequence,
		Conversions.ToHex(nonce),
		Conversions.ToHex(ciphertext),
		Conversions.ToHex(tag),
		Conversions.ToHex(signature)
	))
	print(string.format("[TrustSDK Debug][%s][%s] parsed=%s", scope, direction, debugPayloadString(plaintext)))
end

local function dispatchServerMessage(state: ServerState, player: Player, plaintext: buffer)
	local handled = false

	for _, listener in state.ServerMessageListeners do
		local listenerHandled = listener(player, plaintext)
		if listenerHandled == true then
			handled = true
		end
	end

	if not handled and state.OnServerMessage then
		state.OnServerMessage(player, plaintext)
	end
end

local function dispatchClientMessage(state: ClientState, plaintext: buffer)
	local handled = false

	for _, listener in state.ClientMessageListeners do
		local listenerHandled = listener(plaintext)
		if listenerHandled == true then
			handled = true
		end
	end

	if not handled and state.OnClientMessage then
		state.OnClientMessage(plaintext)
	end
end

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

local function getRemoteFolder(parent: Instance): Folder
	local folder = if RunService:IsClient()
		then parent:WaitForChild(REMOTE_FOLDER_NAME, REPLICATION_TIMEOUT_SECONDS)
		else parent:FindFirstChild(REMOTE_FOLDER_NAME)
	assert(folder and folder:IsA("Folder"), string.format("Expected %s folder under %s", REMOTE_FOLDER_NAME, parent:GetFullName()))
	return folder
end

local function getRemoteFunction(parent: Instance, name: string): RemoteFunction
	local remote = if RunService:IsClient()
		then parent:WaitForChild(name, REPLICATION_TIMEOUT_SECONDS)
		else parent:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteFunction"), string.format("Expected RemoteFunction %s", name))
	return remote
end

local function getRemoteEvent(parent: Instance, name: string): RemoteEvent
	local remote = if RunService:IsClient()
		then parent:WaitForChild(name, REPLICATION_TIMEOUT_SECONDS)
		else parent:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteEvent"), string.format("Expected RemoteEvent %s", name))
	return remote
end

local function waitForStringAttribute(instance: Instance, attributeName: string): string
	local attributeValue = instance:GetAttribute(attributeName)
	if type(attributeValue) == "string" then
		return attributeValue
	end

	local deadline = os.clock() + REPLICATION_TIMEOUT_SECONDS
	while os.clock() < deadline do
		task.wait(0.1)
		attributeValue = instance:GetAttribute(attributeName)
		if type(attributeValue) == "string" then
			return attributeValue
		end
	end

	error(string.format("Timed out waiting for attribute %s on %s", attributeName, instance:GetFullName()))
end

local function publishServerPublicKeys(state: ServerState)
	state.HandshakeFolder:SetAttribute(SERVER_PUBLIC_KEY_ATTRIBUTE, Conversions.ToHex(state.IdentityPublicKey))

	if state.StaticPublicKey then
		state.HandshakeFolder:SetAttribute(SERVER_STATIC_PUBLIC_KEY_ATTRIBUTE, Conversions.ToHex(state.StaticPublicKey))
	else
		state.HandshakeFolder:SetAttribute(SERVER_STATIC_PUBLIC_KEY_ATTRIBUTE, nil)
	end
end

local function getIdentityStore(config: ServerConfig?): GlobalDataStore
	local storeName = if config and config.PlayerIdentityStoreName then config.PlayerIdentityStoreName else PLAYER_IDENTITY_STORE_NAME
	return DataStoreService:GetDataStore(storeName)
end

local function getPlayerIdentityStoreKey(userId: number): string
	return string.format("player:%d", userId)
end

local function getOrCreatePlayerIdentity(state: ServerState, player: Player): {SecretKey: buffer, PublicKey: buffer}
	local cached = state.PlayerIdentitiesByUserId[player.UserId]
	if cached then
		return cached
	end

	local storeKey = getPlayerIdentityStoreKey(player.UserId)
	local success, recordOrError = pcall(function()
		return state.PlayerIdentityStore:UpdateAsync(storeKey, function(previousValue)
			if type(previousValue) == "table"
				and type(previousValue.SecretKeyHex) == "string"
				and type(previousValue.PublicKeyHex) == "string" then
				return previousValue
			end

			local secretKey = randomSecretKey()
			local publicKey = EdDSA.PublicKey(secretKey)

			return {
				Version = 1,
				SecretKeyHex = Conversions.ToHex(secretKey),
				PublicKeyHex = Conversions.ToHex(publicKey),
			} :: PlayerIdentityRecord
		end)
	end)

	assert(success, string.format("Failed to load player identity for %s: %s", player.Name, tostring(recordOrError)))

	local record = recordOrError :: any
	assert(type(record) == "table", "Player identity record must be a table")
	assert(type(record.SecretKeyHex) == "string", "Player identity record missing SecretKeyHex")
	assert(type(record.PublicKeyHex) == "string", "Player identity record missing PublicKeyHex")

	local identity = {
		SecretKey = Conversions.FromHex(record.SecretKeyHex),
		PublicKey = Conversions.FromHex(record.PublicKeyHex),
	}

	state.PlayerIdentitiesByUserId[player.UserId] = identity
	return identity
end

local function beginServerRekey(state: ServerState, player: Player): boolean
	local session = state.SessionsByPlayer[player]
	if not session then
		return false
	end

	local serverEphemeralSecret = randomSecretKey()
	local serverEphemeralMasked = X25519.Mask(serverEphemeralSecret)
	local serverEphemeralPublic = X25519.PublicKey(serverEphemeralMasked)
	local requestId = HttpService:GenerateGUID(false)
	local signatureInput = buildRekeySignatureInput(requestId, serverEphemeralPublic)
	local signature = EdDSA.Sign(signatureInput, state.IdentitySecretKey, state.IdentityPublicKey)

	state.RekeyStateByPlayer[player] = {
		RequestId = requestId,
		ServerEphemeralMasked = serverEphemeralMasked,
		ServerEphemeralPublic = serverEphemeralPublic,
	}

	state.RekeySignal:FireClient(player, requestId, serverEphemeralPublic, signature)
	return true
end

local function buildServerState(config: ServerConfig?): ServerState
	local remoteParent = getRemoteParent(config)
	local handshakeFolder = getOrCreateRemoteFolder(remoteParent)

	local identitySecretKey = normalizeOptionalBuffer(config and config.ServerIdentitySecretKey, "ServerIdentitySecretKey") or randomSecretKey()
	local staticSecretKey = normalizeOptionalBuffer(config and config.ServerStaticSecretKey, "ServerStaticSecretKey")
	local identityPublicKey = EdDSA.PublicKey(identitySecretKey)
	local staticPublicKey: buffer? = nil

	if staticSecretKey then
		local maskedStaticSecret = X25519.Mask(staticSecretKey)
		staticPublicKey = X25519.PublicKey(maskedStaticSecret)
	end

	local state: ServerState = {
		HandshakeFolder = handshakeFolder,
		HandshakeRequest = getOrCreateRemoteFunction(handshakeFolder, HANDSHAKE_REQUEST_NAME),
		HandshakeComplete = getOrCreateRemoteFunction(handshakeFolder, HANDSHAKE_COMPLETE_NAME),
		RekeyRequest = getOrCreateRemoteFunction(handshakeFolder, REKEY_REQUEST_NAME),
		SecureMessage = getOrCreateRemoteEvent(handshakeFolder, SECURE_MESSAGE_NAME),
		RekeySignal = getOrCreateRemoteEvent(handshakeFolder, REKEY_SIGNAL_NAME),
		IdentitySecretKey = identitySecretKey,
		IdentityPublicKey = identityPublicKey,
		StaticSecretKey = staticSecretKey,
		StaticPublicKey = staticPublicKey,
		PlayerIdentityStore = getIdentityStore(config),
		PlayerIdentitiesByUserId = {},
		HandshakeStateByPlayer = {},
		RekeyStateByPlayer = {},
		SessionsByPlayer = {},
		ServerMessageListeners = {},
		OnServerMessage = if config then config.OnServerMessage else nil,
		Debug = if config and config.Debug == true then true else false,
	}

	publishServerPublicKeys(state)

	state.HandshakeRequest.OnServerInvoke = function(player: Player)
		local serverEphemeralSecret = randomSecretKey()
		local serverEphemeralMasked = X25519.Mask(serverEphemeralSecret)
		local serverEphemeralPublic = X25519.PublicKey(serverEphemeralMasked)
		local signature = EdDSA.Sign(serverEphemeralPublic, state.IdentitySecretKey, state.IdentityPublicKey)

		state.HandshakeStateByPlayer[player] = {
			ServerEphemeralMasked = serverEphemeralMasked,
			ServerEphemeralPublic = serverEphemeralPublic,
		}

		return {
			ServerEphemeralPublic = serverEphemeralPublic,
			Signature = signature,
			ServerStaticPublicKey = state.StaticPublicKey,
		}
	end

	state.HandshakeComplete.OnServerInvoke = function(player: Player, clientEphemeralPublic: buffer)
		local pending = state.HandshakeStateByPlayer[player]
		if not pending then
			return false, "Missing server handshake state"
		end

		if typeof(clientEphemeralPublic) ~= "buffer" then
			return false, "Client public key must be a buffer"
		end

		local ok, bootstrapOrError = pcall(function()
			local sharedSecret = select(1, X25519.Exchange(pending.ServerEphemeralMasked, clientEphemeralPublic))
			local sessionKey = deriveSessionKey(sharedSecret, pending.ServerEphemeralPublic, clientEphemeralPublic)
			local playerIdentity = getOrCreatePlayerIdentity(state, player)

			state.SessionsByPlayer[player] = {
				Key = sessionKey,
				PlayerIdentitySecretKey = playerIdentity.SecretKey,
				PlayerIdentityPublicKey = playerIdentity.PublicKey,
				ServerIdentityPublicKey = state.IdentityPublicKey,
				NextOutboundSequence = 0,
				LastInboundSequence = -1,
			}
			state.HandshakeStateByPlayer[player] = nil

			local bootstrapPlaintext = encodeIdentityPayload(playerIdentity.SecretKey, playerIdentity.PublicKey)
			local nonce, ciphertext, tag = encryptPayload(sessionKey, bootstrapPlaintext, IDENTITY_BOOTSTRAP_AAD)

			return {
				IdentityNonce = nonce,
				IdentityCiphertext = ciphertext,
				IdentityTag = tag,
				PlayerIdentityPublicKey = playerIdentity.PublicKey,
			}
		end)

		if not ok then
			state.HandshakeStateByPlayer[player] = nil
			return false, tostring(bootstrapOrError)
		end

		return true, bootstrapOrError
	end

	state.RekeyRequest.OnServerInvoke = function(player: Player, requestId: string, clientEphemeralPublic: buffer)
		local pending = state.RekeyStateByPlayer[player]
		local session = state.SessionsByPlayer[player]
		if not pending or not session then
			return false, "Missing rekey state"
		end

		if type(requestId) ~= "string" or requestId ~= pending.RequestId then
			return false, "Invalid rekey request id"
		end

		if typeof(clientEphemeralPublic) ~= "buffer" then
			return false, "Client public key must be a buffer"
		end

		local ok, errorMessage = pcall(function()
			local sharedSecret = select(1, X25519.Exchange(pending.ServerEphemeralMasked, clientEphemeralPublic))
			local sessionKey = deriveSessionKey(sharedSecret, pending.ServerEphemeralPublic, clientEphemeralPublic)
			session.Key = sessionKey
			state.RekeyStateByPlayer[player] = nil
		end)

		if not ok then
			state.RekeyStateByPlayer[player] = nil
			return false, tostring(errorMessage)
		end

		return true
	end

	state.SecureMessage.OnServerEvent:Connect(function(player: Player, sequence: number, nonce: buffer, ciphertext: buffer, tag: buffer, signature: buffer)
		local session = state.SessionsByPlayer[player]
		if not session then
			warn(string.format("Rejected secure message from %s before handshake completion", player.Name))
			return
		end

		if type(sequence) ~= "number"
			or typeof(nonce) ~= "buffer"
			or typeof(ciphertext) ~= "buffer"
			or typeof(tag) ~= "buffer"
			or typeof(signature) ~= "buffer" then
			warn(string.format("Rejected malformed secure message from %s", player.Name))
			return
		end

		if sequence <= session.LastInboundSequence then
			warn(string.format("Rejected replayed secure message from %s", player.Name))
			return
		end

		local signatureInput = buildSignatureInput(CLIENT_TO_SERVER_CONTEXT, sequence, nonce, ciphertext, tag)
		if not EdDSA.Verify(signatureInput, session.PlayerIdentityPublicKey, signature) then
			warn(string.format("Rejected forged secure message from %s", player.Name))
			return
		end

		local plaintext = decryptPayload(session.Key, nonce, ciphertext, tag, MESSAGE_AAD)
		if not plaintext then
			warn(string.format("Failed to decrypt secure message from %s", player.Name))
			return
		end

		if state.Debug then
			debugLogPacket("Server", string.format("recv:%s", player.Name), sequence, nonce, ciphertext, tag, signature, plaintext)
		end

		session.LastInboundSequence = sequence

		dispatchServerMessage(state, player, plaintext)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		state.HandshakeStateByPlayer[player] = nil
		state.RekeyStateByPlayer[player] = nil
		state.SessionsByPlayer[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(REKEY_INTERVAL_SECONDS)
			if serverState ~= state then
				break
			end

			for player in state.SessionsByPlayer do
				beginServerRekey(state, player)
			end
		end
	end)

	return state
end

local function resolveServerPublicKey(config: ClientConfig?, handshakeFolder: Folder): buffer
	local configured = normalizeOptionalBuffer(config and config.ServerEd25519PublicKey, "ServerEd25519PublicKey")
	if configured then
		return configured
	end

	local publishedHex = waitForStringAttribute(handshakeFolder, SERVER_PUBLIC_KEY_ATTRIBUTE)
	return Conversions.FromHex(publishedHex)
end

local function buildClientState(config: ClientConfig?): ClientState
	local remoteParent = getRemoteParent(config)
	local handshakeFolder = getRemoteFolder(remoteParent)

	local state: ClientState = {
		HandshakeFolder = handshakeFolder,
		HandshakeRequest = getRemoteFunction(handshakeFolder, HANDSHAKE_REQUEST_NAME),
		HandshakeComplete = getRemoteFunction(handshakeFolder, HANDSHAKE_COMPLETE_NAME),
		RekeyRequest = getRemoteFunction(handshakeFolder, REKEY_REQUEST_NAME),
		SecureMessage = getRemoteEvent(handshakeFolder, SECURE_MESSAGE_NAME),
		RekeySignal = getRemoteEvent(handshakeFolder, REKEY_SIGNAL_NAME),
		ServerEd25519PublicKey = resolveServerPublicKey(config, handshakeFolder),
		Session = nil,
		ClientMessageListeners = {},
		OnClientMessage = if config then config.OnClientMessage else nil,
		Debug = if config and config.Debug == true then true else false,
	}

	state.SecureMessage.OnClientEvent:Connect(function(sequence: number, nonce: buffer, ciphertext: buffer, tag: buffer, signature: buffer)
		local session = state.Session
		if not session then
			warn("Rejected secure message before handshake completion")
			return
		end

		if type(sequence) ~= "number"
			or typeof(nonce) ~= "buffer"
			or typeof(ciphertext) ~= "buffer"
			or typeof(tag) ~= "buffer"
			or typeof(signature) ~= "buffer" then
			warn("Rejected malformed secure message from server")
			return
		end

		if sequence <= session.LastInboundSequence then
			warn("Rejected replayed secure message from server")
			return
		end

		local signatureInput = buildSignatureInput(SERVER_TO_CLIENT_CONTEXT, sequence, nonce, ciphertext, tag)
		if not EdDSA.Verify(signatureInput, session.ServerIdentityPublicKey, signature) then
			warn("Rejected forged secure message from server")
			return
		end

		local plaintext = decryptPayload(session.Key, nonce, ciphertext, tag, MESSAGE_AAD)
		if not plaintext then
			warn("Failed to decrypt secure message from server")
			return
		end

		if state.Debug then
			debugLogPacket("Client", "recv:server", sequence, nonce, ciphertext, tag, signature, plaintext)
		end

		session.LastInboundSequence = sequence

		dispatchClientMessage(state, plaintext)
	end)

	state.RekeySignal.OnClientEvent:Connect(function(requestId: string, serverEphemeralPublic: buffer, signature: buffer)
		local session = state.Session
		if not session then
			return
		end

		if type(requestId) ~= "string" or typeof(serverEphemeralPublic) ~= "buffer" or typeof(signature) ~= "buffer" then
			warn("Rejected malformed rekey request from server")
			return
		end

		local signatureInput = buildRekeySignatureInput(requestId, serverEphemeralPublic)
		if not EdDSA.Verify(signatureInput, state.ServerEd25519PublicKey, signature) then
			warn("Rejected forged rekey request from server")
			return
		end

		local clientEphemeralSecret = randomSecretKey()
		local clientEphemeralMasked = X25519.Mask(clientEphemeralSecret)
		local clientEphemeralPublic = X25519.PublicKey(clientEphemeralMasked)
		local sharedSecret = select(1, X25519.Exchange(clientEphemeralMasked, serverEphemeralPublic))
		local nextSessionKey = deriveSessionKey(sharedSecret, serverEphemeralPublic, clientEphemeralPublic)

		local success, errorMessage = state.RekeyRequest:InvokeServer(requestId, clientEphemeralPublic)
		if not success then
			warn(errorMessage or "Server rejected rekey request")
			return
		end

		session.Key = nextSessionKey
	end)

	return state
end

function Transport:Initialize(config: ServerConfig | ClientConfig?)
	if RunService:IsServer() then
		if serverState then
			return {
				ServerEd25519PublicKey = serverState.IdentityPublicKey,
				ServerStaticX25519PublicKey = serverState.StaticPublicKey,
			}
		end

		serverState = buildServerState(config :: ServerConfig?)
		return {
			ServerEd25519PublicKey = serverState.IdentityPublicKey,
			ServerStaticX25519PublicKey = serverState.StaticPublicKey,
		}
	end

	if clientState then
		return {
			ServerEd25519PublicKey = clientState.ServerEd25519PublicKey,
		}
	end

	clientState = buildClientState(config :: ClientConfig?)
	return {
		ServerEd25519PublicKey = clientState.ServerEd25519PublicKey,
	}
end

function Transport:BeginClientHandshake()
	assert(not RunService:IsServer(), "BeginClientHandshake can only be called on the client")
	assert(clientState, "Initialize must be called on the client first")

	local response = clientState.HandshakeRequest:InvokeServer()
	assert(type(response) == "table", "HandshakeRequest returned an invalid payload")

	local serverEphemeralPublic = response.ServerEphemeralPublic
	local signature = response.Signature

	assert(typeof(serverEphemeralPublic) == "buffer", "HandshakeRequest missing ServerEphemeralPublic buffer")
	assert(typeof(signature) == "buffer", "HandshakeRequest missing Signature buffer")

	local validSignature = EdDSA.Verify(serverEphemeralPublic, clientState.ServerEd25519PublicKey, signature)
	if not validSignature then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			localPlayer:Kick("Server identity verification failed")
		end
		error("Server identity verification failed")
	end

	local clientEphemeralSecret = randomSecretKey()
	local clientEphemeralMasked = X25519.Mask(clientEphemeralSecret)
	local clientEphemeralPublic = X25519.PublicKey(clientEphemeralMasked)
	local sharedSecret = select(1, X25519.Exchange(clientEphemeralMasked, serverEphemeralPublic))
	local sessionKey = deriveSessionKey(sharedSecret, serverEphemeralPublic, clientEphemeralPublic)

	local success, bootstrapOrError = clientState.HandshakeComplete:InvokeServer(clientEphemeralPublic)
	if not success then
		error(bootstrapOrError or "HandshakeComplete failed")
	end

	assert(type(bootstrapOrError) == "table", "HandshakeComplete returned an invalid bootstrap payload")
	assert(typeof(bootstrapOrError.IdentityNonce) == "buffer", "HandshakeComplete missing IdentityNonce")
	assert(typeof(bootstrapOrError.IdentityCiphertext) == "buffer", "HandshakeComplete missing IdentityCiphertext")
	assert(typeof(bootstrapOrError.IdentityTag) == "buffer", "HandshakeComplete missing IdentityTag")

	local bootstrapPlaintext = decryptPayload(
		sessionKey,
		bootstrapOrError.IdentityNonce,
		bootstrapOrError.IdentityCiphertext,
		bootstrapOrError.IdentityTag,
		IDENTITY_BOOTSTRAP_AAD
	)
	assert(bootstrapPlaintext, "Failed to decrypt assigned player identity")

	local playerIdentitySecretKey, playerIdentityPublicKey = decodeIdentityPayload(bootstrapPlaintext)

	clientState.Session = {
		Key = sessionKey,
		PlayerIdentitySecretKey = playerIdentitySecretKey,
		PlayerIdentityPublicKey = playerIdentityPublicKey,
		ServerIdentityPublicKey = clientState.ServerEd25519PublicKey,
		NextOutboundSequence = 0,
		LastInboundSequence = -1,
	}

	return true
end

function Transport:SetServerMessageHandler(handler: (Player, buffer) -> ())
	assert(RunService:IsServer(), "SetServerMessageHandler can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")
	serverState.OnServerMessage = handler
end

function Transport:AddServerMessageListener(listenerId: string, listener: (Player, buffer) -> boolean?)
	assert(RunService:IsServer(), "AddServerMessageListener can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")
	serverState.ServerMessageListeners[listenerId] = listener
end

function Transport:RemoveServerMessageListener(listenerId: string)
	assert(RunService:IsServer(), "RemoveServerMessageListener can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")
	serverState.ServerMessageListeners[listenerId] = nil
end

function Transport:SetClientMessageHandler(handler: (buffer) -> ())
	assert(not RunService:IsServer(), "SetClientMessageHandler can only be called on the client")
	assert(clientState, "Initialize must be called on the client first")
	clientState.OnClientMessage = handler
end

function Transport:AddClientMessageListener(listenerId: string, listener: (buffer) -> boolean?)
	assert(not RunService:IsServer(), "AddClientMessageListener can only be called on the client")
	assert(clientState, "Initialize must be called on the client first")
	clientState.ClientMessageListeners[listenerId] = listener
end

function Transport:RemoveClientMessageListener(listenerId: string)
	assert(not RunService:IsServer(), "RemoveClientMessageListener can only be called on the client")
	assert(clientState, "Initialize must be called on the client first")
	clientState.ClientMessageListeners[listenerId] = nil
end

function Transport:SendToClient(player: Player, payload: buffer | string)
	assert(RunService:IsServer(), "SendToClient can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")

	local session = serverState.SessionsByPlayer[player]
	assert(session, string.format("No secure session for player %s", player.Name))

	local plaintext = coercePlaintext(payload)
	local nonce, ciphertext, tag = encryptPayload(session.Key, plaintext, MESSAGE_AAD)
	local sequence = session.NextOutboundSequence
	local signatureInput = buildSignatureInput(SERVER_TO_CLIENT_CONTEXT, sequence, nonce, ciphertext, tag)
	local signature = EdDSA.Sign(signatureInput, serverState.IdentitySecretKey, serverState.IdentityPublicKey)

	session.NextOutboundSequence += 1
	if serverState.Debug then
		debugLogPacket("Server", string.format("send:%s", player.Name), sequence, nonce, ciphertext, tag, signature, plaintext)
	end
	serverState.SecureMessage:FireClient(player, sequence, nonce, ciphertext, tag, signature)
end

function Transport:Broadcast(payload: buffer | string)
	assert(RunService:IsServer(), "Broadcast can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")

	for player in serverState.SessionsByPlayer do
		self:SendToClient(player, payload)
	end
end

function Transport:SendToServer(payload: buffer | string)
	assert(not RunService:IsServer(), "SendToServer can only be called on the client")
	assert(clientState, "Initialize must be called on the client first")

	local session = clientState.Session
	assert(session, "BeginClientHandshake must complete before sending secure messages")

	local plaintext = coercePlaintext(payload)
	local nonce, ciphertext, tag = encryptPayload(session.Key, plaintext, MESSAGE_AAD)
	local sequence = session.NextOutboundSequence
	local signatureInput = buildSignatureInput(CLIENT_TO_SERVER_CONTEXT, sequence, nonce, ciphertext, tag)
	local signature = EdDSA.Sign(signatureInput, session.PlayerIdentitySecretKey, session.PlayerIdentityPublicKey)

	session.NextOutboundSequence += 1
	if clientState.Debug then
		debugLogPacket("Client", "send:server", sequence, nonce, ciphertext, tag, signature, plaintext)
	end
	clientState.SecureMessage:FireServer(sequence, nonce, ciphertext, tag, signature)
end

function Transport:GetServerEd25519PublicKey(): buffer?
	if serverState then
		return serverState.IdentityPublicKey
	end

	if clientState then
		return clientState.ServerEd25519PublicKey
	end

	return nil
end

function Transport:GetServerStaticX25519PublicKey(): buffer?
	if serverState then
		return serverState.StaticPublicKey
	end

	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		local publicKeyHex = folder:GetAttribute(SERVER_STATIC_PUBLIC_KEY_ATTRIBUTE)
		if type(publicKeyHex) == "string" then
			return Conversions.FromHex(publicKeyHex)
		end
	end

	return nil
end

function Transport:GetAssignedPlayerIdentityPublicKey(): buffer?
	if clientState and clientState.Session then
		return clientState.Session.PlayerIdentityPublicKey
	end

	return nil
end

function Transport:GetPlayerIdentityPublicKey(player: Player): buffer?
	if serverState then
		local identity = serverState.PlayerIdentitiesByUserId[player.UserId]
		if identity then
			return identity.PublicKey
		end
	end

	return nil
end

function Transport:RequestRekey(player: Player)
	assert(RunService:IsServer(), "RequestRekey can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")

	local started = beginServerRekey(serverState, player)
	assert(started, string.format("No secure session for player %s", player.Name))
end

function Transport:RequestRekeyAll()
	assert(RunService:IsServer(), "RequestRekeyAll can only be called on the server")
	assert(serverState, "Initialize must be called on the server first")

	for player in serverState.SessionsByPlayer do
		beginServerRekey(serverState, player)
	end
end

return Transport
