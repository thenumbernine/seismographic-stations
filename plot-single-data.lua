#!/usr/bin/env luajit

-- plot a single entry of sac.zip from the data/ folder

local table = require 'ext.table'
local range = require 'ext.range'
local file = require 'ext.file'
local readSAC = require 'readsac'
local gnuplot = require 'gnuplot'
local zipIter = require 'zipiter'

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

local alldata = table()
for buffer, stats in zipIter(fn) do
	local data, header = readSAC(buffer, stats)
	alldata:insert(range(header[0].npts):mapi(function(i)
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
