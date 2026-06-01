# Type Reference

Public exported types for TrustSDK modules.

## Root

## `PackageName`

```luau
type PackageName = "Identity" | "Robots" | "Transport"
```

## Identity

## `RobloxIdentity`

```luau
type RobloxIdentity = {
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
```

## `PlayerIdentity`

```luau
type PlayerIdentity = {
	PlayerIdentityId: string?,
	PublicKey: string, -- PEM-encoded public key
	SessionToken: string,
	SessionExpiresAt: number?,
	IsNewRegistration: boolean,
	RobloxIdentity: RobloxIdentity,
	LastUpdatedAt: number,
}
```

## `IdentityServerResponse`

```luau
type IdentityServerResponse = {
	PlayerIdentityId: string?,
	PublicKey: string, -- PEM-encoded public key
	SessionToken: string,
	SessionExpiresAt: number?,
	ExpiresInSeconds: number?,
	IsNewRegistration: boolean?,
}
```

## `IdentityServerCapabilitiesResponse`

```luau
type IdentityServerCapabilitiesResponse = {
	Capabilities: {string}?,
	capabilities: {string}?,
}
```

## `PlayerStorageItem`

```luau
type PlayerStorageItem = {
	Key: string,
	Value: any,
	GameId: number,
	JobId: string,
	CreatedAt: number,
	UpdatedAt: number,
}
```

## `PlayerStorageKeysResponse`

```luau
type PlayerStorageKeysResponse = {
	Keys: {string},
}
```

## `TransportModule`

This is the transport interface `Identity` expects when `UseTransport` is enabled.

```luau
type TransportModule = {
	AddServerMessageListener: (self: any, listenerId: string, listener: (Player, buffer) -> boolean?) -> (),
	RemoveServerMessageListener: (self: any, listenerId: string) -> (),
	AddClientMessageListener: (self: any, listenerId: string, listener: (buffer) -> boolean?) -> (),
	RemoveClientMessageListener: (self: any, listenerId: string) -> (),
	SendToClient: (self: any, player: Player, payload: buffer | string) -> (),
	SendToServer: (self: any, payload: buffer | string) -> (),
}
```

## `Identity.ServerConfig`

```luau
type ServerConfig = {
	IdentityServerUrl: string,
	CapabilitiesEndpointPath: string?,
	SessionEndpointPath: string?,
	RefreshEndpointPath: string?,
	PlayerStorageEndpointPath: string?,
	Transport: TransportModule?,
	UseTransport: boolean?,
	RemoteParent: Instance?,
	Headers: {[string]: any}?,
	SessionRefreshIntervalSeconds: number?,
	RequestTimeoutSeconds: number?,
	OnIdentityUpdated: ((Player, PlayerIdentity) -> ())?,
	OnIdentityFailed: ((Player, string) -> ())?,
}
```

## `Identity.ClientConfig`

```luau
type ClientConfig = {
	Transport: TransportModule?,
	UseTransport: boolean?,
	RemoteParent: Instance?,
	OnIdentityUpdated: ((PlayerIdentity) -> ())?,
}
```

## Transport

## `Transport.ServerConfig`

```luau
type ServerConfig = {
	ServerIdentitySecretKey: buffer | string?,
	ServerStaticSecretKey: buffer | string?,
	ServerEd25519PublicKey: buffer | string?,
	OnServerMessage: ((Player, buffer) -> ())?,
	RemoteParent: Instance?,
	Debug: boolean?,
}
```

## `Transport.ClientConfig`

```luau
type ClientConfig = {
	ServerEd25519PublicKey: buffer | string?,
	OnClientMessage: ((buffer) -> ())?,
	RemoteParent: Instance?,
	Debug: boolean?,
}
```

## Robots

## `CaptchaTheme`

```luau
type CaptchaTheme = {
	OverlayColor: string?,
	CardColor: string?,
	AccentColor: string?,
	TextColor: string?,
	MutedTextColor: string?,
	ErrorColor: string?,
}
```

## `CaptchaOptions`

```luau
type CaptchaOptions = {
	Title: string?,
	Prompt: string?,
	CodeLength: number?,
	MaxAttempts: number?,
	TimeoutSeconds: number?,
	LockMovement: boolean?,
	FailOnMovement: boolean?,
	AllowClose: boolean?,
	Theme: CaptchaTheme?,
	OnShown: ((Player, string) -> ())?,
	OnSolved: ((Player, string, string) -> ())?,
	OnFailed: ((Player, string, string?) -> ())?,
	OnTampered: ((Player, string, string) -> ())?,
	OnClosed: ((Player, string) -> ())?,
	OnTimeout: ((Player, string) -> ())?,
	OnMoveWhileLocked: ((Player, string) -> ())?,
}
```
