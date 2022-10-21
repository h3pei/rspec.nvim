local Jumper = {}

local to_spec_patterns = {
  simple = {
    pattern = [[^\(.*/\)\?\(.*\).rb$]],
    replace = "spec/\\1\\2_spec.rb",
  },
  gem = {
    pattern = [[^lib/\(.*/\)\?\(.*\).rb$]],
    replace = "spec/\\1\\2_spec.rb",
  },
  rails = {
    default = {
      pattern = [[^app/\(.*/\)\?\(.*\).rb$]],
      replace = "spec/\\1\\2_spec.rb",
    },
    request = {
      pattern = [[^app/controllers/\(.*/\)\?\(.*\)_controller.rb$]],
      replace = "spec/requests/\\1\\2_spec.rb",
    },
    view = {
      pattern = [[^app/views/\(.*/\)\?\(.*\)$]],
      replace = "spec/views/\\1\\2_spec.rb",
    },
  },
}

--- Trace back the parent directory from bufname and infer the root path of the project.
---
--- example:
---   bufname: "/path/to/project/lib/foo/sample.rb"
---   => "/path/to/project"
---
---@param bufname string
---@return string|nil
local function infer_project_root(bufname)
  local paths = vim.fs.find({ ".rspec", "spec" }, { upward = true, path = bufname })

  if vim.tbl_isempty(paths) then
    return nil
  end

  return vim.fs.dirname(paths[1])
end

--- Get a relative path to the project root for bufname
---
--- example:
---   bufname: "/path/to/project/lib/foo/sample.rb"
---   project_root: "/path/to/project"
---   => "lib/foo/sample.rb"
---
---@param bufname string
---@param project_root string
---@return string
local function get_relative_pathname_from_project_root(bufname, project_root)
  local bufpath = vim.split(bufname, "/")
  local project_root_path = vim.split(project_root, "/")
  local relative_path = vim.list_slice(bufpath, #project_root_path + 1)

  return table.concat(relative_path, "/")
end

---@param subject string
---@param params { pattern: string, replace: string }
---@return string
local function sub(subject, params)
  return vim.fn.substitute(subject, params.pattern, params.replace, "")
end

---@param relative_product_code_path string
---@return string[]
local function infer_rails_spec_paths(relative_product_code_path)
  local dir_entries = vim.split(relative_product_code_path, "/")

  -- TODO: Routing specs, Generator specs
  local results
  if dir_entries[2] == "controllers" then
    results = {
      sub(relative_product_code_path, to_spec_patterns.rails.request), -- Request specs
      sub(relative_product_code_path, to_spec_patterns.rails.default), -- Controller specs
    }
  elseif dir_entries[2] == "views" then
    results = { sub(relative_product_code_path, to_spec_patterns.rails.view) }
  else
    results = { sub(relative_product_code_path, to_spec_patterns.rails.default) }
  end

  return results
end

--- Infer spec paths from the current product code path.
--- This function does not check the existence of the inferred file.
---
---@param bufname string
---@param project_root string
---@return string[]
local function infer_spec_paths(bufname, project_root)
  local relative_path = get_relative_pathname_from_project_root(bufname, project_root)

  local relative_spec_paths = {}
  if vim.startswith(relative_path, "lib/") then
    relative_spec_paths = { sub(relative_path, to_spec_patterns.gem) }
  elseif vim.startswith(relative_path, "app/") then
    relative_spec_paths = infer_rails_spec_paths(relative_path)
  else
    relative_spec_paths = { sub(relative_path, to_spec_patterns.simple) }
  end

  local results = {}
  for _, relative_spec_path in pairs(relative_spec_paths) do
    table.insert(results, project_root .. "/" .. relative_spec_path)
  end

  return results
end

--- Infer product code paths from the current spec path.
--- This function does not check the existence of the inferred file.
---
---@param bufname string
---@param project_root string
---@return string[]
local function infer_product_code_paths(bufname, project_root)
  local results = {}
  local relative_path = get_relative_pathname_from_project_root(bufname, project_root)
  local relative_product_code_path = vim.fn.substitute(relative_path, [[^spec/\(.*/\)\?\(.*\)_spec.rb$]], "\\1\\2.rb", "")

  -- TODO: Consider rspec-rails (e.g. request spec)
  for _, basedir in pairs({ "/app/", "/lib/", "/" }) do
    if vim.fn.isdirectory(project_root .. basedir) == 1 then
      table.insert(results, project_root .. basedir .. relative_product_code_path)
    end
  end

  return results
end

--- Jump between specs and product code.
---
--- If the current buffer is a product code, it jumps to the related specs.
--- If the current buffer is a specs, it jumps to the related product code.
---
--- The file to jump to is inferred based on the general directory structure and general file naming conventions.
--- - Example1. lib/foo/bar/baz.rb -> spec/foo/bar/baz_spec.rb
--- - Example2. app/models/user.rb -> spec/models/user_spec.rb
---
--- The inferred jump destination files have a priority order.
--- The files are searched in order of priority and the first file found is jumped to.
function Jumper.jump()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  local basename = vim.fs.basename(bufname)

  if not vim.endswith(basename, ".rb") then
    vim.notify("[rspec.nvim] RSpecJump can only be run on `.rb` files", vim.log.levels.WARN)
    return
  end

  local project_root = infer_project_root(bufname)
  if not project_root then
    vim.notify("[rspec.nvim] RSpecJump cannot infer project root path", vim.log.levels.WARN)
    return
  end

  local inferred_paths = {}
  if vim.endswith(basename, "_spec.rb") then
    inferred_paths = infer_product_code_paths(bufname, project_root)
  else
    inferred_paths = infer_spec_paths(bufname, project_root)
  end

  if vim.tbl_isempty(inferred_paths) then
    vim.notify("[rspec.nvim] RSpecJump cannot infer jump path", vim.log.levels.WARN)
    return
  end

  for _, inferred_path in pairs(inferred_paths) do
    if vim.fn.filereadable(inferred_path) == 1 then
      vim.api.nvim_command("edit " .. inferred_path)
      break
    end
  end
end

return Jumper
