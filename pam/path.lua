local M = {}

local abs = math.abs
local sqrt = math.sqrt

local function supercover(x0, y0, x1, y1, on_cell, corner_cutting)
  local dx = x1 - x0
  local dy = y1 - y0
  local nx = abs(dx)
  local ny = abs(dy)
  local sign_x = dx >= 0 and 1 or -1
  local sign_y = dy >= 0 and 1 or -1
  local x, y = x0, y0
  if not on_cell(x, y) then
    return false
  end
  local ix, iy = 0, 0
  while ix < nx or iy < ny do
    local decision = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
    if decision == 0 then
      if not corner_cutting then
        if not on_cell(x + sign_x, y) then
          return false
        end
        if not on_cell(x, y + sign_y) then
          return false
        end
      end
      x = x + sign_x
      y = y + sign_y
      ix = ix + 1
      iy = iy + 1
    elseif decision < 0 then
      x = x + sign_x
      ix = ix + 1
    else
      y = y + sign_y
      iy = iy + 1
    end
    if not on_cell(x, y) then
      return false
    end
  end
  return true
end

function M.each_cell(x0, y0, x1, y1, callback, opts)
  opts = opts or {}
  return supercover(x0, y0, x1, y1, function(x, y)
    return callback(x, y) ~= false
  end, opts.corner_cutting == true)
end

function M.line_of_sight(grid, x0, y0, x1, y1, opts)
  opts = opts or {}
  local corner_cutting = opts.corner_cutting
  if corner_cutting == nil then
    corner_cutting = grid.corner_cutting
  end
  return supercover(x0, y0, x1, y1, function(x, y)
    return grid:is_walkable(x, y)
  end, corner_cutting)
end

function M.smooth(grid, path, opts)
  opts = opts or {}
  local count = #path
  if count <= 2 then
    local copy = {}
    for index = 1, count do
      copy[index] = path[index]
    end
    return copy
  end

  local out = { path[1] }
  local index = 1
  while index < count do
    local farthest = index + 1
    for candidate = count, index + 2, -1 do
      if M.line_of_sight(grid, path[index].x, path[index].y, path[candidate].x, path[candidate].y, opts) then
        farthest = candidate
        break
      end
    end
    out[#out + 1] = path[farthest]
    index = farthest
  end
  return out
end

function M.compress(path, opts)
  opts = opts or {}
  local tolerance = opts.tolerance or 0.0001
  local count = #path
  if count <= 2 then
    local copy = {}
    for index = 1, count do
      copy[index] = path[index]
    end
    return copy
  end

  local out = { path[1] }
  for index = 2, count - 1 do
    local previous = out[#out]
    local current = path[index]
    local following = path[index + 1]
    local ax = current.x - previous.x
    local ay = current.y - previous.y
    local bx = following.x - current.x
    local by = following.y - current.y
    local cross = ax * by - ay * bx
    if abs(cross) > tolerance then
      out[#out + 1] = current
    end
  end
  out[#out + 1] = path[count]
  return out
end

function M.length(path, cell_size)
  local size = cell_size or 1
  local total = 0
  for index = 2, #path do
    local dx = (path[index].x - path[index - 1].x) * size
    local dy = (path[index].y - path[index - 1].y) * size
    total = total + sqrt(dx * dx + dy * dy)
  end
  return total
end

function M.reverse(path)
  local out = {}
  for index = #path, 1, -1 do
    out[#out + 1] = path[index]
  end
  return out
end

return M
