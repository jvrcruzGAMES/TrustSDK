--!strict

local Packages = {
	Identity = require(script.Identity),
	Robots = require(script.Robots),
	Transport = require(script.Transport),
}

export type PackageName = "Identity" | "Robots" | "Transport"

local TrustSDK = {}

function TrustSDK.GetPackage(packageName: PackageName)
	local selectedPackage = Packages[packageName]
	assert(selectedPackage ~= nil, string.format("Unknown TrustSDK package %q", packageName))
	return selectedPackage
end

function TrustSDK.GetPackages()
	return table.clone(Packages)
end

return setmetatable(TrustSDK, {
	__call = function(_, selection: PackageName? | {PackageName}?)
		if selection == nil then
			return TrustSDK.GetPackages()
		end

		if type(selection) == "string" then
			return TrustSDK.GetPackage(selection :: PackageName)
		end

		assert(type(selection) == "table", "TrustSDK selector expects a package name or an array of package names")

		local selectedPackages = {}
		for _, packageName in selection :: {PackageName} do
			selectedPackages[packageName] = TrustSDK.GetPackage(packageName)
		end

		return selectedPackages
	end,
})
