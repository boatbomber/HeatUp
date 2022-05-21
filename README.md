# HeatUp

Why cool down when you can heat up? A Roblox Datastore wrapper that avoids the cooldown limit.

Roblox imposes a 6 second cooldown per key (across all your servers) in Datastores, preventing you from updating any key faster than ten times per minute. I wanted to go a little faster than that, and avoid risk of throttling causing dropped requests.

## How does this do that?

The secret sauce is that under the hood it's not actually writing to the same key. It doesn't really store your value at the key you chose, it stores your value at its own hash. It records that hash in a MemoryStore at your real key, so it knows where the most recent data is being held. (Periodically saving the hash to Datastore as well so it doesn't expire.) Now when you update your data, it'll be a new hash and therefore a new Datastore key- so no cooldown!

The limit is now the bounds of a MemoryStore, but that's [very high](https://developer.roblox.com/en-us/articles/memory-store#limits).

## Example

```Lua
local HttpService = game:GetService("HttpService")

local HeatUp = require(script.HeatUp)
local Store = HeatUp.new("testingHeatUp")

while true do
	Store:Update("hotKey", function(old)
		local new = (old or {})
		new[DateTime.now().UnixTimestampMillis] = HttpService:GenerateGUID(false)
		print(string.format("Updated value: %.2fkb", #HttpService:JSONEncode(new)/1024))
		return new
	end)
	task.wait(1) -- Much less than 6!
end
```
