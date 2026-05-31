# Transport

## Overview

`Transport` is the secure transport package in TrustSDK.

It uses:

- `X25519` for per-session key agreement
- `HKDF-SHA256` for session key derivation
- `ChaCha20-Poly1305` for message encryption
- `Ed25519` for message signatures

This package is designed for in-transit protection only.

It does **not** replace Roblox `UserId`.
Instead, it adds a server-managed per-player cryptographic identity that is stable across servers.

## What It Does

On the server:

- Creates or loads a persistent per-player identity from `DataStoreService`
- Creates a server identity for signing handshake material
- Accepts secure messages from clients
- Sends secure messages to clients
- Supports manual and automatic rekeying

On the client:

- Verifies the server handshake signature
- Establishes a shared session key
- Receives its assigned player identity for the current session
- Sends signed and encrypted messages to the server
- Verifies signed and encrypted messages from the server

## Important Security Notes

- This system protects traffic in transit.
- The assigned player private key is delivered to the client during the handshake and kept only in memory for that session.
- A determined exploiter may still extract that session identity from client memory.
- Because of that, this should be treated as an authenticated transport layer, not as a tamper-proof client trust anchor.
- `UserId` should remain your primary account identity.

## Server Identity Model

The package uses two identity layers:

1. Server identity
- A long-term Ed25519 keypair used to sign the server handshake and outbound messages.
- If `ServerIdentitySecretKey` is not provided, a new server identity is generated at runtime.

2. Player identity
- A long-term Ed25519 keypair stored by the server in a DataStore per `UserId`.
- The same player gets the same identity in every server.
- The server sends that identity to the client only after the encrypted session is established.

## DataStore Behavior

Default store name:

- `TrustSDK.PlayerIdentities`

Stored record shape:

```json
{
  "Version": 1,
  "SecretKeyHex": "...",
  "PublicKeyHex": "..."
}
```

You can override the store name with `PlayerIdentityStoreName` in server config.

## Public API

## `Initialize(config)`

Server config fields:

- `ServerIdentitySecretKey: buffer | string?`
- `ServerStaticSecretKey: buffer | string?`
- `OnServerMessage: ((Player, buffer) -> ())?`
- `RemoteParent: Instance?`
- `PlayerIdentityStoreName: string?`

Client config fields:

- `ServerEd25519PublicKey: buffer | string?`
- `OnClientMessage: ((buffer) -> ())?`
- `RemoteParent: Instance?`

Notes:

- String keys are expected to be hex strings.
- `RemoteParent` defaults to `ReplicatedStorage`.
- On the client, if `ServerEd25519PublicKey` is omitted, the client reads it from the remote folder attributes.

Server return value:

```luau
{
    ServerEd25519PublicKey = buffer,
    ServerStaticX25519PublicKey = buffer?
}
```

Client return value:

```luau
{
    ServerEd25519PublicKey = buffer
}
```

## `BeginClientHandshake()`

Client-only.

What happens:

- client requests server ephemeral key
- server signs its ephemeral public key
- client verifies the signature
- both sides derive the same session key
- server loads or creates the player identity from DataStore
- server sends the player identity to the client encrypted under the session key

Must be called before `SendToServer()`.

## `SetServerMessageHandler(handler)`

Server-only.

Handler signature:

```luau
(player: Player, plaintext: buffer) -> ()
```

## `SetClientMessageHandler(handler)`

Client-only.

Handler signature:

```luau
(plaintext: buffer) -> ()
```

## `AddServerMessageListener(listenerId, listener)`

Server-only.

Registers a non-exclusive secure message listener. Return `true` from the listener to mark the message as handled.

## `RemoveServerMessageListener(listenerId)`

Server-only.

Removes a previously registered server message listener.

## `AddClientMessageListener(listenerId, listener)`

Client-only.

Registers a non-exclusive secure message listener. Return `true` from the listener to mark the message as handled.

## `RemoveClientMessageListener(listenerId)`

Client-only.

Removes a previously registered client message listener.

## `SendToServer(payload)`

Client-only.

Accepted payload types:

- `buffer`
- `string`

## `SendToClient(player, payload)`

Server-only.

Accepted payload types:

- `buffer`
- `string`

## `Broadcast(payload)`

Server-only.

Calls `SendToClient()` for every connected player with an active secure session.

## `RequestRekey(player)`

Server-only.

Starts a transport rekey for one player with an active secure session.

## `RequestRekeyAll()`

Server-only.

Starts a transport rekey for every player with an active secure session.

## `GetServerEd25519PublicKey()`

Returns the server public signing key if available on the current side.

## `GetServerStaticX25519PublicKey()`

Returns the server static X25519 public key if configured.

## `GetAssignedPlayerIdentityPublicKey()`

Client-only helper.

Returns the player identity public key assigned for the current secure session.

## `GetPlayerIdentityPublicKey(player)`

Server-only helper.

Returns the server-known persistent public key for that player if it has already been loaded into memory.

## Server Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")

Transport:Initialize({
    PlayerIdentityStoreName = "TrustSDK.PlayerIdentities",
    OnServerMessage = function(player, plaintext)
        print("Secure message from", player.Name, buffer.tostring(plaintext))
    end,
})

Transport:SendToClient(player, "hello from server")
```

## Client Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")

Transport:Initialize({
    OnClientMessage = function(plaintext)
        print("Server said:", buffer.tostring(plaintext))
    end,
})

Transport:BeginClientHandshake()
Transport:SendToServer("hello from client")
```

## Remote Objects Created

Under the configured `RemoteParent`, the package creates a folder:

- `TrustSDKRemotes`

Inside it:

- `HandshakeRequest` (`RemoteFunction`)
- `HandshakeComplete` (`RemoteFunction`)
- `SecureMessage` (`RemoteEvent`)
- `RekeyRequest` (`RemoteFunction`)
- `RekeySignal` (`RemoteEvent`)

Published attributes:

- `ServerEd25519PublicKeyHex`
- `ServerStaticX25519PublicKeyHex`

## Packet Model

Client -> Server:

- `sequence`
- `nonce`
- `ciphertext`
- `tag`
- `signature`

Server -> Client:

- `sequence`
- `nonce`
- `ciphertext`
- `tag`
- `signature`

The signature covers:

- direction context
- sequence number
- nonce
- ciphertext
- tag

This provides:

- confidentiality
- integrity
- sender authentication
- replay protection using sequence numbers

## Rekeying

- The player identity does not change during rekey.
- Only the session encryption key is rotated.
- The server can trigger rekey manually with `RequestRekey(player)` or `RequestRekeyAll()`.
- The server also forces a rekey automatically every 5 minutes for active sessions.

Rekey flow:

1. Server generates a fresh ephemeral X25519 keypair
2. Server signs the rekey payload and sends it to the client
3. Client verifies the signature
4. Client generates a fresh ephemeral X25519 keypair
5. Both sides derive a new shared session key
6. Session traffic continues under the new key

## Replay Protection

Each side tracks the highest inbound sequence number seen for the current session.

- Replayed packets are rejected.
- Out-of-order packets are also rejected.

## Failure Cases To Expect

- DataStore failures can prevent player identity loading.
- If the client has not completed the handshake, secure messages are rejected.
- If signature verification fails, the packet is rejected.
- If AEAD decryption fails, the packet is rejected.
- If sequence numbers are replayed or reused, the packet is rejected.

## Current Limitations

- Player private identity exists on the client during the session, so it is not secure against a local attacker.
- This package protects transport, not stored data.
- This package does not serialize structured game messages for you; it only transports buffers and strings.
- This package does not currently expose reconnect/session resumption behavior.
