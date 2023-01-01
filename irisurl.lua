local table = require 'ext.table'

local url = {}

function url.iris(page, args)
	local gets = table.map(args, function(v,k,t) return k..'='..tostring(v), #t+1 end)
	return 'http://service.iris.edu/fdsnws/'..page..'/1/query?'..gets:concat'&'
end

function url.station(args)
	return url.iris('station', args)
end

function url.dataselect(args)
	return url.iris('dataselect', args)
end

return url
