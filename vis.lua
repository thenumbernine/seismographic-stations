#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local timer = require 'ext.timer'
local file = require 'ext.file'
local charts = require 'geographic-charts'
local template = require 'template'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local glreport = require 'gl.report'
local ig = require 'imgui'
local Image = require 'image'
local matrix_ffi = require 'matrix.ffi'
local sdl = require 'ffi.sdl'
local readSAC = require 'readsac'
local zipIter = require 'zipiter'

matrix_ffi.real = 'float'	-- default matrix_ffi type

local wgs84 = charts.WGS84

local stations = require 'get-stations'

local stationsForSig = {}
for _,s in ipairs(stations) do
	local k = s.Network..'-'..s.code
	stationsForSig[k] = stationsForSig[k] or table()
	stationsForSig[k]:insert(s)
end

local App = require 'imguiapp.withorbit'()

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

function App:initGL(...)
	App.super.initGL(self, ...)
	self.view.ortho = true
	self.view.orthoSize = self.viewOrthoSize

	gl.glEnable(gl.GL_DEPTH_TEST)
	gl.glEnable(gl.GL_POINT_SMOOTH)
	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

	--local image = Image'earth-color.png'
	-- both are too big, max tex size is 16384
	-- and resizing takes too long (and crashes)
	--local image = Image'world.topo.bathy.200412.3x21600x10800.jpg'
	--local image = Image'world.topo.bathy.200412.3x21600x10800.png'
	-- so just resize offline
	local image
	timer('loading earth texture', function()
		image = Image'world.topo.bathy.200412.3x16384x8192.png'
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

glreport'here'
	self.colorTex = GLTex2D{
		image = image,
		minFilter = gl.GL_LINEAR,
		magFilter = gl.GL_LINEAR,
		generateMipmap = true,
	}
glreport'here'
	GLTex2D:unbind()
glreport'here'

	self.modelViewMatrix = matrix_ffi.zeros{4,4}
	self.projectionMatrix = matrix_ffi.zeros{4,4}

	local ModuleSet = require 'modules'
	self.modules = ModuleSet()
	self.modules:addFromMarkup(template[[
//// MODULE_NAME: M_PI
const float M_PI = <?=math.pi?>;

//// MODULE_NAME: rad
//// MODULE_DEPENDS: M_PI
float rad(float d) {
	return d * M_PI / 180.;
}

//// MODULE_NAME: perp2
vec2 perp2(vec2 a) {
	return vec2(-a.y, a.x);
}

//// MODULE_NAME: isfinite
bool isfinite(float x) {
	return !(isinf(x) || isnan(x));
}
]])
	local code_WGS84 = [[
//// MODULE_NAME: chart_WGS84
//// MODULE_DEPENDS: M_PI perp2 rad

const float WGS84_a = 6378137.;		// equatorial radius
const float WGS84_b = 6356752.3142;	// polar radius
const float WGS84_esq = 1. - WGS84_b * WGS84_b / (WGS84_a * WGS84_a);
const float WGS84_e = sqrt(WGS84_esq);
const float WGS84_flattening = 1. - WGS84_b / WGS84_a;
const float WGS84_inverseFlattening = 298.257223563;
const float WGS84_eccentricitySquared = (2. * WGS84_inverseFlattening - 1.) / (WGS84_inverseFlattening * WGS84_inverseFlattening);
		
float WGS84_calc_N(
	float sinTheta
) {
	float denom = sqrt(1. - WGS84_eccentricitySquared * sinTheta * sinTheta);
	return WGS84_a / denom;
}

vec3 chart_WGS84(vec3 x) {
	float lat = x.x;
	float lon = x.y;
	float height = x.z;

	float phi = rad(lon);		// spherical φ
	float theta = rad(lat);		// spherical inclination angle (not azumuthal θ)
	float cosTheta = cos(theta);
	float sinTheta = sin(theta);
	
	float N = WGS84_calc_N(sinTheta);
	
	float NPlusH = N + height;
	vec3 y = vec3(
		NPlusH * cosTheta * cos(phi),
		NPlusH * cosTheta * sin(phi),
		(N * (1. - WGS84_eccentricitySquared) + height) * sinTheta
	);
	// at this point we're in meters, matching the geographic-charts code
	// but now I'm going to transform further to match the seismographic-visualization / geo-center-earth code
	y /= WGS84_a;			//convert from meters to normalized coordinates
	y.yz = -perp2(y.yz);	//rotate back so y is up
	y.xz = perp2(y.xz);		//now rotate so prime meridian is along -z instead of +x
	return y;
}
]]
	self.modules:addFromMarkup(code_WGS84)
	
	local code_cylinder = [[
//// MODULE_NAME: chart_cylinder
//// MODULE_DEPENDS: perp2 rad chart_WGS84

vec3 chart_cylinder(vec3 latLonHeight) {
	float lat = latLonHeight.x;
	float lon = latLonHeight.y;
	float height = latLonHeight.z;
	float latrad = rad(lat);
	float lonrad = rad(lon);
	float r = WGS84_a + height;
	float x = r * cos(lonrad);
	float y = r * sin(lonrad);
	float z = r * latrad;
	vec3 cartpos = vec3(x, y, z);
	// end of geographic-charts, beginning of vis aligning stuff
	cartpos /= WGS84_a;
	cartpos.yz = -perp2(cartpos.yz);	//rotate back so cartpos is up
	cartpos.xz = perp2(cartpos.xz);		//now rotate so prime meridian is along -z instead of +x
	return cartpos;
}
]]
	self.modules:addFromMarkup(code_cylinder)

	-- TODO instead of making one chart depend on another, put the WGS84 constants in one place
	local code_Equirectangular = [[
//// MODULE_NAME: chart_Equirectangular
//// MODULE_DEPENDS: M_PI rad chart_WGS84

const float Equirectangular_R = 2. / M_PI;
const float Equirectangular_lambda0 = 0.;
const float Equirectangular_phi0 = 0.;
const float Equirectangular_phi1 = 0.;
const float cos_Equirectangular_phi1 = cos(Equirectangular_phi1);
vec3 chart_Equirectangular(vec3 latLonHeight) {
	float lat = latLonHeight.x;
	float lon = latLonHeight.y;
	float height = latLonHeight.z;
	float latrad = rad(lat);
	float lonrad = rad(lon);
	float x = Equirectangular_R * (lonrad - Equirectangular_lambda0) * cos_Equirectangular_phi1;
	float y = Equirectangular_R * (latrad - Equirectangular_phi0);
	float z = height / WGS84_a;
	return vec3(x,y,z);
}
]]
	self.modules:addFromMarkup(code_Equirectangular)

	local code_Azimuthal_equidistant = [[
//// MODULE_NAME: chart_Azimuthal_equidistant 
//// MODULE_DEPENDS: M_PI rad chart_WGS84

vec3 chart_Azimuthal_equidistant(vec3 latLonHeight) {
	float lat = latLonHeight.x;
	float lon = latLonHeight.y;
	float height = latLonHeight.z;
	float latrad = rad(lat);
	float lonrad = rad(lon);
	float azimuthal = M_PI / 2. - latrad;
	float x = -sin(lonrad + M_PI) * azimuthal;
	float y = cos(lonrad + M_PI) * azimuthal;
	float z = height / WGS84_a;
	return vec3(x,y,z);
}
]]
	self.modules:addFromMarkup(code_Azimuthal_equidistant)
	
	local code_Mollweide = [[
//// MODULE_NAME: chart_Mollweide
//// MODULE_DEPENDS: M_PI rad isfinite chart_WGS84

const float M_SQRT_2 = sqrt(2.);
const float M_SQRT_8 = sqrt(8.);
const float Mollweide_R = M_PI / 4.;
const float Mollweide_lambda0 = 0.;	// in degrees

vec3 chart_Mollweide(vec3 latLonHeight) {
	float lat = latLonHeight.x;
	float lon = latLonHeight.y;
	float height = latLonHeight.z;
	float lonrad = rad(lon);
	float lambda = lonrad;
	float latrad = rad(lat);
	float phi = latrad;
	float theta;
	if (phi == .5 * M_PI) {
		theta = .5 * M_PI;
	} else {
		theta = phi;
		for (int i = 0; i < 10; ++i) {
			float dtheta = (2. * theta + sin(2. * theta) - M_PI * sin(phi)) / (2. + 2. * cos(theta));
			if (abs(dtheta) < 1e-5) break;
			theta -= dtheta;
		}
	}
	float mollweidex = Mollweide_R * M_SQRT_8 / M_PI * (lambda - Mollweide_lambda0) * cos(theta);
	float mollweidey = Mollweide_R * M_SQRT_2 * sin(theta);
	float mollweidez = height / WGS84_a;
	if (!isfinite(mollweidex)) mollweidex = 0;
	if (!isfinite(mollweidey)) mollweidey = 0;
	if (!isfinite(mollweidez)) mollweidez = 0;
	return vec3(mollweidex, mollweidey, mollweidez);
}
]]
	self.modules:addFromMarkup(code_Mollweide)

	local allChartCode = self.modules:getCodeAndHeader(
		'chart_WGS84',
		'chart_cylinder',
		'chart_Equirectangular',
		'chart_Azimuthal_equidistant',
		'chart_Mollweide'
	)

	self.globeTexShader = GLProgram{
		vertexCode = table{
'#version 460',
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
#version 460
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
glreport'here'
	self.globeTexShader:useNone()
glreport'here'

	self.globeStationPointShader = GLProgram{
		vertexCode = table{
'#version 460',
allChartCode,
[[
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform float weight_WGS84;
uniform float weight_cylinder;
uniform float weight_Equirectangular;
uniform float weight_Azimuthal_equidistant;
uniform float weight_Mollweide;

uniform float playtime;
uniform float pointSizeBase;

uniform sampler2D dataTex;
uniform int dataTexSize;	// == maxTextureSize

in vec3 vertex;

// (index, size) in the dataTex
in ivec2 stationTexCoord;

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
	gl_Position = projectionMatrix * (modelViewMatrix * vec4(pos, 1.));


	// TODO falloff of some kind
	// at a ortho width of 1 the point size can safely be 1 or so
	// at ortho width 1e-4 or so it can be 5 or so idk
	gl_PointSize = pointSizeBase;
	//gl_PointSize = 5. * projectionMatrix[0].x;


	// get the index based on playtime
	int index = stationTexCoord.x + int(
		clamp(playtime, 0., 1.) 
		* float(stationTexCoord.y-1)
	);
	// convert it to pixel location / channel
	// maybe this is better in integers / as a compute shader?
	// then I don't have to use max texture size too
	const int numChannels = 4;
	int ch = index % numChannels;
	index -= ch;
	index /= numChannels;
	int dx = index % dataTexSize;
	index -= dx;
	index /= dataTexSize;
	int dy = index;	//should be in bounds 
	vec4 c = texture(dataTex,
		vec2(
			(.5 + float(dx)),
			(.5 + float(dy))
		) / float(dataTexSize)
	);
	datav = c[ch];
}
]]
}:concat'\n',
		fragmentCode = [[
#version 460
in float datav;
out vec4 fragColor;
void main() {
	fragColor = vec4(datav, .5, -datav, 1.);
}
]],
		uniforms = {
			dataTex = 0,
		},
	}
glreport'here'
	self.globeStationPointShader:useNone()
glreport'here'

	datas = table()
	local dataDir = 'data'
	for f in file(dataDir):dir() do
		local fn = dataDir..'/'..f
		local size = file(fn):attr().size
		if size > 0 then
			datas:insert{sacfn=fn}
		end
	end

	-- row i = datas[i], col j = time j
	-- how to decide what size to use?
	-- for max tex size 16384 and 288000 records we got 17.5 texture rows per record ...
	-- so if i have to wrap data then why not just pack it and store each data in texture x and y and size
	-- ok also if I have 288000 values at 20 hz then I have 14400 seconds worth = 240 mins = 4 hr
	local numChannels = 4
	local dataImageSize = maxTextureSize	-- hmm this is getting me GL_OUT_OF_MEMORY error
	-- TODO what can I query to find the max tex memory?
	local dataImageSize = 8192
	local dataImage = Image(dataImageSize, dataImageSize, numChannels, 'float')
	local indexmax = dataImageSize * dataImageSize * numChannels
	local index = 0
	timer('reading data', function()
		for row,data in ipairs(datas) do
			for buffer, stats in zipIter(data.sacfn) do
				data.pts, data.hdr = readSAC(buffer, stats)
				data.hdr = data.hdr[0]	-- ref instead of ptr
				-- data.pts is data.hdr.npts in size
				if index + data.hdr.npts >= indexmax then
					error("ran out of pixels in our seismo dataImage")
				end
				data.pixelIndex = index
				--[[ don't really need this.
				local i = index
				data.pixelChannel = i % numChannels
				i = (i - data.pixelChannel) / numChannels
				data.pixelX = i % dataImageSize
				i = (i - data.pixelX) / dataImageSize
				data.pixelY = i
				assert(data.pixelY < dataImageSize)
				--]]
				ffi.copy(
					dataImage.buffer + index,
					data.pts,
					ffi.sizeof'float' * data.hdr.npts)
				index = index + data.hdr.npts
				
				-- get station info associated with data
				-- use the first station
				local sig = data.sacfn:match('^'..dataDir..'/query%-(.*)%-sac%.zip$')
				assert(sig, "couldn't get sig from file")
				local s = stationsForSig[sig]
				assert(#s > 0, "couldn't find a station for sig "..sig)
				data.station = s[1]

print(data.hdr.npts, data.sacfn, data.pixelIndex)--, data.pixelChannel, data.pixelX, data.pixelY)
				-- ok theres no VertexAttrib2i so here goes
				-- I should just use attribpointer
				local vec4i = require 'vec-ffi.vec4i'
				data.stationTexCoordPtr = vec4i(
					data.pixelIndex,
					data.hdr.npts,
					0,
					0
				)
			end
		end
	end)
	--[[ this doesn't show anything useful and takes too long so ...
	timer('writing', function()
		dataImage:normalize():save'dataimage.png'
	end)
	--]]
print('dataImage size', dataImage.width, dataImage.height)
glreport'here'
	self.dataTex = GLTex2D{
		image = dataImage,
		format = gl.GL_RGBA,
		type = gl.GL_FLOAT,
		internalFormat = gl.GL_RGBA32F,
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
	}
glreport'here'
	GLTex2D:unbind()
glreport'here'
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
playSpeed = 1
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
		playtime = playtime,
		pointSizeBase = pointSizeBase,
	}
	self.dataTex:bind()
	gl.glDepthMask(gl.GL_FALSE)
	gl.glEnable(gl.GL_VERTEX_PROGRAM_POINT_SIZE)
	-- ok not all stations have data associated with them ...
	-- maybe I should be cycling thru the data, and then lining up data with stations with lat/lon
	gl.glUniform1i(self.globeStationPointShader.uniforms.dataTexSize.loc, self.dataTex.width)
	gl.glBegin(gl.GL_POINTS)
	-- [[ draw only the data sensors
	for _,d in ipairs(datas) do
		gl.glVertexAttrib4iv(
			self.globeStationPointShader.attrs.stationTexCoord.loc,
			d.stationTexCoordPtr.s
		)
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
	
	self.dataTex:unbind()
	self.globeStationPointShader:useNone()
--]==]

	if playing then
		playtime = playtime + dt * playSpeed
		if playtime > 1 then
			playtime = 0
			playing = false
		end
	end

	App.super.update(self)
glreport'here'
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
	ig.luatableInputFloat('play speed', _G, 'playSpeed')
	if playing then
		if ig.igButton'stop' then
			playing = false
		end
	else
		if ig.igButton'play' then
			playing = true
		end
	end
	ig.igSameLine()
	ig.luatableInputFloat('play time', _G, 'playtime')
	ig.luatableInputFloat('pointSizeBase', _G, 'pointSizeBase')
end

App():run()
