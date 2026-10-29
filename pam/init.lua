local PAM = {
  Grid = require("pam.grid"),
  Heap = require("pam.heap"),
  Spatial = require("pam.spatial"),
  astar = require("pam.astar"),
  path = require("pam.path"),
  alignment = require("pam.alignment"),
  love = require("pam.love"),
}

function PAM.new_grid(opts)
  return PAM.Grid.new(opts)
end

function PAM.new_spatial(cell_size)
  return PAM.Spatial.new(cell_size)
end

function PAM.find(grid, start, goal, opts)
  return PAM.astar.find(grid, start, goal, opts)
end

function PAM.walkable_path(grid, start, goal, opts)
  local path, stats, reason = PAM.astar.find(grid, start, goal, opts)
  if not path then
    return nil, stats, reason
  end
  return PAM.path.smooth(grid, path, opts), stats
end

return PAM
