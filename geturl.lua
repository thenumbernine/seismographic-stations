local path = require 'ext.path'

-- this just caches a file or downloads it
local function geturl(fn, url)
	if path(fn):exists() then 
		return path(fn):read()
	end
	print('downloading '..fn..' from '..url)
	-- [[ pure lua.  no output.
	local http = require 'socket.http'
	local d = assert(http.request(url))
	assert(path(fn):write(d))
	--]]
	--[[ use wget.  nice animation.
	assert(os.execute('wget -O "'..fn..'" "'..url..'"'))
	local d = path(fn):read()
	--]]
	return d
end

return geturl
