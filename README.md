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

# Dependencies

- `lua-ext`
- `lua-imguiapp`
- `lua-imgui`
- `luasocket` for getting the data
- `geographic-charts`
