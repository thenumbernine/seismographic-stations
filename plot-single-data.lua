#!/usr/bin/env luajit

-- plot a single entry of sac.zip from the data/ folder

local table = require 'ext.table'
local range = require 'ext.range'
local timer = require 'ext.timer'
local file = require 'ext.file'
local readSAC = require 'readsac'
local gnuplot = require 'gnuplot'
local zipIter = require 'zipiter'
local ffi = require 'ffi'
local matrix_ffi = require 'matrix.ffi'
local matrix_lua = require 'matrix'

local stations = require 'get-stations'
local stationsForSig = {}
for _,s in ipairs(stations) do
	local k = s.Network..'-'..s.code
	stationsForSig[k] = stationsForSig[k] or table()
	stationsForSig[k]:insert(s)
end

local dataDir = 'data'

local fn = ...
if not fn then
	print("here's all your possible files:")
	for f in file(dataDir):dir() do
		local fn = dataDir..'/'..f
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


-- get station info associated with data
-- use the first station
local sig = fn:match('^'..dataDir..'/query%-(.*)%-sac%.zip$')
assert(sig, "couldn't get sig from file")
local s = stationsForSig[sig]
assert(#s > 0, "couldn't find a station for sig "..sig)
local station = s[1]
print('lat', station.Latitude, 'lon', station.Longitude)

local hzs = table()	-- one of these per 'alldata' float buffer
local alldata = table()
for buffer, stats in zipIter(fn) do
	local sac = readSAC(buffer, stats)
	local data = sac.data
	local hdr = sac.hdr[0]
	local n = hdr.npts
	local m = matrix_ffi(nil, 'float', n)
	ffi.copy(m.ptr, sac.data, ffi.sizeof'float' * n)

	-- [[ TODO this is arbitrary, but how do i find a baseline?
	local subn = 1000
	local baseline = 0
	for i=0,subn-1 do 
		baseline = baseline + m.ptr[i]
	end
	baseline = baseline / subn
	--]]

	-- [[ assume the initial data is the rest state and zero it
	for i=0,n-1 do
		m.ptr[i] = m.ptr[i] - baseline
	end
	--]]
	alldata:insert(m)
	hzs:insert(1/hdr.delta)
end
print("#alldata", #alldata)

-- taken from smooth_graph 
local function gaussian(x, sigma, sigmaSearch)
	sigmaSearch = sigmaSearch or sigma
	local xp = x.ptr
	local nx = x:size():zeros(x.ctype)
	local nxp = nx.ptr
	for i=0,x.volume-1 do
		if sigma == 0 then
			nxp[i] = xp[i]
		else
			local sum = 0
			local ksum = 0
			for j =
				math.max(0, i - sigmaSearch * sigma),
				math.min(x.volume - 1, i + sigmaSearch * sigma)
			do
				local y = (i - j) / sigma
				local k = math.exp(-y * y)
				sum = sum + xp[j] * k
				ksum = ksum + k
			end
			nxp[i] = sum / math.max(ksum, 1e-7)
		end
	end
	return nx
end

-- TODO here ... downsample ...
-- which I've maybe got in my Image library but not my Matrix library ... bleh ...

-- [[
timer('applying log', function()
	for j,data in ipairs(alldata) do
		for i=0,data.volume-1 do
			local x = data.ptr[i]
			data.ptr[i] = math.log(math.max(math.abs(x), 1)) / math.log(10)
		end
	end
end)
--]]
-- [[
timer('applying gaussian', function()
	-- stil has some waves but meh
	local sigma = 840
	for i=1,#alldata do
		local data = alldata[i]
		alldata[i] = (gaussian(data, sigma, 3))
	end
end)
--]]

gnuplot(table({
	persist = true,
	style = 'data lines',
	xlabel = 'seconds',
	data = alldata:mapi(function(d)
		--return matrix_lua(d)
		return d.size_:lambda(function(i) return d.ptr[i-1] end)
	end),
}, alldata:mapi(function(d,i) 
	-- as-is
	return {using='($0/'..hzs[i]..'):'..i, notitle=true}
	-- hmm can't do this without zeroing the baseline signal
	--return {using='($0/'..hzs[i]..'):(log(abs($'..i..')+1.)/log(10.))', notitle=true}
end)))
