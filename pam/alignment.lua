local M = {}

local floor = math.floor
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local pi = math.pi
local max = math.max
local min = math.min

function M.world_to_cell(x, y, cell_size)
  return floor(x / cell_size) + 1, floor(y / cell_size) + 1
end

function M.cell_to_world(cx, cy, cell_size, center)
  local x = (cx - 1) * cell_size
  local y = (cy - 1) * cell_size
  if center then
    x = x + cell_size / 2
    y = y + cell_size / 2
  end
  return x, y
end

function M.snap(value, cell_size, mode)
  local scaled = value / cell_size
  if mode == "floor" then
    return floor(scaled) * cell_size
  elseif mode == "ceil" then
    return math.ceil(scaled) * cell_size
  end
  return floor(scaled + 0.5) * cell_size
end

function M.snap_center(value, cell_size)
  return M.snap(value - cell_size / 2, cell_size) + cell_size / 2
end

function M.path_to_world(path, cell_size, center)
  local out = {}
  for index, cell in ipairs(path) do
    local x, y = M.cell_to_world(cell.x, cell.y, cell_size, center)
    local point = { x = x, y = y }
    if cell.x ~= nil then
      point.cx = cell.x
      point.cy = cell.y
    end
    out[index] = point
  end
  return out
end

function M.formation(cx, cy, count, opts)
  opts = opts or {}
  count = max(0, floor(count or 0))
  local spacing = opts.spacing or 32
  local angle = opts.angle or 0
  local shape = opts.shape or "line"
  local fx = cos(angle)
  local fy = sin(angle)
  local rx = -fy
  local ry = fx
  local out = {}

  if shape == "column" then
    for index = 1, count do
      local distance = -(index - 1) * spacing
      out[index] = { x = cx + fx * distance, y = cy + fy * distance }
    end
    return out
  end

  if shape == "wedge" then
    if count > 0 then
      out[1] = { x = cx, y = cy }
    end
    local row = 1
    while #out < count do
      local distance = row * spacing
      local lateral = row * spacing * 0.6
      local base_x = cx - fx * distance
      local base_y = cy - fy * distance
      out[#out + 1] = { x = base_x + rx * lateral, y = base_y + ry * lateral }
      if #out < count then
        out[#out + 1] = { x = base_x - rx * lateral, y = base_y - ry * lateral }
      end
      row = row + 1
    end
    return out
  end

  if shape == "circle" then
    local radius = opts.radius
    if not radius then
      if count <= 1 then
        radius = 0
      else
        radius = spacing / (2 * sin(pi / count))
      end
    end
    local start_angle = opts.start_angle or 0
    for index = 1, count do
      local theta = start_angle + (index - 1) * (2 * pi / count)
      out[index] = { x = cx + cos(theta) * radius, y = cy + sin(theta) * radius }
    end
    return out
  end

  local span = (count - 1) * spacing / 2
  for index = 1, count do
    local offset = (index - 1) * spacing - span
    out[index] = { x = cx + rx * offset, y = cy + ry * offset }
  end
  return out
end

local function angle_for(id)
  if type(id) == "number" then
    return id * 2.399963
  end
  local code = 0
  for index = 1, #tostring(id) do
    code = code + tostring(id):byte(index) * index
  end
  return code * 0.618033
end

function M.separation(entities, spatial, opts)
  opts = opts or {}
  local strength = opts.strength or 1
  local default_radius = opts.radius or 16
  local neighbor_radius = opts.neighbor_radius or default_radius
  local layer = opts.layer
  local max_push = opts.max_push
  local displacements = {}

  for index, entity in ipairs(entities) do
    local radius = entity.radius or default_radius
    local dx, dy = 0, 0
    local count = 0
    local candidates = spatial:query_circle(entity.x, entity.y, radius + neighbor_radius, layer)
    for _, other in ipairs(candidates) do
      if other.id ~= entity.id then
        local other_radius = other.radius or default_radius
        local ox = entity.x - (other.x + other.w / 2)
        local oy = entity.y - (other.y + other.h / 2)
        local distance_sq = ox * ox + oy * oy
        local minimum = radius + other_radius
        if distance_sq < minimum * minimum then
          local distance = sqrt(distance_sq)
          local overlap = minimum - distance
          if distance < 0.0001 then
            local angle = angle_for(other.id or index)
            ox = cos(angle)
            oy = sin(angle)
            distance = 1
          end
          count = count + 1
          dx = dx + (ox / distance) * overlap
          dy = dy + (oy / distance) * overlap
        end
      end
    end
    if count > 0 then
      dx = dx * strength
      dy = dy * strength
      if max_push then
        local magnitude = sqrt(dx * dx + dy * dy)
        if magnitude > max_push then
          dx = dx / magnitude * max_push
          dy = dy / magnitude * max_push
        end
      end
    end
    displacements[index] = { id = entity.id, dx = dx, dy = dy }
  end

  return displacements
end

function M.resolve(entities, spatial, opts)
  local displacements = M.separation(entities, spatial, opts)
  for index, entity in ipairs(entities) do
    local push = displacements[index]
    if push.dx ~= 0 or push.dy ~= 0 then
      entity.x = entity.x + push.dx
      entity.y = entity.y + push.dy
      if spatial:get(entity.id) then
        local radius = entity.radius or (opts and opts.radius) or 16
        spatial:update(entity.id, entity.x - radius, entity.y - radius, radius * 2, radius * 2)
      end
    end
  end
  return displacements
end

function M.clamp_to_grid(x, y, grid, cell_size)
  local half = cell_size / 2
  x = max(half, min(x, grid.width * cell_size - half))
  y = max(half, min(y, grid.height * cell_size - half))
  return x, y
end

return M
