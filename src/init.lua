local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local HashLib = require(script.Parent.HashLib)

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

	function Store:_commitLocation()
		local exclusiveLowerBound = nil
		dPrint("[COMMIT] Committing locations for", self._name)
		while true do
			local items = self._memory:GetRangeAsync(Enum.SortDirection.Ascending, 100, exclusiveLowerBound)
			for _, item in ipairs(items) do
				dPrint("[COMMIT]   ",item.key, item.value)
				self._data:SetAsync(item.key, item.value)
			end

			-- if the call returned less than a hundred items it means we’ve reached the end of the map
			if #items < 100 then
				break
			end

			-- the last retrieved key is the exclusive lower bound for the next iteration
			exclusiveLowerBound = items[#items].key
		end
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
			timestamp = DateTime.now().UnixTimestampMillis,
		}

		dPrint("[SET] Location:", location, "Value:", value)

		self._data:SetAsync(location.hash, value)
		self._memory:UpdateAsync(key, function(oldLocation)
			if oldLocation and oldLocation.timestamp > location.timestamp then
				-- Stored is more recent, cancel this
				return nil
			end
			return location
		end, 2592000)
	end

	function Store:Update(key: string, transformer: (any) -> any)
		self:Set(key, transformer(self:Get(key)))
	end

	function Store:Remove(key: string)
		self._memory:RemoveAsync(key)
		self._data:RemoveAsync(key)
	end

	function Store:Destroy()
		self:_commitLocation()
		HeatUp._cache[name] = nil
		table.clear(self)
	end

	HeatUp._cache[name] = Store
	return Store
end

function HeatUp.commitLocations()
	for _, Store in pairs(HeatUp._cache) do
		task.spawn(Store._commitLocation, Store)
	end
end

-- Prevent memory expiry losing the location by periodically mirroring to datastore
task.spawn(function()
	while task.wait(6 + math.random(100,400)/100) do
		HeatUp.commitLocations()
	end
end)
game:BindToClose(HeatUp.commitLocations)

return HeatUp
