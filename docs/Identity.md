# Identity

`Identity` is the TrustSDK module responsible for binding a Roblox player to an externally managed cryptographic identity.

It is server-driven:

- The server requires `HttpService` and calls an external `IdentityServer`.
- When a player joins, the server sends the player's Roblox identity data to the `IdentityServer`.
- If the player already exists, the server receives the existing public key plus a fresh session token.
- If the player does not exist yet, the `IdentityServer` creates the identity and returns the new public key plus a fresh session token.
- The session token is intentionally non-persistent and is refreshed every 5 minutes by default.
- The client only receives the local player's current identity snapshot.
- Client sync can use built-in remotes or optionally run through the `Transport` module.
- On server initialization, the module first checks the IdentityServer root route for advertised capabilities.

## Roblox Identity Payload

The module submits a `robloxIdentity` object containing:

- `UserId`
- `Username`
- `DisplayName`
- `AccountAge`
- `MembershipType`
- `HasVerifiedBadge` when available
- `Team` when available
- `LocaleId` when available
- `PlaceId`
- `GameId`
- `JobId`

## Expected IdentityServer Contract

The module first checks `GET /` for server capabilities.

Example response:

```json
{
  "Capabilities": ["PlayerIdentity", "PlayerStorage"]
}
```

Current capabilities:

- `PlayerIdentity`
- `PlayerStorage`

Default endpoints:

- Capabilities: `GET /`
- Session/bootstrap: `POST /identity/session`
- Session refresh: `POST /identity/refresh`
- Player storage item: `POST /storage/:key`
- Player storage item: `GET /storage/:key`
- Player storage item: `DELETE /storage/:key`
- Player storage keys: `GET /storage/keys`

Request body:

```json
{
  "robloxIdentity": {
    "UserId": 123,
    "Username": "Example",
    "DisplayName": "Example",
    "AccountAge": 365,
    "MembershipType": "Premium",
    "PlaceId": 0,
    "GameId": "00000000-0000-0000-0000-000000000000",
    "JobId": "00000000-0000-0000-0000-000000000000"
  }
}
```

Response body:

```json
{
  "PlayerIdentityId": "identity_123",
  "PublicKey": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n",
  "SessionToken": "ephemeral-session-token",
  "SessionExpiresAt": 1767225600,
  "IsNewRegistration": false
}
```

`SessionExpiresAt` can be replaced by `ExpiresInSeconds` if your server prefers relative expiry.

`PublicKey` must be returned as a PEM-encoded public key string.

## PlayerStorage

`PlayerStorage` is a cross-experience per-player data store exposed by the IdentityServer.

Every stored item should use this shape:

```json
{
  "Key": "string",
  "Value": {},
  "GameId": 1234567890,
  "JobId": "server-job-id",
  "CreatedAt": 1767225600,
  "UpdatedAt": 1767225600
}
```

Notes:

- `Key` is the item identifier.
- `Value` can be any JSON-serializable value.
- `GameId` and `JobId` are attached by the caller so the server can track where the write came from.
- `CreatedAt` and `UpdatedAt` are expected to be maintained by the IdentityServer.
- Storage access is server-only in this module.
- If clients need storage-backed data, your server should fetch it and relay it with `Transport` or your own `RemoteEvent` / `RemoteFunction` flow.

## Server Usage

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Identity = TrustSDK("Identity")

Identity:Initialize({
	IdentityServerUrl = "https://identity.example.com",
	Headers = {
		["Authorization"] = "Bearer your-service-token",
	},
	OnIdentityUpdated = function(player, identity)
		print("Identity synced for", player.Name, identity.PublicKey)
	end,
})
```

## Optional Transport Sync

If `Transport` is already initialized and the client handshake is complete, `Identity` can send its client sync packets through `Transport` instead of its own remotes.

Server:

```luau
local Transport = TrustSDK("Transport")
local Identity = TrustSDK("Identity")

Transport:Initialize()

Identity:Initialize({
	IdentityServerUrl = "https://identity.example.com",
	Transport = Transport,
	UseTransport = true,
})
```

Client:

```luau
local Transport = TrustSDK("Transport")
local Identity = TrustSDK("Identity")

Transport:Initialize()
Transport:BeginClientHandshake()

Identity:Initialize({
	Transport = Transport,
	UseTransport = true,
})
```

When `UseTransport` is `false` or omitted, `Identity` uses its own remotes exactly as before.

## Server Usage With Creator Dashboard Secrets

If you want the server URL and bearer token to come from Roblox secrets, use `HttpService:GetSecret()` in a server script and keep the secret values inside the HTTP request.

Required secrets for the included test harness:

- `identity_bearer_token`

Reference implementation: [IdentityTest.server.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/src/server/IdentityTest.server.luau)

Notes:

- Roblox secrets are only available on live servers, not in local Studio play sessions.
- Secrets can be used in headers and URLs, but not in the request body.
- The included test harness targets `https://identity.jvrcruz.games/`.
- Pass any extra request headers through `Headers` when initializing `Identity`.
- The included identity test harness uses `Transport` for both Identity sync and the React test UI request/response flow instead of standalone remotes.
- Type `!identity` in chat to open the React test UI for capability inspection and the PlayerStorage test flow.

## Client Usage

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Identity = TrustSDK("Identity")

Identity:Initialize({
	OnIdentityUpdated = function(identity)
		print("My public key", identity.PublicKey)
	end,
})

local identity = Identity:GetLocalIdentity()
if identity then
	print(identity.SessionToken)
end
```

## API

- `Identity:Initialize(config?)`
- `Identity:GetPlayerIdentity(player)`
- `Identity:GetLocalIdentity()`
- `Identity:GetPlayerPublicKey(player)`
- `Identity:GetLocalPublicKey()`
- `Identity:GetPlayerSessionToken(player)`
- `Identity:GetLocalSessionToken()`
- `Identity:GetCapabilities()`
- `Identity:HasCapability(capabilityName)`
- `Identity:RefreshPlayerSession(player)`
- `Identity:GetPlayerStorageItem(player, key)`
- `Identity:GetPlayerStorageKeys(player)`
- `Identity:SetPlayerStorageItem(player, key, value)`
- `Identity:DeletePlayerStorageItem(player, key)`
- `Identity:AddClientIdentityListener(listenerId, listener)`
- `Identity:RemoveClientIdentityListener(listenerId)`
