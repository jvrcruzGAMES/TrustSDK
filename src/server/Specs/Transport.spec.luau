--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")

local expectedMethods = {
	"Initialize",
	"BeginClientHandshake",
	"SetServerMessageHandler",
	"AddServerMessageListener",
	"RemoveServerMessageListener",
	"SetClientMessageHandler",
	"AddClientMessageListener",
	"RemoveClientMessageListener",
	"SendToClient",
	"Broadcast",
	"SendToServer",
	"GetServerEd25519PublicKey",
	"GetServerStaticX25519PublicKey",
	"GetAssignedPlayerIdentityPublicKey",
	"GetPlayerIdentityPublicKey",
	"RequestRekey",
	"RequestRekeyAll",
}

return function()
	describe("Transport package", function()
		it("exposes the expected public methods", function()
			for _, methodName in expectedMethods do
				expect(type((Transport :: any)[methodName])).to.equal("function")
			end
		end)
	end)
end
