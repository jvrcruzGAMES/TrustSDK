# Transport Reference

`Transport` provides secure in-transit messaging for TrustSDK.

## Initialize

## `Transport:Initialize(config?)`

Server and client.

Server config fields:

- `ServerIdentitySecretKey: buffer | string?`
- `ServerStaticSecretKey: buffer | string?`
- `ServerEd25519PublicKey: buffer | string?`
- `OnServerMessage: ((Player, buffer) -> ())?`
- `RemoteParent: Instance?`
- `Debug: boolean?`

Client config fields:

- `ServerEd25519PublicKey: buffer | string?`
- `OnClientMessage: ((buffer) -> ())?`
- `RemoteParent: Instance?`
- `Debug: boolean?`

Server return value:

```luau
{
	ServerEd25519PublicKey = buffer,
	ServerStaticX25519PublicKey = buffer?,
}
```

Client return value:

```luau
{
	ServerEd25519PublicKey = buffer,
}
```

## Handshake

## `Transport:BeginClientHandshake()`

Client-only.

Establishes the secure transport session.

Must be called before `Transport:SendToServer()`.

## Message Handlers

## `Transport:SetServerMessageHandler(handler)`

Server-only.

Arguments:

- `handler: (Player, buffer) -> ()`

## `Transport:SetClientMessageHandler(handler)`

Client-only.

Arguments:

- `handler: (buffer) -> ()`

## Message Listeners

## `Transport:AddServerMessageListener(listenerId, listener)`

Server-only.

Arguments:

- `listenerId: string`
- `listener: (Player, buffer) -> boolean?`

## `Transport:RemoveServerMessageListener(listenerId)`

Server-only.

## `Transport:AddClientMessageListener(listenerId, listener)`

Client-only.

Arguments:

- `listenerId: string`
- `listener: (buffer) -> boolean?`

## `Transport:RemoveClientMessageListener(listenerId)`

Client-only.

## Sending

## `Transport:SendToClient(player, payload)`

Server-only.

Arguments:

- `player: Player`
- `payload: buffer | string`

## `Transport:Broadcast(payload)`

Server-only.

Arguments:

- `payload: buffer | string`

## `Transport:SendToServer(payload)`

Client-only.

Arguments:

- `payload: buffer | string`

## Key Helpers

## `Transport:GetServerEd25519PublicKey()`

Returns:

- `buffer?`

## `Transport:GetServerStaticX25519PublicKey()`

Returns:

- `buffer?`

## Rekeying

## `Transport:RequestRekey(player)`

Server-only.

Arguments:

- `player: Player`

## `Transport:RequestRekeyAll()`

Server-only.
