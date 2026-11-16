-- Generates the addon's few textures (Media/*.tga): white rounded rectangles for 9-slice fills, a circle for dots and
-- markers, arrows and route chevrons, and the addon icon. Original art made by this script (MIT, like the rest of the repo); no game art.
-- Run from the repo root:  lua tools/gen_textures.lua
-- Textures are white so frames tint them with SetVertexColor; WoW needs power-of-two sizes.

local function writeTGA(path, w, h, pixel)
	local f = assert(io.open(path, "wb"))
	-- Uncompressed true-colour TGA, 32 bpp, origin top-left (descriptor 0x28: 8 alpha bits + top-left).
	f:write(string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w % 256, math.floor(w / 256), h % 256, math.floor(h / 256), 32,
		0x28))
	local row = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, b, a = pixel(x, y)
			row[#row + 1] = string.char(b, g, r, a)
		end
		f:write(table.concat(row))
		row = {}
	end
	f:close()
end

-- Coverage of a shape by 4x4 supersampling; inside(px, py) takes continuous coordinates.
local function coverage(x, y, inside)
	local n = 0
	for sy = 0, 3 do
		for sx = 0, 3 do
			if inside(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4) then
				n = n + 1
			end
		end
	end
	return n / 16
end

local function roundedRect(size, radius)
	return function(px, py)
		local cx = math.max(radius, math.min(size - radius, px))
		local cy = math.max(radius, math.min(size - radius, py))
		local dx, dy = px - cx, py - cy
		return dx * dx + dy * dy <= radius * radius
	end
end

local function white(inside)
	return function(x, y)
		local a = math.floor(coverage(x, y, inside) * 255 + 0.5)
		return 255, 255, 255, a
	end
end

local out = "Media/"
writeTGA(out .. "Rounded2.tga", 16, 16, white(roundedRect(16, 2)))
writeTGA(out .. "Rounded4.tga", 16, 16, white(roundedRect(16, 4)))
writeTGA(out .. "Rounded6.tga", 16, 16, white(roundedRect(16, 6)))
writeTGA(out .. "Circle.tga", 32, 32, white(function(px, py)
	local dx, dy = px - 16, py - 16
	return dx * dx + dy * dy <= 15 * 15
end))

-- Arrow: a chevron pointing up, for route direction arrows and patrol markers (rotated at runtime).
writeTGA(out .. "Arrow.tga", 32, 32, white(function(px, py)
	-- Triangle (16,4) (28,26) (4,26) with a notch cut from the base: a chevron.
	local function side(ax, ay, bx, by)
		return (bx - ax) * (py - ay) - (by - ay) * (px - ax)
	end
	local inTri = side(16, 4, 28, 26) >= 0 and side(28, 26, 4, 26) >= 0 and side(4, 26, 16, 4) >= 0
	local inNotch = side(16, 17, 28, 27) >= 0 and side(28, 27, 4, 27) >= 0 and side(4, 27, 16, 17) >= 0
	return inTri and not inNotch
end))
-- Ring: a 3 px circle outline (role rings, selection rings).
writeTGA(out .. "Ring.tga", 32, 32, white(function(px, py)
	local dx, dy = px - 16, py - 16
	local d = dx * dx + dy * dy
	return d <= 15 * 15 and d >= 12 * 12
end))

local function segDist(px, py, ax, ay, bx, by)
	local vx, vy = bx - ax, by - ay
	local t = ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)
	t = math.max(0, math.min(1, t))
	local dx, dy = px - (ax + t * vx), py - (ay + t * vy)
	return math.sqrt(dx * dx + dy * dy)
end

-- Chevron: a bold open chevron pointing up with a dark edge baked in, for route direction marks (rotated at runtime).
-- The white body takes the route's tint; the edge stays dark under any tint, so the mark reads on light parchment and on
-- its own line alike.
local function chevronDist(px, py)
	return math.min(segDist(px, py, 7, 21, 16, 11), segDist(px, py, 16, 11, 25, 21))
end
writeTGA(out .. "Chevron.tga", 32, 32, function(x, y)
	local body = coverage(x, y, function(px, py)
		return chevronDist(px, py) <= 3.6
	end)
	local edge = coverage(x, y, function(px, py)
		return chevronDist(px, py) <= 5.8
	end)
	if edge <= 0 then
		return 0, 0, 0, 0
	end
	-- The body's share of what is drawn here is white, the rest of the edge near-black.
	local v = math.floor(20 + 235 * body / edge + 0.5)
	return v, v, v, math.floor(edge * 255 + 0.5)
end)

-- Icon: a soft-grey rounded tile with an ink route (three stops joined by a line). The launcher shows Media/LogoIcon.tga
-- (tools/render_logo.py); this is only the fallback for the game's map icon (settings.gameIcon) on a client without it.
local stops = { { 16, 46 }, { 30, 22 }, { 48, 40 } }
writeTGA(out .. "Icon.tga", 64, 64, function(x, y)
	local tile = coverage(x, y, roundedRect(64, 10))
	local line = coverage(x, y, function(px, py)
		return segDist(px, py, stops[1][1], stops[1][2], stops[2][1], stops[2][2]) <= 2.2
			or segDist(px, py, stops[2][1], stops[2][2], stops[3][1], stops[3][2]) <= 2.2
	end)
	local dots = coverage(x, y, function(px, py)
		for _, s in ipairs(stops) do
			local dx, dy = px - s[1], py - s[2]
			if dx * dx + dy * dy <= 6 * 6 then
				return true
			end
		end
		return false
	end)
	local ink = math.max(line, dots)
	-- Tile #2a2a2a, ink #ededed.
	local v = math.floor(42 + (237 - 42) * ink + 0.5)
	return v, v, v, math.floor(tile * 255 + 0.5)
end)

-- Vignette: white, clear in the middle and rising to opaque at the edges (a soft band an eighth of the side wide, then
-- a gentle falloff), stretched over a map's art and tinted dark brown: the burnt edge of a parchment map.
writeTGA(out .. "Vignette.tga", 64, 64, function(x, y)
	local d = math.min(x + 0.5, y + 0.5, 64 - x - 0.5, 64 - y - 0.5) / 64 -- 0 at an edge, 0.5 in the middle
	local t = math.max(0, 1 - d / 0.16)
	return 255, 255, 255, math.floor(255 * t * t + 0.5)
end)

print("textures written to " .. out)
