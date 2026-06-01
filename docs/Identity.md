# Identity

`Identity` is the TrustSDK module responsible for binding a Roblox player to an externally managed cryptographic identity.

It is server-driven:

- The server requires `HttpService` and calls an external `IdentityServer`.
- When a player joins, the server sends the player's Roblox identity data to the `IdentityServer`.
- If the player already exists, the server receives the existing public key plus a fresh session token.
- If the player does not exist yet, the `IdentityServer` creates the identity and returns the new public key plus a fresh session token.
- The session token is intentionally non-persistent and is refreshed every 5 minutes by default.
- The client only receives the local player's current identity snapshot.

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

Default endpoints:

- Session/bootstrap: `POST /identity/session`
- Session refresh: `POST /identity/refresh`

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
  "PublicKey": "player-public-key",
  "SessionToken": "ephemeral-session-token",
  "SessionExpiresAt": 1767225600,
  "IsNewRegistration": false
}
```

`SessionExpiresAt` can be replaced by `ExpiresInSeconds` if your server prefers relative expiry.

## Server Usage

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Identity = TrustSDK("Identity")

Identity:Initialize({
	IdentityServerUrl = "https://identity.example.com",
	DefaultHeaders = {
		["Authorization"] = "Bearer your-service-token",
	},
	OnIdentityUpdated = function(player, identity)
		print("Identity synced for", player.Name, identity.PublicKey)
	end,
})
```

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
- `Identity:RefreshPlayerSession(player)`
- `Identity:AddClientIdentityListener(listenerId, listener)`
- `Identity:RemoveClientIdentityListener(listenerId)`
