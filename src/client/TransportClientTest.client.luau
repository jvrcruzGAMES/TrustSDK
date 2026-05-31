--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")

Transport:Initialize({
	OnClientMessage = function(plaintext)
		print("[TrustSDK Client] Secure message:", buffer.tostring(plaintext))
	end,
})

Robots:Initialize({
	Transport = Transport,
})

local ok, errorMessage = pcall(function()
		Transport:BeginClientHandshake()
	end)

if ok then
	print("[TrustSDK Client] Handshake complete")
	Transport:SendToServer("client_ready_for_captcha")
else
	warn("[TrustSDK Client] Handshake failed:", errorMessage)
end
