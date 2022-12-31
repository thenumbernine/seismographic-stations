#!/usr/bin/env luajit

local charts = require 'geographic-charts'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local glreport = require 'gl.report'
local ig = require 'imgui'
local wgs84 = charts.WGS84

local stations = require 'get-stations'

for _,s in ipairs(stations) do
	for _,k in ipairs{'Latitude', 'Longitude', 'Elevation'} do
		s[k] = tonumber(s[k])
	end
end

local App = require 'imguiapp.withorbit'()

App.title = 'seismograph stations'
App.viewDist = 1.6

function App:initGL(...)
	App.super.initGL(self, ...)
	gl.glEnable(gl.GL_DEPTH_TEST)
	gl.glEnable(gl.GL_POINT_SMOOTH)
	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

glreport'here'
	self.colorTex = GLTex2D{
		filename = 'earth-color.png',
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}

	self.shader = GLProgram{
		vertexCode = [[
varying vec3 color;
varying vec2 tc;
void main() {
	gl_Position = ftransform();
	color = gl_Color.rgb;
	tc = gl_MultiTexCoord0.st;
}
]],
		fragmentCode = [[
uniform sampler2D colorTex;
varying vec3 color;
varying vec2 tc;
void main() {
	gl_FragColor = texture2D(colorTex, tc);
}
]],
		uniforms = {
			colorTex = 0,
		},
	}
end

idivs = 100
jdivs = 100
normalizeWeights = true
spheroidCoeff = 0
cylCoeff = 0
equirectCoeff = 1
aziequiCoeff = 0
mollweideCoeff = 0

local function vertexpos(lat, lon, height)
	local latrad = math.rad(lat)
	local azimuthal = .5*math.pi - latrad
	local aziFrac = azimuthal / math.pi

	local lonrad = math.rad(lon)
	local lonFrac = lonrad / (2 * math.pi)
	local unitLonFrac = lonFrac + .5
	
	gl.glTexCoord2d(unitLonFrac, aziFrac)

	local spheroidx, spheroidy, spheroidz = wgs84:chart(lat, lon, height)
	spheroidx = spheroidx / wgs84.a
	spheroidy = spheroidy / wgs84.a
	spheroidz = spheroidz / wgs84.a
	-- rotate back so y is up
	spheroidy, spheroidz = spheroidz, -spheroidy
	-- now rotate so prime meridian is along -z instead of +x
	spheroidx, spheroidz = -spheroidz, spheroidx

	-- cylindrical
	local cylx, cyly, cylz = charts.cylinder:chart(lat, lon, height)
	-- rotate back so y is up
	cyly, cylz = cylz, -cyly
	-- now rotate so prime meridian is along -z instead of +x
	cylx, cylz = -cylz, cylx

	local equirectx, equirecty, equirectz = charts.Equirectangular:chart(lat, lon, height)
	local aziequix, aziequiy, aziequiz = charts['Azimuthal equidistant']:chart(lat, lon, height)
	local mollweidex, mollweidey, mollweidez = charts.Mollweide:chart(lat, lon, height)

	local x = spheroidCoeff * spheroidx + cylCoeff * cylx + equirectCoeff * equirectx + aziequiCoeff * aziequix + mollweideCoeff * mollweidex
	local y = spheroidCoeff * spheroidy + cylCoeff * cyly + equirectCoeff * equirecty + aziequiCoeff * aziequiy + mollweideCoeff * mollweidey
	local z = spheroidCoeff * spheroidz + cylCoeff * cylz + equirectCoeff * equirectz + aziequiCoeff * aziequiz + mollweideCoeff * mollweidez
	return x,y,z
end

local function vertex(lat, lon, height)
	gl.glVertex3d(vertexpos(lat, lon, height))
end

function App:update()
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	self.shader:use()
	self.colorTex:bind(0)
	gl.glColor3f(1,1,1)
	for j=0,jdivs-1 do
		gl.glColor3f(1,1,1)
		gl.glBegin(gl.GL_TRIANGLE_STRIP)
		for i=0,idivs do
			local aziFrac = i/idivs
			local azimuthal = aziFrac * math.pi-- azimuthal angle
			local latrad = .5*math.pi - azimuthal	-- latitude
			local lat = math.deg(latrad)

			local unitLonFrac = (j+1)/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			vertex(lat, lon, 0)

			local unitLonFrac = j/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			vertex(lat, lon, 0)
		end
		gl.glEnd()
	end
	self.colorTex:unbind(0)
	self.shader:useNone()

	gl.glDepthMask(gl.GL_FALSE)
	gl.glPointSize(3)
	gl.glColor3f(0,0,0)
	gl.glBegin(gl.GL_POINTS)
	for _,s in ipairs(stations) do
		vertex(s.Latitude, s.Longitude, s.Elevation + .1)
	end
	gl.glEnd()
	gl.glPointSize(2)
	gl.glColor3f(1,0,0)
	gl.glBegin(gl.GL_POINTS)
	for _,s in ipairs(stations) do
		vertex(s.Latitude, s.Longitude, s.Elevation + .2)
	end
	gl.glEnd()
	gl.glPointSize(1)
	gl.glDepthMask(gl.GL_TRUE)

	App.super.update(self)
end

local weightFields = {
	'spheroidCoeff',
	'cylCoeff',
	'equirectCoeff',
	'aziequiCoeff',
	'mollweideCoeff',
}

function App:updateGUI()
	ig.luatableInputInt('idivs', _G, 'idivs')
	ig.luatableInputInt('jdivs', _G, 'jdivs')
	ig.luatableCheckbox('normalize weights', _G, 'normalizeWeights')
	local changed
	for _,field in ipairs(weightFields) do
		if ig.luatableSliderFloat(field, _G, field, 0, 1) then
			changed = field
		end
	end
	if normalizeWeights and changed then
		local restFrac = 1 - _G[changed]
		local totalRest = 0
		for _,field in ipairs(weightFields) do
			if field ~= changed then
				totalRest = totalRest + _G[field]
			end
		end
		for _,field in ipairs(weightFields) do
			if field ~= changed then
				if totalRest == 0 then
					_G[field] = 0
				else
					_G[field] = restFrac * _G[field] / totalRest
				end
			end
		end
	end
end

App():run()
