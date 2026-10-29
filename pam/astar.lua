local Heap = require("pam.heap")

local M = {}

local sqrt = math.sqrt
local abs = math.abs
local max = math.max
local min = math.min

local SQRT2 = sqrt(2)

local heuristics = {}

heuristics.manhattan = function(dx, dy)
  return abs(dx) + abs(dy)
end

heuristics.euclidean = function(dx, dy)
  return sqrt(dx * dx + dy * dy)
end

heuristics.octile = function(dx, dy)
  dx, dy = abs(dx), abs(dy)
  return max(dx, dy) + (SQRT2 - 1) * min(dx, dy)
end

heuristics.chebyshev = function(dx, dy)
  return max(abs(dx), abs(dy))
end

local function each_neighbor(grid, x, y, diagonal, corner_cutting, fn)
  local function visit(nx, ny, base)
    local cost = grid:cell_cost(nx, ny)
    if cost then
      fn(nx, ny, base * cost)
    end
  end

  visit(x + 1, y, 1)
  visit(x - 1, y, 1)
  visit(x, y + 1, 1)
  visit(x, y - 1, 1)

  if not diagonal then
    return
  end

  local function corner_open(nx, ny)
    if corner_cutting then
      return true
    end
    if nx ~= x then
      if not grid:is_walkable(nx, y) then
        return false
      end
    end
    if ny ~= y then
      if not grid:is_walkable(x, ny) then
        return false
      end
    end
    return true
  end

  if corner_open(x + 1, y + 1) then
    visit(x + 1, y + 1, SQRT2)
  end
  if corner_open(x - 1, y + 1) then
    visit(x - 1, y + 1, SQRT2)
  end
  if corner_open(x + 1, y - 1) then
    visit(x + 1, y - 1, SQRT2)
  end
  if corner_open(x - 1, y - 1) then
    visit(x - 1, y - 1, SQRT2)
  end
end

function M.find(grid, start, goal, opts)
  opts = opts or {}
  local sx, sy = start.x, start.y
  local gx, gy = goal.x, goal.y

  local stats = {
    expanded = 0,
    generated = 0,
    max_open = 0,
    open_at_end = 0,
  }

  if not grid:is_inside(sx, sy) then
    return nil, stats, "start outside grid"
  end
  if not grid:is_inside(gx, gy) then
    return nil, stats, "goal outside grid"
  end
  if not grid:is_walkable(sx, sy) then
    return nil, stats, "start blocked"
  end
  if not grid:is_walkable(gx, gy) then
    return nil, stats, "goal blocked"
  end

  if sx == gx and sy == gy then
    return { { x = sx, y = sy } }, stats, nil
  end

  local diagonal = opts.diagonal
  if diagonal == nil then
    diagonal = grid.diagonal
  end
  local corner_cutting = opts.corner_cutting
  if corner_cutting == nil then
    corner_cutting = grid.corner_cutting
  end
  local weight = opts.heuristic_weight or 1
  local max_nodes = opts.max_nodes or 100000

  local heuristic
  if type(opts.heuristic) == "function" then
    heuristic = opts.heuristic
  else
    local name = opts.heuristic or (diagonal and "octile" or "manhattan")
    heuristic = heuristics[name]
    if not heuristic then
      error("unknown heuristic '" .. tostring(name) .. "'", 2)
    end
  end

  local width = grid.width
  local open = Heap.new(function(a, b)
    if a.f ~= b.f then
      return a.f < b.f
    end
    if a.h ~= b.h then
      return a.h < b.h
    end
    return a.seq < b.seq
  end)

  local start_key = (sy - 1) * width + sx
  local goal_key = (gy - 1) * width + gx
  local g_score = { [start_key] = 0 }
  local came_from = {}
  local closed = {}
  local sequence = 0

  open:push({ x = sx, y = sy, g = 0, h = heuristic(sx - gx, sy - gy) * weight, seq = 0 })

  while not open:empty() do
    local current = open:pop()
    local key = (current.y - 1) * width + current.x

    if key == goal_key then
      local path = {}
      local node_key = key
      while node_key do
        local cx = (node_key - 1) % width + 1
        local cy = math.floor((node_key - 1) / width) + 1
        path[#path + 1] = { x = cx, y = cy }
        node_key = came_from[node_key]
      end
      local reversed = {}
      for index = #path, 1, -1 do
        reversed[#reversed + 1] = path[index]
      end
      stats.open_at_end = open:size()
      return reversed, stats, nil
    end

    if not closed[key] then
      closed[key] = true
      stats.expanded = stats.expanded + 1

      if stats.expanded > max_nodes then
        stats.open_at_end = open:size()
        return nil, stats, "node budget exceeded"
      end

      each_neighbor(grid, current.x, current.y, diagonal, corner_cutting, function(nx, ny, step)
        local neighbor_key = (ny - 1) * width + nx
        if closed[neighbor_key] then
          return
        end
        local tentative = current.g + step
        local known = g_score[neighbor_key]
        if known == nil or tentative < known then
          g_score[neighbor_key] = tentative
          came_from[neighbor_key] = key
          sequence = sequence + 1
          local h = heuristic(nx - gx, ny - gy) * weight
          open:push({ x = nx, y = ny, g = tentative, h = h, f = tentative + h, seq = sequence })
          stats.generated = stats.generated + 1
          if open:size() > stats.max_open then
            stats.max_open = open:size()
          end
        end
      end)
    end
  end

  stats.open_at_end = 0
  return nil, stats, "unreachable"
end

M.heuristics = heuristics

return M
