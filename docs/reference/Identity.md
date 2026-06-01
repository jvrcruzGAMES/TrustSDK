# Identity Reference

`Identity` binds a Roblox player to an external `IdentityServer` and manages capability-aware identity features such as `PlayerStorage`.

## Initialize

## `Identity:Initialize(config?)`

Server and client.

Server config fields:

- `IdentityServerUrl: string`
- `CapabilitiesEndpointPath: string?`
- `SessionEndpointPath: string?`
- `RefreshEndpointPath: string?`
- `PlayerStorageEndpointPath: string?`
- `Transport: Transport?`
- `UseTransport: boolean?`
- `RemoteParent: Instance?`
- `Headers: {[string]: any}?`
- `SessionRefreshIntervalSeconds: number?`
- `RequestTimeoutSeconds: number?`
- `OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?`
- `OnIdentityFailed: ((Player, string) -> ())?`

Client config fields:

- `Transport: Transport?`
- `UseTransport: boolean?`
- `RemoteParent: Instance?`
- `OnIdentityUpdated: ((PlayerIdentity) -> ())?`

Notes:

- Server initialization requires `HttpService.HttpEnabled`.
- On the server, `IdentityServerUrl` is required.
- If `UseTransport` is enabled, `Transport` must already be initialized.
- In transport mode, the client should complete the `Transport` handshake before expecting identity sync.

## Identity Access

`Identity:GetPlayerIdentity()` and related key helpers expose the external public key exactly as returned by the `IdentityServer`.

Current required format:

- PEM-encoded public key string

## `Identity:GetPlayerIdentity(player)`

Server-only.

Returns:

- `PlayerIdentity?`

## `Identity:GetLocalIdentity()`

Client-only.

Returns:

- `PlayerIdentity?`

## `Identity:GetPlayerPublicKey(player)`

Server-only.

Returns:

- `string?`

## `Identity:GetLocalPublicKey()`

Client-only.

Returns:

- `string?`

## `Identity:GetPlayerSessionToken(player)`

Server-only.

Returns:

- `string?`

## `Identity:GetLocalSessionToken()`

Client-only.

Returns:

- `string?`

## Capabilities

## `Identity:GetCapabilities()`

Server-only.

Returns:

- `{[string]: boolean}`

## `Identity:HasCapability(capabilityName)`

Server-only.

Arguments:

- `capabilityName: string`

Returns:

- `boolean`

## Session Refresh

## `Identity:RefreshPlayerSession(player)`

Server-only.

Refreshes the player session token with the configured refresh endpoint.

## PlayerStorage

`PlayerStorage` is server-only in this module.

Single-item endpoints:

- `POST /storage/:key`
- `GET /storage/:key`
- `DELETE /storage/:key`

Bulk endpoint:

- `GET /storage/keys`

Stored item shape:

```json
{
  "Key": "string",
  "Value": {},
  "GameId": 1234567890,
  "JobId": "job-id",
  "CreatedAt": 1767225600,
  "UpdatedAt": 1767225600
}
```

## `Identity:GetPlayerStorageItem(player, key)`

Server-only.

Arguments:

- `player: Player`
- `key: string`

Returns:

- `PlayerStorageItem?`

## `Identity:GetPlayerStorageKeys(player)`

Server-only.

Arguments:

- `player: Player`

Returns:

- `{string}`

## `Identity:SetPlayerStorageItem(player, key, value)`

Server-only.

Arguments:

- `player: Player`
- `key: string`
- `value: any`

Returns:

- `PlayerStorageItem?`

## `Identity:DeletePlayerStorageItem(player, key)`

Server-only.

Arguments:

- `player: Player`
- `key: string`

Returns:

- `PlayerStorageItem?`

If clients need storage-backed data, your server should fetch it and relay it with `Transport` or your own remotes.

## Client Listeners

## `Identity:AddClientIdentityListener(listenerId, listener)`

Client-only.

Arguments:

- `listenerId: string`
- `listener: (PlayerIdentity) -> boolean?`

Return `true` from the listener to mark the identity update as handled.

## `Identity:RemoveClientIdentityListener(listenerId)`

Client-only.

Arguments:

- `listenerId: string`
