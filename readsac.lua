-- honestly this is just a float buffer at the right offset
local ffi = require 'ffi'
local sacformat = require 'sacformat'

local function readSAC(buffer, stats)
	local bufferSize = stats[0].size
	print('file '..ffi.string(stats[0].name)..' size '..tostring(bufferSize))
	-- now decode this horrible file format somehow and plot what we find
	-- going by https://github.com/iris-edu/sac2mseed/blob/master/src/sac2mseed.c for how to read a SAC file
	-- I'm going to skip the override-format and skip the ascii-format options in it

	if bufferSize < ffi.sizeof'SACHeader_t' then
		error("skipping sac file -- not room for header")
	end

	if ffi.string(buffer, 4) == '    ' then
		error("I don't support SAC ALPHA files yet")
	end
	
	--readbinaryheader(buffer)
	local header = ffi.cast('SACHeader_t *', buffer)
	if header[0].nvhdr < 1 or header[0].nvhdr > 10 then
		-- swap byte order
		header[0].nvhdr = bit.bor(
			bit.lshift(bit.band(header[0].nvhdr, 0xff), 24),
			bit.lshift(bit.band(header[0].nvhdr, 0xff00), 8),
			bit.rshift(bit.band(header[0].nvhdr, 0xff0000), 8),
			bit.rshift(bit.band(header[0].nvhdr, 0xff000000), 24)
		)
		assert(header[0].nvhdr >= 1 and header[0].nvhdr <= 10, "cannot determine byte order")
		-- and here we swap all the other fields in the header
		error("gotta swap all your words now")
	end
	
	if header[0].nzyear >= 0 and header[0].nzyear <= 200 then
		header[0].nzyear = header[0].nzyear + 1900
	end

	assert(not (header[0].nzyear < 1900 or header[0].nzyear > 3000 or
		header[0].nzjday < 1 or header[0].nzjday > 366 or
		header[0].nzhour < 0 or header[0].nzhour > 23 or
		header[0].nzmin < 0 or header[0].nzmin > 59 or
		header[0].nzsec < 0 or header[0].nzsec > 60 or
		header[0].nzmsec < 0 or header[0].nzmsec > 999999
	), 	"bad date entry in sac file")
	assert(header[0].nvhdr == 6, "sac header version not supported: "..header[0].nvhdr)
	assert(header[0].npts > 0, "no data, number of sample = "..header[0].npts)
	assert(header[0].npts*ffi.sizeof'float' + ffi.sizeof'SACHeader_t' <= bufferSize, "file isnt big enough to hold "..header[0].npts.." points")
	assert(header[0].iftype == sacformat.ITIME, "Data is not time series ("..header[0].iftype.."), cannot convert other types")
	assert(header[0].leven ~= 0, "Data is not evenly spaced (LEVEN not true), cannot convert")

	--local data = ffi.new('float[?]', header[0].npts)
	local data = ffi.cast('float*', header+1)

	print('got '..header[0].npts..' pts')

	return data, header
end

return readSAC
