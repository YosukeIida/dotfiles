-- =========================
-- Neovim config (minimal) for Git graph in TUI-ish style
-- Location: ~/.config/nvim/init.lua
-- =========================

-- Basic UX (optional)
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.termguicolors = true

-- =========================
-- bootstrap lazy.nvim (plugin manager)
-- =========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local uv = vim.uv or vim.loop

if not uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nCheck your network / git install, then retry.\n", "None" },
    }, true, {})
    return
  end
end

vim.opt.rtp:prepend(lazypath)

-- =========================
-- plugins
-- =========================
require("lazy").setup({
  -- Git wrapper: :Git ...
  { "tpope/vim-fugitive" },

  -- TUI-ish commit graph viewer: :Flog / :Flogsplit
  {
    "rbong/vim-flog",
    cmd = { "Flog", "Flogsplit", "Floggit" },
    dependencies = { "tpope/vim-fugitive" },
  },

  -- Diff UI (optional but very useful)
  { "sindrets/diffview.nvim" },

  -- Git graph in a buffer + Diffview integration (optional)
  {
    "isakbm/gitgraph.nvim",
    dependencies = { "sindrets/diffview.nvim" },
    keys = {
      {
        "<leader>gg",
        function()
          require("gitgraph").draw({}, { all = true, max_count = 5000 })
        end,
        desc = "GitGraph",
      },
    },
  },
})

-- =========================
-- keymaps
-- =========================
vim.keymap.set("n", "<leader>gf", "<cmd>Flog<cr>", { desc = "Flog (git graph)" })
vim.keymap.set("n", "<leader>gF", "<cmd>Flogsplit<cr>", { desc = "Flog split" })
