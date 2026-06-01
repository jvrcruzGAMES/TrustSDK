# IdentityServer Reference

`IdentityServer` is the external service expected by the TrustSDK `Identity` module.

It is responsible for:

- advertising server capabilities
- resolving Roblox players into external player identities
- issuing short-lived session tokens
- refreshing session tokens
- providing cross-experience `PlayerStorage`

## Base URL

`Identity:Initialize()` expects a single base URL:

```luau
Identity:Initialize({
	IdentityServerUrl = "https://identity.jvrcruz.games/",
})
```

Every route described here is resolved relative to that base URL.

## Capabilities

The server must expose a root capability document:

## `GET /`

Response:

```json
{
  "Capabilities": ["PlayerIdentity", "PlayerStorage"]
}
```

Accepted response shapes:

- `Capabilities`
- `capabilities`

Current capability names used by TrustSDK:

- `PlayerIdentity`
- `PlayerStorage`

Notes:

- `PlayerIdentity` is required for `Identity` initialization to succeed.
- `PlayerStorage` is optional, but required for storage methods such as `GetPlayerStorageItem()`.

## PlayerIdentity

## Roblox Identity Payload

TrustSDK sends this shape to the identity session endpoints:

```json
{
  "robloxIdentity": {
    "UserId": 123,
    "Username": "Example",
    "DisplayName": "Example",
    "AccountAge": 365,
    "MembershipType": "Premium",
    "HasVerifiedBadge": true,
    "Team": "Blue",
    "LocaleId": "en-us",
    "PlaceId": 123456789,
    "GameId": "00000000-0000-0000-0000-000000000000",
    "JobId": "00000000-0000-0000-0000-000000000000"
  }
}
```

## `POST /identity/session`

Used when a player first joins a server.

Expected behavior:

- if the Roblox player is already registered, return the existing public key and a fresh session token
- if the Roblox player is not registered, create the identity and return the new public key and session token

Response:

```json
{
  "PlayerIdentityId": "identity_123",
  "PublicKey": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n",
  "SessionToken": "ephemeral-session-token",
  "SessionExpiresAt": 1767225600,
  "IsNewRegistration": false
}
```

## `POST /identity/refresh`

Used by TrustSDK to refresh a session token for an already-associated player.

Request body:

Same as `POST /identity/session`.

Response:

Same as `POST /identity/session`.

## Identity Response Schema

```json
{
  "PlayerIdentityId": "string",
  "PublicKey": "string",
  "SessionToken": "string",
  "SessionExpiresAt": 1767225600,
  "ExpiresInSeconds": 300,
  "IsNewRegistration": false
}
```

Field notes:

- `PlayerIdentityId` is optional but recommended.
- `PublicKey` is required and must be PEM-encoded.
- `SessionToken` is required.
- `SessionExpiresAt` is optional.
- `ExpiresInSeconds` is optional and can be used instead of `SessionExpiresAt`.
- `IsNewRegistration` is optional.

Accepted `PublicKey` format:

```text
-----BEGIN PUBLIC KEY-----
...
-----END PUBLIC KEY-----
```

If your current server returns hex, base64, or another raw string format, update it to return PEM instead.

If both `SessionExpiresAt` and `ExpiresInSeconds` are present, TrustSDK uses `SessionExpiresAt` as authoritative.

## PlayerStorage

`PlayerStorage` is a cross-experience per-player storage surface.

TrustSDK accesses it on the server only.

Client code should never call the external storage endpoints directly. If client UI needs storage-backed data, the game server should fetch it and relay it through `Transport` or its own remote layer.

## Authentication

TrustSDK expects the game server to authenticate storage requests with the player's current identity session token:

Headers:

- `Authorization: Bearer <SessionToken>`
- `X-TrustSDK-PlayerIdentityId: <PlayerIdentityId>`

Additional service-to-service authentication headers can be added through the `Headers` field on `Identity:Initialize()`.

## Item Schema

Stored items are expected to use this shape:

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

Field notes:

- `Key` is the logical key for the item.
- `Value` is any JSON-serializable value.
- `GameId` identifies the Roblox universe where the write originated.
- `JobId` identifies the Roblox server instance where the write originated.
- `CreatedAt` should be managed by the `IdentityServer`.
- `UpdatedAt` should be managed by the `IdentityServer`.

## `POST /storage/:key`

Creates or replaces one storage item for the authenticated player identity.

Path parameter:

- `key: string`

Request body:

```json
{
  "Value": {},
  "GameId": 1234567890,
  "JobId": "server-job-id",
  "PlayerIdentityId": "identity_123",
  "RobloxIdentity": {
    "UserId": 123,
    "Username": "Example",
    "DisplayName": "Example",
    "AccountAge": 365,
    "MembershipType": "Premium",
    "PlaceId": 123456789,
    "GameId": "00000000-0000-0000-0000-000000000000",
    "JobId": "00000000-0000-0000-0000-000000000000"
  }
}
```

Response:

`PlayerStorageItem`

## `GET /storage/:key`

Fetches one storage item for the authenticated player identity.

Path parameter:

- `key: string`

Response:

`PlayerStorageItem`

## `DELETE /storage/:key`

Deletes one storage item for the authenticated player identity.

Path parameter:

- `key: string`

Response:

`PlayerStorageItem`

Notes:

- Returning the deleted item is the most useful behavior for TrustSDK tests and diagnostics.
- An empty response body is tolerated by the module and treated as `nil`.

## `GET /storage/keys`

Lists the currently stored keys for the authenticated player identity.

Response:

```json
{
  "Keys": ["profile", "settings", "inventory"]
}
```

## Error Handling

TrustSDK expects normal HTTP failure semantics:

- non-2xx responses should set a useful status message and, ideally, a response body
- transport-level failures should be surfaced by the module's internal `HttpService:RequestAsync()` call

Recommended error body shape:

```json
{
  "error": "human-readable message",
  "code": "OPTIONAL_MACHINE_CODE"
}
```

## Compatibility Notes

- TrustSDK currently expects JSON responses for capabilities, identity resolution, and storage reads.
- Storage keys are URL-encoded by the game server before the request is sent.
- `IdentityServer` should treat the authenticated session token as ephemeral and non-persistent.
