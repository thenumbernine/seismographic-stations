#!/usr/bin/env luajit

local charts = require 'geographic-charts'
local template = require 'template'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local glreport = require 'gl.report'
local ig = require 'imgui'
local matrix_ffi = require 'matrix.ffi'

matrix_ffi.real = 'float'	-- default matrix_ffi type

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

	self.modelViewMatrix = matrix_ffi.zeros{4,4}
	self.projectionMatrix = matrix_ffi.zeros{4,4}
	self.globeShader = GLProgram{
		vertexCode = template([[
#version 460

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform float weight_WGS84;
uniform float weight_cylinder;
uniform float weight_Equirectangular;
uniform float weight_Azimuthal_equidistant;
uniform float weight_Mollweide;

const float M_PI = <?=math.pi?>;

float rad(float d) {
	return d * M_PI / 180.;
}

vec2 perp2(vec2 a) {
	return vec2(-a.y, a.x);
}

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

vec3 chart_cylinder(vec3 latLonHeight) {
	float lat = latLonHeight.x;
	float lon = latLonHeight.y;
	float height = latLonHeight.z;
	float latrad = rad(lat);
	float lonrad = rad(lon);
	float r = height + 1;
	float x = r * cos(lonrad);
	float y = r * sin(lonrad);
	float z = r * latrad;
	vec3 cartpos = vec3(x, y, z);
	// end of geographic-charts, beginning of vis aligning stuff
	cartpos.yz = -perp2(cartpos.yz);	//rotate back so cartpos is up
	cartpos.xz = perp2(cartpos.xz);		//now rotate so prime meridian is along -z instead of +x
	return cartpos;
}

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

bool isfinite(float x) { return !(isinf(x) || isnan(x)); }

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
	float lon = vertex.y;
	float height = vertex.z;

	float latrad = rad(lat);
	float azimuthal = .5*M_PI - latrad;
	float aziFrac = azimuthal / M_PI;

	float lonrad = rad(lon);
	float lonFrac = lonrad / (2. * M_PI);
	float unitLonFrac = lonFrac + .5;

	texcoordv = vec2(unitLonFrac, aziFrac);
}
]]),
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

function App:vertex(lat, lon, height)
	local latrad = math.rad(lat)
	local azimuthal = .5*math.pi - latrad
	local aziFrac = azimuthal / math.pi

	local lonrad = math.rad(lon)
	local lonFrac = lonrad / (2 * math.pi)
	local unitLonFrac = lonFrac + .5
	
	gl.glVertexAttrib3f(self.globeShader.attrs.vertex.loc, lat, lon, height)
end

function App:update()
	gl.glClearColor(0, 0, 0, 1)
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	self.globeShader:use()
	gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.modelViewMatrix.ptr)
	gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projectionMatrix.ptr)
	self.globeShader:setUniforms{
		weight_WGS84 = spheroidCoeff,
		weight_cylinder = cylCoeff,
		weight_Equirectangular = equirectCoeff,
		weight_Azimuthal_equidistant = aziequiCoeff,
		weight_Mollweide = mollweideCoeff,
		modelViewMatrix = self.modelViewMatrix.ptr,
		projectionMatrix = self.projectionMatrix.ptr,
	}
	self.colorTex:bind(0)
	gl.glVertexAttrib4f(self.globeShader.attrs.color.loc, 1, 1, 1, 1)
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
			self:vertex(lat, lon, 0)

			local unitLonFrac = j/jdivs
			local lonFrac = unitLonFrac - .5
			local lonrad = lonFrac * 2 * math.pi			-- longitude
			local lon = math.deg(lonrad)
			self:vertex(lat, lon, 0)
		end
		gl.glEnd()
	end

	-- TODO charts in GLSL so I can put the vertex code in GPU mem
	gl.glDepthMask(gl.GL_FALSE)
	gl.glPointSize(3)
	gl.glVertexAttrib4f(self.globeShader.attrs.color.loc, 0, 0, 0, 1)
	gl.glBegin(gl.GL_POINTS)
	for _,s in ipairs(stations) do
		self:vertex(s.Latitude, s.Longitude, s.Elevation + .1)
	end
	gl.glEnd()
	gl.glPointSize(2)
	gl.glVertexAttrib4f(self.globeShader.attrs.color.loc, 1, 0, 0, 1)
	gl.glBegin(gl.GL_POINTS)
	for _,s in ipairs(stations) do
		self:vertex(s.Latitude, s.Longitude, s.Elevation + .2)
	end
	gl.glEnd()
	gl.glPointSize(1)
	gl.glDepthMask(gl.GL_TRUE)
	
	self.colorTex:unbind(0)
	self.globeShader:useNone()

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
