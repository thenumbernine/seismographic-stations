#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local timer = require 'ext.timer'
local path = require 'ext.path'
local vec4x4f = require 'vec-ffi.vec4x4f'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local GLShaderStorageBuffer = require 'gl.shaderstoragebuffer'
local ig = require 'imgui'
local Zip = require 'zip'
local Image = require 'image'
local sdl = require 'sdl'

local charts = require 'geographic-charts.buildall'
local allChartCode = require 'geographic-charts.code'(charts)

local readSAC = require 'readsac'

local stations = require 'get-stations'
local stationsForSig = {}
for _,s in ipairs(stations) do
	local k = s.Network..'-'..s.code
	stationsForSig[k] = stationsForSig[k] or table()
	stationsForSig[k]:insert(s)
end

local App = require 'imgui.appwithorbit'()
App.viewUseGLMatrixMode = true
App.title = 'seismograph stations'
App.viewDist = 1.6
App.viewOrthoSize = 2	-- TODO assign in glapp.view

local int = ffi.new'int[1]'
local function glget(k)
	gl.glGetIntegerv(assert(gl[k]), int);
	return int[0]
end

local datas
local maxTextureSize 
local totalStartTime
local totalEndTime

function App:initGL(...)
	App.super.initGL(self, ...)
	self.view.ortho = true
	self.view.orthoSize = self.viewOrthoSize

	gl.glEnable(gl.GL_DEPTH_TEST)
	gl.glEnable(gl.GL_POINT_SMOOTH)
	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

	-- both are too big, max tex size is 16384
	-- and resizing takes too long (and crashes)
	-- so just resize offline
	local image
	timer('loading earth texture', function()
		image = Image'earth-color.png'
		--image = Image'world.topo.bathy.200412.3x21600x10800.jpg'
		--image = Image'world.topo.bathy.200412.3x21600x10800.png'
		--image = Image'world.topo.bathy.200412.3x16384x8192.png'
	end)
	maxTextureSize = glget'GL_MAX_TEXTURE_SIZE'
	if image.width > maxTextureSize
	or image.height > maxTextureSize then
		timer('resizing', function()
			image = image:resize(
				math.min(maxTextureSize, image.width),
				math.min(maxTextureSize, image.height)
			)
		end)
	end

	self.colorTex = GLTex2D{
		image = image,
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}
	GLTex2D:unbind()

	self.modelViewMatrix = vec4x4f()
	self.projectionMatrix = vec4x4f()

	self.globeTexShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = table{
allChartCode,
[[
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform float weight_WGS84;
uniform float weight_cylinder;
uniform float weight_Equirectangular;
uniform float weight_Azimuthal_equidistant;
uniform float weight_Mollweide;

in vec3 vertex;
in vec4 color;

out vec4 colorv;
out vec2 texcoordv;

void main() {
	// expect vertex xyz to be lat lon height
	// then generate texcoord etc
	// based on constraints
	vec3 pos = weight_WGS84 * chart_WGS84(vertex)
			+ weight_cylinder * chart_cylinder(vertex)
			+ weight_Equirectangular * chart_Equirectangular(vertex)
			+ weight_Azimuthal_equidistant * chart_Azimuthal_equidistant(vertex)
			+ weight_Mollweide * chart_Mollweide(vertex);
	pos /= WGS84_a;
	gl_Position = projectionMatrix * (modelViewMatrix * vec4(pos, 1.));
	colorv = color;

	float lat = vertex.x;
	float latrad = rad(lat);
	float azimuthal = .5*M_PI - latrad;
	float aziFrac = azimuthal / M_PI;

	float lon = vertex.y;
	float lonrad = rad(lon);
	float lonFrac = lonrad / (2. * M_PI);
	float unitLonFrac = lonFrac + .5;

	texcoordv = vec2(unitLonFrac, aziFrac);
}
]]
}:concat'\n',
		fragmentCode = [[
uniform sampler2D colorTex;
in vec4 colorv;
in vec2 texcoordv;
out vec4 fragColor;
void main() {
	fragColor = colorv * texture(colorTex, texcoordv);
}
]],
		uniforms = {
			colorTex = 0,
		},
	}
	self.globeTexShader:useNone()

	
	local station_t_C_code = [[
typedef struct station_t {
	int sensorDataOffset;	//offset into sensorData buffer
	int numPts;	// size of buffer in sensorData buffer
	int startTime;	// timestamp ... second-accurate, goes bad in 2038 or something
	int endTime;	// timestamp ...
} station_t;
]]
	-- glsl needs 'struct name' like C++ and not 'typedef ... name' like C
	local station_t_GLSL_code = [[
struct station_t {
	int sensorDataOffset;	//offset into sensorData buffer
	int numPts;	// size of buffer in sensorData buffer
	int startTime;	// timestamp ... second-accurate, goes bad in 2038 or something
	int endTime;	// timestamp ...
};
]]
	
	ffi.cdef(station_t_C_code)

	self.globeStationPointShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = table{
allChartCode,
station_t_GLSL_code,
[[
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform float weight_WGS84;
uniform float weight_cylinder;
uniform float weight_Equirectangular;
uniform float weight_Azimuthal_equidistant;
uniform float weight_Mollweide;

uniform int playtime;	//timestamp

uniform float pointSizeBase;

// what is binding? other than glBindBufferBase to associate with this field?
// and what's the difference between binding= and with 'layoutName' ?
//   sure enough the longer alternative is to use glGetProgramResourceIndex and glShaderStorageBlockBinding to associate the buffer by layoutName instead of by binding
// why std430 and not ... later?
// and what is 'set=' ?
layout(binding=2, std430) buffer SensorData {
	float v[];
} sensorData;

layout(binding=3, std430) buffer StationData {
	station_t v[];
} stationData;

uniform int sensorDataSize;	// == maxTextureSize

in vec3 vertex;

out float datav;

void main() {
	// expect vertex xyz to be lat lon height
	// then generate texcoord etc
	// based on constraints
	vec3 pos = weight_WGS84 * chart_WGS84(vertex)
			+ weight_cylinder * chart_cylinder(vertex)
			+ weight_Equirectangular * chart_Equirectangular(vertex)
			+ weight_Azimuthal_equidistant * chart_Azimuthal_equidistant(vertex)
			+ weight_Mollweide * chart_Mollweide(vertex);
	pos /= WGS84_a;
	gl_Position = projectionMatrix * (modelViewMatrix * vec4(pos, 1.));


	// TODO falloff of some kind
	// at a ortho width of 1 the point size can safely be 1 or so
	// at ortho width 1e-4 or so it can be 5 or so idk
	gl_PointSize = pointSizeBase;
	//gl_PointSize = 5. * projectionMatrix[0].x;


	int stationPixelIndex = stationData.v[gl_VertexID].sensorDataOffset;
	int stationNumPts = stationData.v[gl_VertexID].numPts;
	int stationStartTime = stationData.v[gl_VertexID].startTime;
	int stationEndTime = stationData.v[gl_VertexID].endTime;

	float playfrac = float(playtime - stationStartTime) / float(stationEndTime - stationStartTime);
	
	// get the index based on playtime
	int index = stationPixelIndex + int(clamp(playfrac, 0., 1.) * float(stationNumPts - 1));

	datav = sensorData.v[index % sensorDataSize];

	// map to 0 thru 10 or so (however big richter scale gets)
	datav = log(abs(datav) + 1.) / log(10.);

	// TODO map to a color scale or something
	datav *= 0.1;
}
]]
}:concat'\n',
		fragmentCode = [[
in float datav;
out vec4 fragColor;
void main() {
	fragColor = vec4(datav, 0., 1. - datav, 1.);
}
]],
		uniforms = {
			dataTex = 0,
		},
	}
	self.globeStationPointShader:useNone()

	datas = table()
	local dataDir = path'data'
	-- iter returns Paths, cuz ext lib
	for f in dataDir:dir() do
		local fn = dataDir/f
		local size = fn:attr().size
		if size > 0 then
			datas:insert{sacfn=fn.path}
		end
	end
	datas:sort(function(a,b) return a.sacfn < b.sacfn end)

	timer('reading data', function()
		local totalNumPts = 0
		for _,data in ipairs(datas) do
			-- iter returns strings, cuz zip lib
			for zipref in Zip(data.sacfn):dir() do
				local buffer, attr = zipref:readbuf()
				local sac = readSAC(buffer, attr.size, attr.name)
				-- TODO use 'sac' as the obj so i have its metamethods based on .hdr
				data.pts = sac.data
				data.hdr = sac.hdr[0]	-- ref instead of ptr
				data.startTime = sac.startTime
				data.endTime = sac.endTime
				totalNumPts = totalNumPts + data.hdr.npts
				-- but wait, I'm just drawing one sensor per station, so why pick any more than one?
				if data.hdr.npts > 0 then break end
			end
		end

		local sensorDataPtr = ffi.new('float[?]', totalNumPts)
		local stationDataPtr = ffi.new('station_t[?]', #datas)
		
		local index = 0
		for i,data in ipairs(datas) do
			local hdr = data.hdr
			data.sensorDataOffset = index
			ffi.copy(
				sensorDataPtr + index,
				data.pts,
				ffi.sizeof'float' * hdr.npts)
			index = index + hdr.npts
			
			-- get station info associated with data
			-- use the first station
			local sig = data.sacfn:match('^'..dataDir..'/query%-(.*)%-sac%.zip$')
			assert(sig, "couldn't get sig from file")
			local s = stationsForSig[sig]
			assert(#s > 0, "couldn't find a station for sig "..sig)
			data.station = s[1]

			local startTime = math.floor(data.startTime)
			local endTime = math.floor(data.endTime)
			totalStartTime = totalStartTime and math.min(startTime, totalStartTime) or startTime
			totalEndTime = totalEndTime and math.max(endTime, totalEndTime) or endTime

print(
	hdr.npts,
	data.sacfn,
	data.sensorDataOffset,
	os.date(nil, startTime),
	os.date(nil, endTime)
)
			stationDataPtr[i-1].sensorDataOffset = data.sensorDataOffset
			stationDataPtr[i-1].numPts = hdr.npts
			stationDataPtr[i-1].startTime = startTime
			stationDataPtr[i-1].endTime = endTime

			--[[
			-- ok theres no VertexAttrib2i so here goes
			--  all they have is VertexAttrib4iv 
			-- I should just use attribpointer
			local vec4i = require 'vec-ffi.vec4i'
			data.stationTexCoordPtr = vec4i(
				data.sensorDataOffset,
				hdr.npts,
				startTime,	-- without ms this will still overflow in 2038 (right?)
				endTime
			)
			--]]
		end
			
		-- ok now create the ssbo
		self.sensorDataSSBO = GLShaderStorageBuffer{
			size = ffi.sizeof'float' * totalNumPts,
			data = sensorDataPtr,
		}:unbind()

		self.stationDataSSBO = GLShaderStorageBuffer{
			size = ffi.sizeof'station_t' * #datas,
			data = stationDataPtr,
		}:unbind()

		-- also I've heard enough complaints about integer attributes 
		-- ... so I might as well use a buffer for holding it too?
		-- and then dereference it via 
	end)
	assert(index == totalNumPts)
	print('got '..#datas..' pts')
	playtime = totalStartTime
print'total time range:'
print('from:', os.date(nil, totalStartTime))
print('end:', os.date(nil, totalEndTime))
	GLTex2D:unbind()
end

idivs = 100
jdivs = 100
normalizeWeights = true
spheroidCoeff = 0
cylCoeff = 0
equirectCoeff = 1
aziequiCoeff = 0
mollweideCoeff = 0
playtime = 0
playSpeed = 60 * 60
playing = false
pointSizeBase = 5

local lastTime = 0
function App:update()
	local thisTime = sdl.SDL_GetTicks() * 1e-3
	local dt = thisTime - lastTime
	lastTime = thisTime
	
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.modelViewMatrix.ptr)
	gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projectionMatrix.ptr)
	self.globeTexShader:use()
	self.globeTexShader:setUniforms{
		weight_WGS84 = spheroidCoeff,
		weight_cylinder = cylCoeff,
		weight_Equirectangular = equirectCoeff,
		weight_Azimuthal_equidistant = aziequiCoeff,
		weight_Mollweide = mollweideCoeff,
		modelViewMatrix = self.modelViewMatrix.ptr,
		projectionMatrix = self.projectionMatrix.ptr,
	}
	self.colorTex:bind()
	gl.glVertexAttrib4f(self.globeTexShader.attrs.color.loc, 1, 1, 1, 1)
	for j=0,jdivs-1 do
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
			gl.glVertexAttrib3f(self.globeTexShader.attrs.vertex.loc, lat, lon, 0)

			local unitLonFrac = j/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			gl.glVertexAttrib3f(self.globeTexShader.attrs.vertex.loc, lat, lon, 0)
		end
		gl.glEnd()
	end
	self.colorTex:unbind()
	self.globeTexShader:useNone()

-- [==[
	self.globeStationPointShader:use()
	self.globeStationPointShader:setUniforms{
		weight_WGS84 = spheroidCoeff,
		weight_cylinder = cylCoeff,
		weight_Equirectangular = equirectCoeff,
		weight_Azimuthal_equidistant = aziequiCoeff,
		weight_Mollweide = mollweideCoeff,
		modelViewMatrix = self.modelViewMatrix.ptr,
		projectionMatrix = self.projectionMatrix.ptr,
		pointSizeBase = pointSizeBase,
	}
	gl.glDepthMask(gl.GL_FALSE)
	gl.glEnable(gl.GL_VERTEX_PROGRAM_POINT_SIZE)
	-- ok not all stations have data associated with them ...
	-- maybe I should be cycling thru the data, and then lining up data with stations with lat/lon
	if self.globeStationPointShader.uniforms.playtime then
		gl.glUniform1i(self.globeStationPointShader.uniforms.playtime.loc, playtime)
	end
	if self.globeStationPointShader.uniforms.sensorDataSize then
		gl.glUniform1i(self.globeStationPointShader.uniforms.sensorDataSize.loc, self.sensorDataSSBO.size)
	end
	
	self.sensorDataSSBO
		:bind()
		:bindBase(2)	-- matches GLSL 'sensorData' binding=
		:unbind()
	self.stationDataSSBO
		:bind()
		:bindBase(3)
		:unbind()
	
	gl.glBegin(gl.GL_POINTS)
	-- [[ draw only the data sensors
	for _,d in ipairs(datas) do
		local s = d.station
		gl.glVertexAttrib3f(
			self.globeStationPointShader.attrs.vertex.loc,
			s.Latitude,
			s.Longitude,
			s.Elevation + 1e+4
		)
	end
	--]]
	--[[ draw all stations
	for _,s in ipairs(stations) do
		gl.glVertexAttrib2f(self.globeStationPointShader.attrs.stationTexCoord.loc, 0, 0)
		gl.glVertexAttrib3f(
			self.globeStationPointShader.attrs.vertex.loc,
			s.Latitude,
			s.Longitude,
			s.Elevation + 1e+4
		)
	end
	--]]
	gl.glEnd()
	gl.glDepthMask(gl.GL_TRUE)
	gl.glDisable(gl.GL_VERTEX_PROGRAM_POINT_SIZE)
	
	self.globeStationPointShader:useNone()
--]==]

	if playing then
		local deltaPlayTime = dt * playSpeed
		playtime = playtime + deltaPlayTime 
		if playtime > totalEndTime then
			playtime = totalEndTime
			playing = false
		end
	end

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
	if ig.igButton'reset view' then
		self.view.ortho = true
		self.view.orthoSize = self.viewOrthoSize
		self.view.angle:set(0,0,0,1)
		self.view.orbit:set(0,0,0)
		self.view.pos:set(0, 0, self.viewDist)
	end
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
	ig.luatableInputFloat('pointSizeBase', _G, 'pointSizeBase')
	
	ig.igText('start: '..totalStartTime)
	ig.igText(os.date(nil, totalStartTime))
	ig.igText('end: '..totalEndTime)
	ig.igText(os.date(nil, totalEndTime))

	if playing then
		if ig.igButton'stop' then
			playing = false
		end
	else
		if ig.igButton'play' then
			playing = true
			if playtime == totalEndTime then
				playtime = totalStartTime
			end
		end
	end
	
	-- how come this is resetting the variable?
	local oldplaytime = playtime
	if not ig.luatableInputFloat('play time', _G, 'playtime') then
		playtime = oldplaytime
	end
	ig.igText('cur: '..os.date(nil, math.floor(playtime)))
	ig.luatableInputFloat('play speed', _G, 'playSpeed')
end


local function canHandleMouse()
	if not mouse then return false end
	if rawget(ig, 'disabled') then return true end
	return not ig.igGetIO()[0].WantCaptureMouse
end

local function canHandleKeyboard()
	if rawget(ig, 'disabled') then return true end
	return not ig.igGetIO()[0].WantCaptureKeyboard
end

function App:event(event, ...)
	if App.super.event then
		App.super.event(self, event, ...)
	end
	if event[0].type == sdl.SDL_EVENT_KEY_DOWN then
		if canHandleKeyboard() then
			if event[0].key.key == sdl.SDLK_SPACE then
				playing = not playing
				if playing then
					if playtime == totalEndTime then
						playtime = totalStartTime
					end
				end
			end
		end
	end
end

return App():run()
