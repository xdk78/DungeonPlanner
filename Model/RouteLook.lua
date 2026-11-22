-- How a route's line looks along its length: the colour ramp from its start to its end, and the pieces a line is drawn
-- in (short pieces so the colour can change along a long straight stretch, dashes on a corridor's way back). Pure
-- colour maths and geometry, run once per map redraw (a plan, view, focus or setting change), never per frame.
--
--   RouteLook.Ramp(r, g, b, o)        a ramp from the colour (r, g, b) to a partner colour (End), as a table of steps.
--   RouteLook.At(ramp, t)             the ramp's colour at t (0 = the route's start, 1 = its end).
--   RouteLook.End(r, g, b, o)         the partner colour: hue turned, lightness moved, in the sRGB gamut.
--   RouteLook.Oklab(r, g, b)          sRGB (0..1) to Oklab L, a, b; RouteLook.FromOklab(L, a, b) back (not clamped).
--   RouteLook.Distance(c1, c2)        the perceptual distance between two { r, g, b } colours (Oklab).
--   RouteLook.Desaturate(r, g, b, k)  the colour moved towards a grey of its own lightness by k (0..1).
--   RouteLook.Along(points)           each point's place along the route, 0..1, by distance.
--   RouteLook.Pieces(pts, o)          the pieces to draw a path (Model/RouteLegs.lua Lanes) in.
--   RouteLook.BackLength(pts, bounds) how long a path's way back is inside bounds (what its dashes cost).
--   RouteLook.Clip(ax, ay, bx, by, b) the part of a segment inside a rectangle, t0 and t1 along it.
--
-- The ramp runs in Oklch (Oklab's lightness, chroma and hue). o (UI/Style.lua ROUTE.ramp) = { turn (degrees of hue
-- from the start to the end), lift (how far the end's lightness moves: lighter when the start is darker than mid,
-- else darker; within low..high), chroma (the end's at least), grey (a start with less chroma counts as grey and turns
-- towards greyHue), steps (in a ramp table; At blends between neighbours), paper (parchment map art) }. The hue turns
-- the way whose end differs more from the start in lightness and on the blue-yellow axis (what red-green colour
-- blindness keeps) and whose colours stay further from parchment. Each step is fitted into the sRGB gamut by lowering
-- its chroma, never its lightness or hue.

local _, ns = ...
local RouteLook = ns:NewModule("RouteLook")

local sqrt, cos, sin, atan2, rad, deg = math.sqrt, math.cos, math.sin, math.atan2, math.rad, math.deg
local max, min, ceil, floor, huge = math.max, math.min, math.ceil, math.floor, math.huge

local function cbrt(x)
	return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3)
end
local function toLinear(c)
	return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local function toGamma(c)
	return c <= 0.0031308 and 12.92 * c or 1.055 * max(0, c) ^ (1 / 2.4) - 0.055
end

function RouteLook.Oklab(r, g, b)
	r, g, b = toLinear(r), toLinear(g), toLinear(b)
	local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

function RouteLook.FromOklab(L, a, b)
	local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
	local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
	local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
	return toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
end

local EPS = 1e-4
local function inGamut(r, g, b)
	return r >= -EPS and r <= 1 + EPS and g >= -EPS and g <= 1 + EPS and b >= -EPS and b <= 1 + EPS
end
local function clamp01(x)
	return max(0, min(1, x))
end

-- Oklch to sRGB, the chroma lowered until the colour fits (hue and lightness kept).
local function fromLch(L, C, h)
	local ca, sa = cos(rad(h)), sin(rad(h))
	local r, g, b = RouteLook.FromOklab(L, C * ca, C * sa)
	if not inGamut(r, g, b) then
		local lo, hi = 0, C
		for _ = 1, 18 do
			local mid = (lo + hi) / 2
			r, g, b = RouteLook.FromOklab(L, mid * ca, mid * sa)
			if inGamut(r, g, b) then
				lo = mid
			else
				hi = mid
			end
		end
		r, g, b = RouteLook.FromOklab(L, lo * ca, lo * sa)
	end
	return clamp01(r), clamp01(g), clamp01(b)
end

local function lch(r, g, b)
	local L, A, B = RouteLook.Oklab(r, g, b)
	return L, sqrt(A * A + B * B), deg(atan2(B, A))
end

-- The start and end in Oklch ({ L0, C0, h0, L1, C1, h1 }), the end's hue unwrapped so that the start's plus the turn
-- reaches it.
local function ends(r, g, b, o)
	local L0, C0, h0 = lch(r, g, b)
	local _, _, b0 = RouteLook.Oklab(r, g, b)
	-- Lighter towards the end (a line reads best lighter than its dark edge), unless the start is light already.
	local L1 = max(o.low, min(o.high, L0 < o.mid and L0 + o.lift or L0 - o.lift))
	local C1 = max(C0, o.chroma)
	local best, bestScore
	for _, sign in ipairs({ 1, -1 }) do
		local turn = sign * o.turn
		local s, h1 = h0, h0 + turn
		if C0 < o.grey then
			h1 = o.greyHue
			s = h1 - turn
		end
		local paper = huge
		for i = 1, 4 do
			local t = i / 4
			paper = min(paper, RouteLook.Distance({ fromLch(L0 + (L1 - L0) * t, C0 + (C1 - C0) * t, s + turn * t) }, o.paper))
		end
		local score = sqrt((L1 - L0) ^ 2 + (sin(rad(h1)) * C1 - b0) ^ 2) + paper
		if not bestScore or score > bestScore + 1e-9 then
			best, bestScore = { L0, C0, s, L1, C1, h1 }, score
		end
	end
	return best
end

function RouteLook.End(r, g, b, o)
	local e = ends(r, g, b, o)
	return fromLch(e[4], e[5], e[6])
end

-- A ramp table: { n = steps, [0..n] = { r, g, b } }. Its first step is the colour given, exactly.
function RouteLook.Ramp(r, g, b, o)
	local e = ends(r, g, b, o)
	local L0, C0, h0, L1, C1, h1 = e[1], e[2], e[3], e[4], e[5], e[6]
	local n = max(1, floor(o.steps))
	local ramp = { n = n, [0] = { r, g, b } }
	for i = 1, n do
		local t = i / n
		ramp[i] = { fromLch(L0 + (L1 - L0) * t, C0 + (C1 - C0) * t, h0 + (h1 - h0) * t) }
	end
	return ramp
end

function RouteLook.At(ramp, t)
	local n = ramp.n
	local x = clamp01(t or 0) * n
	local i = min(n - 1, floor(x))
	local f = x - i
	local a, b = ramp[i], ramp[i + 1]
	return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
end

function RouteLook.Distance(c1, c2)
	local L1, a1, b1 = RouteLook.Oklab(c1[1], c1[2], c1[3])
	local L2, a2, b2 = RouteLook.Oklab(c2[1], c2[2], c2[3])
	return sqrt((L1 - L2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

function RouteLook.Desaturate(r, g, b, k)
	local L, A, B = RouteLook.Oklab(r, g, b)
	local f = 1 - max(0, min(1, k))
	local dr, dg, db = RouteLook.FromOklab(L, A * f, B * f)
	return clamp01(dr), clamp01(dg), clamp01(db)
end

-- points: { { x, y }, ... } (a route's own points). Returns { [i] = 0..1 }: the path length up to point i over the
-- whole length (all 0 for a route without length).
function RouteLook.Along(points)
	local out, total = { 0 }, 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		total = total + sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		out[i] = total
	end
	for i = 1, #points do
		out[i] = total > 0 and out[i] / total or 0
	end
	return out
end

-- The part of segment (ax, ay)..(bx, by) inside the rectangle b = { x1, y1, x2, y2 }: t0, t1 (0..1 along it), or nil
-- when it lies outside (Liang-Barsky).
local function clip(ax, ay, bx, by, b)
	local t0, t1 = 0, 1
	local dx, dy = bx - ax, by - ay
	for _, pq in ipairs({ { -dx, ax - b[1] }, { dx, b[3] - ax }, { -dy, ay - b[2] }, { dy, b[4] - ay } }) do
		local p, q = pq[1], pq[2]
		if p == 0 then
			if q < 0 then
				return nil
			end
		else
			local r = q / p
			if p < 0 then
				if r > t1 then
					return nil
				end
				t0 = max(t0, r)
			else
				if r < t0 then
					return nil
				end
				t1 = min(t1, r)
			end
		end
	end
	return t0, t1
end
RouteLook.Clip = clip

-- The length of a drawn path's way back (pts as for Pieces) inside bounds ({ x1, y1, x2, y2 }; nil: all of it), and
-- how many of its segments lie (partly) inside.
function RouteLook.BackLength(pts, bounds)
	local total, parts = 0, 0
	for k = 2, #pts do
		if pts[k].back then
			local a, b = pts[k - 1], pts[k]
			local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
			local t0, t1 = 0, 1
			if bounds then
				t0, t1 = clip(a[1], a[2], b[1], b[2], bounds)
			end
			if t0 then
				total, parts = total + len * (t1 - t0), parts + 1
			end
		end
	end
	return total, parts
end

-- pts: a drawn path (RouteLegs.Lanes: points { x, y, seg, back }), segment k joining pts[k - 1] and pts[k]; a point
-- with `back` ends a stretch on a corridor's way back. o = { steps (a stretch longer than 1/steps of the path is cut
-- into pieces that long, at most `split` pieces; nil: one piece per segment), split, dash = { on, off } (dash and gap
-- lengths on the way back; nil: no dashes), bounds ({ x1, y1, x2, y2 }: dashes only inside it, their spacing kept as
-- if drawn all along; nil: everywhere), limit (most dashes inside the bounds: longer dashes and gaps when there would
-- be more; nil: as given) }. Returns the pieces { x0, y0, x1, y1, k, dash = true? } in path order, and how many of
-- them are dashes.
local TINY = 1e-6 -- screen units: a rest shorter than this is no dash or gap
function RouteLook.Pieces(pts, o)
	o = o or {}
	local n = #pts
	local lens, total = {}, 0
	for k = 2, n do
		local a, b = pts[k - 1], pts[k]
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		lens[k] = len
		total = total + len
	end
	local dash, bounds = o.dash, o.bounds
	local on, off
	if dash then
		on, off = dash.on, dash.off
		local count = o.limit and RouteLook.BackLength(pts, bounds) / (on + off) or 0
		if o.limit and count > o.limit then
			on, off = on * count / o.limit, off * count / o.limit
		end
	end
	local period = on and on + off
	local step = o.steps and total > 0 and total / o.steps or nil
	local split = o.split or 8
	local out, dashes = {}, 0
	local phase = 0
	for k = 2, n do
		local a, b, len = pts[k - 1], pts[k], lens[k]
		if len == 0 then
			out[#out + 1] = { a[1], a[2], b[1], b[2], k } -- a point drawn twice (a route just begun): one piece
		else
			local dx, dy = (b[1] - a[1]) / len, (b[2] - a[2]) / len
			if on and pts[k].back then
				if not pts[k - 1].back then
					phase = 0 -- a new stretch starts with a dash
				end
				-- Only the part inside the bounds gets dashes; the rest moves the phase on.
				local t0, t1 = 0, 1
				if bounds then
					t0, t1 = clip(a[1], a[2], b[1], b[2], bounds)
				end
				if not t0 then
					phase = (phase + len) % period
				else
					local pos, stop = len * t0, len * t1
					phase = (phase + pos) % period
					while pos < stop - TINY do
						if phase < on - TINY then
							local e = min(stop, pos + on - phase)
							out[#out + 1] = { a[1] + dx * pos, a[2] + dy * pos, a[1] + dx * e, a[2] + dy * e, k, dash = true }
							dashes = dashes + 1
							phase = phase + (e - pos)
							pos = e
						elseif phase < period - TINY then
							local e = min(stop, pos + period - phase)
							phase = phase + (e - pos)
							pos = e
						else
							phase = 0
						end
					end
					phase = (phase + (len - pos)) % period
				end
			else
				local m = step and max(1, min(split, ceil(len / step - 1e-9))) or 1
				for j = 1, m do
					local p0, p1 = len * (j - 1) / m, len * j / m
					out[#out + 1] = { a[1] + dx * p0, a[2] + dy * p0, a[1] + dx * p1, a[2] + dy * p1, k }
				end
			end
		end
	end
	return out, dashes
end
