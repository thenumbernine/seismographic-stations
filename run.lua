#!/usr/bin/env lua
local http = require 'socket.http'
local file = require 'ext.file'
local fromlua = require 'ext.fromlua'
local tolua = require 'ext.tolua'
local string = require 'ext.string'
local table = require 'ext.table'

file'txt':mkdir()
file'luon':mkdir()

-- this just caches a file or downloads it
local function geturl(fn, url)
	if file(fn):exists() then 
		return file(fn):read()
	end
	print('downloading '..fn..' from '..url)
	-- [[ pure lua.  no output.
	local d = assert(http.request(url))
	assert(file(fn):write(d))
	--]]
	--[[ use wget.  nice animation.
	assert(os.execute('wget -O "'..fn..'" "'..url..'"'))
	local d = file(fn):read()
	--]]
	return d
end

-- this interprets the file too
-- it assumes the first row is # with fields | separated
-- and all subsequent rows are values | separated
local function getdata(basename, url)
	local luonname = 'luon/'..basename..'.luon'	-- ok this is just a lua object.  idk if its really LUON, cuz i think that used binary or something.
	local rows
	if file(luonname):exists() then
		rows = setmetatable(assert(fromlua(file(luonname):read())), table)
	else
		local d = geturl('txt/'..basename..'.txt', url)
		rows = string.split(d, '\n')
		while rows:last() == '' do rows:remove() end
		if #rows == 0 then
			error("somehow I removed all the rows")
		end
		local keyrow = rows:remove(1)
		if keyrow:sub(1,1) ~= '#' then
			error("found an improperly formatted file first line: "..keyrow)
		end
		local keys = string.split(keyrow:sub(2), '|'):mapi(function(k) return string.trim(k) end)
		rows = rows:mapi(function(row)
			return string.split(row, '|')
				-- idk that value rows have extra spaces
				-- :mapi(function(v) return string.trim(v) end)
				:mapi(function(v,i) return v, assert(keys[i]) end)
		end)
		file(luonname):write(tolua(rows))
	end
	return rows
end

local networks = getdata('networks', 'http://service.iris.edu/fdsnws/station/1/query?level=network&format=text&includecomments=true&nodata=404')
-- ok multiple entries here can have matching .Network
-- so get all unique ones
local netsigs = networks
	:mapi(function(n,_,t) t[n.Network] = true end)
	:map(function(v,k,t) return k, #t+1 end)
	:sort()
local stations = table()
for _,nsig in ipairs(netsigs) do
	print('getting stations for network '..nsig)
	local thisstation = getdata(
		'stations-'..nsig,
		'http://service.iris.edu/fdsnws/station/1/query?net='..nsig..'&level=station&format=text&includecomments=true&nodata=404'
	)
	stations:append(thisstation)
	print('...has '..#thisstation..', total so far '..#stations)
end
print('#stations', #stations)
