-- hmm, do i need a zip lua lib?
local ffi = require 'ffi'
local zip = require 'ffi.zip'

-- ok now try to open the zip
-- https://stackoverflow.com/questions/10440113/simple-way-to-unzip-a-zip-file-using-zlib
-- zip file stats+data iterator 
local function zipIter(fn)
	return coroutine.wrap(function()
		local err = ffi.new('int[1]', 0)
		local z = zip.zip_open(fn, 0, err)
		assert(err[0] == 0)
		assert(z ~= nil, "zip couldn't load")
		local n = zip.zip_get_num_files(z)
--print('zip_get_num_files', n)
--print('zip_get_num_entries', zip.zip_get_num_entries(z, 0))
		for i=0,n-1 do
			local st = ffi.new('struct zip_stat[1]')
			zip.zip_stat_init(st)
			zip.zip_stat_index(z, i, 0, st)
			local buffer = ffi.new('uint8_t[?]', st[0].size)
			local f = zip.zip_fopen_index(z, i, 0)
			assert(f ~= nil, "failed to open "..i.."'th file")
			zip.zip_fread(f, buffer, st[0].size)
			coroutine.yield(buffer, st)
		end
		zip.zip_close(z)
	end)
end

return zipIter
