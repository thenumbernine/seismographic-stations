# Plotting Data

Well I've got the station locations:

![](sensor-locations.png)

# Getting Data

ok I just want to visualize the raw data like you see on some youtube videos of the waves travelling thru all seismos from dif earthquakes

idk about 'network' vs 'station' vs whatever else

ok random detail: station Latitude and Longitude are in degrees
station Elevation is in meters(?right?)

How many locations are there?
How many channels are there?
How come these fields don't come up when querying the stations and networks?
Someone didn't think these things through, or maybe the text format I used just doesn't have all this information.
Yeah looks like I need to use XML format to get all fields.  Ha, XML.
And from there the station XML info will have the number of channels ... but where do I find the total number of locations?
And isn't channel requesting using some 3-letter/number acronym?  How do we query that, especially when we have over 1000 channels according to the "TotalNumberChannels" field?
Whoever made this, you can tell, never worked with data in the past.

# Reference

- earth pic is from NASA blue marble https://visibleearth.nasa.gov/collection/1484/blue-marble

# Dependencies

- my `lua-ext`
- my `lua-imguiapp`
- my `lua-imgui`
- my `lua-zip`
- my `geographic-charts`
- `luasocket` for getting the data
