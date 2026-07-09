local function has_local_tsgo(root_dir)
  return vim.fn.executable(vim.fs.joinpath(root_dir, "node_modules", ".bin", "tsgo")) == 1
end

require("mason").setup()

local completion_opts = { expr = true, silent = true }
vim.keymap.set("i", "<C-x><C-z>", 'pumvisible() ? "\\<C-e>" : "\\<C-x>\\<C-z>"', completion_opts)
vim.keymap.set("i", "<Tab>", 'pumvisible() ? "\\<C-n>" : "\\<Tab>"', completion_opts)
vim.keymap.set("i", "<S-Tab>", 'pumvisible() ? "\\<C-p>" : "\\<C-h>"', completion_opts)
vim.keymap.set("i", "<C-j>", 'pumvisible() ? "\\<C-n>" : "\\<C-j>"', completion_opts)
vim.keymap.set("i", "<C-k>", 'pumvisible() ? "\\<C-p>" : "\\<C-k>"', completion_opts)
vim.keymap.set(
  "i",
  "<CR>",
  'pumvisible() && complete_info().selected >= 0 ? "\\<C-y>" : "\\<C-g>u\\<CR>"',
  completion_opts
)
vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, { silent = true, desc = "Trigger completion" })

local typescript_fallback_dir = vim.fs.joinpath(
  vim.fn.expand("~/.local/share"),
  "typescript-language-service",
  "node_modules",
  "typescript",
  "lib"
)
local managed_servers = { "bashls", "ts_ls" }
if vim.fn.executable("go") == 1 then
  table.insert(managed_servers, "gopls")
end
if vim.fn.executable("opam") == 1 then
  table.insert(managed_servers, "ocamllsp")
end
local java_version
if vim.fn.executable("java") == 1 then
  local result = vim.system({ "java", "-version" }, { text = true }):wait()
  local output = (result.stderr or "") .. (result.stdout or "")
  java_version = tonumber(output:match('version "(%d+)'))
end
if java_version and java_version >= 21 then
  table.insert(managed_servers, "jdtls")
end

local tsgo_root_dir = vim.lsp.config.tsgo.root_dir
local ts_ls_root_dir = vim.lsp.config.ts_ls.root_dir

vim.lsp.config("tsgo", {
  root_dir = function(bufnr, on_dir)
    tsgo_root_dir(bufnr, function(root_dir)
      if has_local_tsgo(root_dir) then
        on_dir(root_dir)
      end
    end)
  end,
})

vim.lsp.config("ts_ls", {
  cmd = {
    vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "typescript-language-server"),
    "--stdio",
  },
  init_options = {
    tsserver = { fallbackPath = typescript_fallback_dir },
  },
  root_dir = function(bufnr, on_dir)
    ts_ls_root_dir(bufnr, function(root_dir)
      if not has_local_tsgo(root_dir) then
        on_dir(root_dir)
      end
    end)
  end,
})

vim.lsp.config("jdtls", {
  settings = {
    java = {
      autobuild = { enabled = false },
      format = { enabled = true },
      import = { maven = { enabled = true } },
      maven = { downloadSources = true },
      completion = { importOrder = { "java", "javax", "org", "com" } },
      configuration = { updateBuildConfiguration = "automatic" },
    },
  },
})

require("mason-lspconfig").setup({
  ensure_installed = managed_servers,
  automatic_enable = managed_servers,
})

local function show_locations(locations, client, win, bufnr, title)
  if not locations or vim.tbl_isempty(locations) then
    vim.notify("No " .. title:lower() .. " found", vim.log.levels.INFO)
    return
  end

  if locations.uri or locations.targetUri then
    locations = { locations }
  end

  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
      return
    end

    vim.api.nvim_win_call(win, function()
      if #locations == 1 then
        vim.lsp.util.show_document(locations[1], client.offset_encoding, { focus = true })
        return
      end

      local items = vim.lsp.util.locations_to_items(locations, client.offset_encoding)
      vim.fn.setqflist({}, " ", { title = title, items = items })
      vim.cmd("botright copen")
    end)
  end)
end

local function go_to_source_definition()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "ts_ls" })
  local client = clients[1]
  if not client then
    vim.lsp.buf.definition()
    return
  end

  local win = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  local function go_to_definition()
    client:request("textDocument/definition", params, function(err, locations)
      if err then
        vim.notify("Go to definition failed: " .. err.message, vim.log.levels.ERROR)
        return
      end
      show_locations(locations, client, win, bufnr, "Definitions")
    end, bufnr)
  end

  client:exec_cmd({
    command = "_typescript.goToSourceDefinition",
    title = "Go to source definition",
    arguments = { params.textDocument.uri, params.position },
  }, { bufnr = bufnr }, function(err, locations)
    if err or not locations or vim.tbl_isempty(locations) then
      go_to_definition()
      return
    end
    show_locations(locations, client, win, bufnr, "Source definitions")
  end)
end

local group = vim.api.nvim_create_augroup("dotfiles.lsp", { clear = true })
local format_group = vim.api.nvim_create_augroup("dotfiles.lsp.format", { clear = true })
local highlight_group = vim.api.nvim_create_augroup("dotfiles.lsp.highlight", { clear = true })
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then
      return
    end

    local opts = { buffer = event.buf, silent = true }
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
    end
    map("n", "gd", go_to_source_definition, "Go to source definition")
    map("n", "gD", vim.lsp.buf.definition, "Go to definition")
    map("n", "<C-w>]", function()
      vim.cmd("split")
      vim.lsp.buf.definition()
    end, "Go to definition in split")
    map("n", "gy", vim.lsp.buf.type_definition, "Go to type definition")
    map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
    map("n", "gr", vim.lsp.buf.references, "List references")
    map("n", "K", vim.lsp.buf.hover, "Show documentation")
    map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("n", "[v", function()
      vim.diagnostic.jump({ count = -1 })
    end, "Previous diagnostic")
    map("n", "]v", function()
      vim.diagnostic.jump({ count = 1 })
    end, "Next diagnostic")
    map("n", "[c", function()
      vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR })
    end, "Previous error")
    map("n", "]c", function()
      vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR })
    end, "Next error")

    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end

    if client:supports_method("textDocument/documentHighlight") then
      vim.api.nvim_clear_autocmds({ group = highlight_group, buffer = event.buf })
      vim.api.nvim_create_autocmd("CursorHold", {
        group = highlight_group,
        buffer = event.buf,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
        group = highlight_group,
        buffer = event.buf,
        callback = vim.lsp.buf.clear_references,
      })
    end

    if client.name == "gopls" then
      vim.api.nvim_clear_autocmds({ group = format_group, buffer = event.buf })
      vim.api.nvim_create_autocmd("BufWritePre", {
        group = format_group,
        buffer = event.buf,
        callback = function()
          vim.lsp.buf.format({ bufnr = event.buf, id = client.id, timeout_ms = 1000 })
        end,
      })
    end
  end,
})

vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "✗",
      [vim.diagnostic.severity.WARN] = "!",
      [vim.diagnostic.severity.INFO] = "ℹ",
      [vim.diagnostic.severity.HINT] = "ℹ",
    },
  },
})

vim.lsp.enable("tsgo")
