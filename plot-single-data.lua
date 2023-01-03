#!/usr/bin/env luajit

-- plot a single entry of sac.zip from the data/ folder

local table = require 'ext.table'
local range = require 'ext.range'
local file = require 'ext.file'
local ffi = require 'ffi'
local gnuplot = require 'gnuplot'
local sac = require 'sacformat'

local fn = ...
if not fn then
	print("here's all your possible files:")
	local dir = 'data'
	for f in file(dir):dir() do
		local fn = dir..'/'..f
		local size = file(fn):attr().size
		if size > 0 then
			print(size, fn)
		end
	end
	return
end

if file(fn):attr().size == 0 then
	error("file has no size")
end

-- ok now try to open the zip
-- https://stackoverflow.com/questions/10440113/simple-way-to-unzip-a-zip-file-using-zlib
-- zip file stats+data iterator 
local function zipIter(fn)
	return coroutine.wrap(function()
		local zip = require 'ffi.zip'
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
			coroutine.yield(st, buffer)
		end
		zip.zip_close(z)
	end)
end

local alldata = table()
for st, buffer in zipIter(fn) do
	local bufferSize = st[0].size
	print('file '..ffi.string(st[0].name)..' size '..tostring(bufferSize))
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
	local sh = ffi.cast('SACHeader_t *', buffer)
	if sh[0].nvhdr < 1 or sh[0].nvhdr > 10 then
		-- swap byte order
		sh[0].nvhdr = bit.bor(
			bit.lshift(bit.band(sh[0].nvhdr, 0xff), 24),
			bit.lshift(bit.band(sh[0].nvhdr, 0xff00), 8),
			bit.rshift(bit.band(sh[0].nvhdr, 0xff0000), 8),
			bit.rshift(bit.band(sh[0].nvhdr, 0xff000000), 24)
		)
		assert(sh[0].nvhdr >= 1 and sh[0].nvhdr <= 10, "cannot determine byte order")
		-- and here we swap all the other fields in the header
	end
	
	if sh[0].nzyear >= 0 and sh[0].nzyear <= 200 then
		sh[0].nzyear = sh[0].nzyear + 1900
	end

	assert(not (sh[0].nzyear < 1900 or sh[0].nzyear > 3000 or
		sh[0].nzjday < 1 or sh[0].nzjday > 366 or
		sh[0].nzhour < 0 or sh[0].nzhour > 23 or
		sh[0].nzmin < 0 or sh[0].nzmin > 59 or
		sh[0].nzsec < 0 or sh[0].nzsec > 60 or
		sh[0].nzmsec < 0 or sh[0].nzmsec > 999999
	), 	"bad date entry in sac file")
	assert(sh[0].nvhdr == 6, "sac header version not supported: "..sh[0].nvhdr)
	assert(sh[0].npts > 0, "no data, number of sample = "..sh[0].npts)
	assert(sh[0].npts*ffi.sizeof'float' + ffi.sizeof'SACHeader_t' <= bufferSize, "file isnt big enough to hold "..sh[0].npts.." points")
	assert(sh[0].iftype == sac.ITIME, "Data is not time series ("..sh[0].iftype.."), cannot convert other types")
	assert(sh[0].leven ~= 0, "Data is not evenly spaced (LEVEN not true), cannot convert")

	--local data = ffi.new('float[?]', sh[0].npts)
	local data = ffi.cast('float*', sh+1)

	print('got '..sh[0].npts..' pts')

	alldata:insert(range(sh[0].npts):mapi(function(i)
		return data[i-1]
	end))
end

gnuplot(table({
	persist = true,
	style = 'data lines',
	xlabel = 'seconds',
	data = alldata,
}, alldata:mapi(function(d,i) 
	return {using='($0/20.):'..i, notitle=true}
end)))
