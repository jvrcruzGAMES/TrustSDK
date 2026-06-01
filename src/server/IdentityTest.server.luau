--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Identity = TrustSDK("Identity")
local Transport = TrustSDK("Transport")

local IDENTITY_SERVER_BASE_URL = "https://trustsdk.identity.test"
local TRANSPORT_LISTENER_ID = "TrustSDK.IdentityTest"
local MESSAGE_PREFIX = "__TrustSDK_IdentityTest__:"

local BASE_URL_SECRET_NAME = "identity_base_url"
local BEARER_TOKEN_SECRET_NAME = "identity_bearer_token"

print("[TrustSDK Identity Test][Server] Booting identity test server harness")

local function getConfiguredSecret(secretName: string)
	local ok, secretOrError = pcall(function()
		return HttpService:GetSecret(secretName)
	end)

	if not ok then
		warn(string.format("[TrustSDK Identity Test] Failed to load secret %q: %s", secretName, tostring(secretOrError)))
		return nil
	end

	return secretOrError
end

local baseUrlSecret = getConfiguredSecret(BASE_URL_SECRET_NAME)
local bearerTokenSecret = getConfiguredSecret(BEARER_TOKEN_SECRET_NAME)

if not baseUrlSecret or not bearerTokenSecret then
	warn("[TrustSDK Identity Test] Identity test bootstrap skipped. Configure secrets identity_base_url and identity_bearer_token in Creator Dashboard.")
	return
end

print("[TrustSDK Identity Test][Server] Loaded required secrets")

local function buildAuthedHeaders(baseHeaders: {[string]: any}?): {[string]: any}
	local headers = {}

	if baseHeaders then
		for key, value in baseHeaders do
			headers[key] = value
		end
	end

	headers["Authorization"] = bearerTokenSecret:AddPrefix("Bearer ")
	headers["Content-Type"] = "application/json"

	return headers
end

local function resolveSecretUrl(requestUrl: string)
	assert(string.sub(requestUrl, 1, #IDENTITY_SERVER_BASE_URL) == IDENTITY_SERVER_BASE_URL, "Unexpected IdentityServer URL")

	local suffix = string.sub(requestUrl, #IDENTITY_SERVER_BASE_URL + 1)
	if suffix == "" then
		suffix = "/"
	end

	return baseUrlSecret:AddSuffix(suffix)
end

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

local function sortedCapabilities(capabilitySet: {[string]: boolean}): {string}
	local capabilities = {}
	for capability, enabled in capabilitySet do
		if enabled == true then
			table.insert(capabilities, capability)
		end
	end

	table.sort(capabilities)
	return capabilities
end

local function serializeStorageItem(item)
	if not item then
		return nil
	end

	return {
		Key = item.Key,
		Value = item.Value,
		GameId = item.GameId,
		JobId = item.JobId,
		CreatedAt = item.CreatedAt,
		UpdatedAt = item.UpdatedAt,
	}
end

local function sendResponse(player: Player, requestId: string, payload: {[string]: any})
	print(string.format(
		"[TrustSDK Identity Test][Server] Sending response to %s requestId=%s ok=%s",
		player.Name,
		requestId,
		tostring(payload.Ok)
	))

	local ok, errorMessage = pcall(function()
		Transport:SendToClient(player, encodePacket({
			Action = "response",
			RequestId = requestId,
			Payload = payload,
		}))
	end)

	if ok then
		print(string.format(
			"[TrustSDK Identity Test][Server] Response delivered to Transport requestId=%s",
			requestId
		))
	else
		warn(string.format(
			"[TrustSDK Identity Test][Server] Failed to send response requestId=%s error=%s",
			requestId,
			tostring(errorMessage)
		))
	end
end

Transport:Initialize()
print("[TrustSDK Identity Test][Server] Transport initialized for identity test harness")

Identity:Initialize({
	IdentityServerUrl = IDENTITY_SERVER_BASE_URL,
	Transport = Transport,
	UseTransport = true,
	RequestAsync = function(request)
		print(string.format(
			"[TrustSDK Identity Test][Server] IdentityServer request method=%s url=%s",
			request.Method,
			request.Url
		))
		local response = HttpService:RequestAsync({
			Url = resolveSecretUrl(request.Url) :: any,
			Method = request.Method,
			Headers = buildAuthedHeaders(request.Headers),
			Body = request.Body,
		})

		if not response.Success then
			local detail = response.StatusMessage
			if type(response.Body) == "string" and response.Body ~= "" then
				detail = string.format("%s (%s)", response.StatusMessage, response.Body)
			end

			warn(string.format("[TrustSDK Identity Test][Server] IdentityServer request failed: %s", detail))

			return false, detail
		end

		print(string.format(
			"[TrustSDK Identity Test][Server] IdentityServer request succeeded method=%s url=%s",
			request.Method,
			request.Url
		))

		return true, response.Body
	end,
	OnIdentityUpdated = function(player, identity)
		print(string.format(
			"[TrustSDK Identity Test] Synced %s (%d) publicKey=%s newRegistration=%s",
			player.Name,
			player.UserId,
			identity.PublicKey,
			tostring(identity.IsNewRegistration)
		))
	end,
	OnIdentityFailed = function(player, reason)
		warn(string.format("[TrustSDK Identity Test] Failed to sync %s (%d): %s", player.Name, player.UserId, reason))
	end,
})

print("[TrustSDK Identity Test][Server] Identity initialized in transport mode")

Transport:AddServerMessageListener(TRANSPORT_LISTENER_ID, function(player: Player, plaintext: buffer)
	local packet = decodePacket(plaintext)
	if not packet then
		return false
	end

	local requestId = tostring(packet.RequestId or "")
	local action = tostring(packet.Action or "")
	print(string.format(
		"[TrustSDK Identity Test][Server] Received packet from %s action=%s requestId=%s",
		player.Name,
		action,
		requestId
	))
	if requestId == "" then
		warn(string.format("[TrustSDK Identity Test][Server] Dropping packet with missing requestId from %s", player.Name))
		return true
	end

	print(string.format(
		"[TrustSDK Identity Test][Server] Beginning handler action=%s requestId=%s",
		action,
		requestId
	))

	local ok, response = pcall(function()
		if action == "status" then
			print(string.format("[TrustSDK Identity Test][Server] Handling status request requestId=%s", requestId))
			local identity = Identity:GetPlayerIdentity(player)
			local capabilities = sortedCapabilities(Identity:GetCapabilities())

			return {
				Ok = true,
				Capabilities = capabilities,
				HasPlayerStorage = Identity:HasCapability("PlayerStorage"),
				PlayerIdentity = if identity then {
					PlayerIdentityId = identity.PlayerIdentityId,
					PublicKey = identity.PublicKey,
					SessionExpiresAt = identity.SessionExpiresAt,
					IsNewRegistration = identity.IsNewRegistration,
					LastUpdatedAt = identity.LastUpdatedAt,
				} else nil,
			}
		end

		if action == "run_player_storage_test" then
			print(string.format("[TrustSDK Identity Test][Server] Handling PlayerStorage test request requestId=%s", requestId))
			assert(Identity:HasCapability("PlayerStorage"), "IdentityServer does not support PlayerStorage")

			local testId = HttpService:GenerateGUID(false)
			local storageKey = string.format("trustsdk:test:%d:%s", player.UserId, testId)
			local storageValue = {
				TestId = testId,
				UserId = player.UserId,
				DisplayName = player.DisplayName,
				TriggeredAt = os.time(),
			}

			local written = Identity:SetPlayerStorageItem(player, storageKey, storageValue)
			local fetched = Identity:GetPlayerStorageItem(player, storageKey)
			local keysAfterWrite = Identity:GetPlayerStorageKeys(player)
			local deleted = Identity:DeletePlayerStorageItem(player, storageKey)

			return {
				Ok = true,
				TestId = testId,
				Key = storageKey,
				Written = serializeStorageItem(written),
				Fetched = serializeStorageItem(fetched),
				KeysAfterWrite = keysAfterWrite,
				Deleted = serializeStorageItem(deleted),
			}
		end

		error(string.format("Unknown identity test action %q", action))
	end)

	if ok then
		print(string.format("[TrustSDK Identity Test][Server] Request completed requestId=%s", requestId))
		sendResponse(player, requestId, response)
	else
		warn(string.format(
			"[TrustSDK Identity Test][Server] Request failed requestId=%s error=%s",
			requestId,
			tostring(response)
		))
		sendResponse(player, requestId, {
			Ok = false,
			Error = tostring(response),
		})
	end

	return true
end)

print("[TrustSDK Identity Test][Server] Server listener registered")
