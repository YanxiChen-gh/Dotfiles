" Keep shared editor behavior in ~/.vimrc, then layer Neovim's native LSP on top.
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
if isdirectory(expand('~/.vim/bundle/nvim-lspconfig')) &&
      \ isdirectory(expand('~/.vim/bundle/mason.nvim')) &&
      \ isdirectory(expand('~/.vim/bundle/mason-lspconfig.nvim'))
  luafile ~/.config/nvim/lsp.lua
endif
