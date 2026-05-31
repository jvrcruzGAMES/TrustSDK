--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

return function()
	describe("TrustSDK root package", function()
		it("returns all packages when called without a selector", function()
			local packages = TrustSDK()

			expect(type(packages)).to.equal("table")
			expect(packages.Transport).never.to.equal(nil)
			expect(packages.Robots).never.to.equal(nil)
		end)

		it("returns the Transport package by selector", function()
			local transport = TrustSDK("Transport")

			expect(type(transport)).to.equal("table")
			expect(type(transport.Initialize)).to.equal("function")
		end)

		it("returns the Robots package by selector", function()
			local robots = TrustSDK("Robots")

			expect(type(robots)).to.equal("table")
			expect(type(robots.Initialize)).to.equal("function")
		end)

		it("returns a selection table when called with an array of package names", function()
			local selectedPackages = TrustSDK({ "Transport", "Robots" })

			expect(type(selectedPackages)).to.equal("table")
			expect(selectedPackages.Transport).never.to.equal(nil)
			expect(selectedPackages.Robots).never.to.equal(nil)
		end)

		it("raises for an unknown package selector", function()
			expect(function()
				(TrustSDK :: any).GetPackage("Unknown")
			end).to.throw()
		end)
	end)
end
