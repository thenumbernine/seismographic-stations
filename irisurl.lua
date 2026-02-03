local URL = require 'url'

local url = {}

function url.iris(page, args)
	return URL{
		scheme = 'http',
		host = 'service.iris.edu',
		path = 'fdsnws/'..page..'/1/query',
		query = args,
	}
end

function url.station(args)
	return url.iris('station', args)
end

function url.dataselect(args)
	return url.iris('dataselect', args)
end

return url
