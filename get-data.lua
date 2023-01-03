#!/usr/bin/env lua
-- right now this is used for downloading seismo data

local tolua = require 'ext.tolua'
local file = require 'ext.file'
local table = require 'ext.table'
local string = require 'ext.string'

local irisurl = require 'irisurl'
local geturl = require 'geturl'
local stations = require 'get-stations'

--[[
-- associate stations by their signature?
-- but there are multiple stations with matching signatures, even with matching signatures+networks ...
local stationsForSig = stations:mapi(function(s)
	print(s.code)
	return s, s.Network..' '..s.code
end):setmetatable(nil)
print(tolua(stationsForSig.ANMO))
--]]

-- [[
-- number of unique net+sta's:
local stationsForSig = table()
for _,s in ipairs(stations) do
	local k = s.Network..' '..s.code
	stationsForSig[k] = stationsForSig[k] or table()
	stationsForSig[k]:insert(s)
end
--[=[ which are dups?
for k,v in pairs(stationsForSig) do
	if #v > 1 then print(k, #v) end
end
--]=]
local stationsForSigKeys = stationsForSig:keys():sort()
print('#stationsForSigKeys', #stationsForSigKeys)	--#stationsForSigKeys	58488 ... but we have 60282 stations ... where did 1794 stations go?  how can we possibly access their data if the stations identification network-name+station-name is redundant?
--]]
-- so how in the world can we pick between hundreds of channels when we can only specify 3 letters to pick the channel?
-- and the channel always starts with "BH" so theres 2 letters down
-- wtf are we using unicode or something?
-- who came up with this?

-- [[
-- ok so network=UI code=ANMO there are 3 matching stations
-- station #1 has TotalNumberChannels=290
-- station #2 has TotalNumberChannels=77 
-- station #3 has TotalNumberChannels=354
-- soo ...
-- hmm yup multiple channels, but only 1 location.
--geturl('query-IU-ANMO-BH1-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH1&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
--geturl('query-IU-ANMO-BH2-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH2&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
--geturl('query-IU-ANMO-BHZ-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BHZ&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
-- doesn't work ... cuz only 3 chars
--geturl('query-IU-ANMO-BH10-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH10&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
-- doesn't work ... cuz first 2 letters have to be BH
--geturl('query-IU-ANMO-000-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=000&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
--geturl('query-IU-ANMO-BH0-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=BH0&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
-- this IRIS web interface is so half-assed it is just sad.
-- I bet if I download the SEED format data all 721 channels will be there.
--geturl('query-IU-ANMO-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=*&start=2010-02-27T06:30:00.000&end=2010-02-27T10:30:00.000&format=geocsv.inline.slist')
-- hmm no it stopped at 900k lines, but it did have in it the following:
-- # SID: IU_ANMO_00_BH1
-- # SID: IU_ANMO_00_BH2
-- # SID: IU_ANMO_00_BHZ
-- # SID: IU_ANMO_00_LH1
-- # SID: IU_ANMO_00_LH2
-- # SID: IU_ANMO_00_LHZ
-- # SID: IU_ANMO_00_VH1
-- # SID: IU_ANMO_00_VH2
-- # SID: IU_ANMO_00_VHZ
-- # SID: IU_ANMO_00_VM1
-- # SID: IU_ANMO_00_VM2
-- # SID: IU_ANMO_00_VMZ
-- so yeah theres our channels.  i guess this is how you get all of them .. by getting zero records and then querying the results.  
--geturl('query-IU-ANMO-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=*&start=2010-02-27T06:30:00.000&end=2010-02-27T06:30:00.000&format=geocsv.inline.slist')
-- ok that didnt work, it only gave me SIDs VM1 VM2 VMZ.  weird.  are SID suffixes not channels?  is their matching just a coincidence?
--geturl('query-IU-ANMO-slist.txt', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=*&start=2010-02-27T06:30:00.000&end=2010-02-27T06:30:01.000&format=geocsv.inline.slist')
-- ok that did work.  i gues yo ugotta query 1 seocnd worth of data to get all ... 12 ... channels...
--  but I thought there were 721 channels?
--geturl('query-IU-ANMO-sac.zip', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=*&start=2010-02-27T06:30:00.000&end=2010-02-27T06:30:01.000&format=sac.zip')
-- this gives yeah 12 channels, each in a binary format.
--geturl('query-IU-ANMO-miniseed', 'https://service.iris.edu/fdsnws/dataselect/1/query?net=IU&sta=ANMO&loc=00&cha=*&start=2010-02-27T06:30:00.000&end=2010-02-27T06:30:01.000&format=miniseed')
-- and yeah I could use the libmseed library but ... I get a feeling thats just more needless complexity.
--]]

-- [[
-- [=[ should at least work for IU-ANMO.  ig lots of sensors werent online so they will give back zero data.
local reqstart = 	os.time{year=2010, month=2, day=27, hour=6, min=30, sec=0}
local reqend = 		os.time{year=2010, month=2, day=27, hour=10, min=30, sec=0}
--]=]
--[=[
local reqstart = 	os.time{year=2022, month=12, day=31, hour=0, min=0, sec=0}
local reqstart = 	os.time{year=2023, month=1, day=1, hour=0, min=0, sec=0}
--]=]

local function tourldate(t)
	return os.date('%Y-%m-%dT%H:%M:%S', t)..'.000'
end

file'data':mkdir()
for _,k in ipairs(table.keys(stationsForSig):sort()) do
	local ss = stationsForSig[k]
	for _,s in ipairs(ss) do
		local net = s.Network
		local sta = s.code
		-- what's the difference between startDate and CreationDate ?
		-- and if our date range doesnt' overlap startDate->endDate then no data right?
		local inbounds = s.startDate < reqend and (not s.endDate or s.endDate > reqstart)
		print(net, sta, s.startDate, s.endDate, reqstart, reqend, inbounds)
		if inbounds then
			-- [==[
			geturl('data/query-'..net..'-'..sta..'-sac.zip', irisurl.dataselect{
				net = net,
				sta = sta,
				loc = '00',
				cha = '*',
				start = tourldate(reqstart),
				['end'] = tourldate(reqend),
				--format = 'geocsv.inline.slist',
				format = 'sac.zip',
			})
			--]==]
		end
	end
end
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


