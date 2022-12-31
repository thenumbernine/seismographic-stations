#!/usr/bin/env lua
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

local function stationURL(args)
	local gets = table.map(args, function(v,k,t) return k..'='..tostring(v), #t+1 end)
	return 'http://service.iris.edu/fdsnws/station/1/query?'..gets:concat'&'
end

local networks = getdata(
	'networks',
	stationURL{format='text', includecomments=true, nodata=404, level='network'}
)
-- ok multiple entries here can have matching .Network
-- so get all unique ones
local netsigs = networks
	:mapi(function(n,_,t) t[n.Network] = true end)
	:map(function(v,k,t) return k, #t+1 end)
	:sort()
local stations = table()
for _,nsig in ipairs(netsigs) do
--	print('getting stations for network '..nsig)
	local thisstation = getdata(
		'stations-'..nsig,
		stationURL{format='text', includecomments=true, nodata=404, level='station', net=nsig}
	)
	stations:append(thisstation)
--	print('...has '..#thisstation..', total so far '..#stations)
end
print('#stations', #stations)	--#stations	60282

--[[
-- associate stations by their signature?
-- but there are multiple stations with matching signatures, even with matching signatures+networks ...
local stationsForSig = stations:mapi(function(s)
	return s, s.Station
end):setmetatable(nil)
print(tolua(stationsForSig.ANMO))
--]]

--[[
-- number of unique net+sta's:
local netsta = table()
for _,s in ipairs(stations) do
	netsta[s.Network..s.Station] = true
end
netsta = netsta:keys():sort()
print('#netsta', #netsta)	--#netsta	58488

geturl('query-IU-ANMO-BH1-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH1&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
geturl('query-IU-ANMO-BH2-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH2&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
--geturl('query-IU-ANMO-BHZ-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BHZ&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
-- hmm yup multiple channels, but only 1 location.
--]]

--[[
http://service.iris.edu/fdsnws/dataselect/1/
ex url: 
https://service.iris.edu/fdsnws/dataselect/1/query
?	net=IU
&	sta=ANMO
&	loc=00
&	cha=BHZ
&	start=2010-02-27T06:30:00.000
&	end=2010-02-27T10:30:00.000
&	format=geocsv.inline

but you still have to fix two things:
1) the row 'Time, Sample' needs to be commented / excluded
2) the separator is a ", " and not a "\t"
and yeah 3) the time format is "%Y-%m-%dT%H:%M:%S"

but what is the location?
is it which of the multiple network+station's that there are?
nope nevermind, for IU-ANMO there are 3 dif stations, but only location=00 works

how do I tell # of locations?
and how do I tell # of channels?

--]]

return stations
