local path = require 'ext.path'

-- this just caches a file or downloads it
local function geturl(fn, url)
	fn = path(fn)
	if fn:exists() then
		return fn:read()
	end
	print('downloading '..fn..' from '..url)
	-- [[ pure lua.  no output.
	local http = require 'socket.http'
	local d = assert(http.request(url))
	assert(fn:write(d))
	--]]
	--[[ use wget.  nice animation.
	assert(os.execute('wget -O "'..fn..'" "'..url..'"'))
	local d = fn:read()
	--]]
	return d
end

return geturl
