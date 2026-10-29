local Grid = {}
Grid.__index = Grid

local floor = math.floor

function Grid.new(opts)
  opts = opts or {}
  local width = assert(tonumber(opts.width), "grid width is required")
  local height = assert(tonumber(opts.height), "grid height is required")
  assert(width > 0 and height > 0, "grid must have a positive size")
  return setmetatable({
    width = floor(width),
    height = floor(height),
    cell_size = opts.cell_size or 1,
    diagonal = opts.diagonal ~= false,
    corner_cutting = opts.corner_cutting == true,
    walkable = opts.walkable,
    cost = opts.cost,
    overrides = {},
  }, Grid)
end

function Grid.from_rows(rows, opts)
  opts = opts or {}
  local height = #rows
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row)
  end
  local blocked = {}
  for y, row in ipairs(rows) do
    for x = 1, width do
      local char = row:sub(x, x)
      if char == "#" or char == "X" then
        blocked[y * width + x] = true
      end
    end
  end
  local grid = Grid.new({
    width = width,
    height = height,
    cell_size = opts.cell_size,
    diagonal = opts.diagonal,
    corner_cutting = opts.corner_cutting,
    cost = opts.cost,
    walkable = function(x, y)
      if blocked[y * width + x] then
        return false
      end
      if opts.walkable then
        return opts.walkable(x, y)
      end
      return true
    end,
  })
  return grid
end

function Grid:is_inside(x, y)
  return x >= 1 and y >= 1 and x <= self.width and y <= self.height
end

function Grid:key(x, y)
  return (y - 1) * self.width + x
end

function Grid:is_walkable(x, y)
  if not self:is_inside(x, y) then
    return false
  end
  local override = self.overrides[(y - 1) * self.width + x]
  if override ~= nil then
    return override
  end
  if self.walkable then
    return self.walkable(x, y) ~= false
  end
  return true
end

function Grid:cell_cost(x, y)
  if not self:is_walkable(x, y) then
    return nil
  end
  if self.cost then
    local value = self.cost(x, y)
    if value ~= nil then
      return math.max(1, value)
    end
  end
  return 1
end

function Grid:set_blocked(x, y, blocked)
  if not self:is_inside(x, y) then
    return false
  end
  if blocked == nil then
    blocked = true
  end
  self.overrides[(y - 1) * self.width + x] = not blocked
  return true
end

function Grid:clear_override(x, y)
  if not self:is_inside(x, y) then
    return false
  end
  self.overrides[(y - 1) * self.width + x] = nil
  return true
end

function Grid:neighbors(x, y, out)
  out = out or {}
  local count = 0
  local widths = self.width
  local overrides = self.overrides
  local walkable = self.walkable
  local cost_fn = self.cost

  local function allowed(cx, cy)
    if cx < 1 or cy < 1 or cx > widths or cy > self.height then
      return false
    end
    local override = overrides[(cy - 1) * widths + cx]
    if override ~= nil then
      return override
    end
    if walkable then
      return walkable(cx, cy) ~= false
    end
    return true
  end

  local function add(cx, cy, base)
    if not allowed(cx, cy) then
      return
    end
    local value = 1
    if cost_fn then
      local custom = cost_fn(cx, cy)
      if custom ~= nil then
        value = math.max(1, custom)
      end
    end
    count = count + 1
    out[count] = { x = cx, y = cy, cost = base * value }
  end

  add(x + 1, y, 1)
  add(x - 1, y, 1)
  add(x, y + 1, 1)
  add(x, y - 1, 1)

  if self.diagonal then
    local diagonal = math.sqrt(2)
    local allow_corner = self.corner_cutting
    if allow_corner or (allowed(x + 1, y) and allowed(x, y + 1)) then
      add(x + 1, y + 1, diagonal)
    end
    if allow_corner or (allowed(x - 1, y) and allowed(x, y + 1)) then
      add(x - 1, y + 1, diagonal)
    end
    if allow_corner or (allowed(x + 1, y) and allowed(x, y - 1)) then
      add(x + 1, y - 1, diagonal)
    end
    if allow_corner or (allowed(x - 1, y) and allowed(x, y - 1)) then
      add(x - 1, y - 1, diagonal)
    end
  end

  return out, count
end

function Grid:world_to_cell(wx, wy)
  local size = self.cell_size
  return floor(wx / size) + 1, floor(wy / size) + 1
end

function Grid:cell_to_world(cx, cy, center)
  local size = self.cell_size
  local wx = (cx - 1) * size
  local wy = (cy - 1) * size
  if center then
    wx = wx + size / 2
    wy = wy + size / 2
  end
  return wx, wy
end

return Grid
