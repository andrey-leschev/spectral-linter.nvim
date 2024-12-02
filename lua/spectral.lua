local M = {}
M._state = {}
M.diag_items = {}
M.diag_files = {}

P = function (table)
  print(vim.inspect(table))
end

local severities = {
  vim.diagnostic.severity.ERROR,
  vim.diagnostic.severity.WARN,
  vim.diagnostic.severity.INFO,
  vim.diagnostic.severity.HINT,
}

local error_types = { "E", "W", "I", "H", }
local ns = vim.api.nvim_create_namespace("Spectral")


local function spectral_to_qflist(data)
  local result = vim.json.decode(data)

  -- prevent warning on yaml files without supported schema
  if result[1].code == "unrecognized-format" then
    return {}
  end

  local qf_items = {}
  for _, diag in ipairs(result) do
    table.insert(qf_items, {
      filename = diag.source,
      lnum = diag.range.start.line + 1,
      end_lnum = diag.range["end"].line + 1,
      col = diag.range.start.character + 1,
      end_col = diag.range["end"].character + 1,
      valid = diag.code,
      type = error_types[diag.severity + 1],
      text = diag.message,
      user_data = diag.path,
    })

    table.insert(M.diag_items, {
      filename = diag.source,
      source = "spectral",
      severity = severities[diag.severity + 1],
      code = diag.code,
      message = diag.message,
      lnum = diag.range.start.line,
      end_lnum = diag.range["end"].line,
      col = diag.range.start.character,
      end_col = diag.range["end"].character,
    })

    if not vim.list_contains(M.diag_files, diag.source) then
      vim.list_extend(M.diag_files, { diag.source })
    end
  end

  if qf_items == nil then return {} end
  return qf_items
end

local on_stdout = function(_, data)
  P(data)
  if data == nil or #data == 0 or string.sub(data, 1, 2) == 'No' or string.sub(data, 1, 2) == '[]' then return end
  local qf_items = spectral_to_qflist(data)
  vim.schedule(function()
    vim.fn.setqflist({}, ' ', { title = "Spectral", id = "spectral", items = qf_items })
  end)
end

local filter_by = function (data, pair)
    local key, value = next(pair, nil)
    local filtered = {}
    for _, item in ipairs(data) do
        if item[key] == value then
            table.insert(filtered, item)
        end
    end
    return filtered
end

local fill_buf_with_diagnostics = function ()
  -- by buffer
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- check if loaded
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      goto continue
    end

    -- clear old diagnostics
    -- после нового запуска линтера, список файлов очищается и в новом списке может не быть файла из старого списка, тогда в нем останется старая диагностика, 
    -- TODO нужно до запуска линтера очищать диагностику из старого списка, если он не пустой
    vim.diagnostic.set(ns, bufnr, {})

    -- check if have new diagnostics
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if not vim.list_contains(M.diag_files, filename) then
      goto continue
    end

    -- get diagnostics
    local dg_by_buf = filter_by(M.diag_items, { filename = filename })
    if not dg_by_buf or #dg_by_buf == 0 then
      goto continue
    end

    -- set diagnostics
    vim.diagnostic.set(ns, bufnr, dg_by_buf)
    ::continue::
  end
end

M.try_lint = function ()
  M.diag_items = {}
  M.diag_files = {}
  vim.fn.setqflist({}, 'r') --очистить quickfix список
  vim.system({'spectral', 'lint', '-f', 'json', 'openapi.yaml'}, { stdout = on_stdout }, vim.schedule_wrap(function(obj)
    _ = obj
    fill_buf_with_diagnostics()
  end))
end

return M
