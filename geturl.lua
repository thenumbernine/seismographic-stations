local file = require 'ext.file'

-- this just caches a file or downloads it
local function geturl(fn, url)
	if file(fn):exists() then 
		return file(fn):read()
	end
	print('downloading '..fn..' from '..url)
	-- [[ pure lua.  no output.
	local http = require 'socket.http'
	local d = assert(http.request(url))
	assert(file(fn):write(d))
	--]]
	--[[ use wget.  nice animation.
	assert(os.execute('wget -O "'..fn..'" "'..url..'"'))
	local d = file(fn):read()
	--]]
	return d
end

return geturl
