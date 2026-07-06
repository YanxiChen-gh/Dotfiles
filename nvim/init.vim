" Neovim reads ~/.config/nvim/init.vim, not ~/.vimrc. Point it at the shared
" config so vim and nvim stay in sync from the single ~/.vimrc in this repo.
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
