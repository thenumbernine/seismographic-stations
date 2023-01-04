-- honestly this is just a float buffer at the right offset
local ffi = require 'ffi'
local sacformat = require 'sacformat'

local function readSAC(buffer, stats)
	local bufferSize = stats[0].size
--print('file '..ffi.string(stats[0].name)..' size '..tostring(bufferSize))
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
	local hdr = ffi.cast('SACHeader_t *', buffer)
	if hdr[0].nvhdr < 1 or hdr[0].nvhdr > 10 then
		-- swap byte order
		hdr[0].nvhdr = bit.bor(
			bit.lshift(bit.band(hdr[0].nvhdr, 0xff), 24),
			bit.lshift(bit.band(hdr[0].nvhdr, 0xff00), 8),
			bit.rshift(bit.band(hdr[0].nvhdr, 0xff0000), 8),
			bit.rshift(bit.band(hdr[0].nvhdr, 0xff000000), 24)
		)
		assert(hdr[0].nvhdr >= 1 and hdr[0].nvhdr <= 10, "cannot determine byte order")
		-- and here we swap all the other fields in the hdr
		error("gotta swap all your words now")
	end
	
	if hdr[0].nzyear >= 0 and hdr[0].nzyear <= 200 then
		hdr[0].nzyear = hdr[0].nzyear + 1900
	end

	assert(not (hdr[0].nzyear < 1900 or hdr[0].nzyear > 3000 or
		hdr[0].nzjday < 1 or hdr[0].nzjday > 366 or
		hdr[0].nzhour < 0 or hdr[0].nzhour > 23 or
		hdr[0].nzmin < 0 or hdr[0].nzmin > 59 or
		hdr[0].nzsec < 0 or hdr[0].nzsec > 60 or
		hdr[0].nzmsec < 0 or hdr[0].nzmsec > 999999
	), 	"bad date entry in sac file")
	assert(hdr[0].nvhdr == 6, "sac hdr version not supported: "..hdr[0].nvhdr)
	assert(hdr[0].npts > 0, "no data, number of sample = "..hdr[0].npts)
	assert(hdr[0].npts*ffi.sizeof'float' + ffi.sizeof'SACHeader_t' <= bufferSize, "file isnt big enough to hold "..hdr[0].npts.." points")
	assert(hdr[0].iftype == sacformat.ITIME, "Data is not time series ("..hdr[0].iftype.."), cannot convert other types")
	assert(hdr[0].leven ~= 0, "Data is not evenly spaced (LEVEN not true), cannot convert")

	--local data = ffi.new('float[?]', hdr[0].npts)
	local data = ffi.cast('float*', hdr+1)

--print('got '..hdr[0].npts..' pts')

	local startTime = os.time{
		year = hdr.nzyear,
		month = 1,
		day = 1,
		hour = hdr.nzhour,
		min = hdr.nzmin,
		sec = hdr.nzsec,
		--msec = hdr.nzmsec,	-- hmm, msec accurate dates ...
	}
		+ 60 * 60 * 24 * hdr.nzjday	-- can't use yday with os.time, only os.date, so gotta offset it here
		+ hdr.nzmsec / 1000
	-- ok so theres no end-duration ...
	-- and i dont see a frequency or hz field ...
	-- so how do i find the end date?
	-- ahhh "delta" of course that means "delta-time"
	local endTime = startTime + hdr.delta * hdr.npts

	return {
		data = data,
		hdr = hdr,
		startTime = startTime,
		endTime = endTime,
	}
end

return readSAC
