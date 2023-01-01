#!/usr/bin/env lua
local file = require 'ext.file'
local fromlua = require 'ext.fromlua'
local tolua = require 'ext.tolua'
local string = require 'ext.string'
local table = require 'ext.table'
local geturl = require 'geturl'
local irisurl = require 'irisurl'

file'luon':mkdir()
file'txt':mkdir()
file'xml':mkdir()

-- this interprets the file too
-- it assumes the first row is # with fields | separated
-- and all subsequent rows are values | separated
-- phasing this out cuz IRIS gives INCOMPLETE data for this format type.
local function gettextdata(basename, url)
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

-- using this insead cuz IRIS is made by boomers still living in the 90s who still use XML
local function getxmldata(basename, url)
	local luonname = 'luon/'..basename..'.luon'
	if file(luonname):exists() then
		return setmetatable(assert(fromlua(file(luonname):read())), table)
	else
		local xml2lua = require 'xml2lua'
		local xmlhandler = require 'xmlhandler.tree'
		local d = geturl('xml/'..basename..'.xml', url)
		local handler = xmlhandler:new()
		local parser = xml2lua.parser(handler)
		parser:parse(d)
		local objs = handler.root 
		file(luonname):write(tolua(objs))
		return objs
	end
end

-- bleh I *have* to use XML or else IRIS gives me a simplified version.
-- smh even JSON is better than XML smh IRIS smh
local networks = getxmldata(
	'networks',
	irisurl.station{format='xml', includecomments=true, nodata=404, level='network'}
)

networks = networks.FDSNStationXML.Network
if #networks == 0 then networks = {networks} end
networks = table(networks)

print('# stations by networks:', networks:mapi(function(n) return tonumber(n.TotalNumberStations) end):sum())

-- ok multiple entries here can have matching .Network
-- so get all unique ones
local netsigs = networks
	:mapi(function(n,_,t) t[n._attr.code] = true end)
	:map(function(v,k,t) return k, #t+1 end)
	:sort()
local stations = table()
for _,nsig in ipairs(netsigs) do
--	print('getting stations for network '..nsig)
	local stationInfoForCode = getxmldata(
		'stations-'..nsig,
		-- ok using loc=01 and no loc produces same results
		-- what is location?
		-- how do i find how many locations there are?
		-- what difference does it make?
		irisurl.station{format='xml', includecomments=true, nodata=404, level='station', net=nsig
			--, loc='*', cha='*' -- makes no dif?
		}
	)
	local function mergeAttrs(o)
		-- while we're here, move the xml2lua _attrs into the main obj
		for k,v in pairs(o._attr) do
			o[k] = v
		end
		o._attr = nil
	end
	local function handleStation(s, n)
		mergeAttrs(s)
		stations:insert(s)
		-- while we're here, give the station the network code
		s.Network = n.code
	end
	local function handleNetwork(n)
		mergeAttrs(n)
		local Stations = n.Station
		-- sometimes its not there ...
		if not Stations then return end
		-- gah another quirk of xml2lua is if theres multiple tags of the same name it lumps them into an array ...
		if #Stations > 0 then
--			print('...has '..#Stations..', total so far '..#stations)
			for _,Station in ipairs(Stations) do
				handleStation(Station, n)
			end
		else
			handleStation(Stations, n)
--			print('...has 1 total so far '..#stations)
		end
	end
	local Networks = stationInfoForCode.FDSNStationXML.Network
	if #Networks > 0 then
		for _,Network in ipairs(Networks) do
			handleNetwork(Network)
		end
	else
		handleNetwork(Networks)
	end
end
print('#stations in station xml:', #stations)	--#stations	60282

-- convert fields from strings.
for _,s in ipairs(stations) do
	for _,k in ipairs{
		'Latitude',
		'Longitude',
		'Elevation',
		'SelectedNumberChannels',
		'TotalNumberChannels',
	} do
		s[k] = tonumber(s[k])
	end
	-- now convert time fields
	for _,k in ipairs{
		'CreationDate',
		'startDate',
		'endDate',
	} do
		local v = s[k]
		--assert(k ~= 'startDate' or v, "faild to find "..k.." for station "..s.Network.." "..s.code)
		if v then
			-- hmm would be nice to get that decimal too
			local Y,M,D,h,m,sec = v:match'^(....)%-(..)%-(..)T(..):(..):(..%.....)$'
			assert(Y, "got bad formatted time "..v)
			s[k] = os.time{
				year = Y,
				month = M,
				day = D,
				hour = h,
				min = m,
				sec = math.floor(sec),	-- error: field 'sec' is not an integer 
			}
		end
	end
end

return stations
