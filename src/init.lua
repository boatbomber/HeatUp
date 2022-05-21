local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Packages = script.Packages
local HashLib = require(Packages.HashLib)

local HeatUp = {
	_cache = {},
	DEBUG = true,
}

local function dPrint(...)
	if HeatUp.DEBUG then
		print(...)
	end
end

function HeatUp.new(name: string)
	if HeatUp._cache[name] then
		return HeatUp._cache[name]
	end

	local Store = {
		_name = name,
		_data = DataStoreService:GetDataStore(name),
		_memory = MemoryStoreService:GetSortedMap(name),
	}

	function Store:_getLocation(key: string)
		local fromMemory = self._memory:GetAsync(key)
		if fromMemory ~= nil then
			return fromMemory
		end

		local fromData = self._data:GetAsync(key)
		if fromData ~= nil then
			return fromData
		end

		return nil
	end

	function Store:Get(key: string, default: any)
		local location = self:_getLocation(key)
		if location == nil then return nil end

		local value = self._data:GetAsync(location.hash)

		dPrint("[GET] Location:", location, "Value:", value)
		return if value ~= nil then value else default
	end

	function Store:Set(key: string, value: any)
		local hash = HashLib.shake128(HttpService:JSONEncode(value), 20)
		local location = {
			hash = hash,
			timestamp = DateTime.now().UnixTimestamp,
		}

		dPrint("[SET] Location:", location, "Value:", value)

		self._memory:SetAsync(key, location, 2592000)
		self._data:SetAsync(location.hash, value)
	end

	function Store:Update(key: string, transformer: (any) -> any)
		self:Set(key, transformer(self:Get(key)))
	end

	function Store:Remove(key: string)
		self._memory:RemoveAsync(key)
		self._data:RemoveAsync(key)
	end

	function Store:Destroy()
		HeatUp._cache[name] = nil
		table.clear(self)
	end

	HeatUp._cache[name] = Store
	return Store
end

function HeatUp.commitLocations()
	for _, Store in pairs(HeatUp._cache) do
		local exclusiveLowerBound = nil
		dPrint("[COMMIT] Committing locations for", Store._name)
		while true do
			local items = Store._memory:GetRangeAsync(Enum.SortDirection.Ascending, 100, exclusiveLowerBound)
			for _, item in ipairs(items) do
				dPrint("  ",item.key, item.value)
				Store._data:SetAsync(item.key, item.value)
			end

			-- if the call returned less than a hundred items it means we’ve reached the end of the map
			if #items < 100 then
				break
			end

			-- the last retrieved key is the exclusive lower bound for the next iteration
			exclusiveLowerBound = items[#items].key
		end
	end
end

-- Prevent memory expiry losing the location by periodically mirroring to datastore
task.spawn(function()
	while task.wait(6+math.random(100,400)/100) do
		HeatUp.commitLocations()
	end
end)

return HeatUp
