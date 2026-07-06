" Include the system settings
if filereadable( "/etc/vimrc" )
   source /etc/vimrc
endif

" download vim-plug
if empty(glob('~/.vim/autoload/plug.vim'))
   silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
            \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
   autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" vim-plug begin
call plug#begin('~/.vim/bundle')

" Plug 'octol/vim-cpp-enhanced-highlight'
Plug 'jdhao/better-escape.vim'
Plug 'dstein64/vim-startuptime'
" Plug 'vim-latex/vim-latex', { 'for': 'tex' }
Plug 'lervag/vimtex', { 'for': 'tex' }
Plug 'KeitaNakamura/tex-conceal.vim', { 'for': 'tex' }
Plug 'rust-lang/rust.vim', { 'for': 'rust' }
Plug 'martinda/Jenkinsfile-vim-syntax', { 'for': 'Jenkinsfile' }
" Plug 'MarcWeber/vim-addon-mw-utils'
" Plug 'honza/vim-snippets'
" Plug 'vimwiki/vimwiki', { 'branch': 'dev' }
" Plug 'airblade/vim-rooter'
" Plug 'tbabej/taskwiki'
" Plug 'reasonml-editor/vim-reason-plus'
Plug 'powerman/vim-plugin-AnsiEsc'
Plug 'leafgarland/typescript-vim', { 'for': ['typescript', 'javascript'] }
Plug 'yggdroot/indentline'
" Plug 'nathanaelkane/vim-indent-guides'
Plug 'godlygeek/tabular'
" Plug 'idris-hackers/idris-vim'
Plug 'Shougo/echodoc.vim'
Plug 'romainl/vim-qf'
Plug 'SeraphRoy/vim-terminal-help'
" Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
" Plug 'Shougo/denite.nvim'
Plug 'gabrielelana/vim-markdown', { 'for': ['markdown', 'javascript'] }
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && npx --yes yarn install' }
" Plug 'xolox/vim-misc'
" Plug 'xolox/vim-notes'
" Plug 'pangloss/vim-javascript'
Plug 'tpope/vim-commentary'
Plug 'sickill/vim-pasta'
Plug 'luochen1990/rainbow'
Plug 'mbbill/undotree'
" Plug 'puremourning/vimspector'
" Plug 'bling/vim-airline'
Plug 'itchyny/lightline.vim'
" Plug 'flazz/vim-colorschemes'
" Plug 'gruvbox-community/gruvbox'
" Plug 'rktjmp/lush.nvim'
" Plug 'npxbr/gruvbox.nvim'
Plug 'sainnhe/gruvbox-material'
Plug 'rakr/vim-one'
" Plug 'neovim/nvim-lspconfig'
" Plug 'glepnir/lspsaga.nvim'
" Plug 'michaelb/sniprun', {'do': 'bash install.sh'}
Plug 'vim-test/vim-test', { 'on': ['UltestNearest', 'Ultest']}
" Plug 'rafamadriz/neon'
Plug 'rcarriga/vim-ultest', { 'do': ':UpdateRemotePlugins', 'on': ['UltestNearest', 'Ultest']}
" Plug 'xuhdev/vim-latex-live-preview'
" Plug 'vim-airline/vim-airline-themes'
" Plug 'oplatek/conque-shell'
" Plug 'wellle/targets.vim'
Plug 'tpope/vim-abolish'
Plug 'tpope/vim-repeat'
" Plug 'autozimu/LanguageClient-neovim', {
"     \ 'branch': 'next',
"     \ 'do': 'bash install.sh',
"     \ }
if has('nvim')
  " Plug 'Shougo/defx.nvim', { 'do': ':UpdateRemotePlugins' }
  " Plug 'kristijanhusak/defx-git'
  " Plug 'kristijanhusak/defx-icons'
else
  " Plug 'Shougo/defx.nvim'
  " Plug 'roxma/nvim-yarp'
  " Plug 'roxma/vim-hug-neovim-rpc'
endif
Plug 'tpope/vim-surround'
Plug 'jiangmiao/auto-pairs'
Plug 'raimondi/delimitmate'
" Plug 'skywind3000/asyncrun.vim'
" Plug 'ConradIrwin/vim-bracketed-paste'
Plug 'easymotion/vim-easymotion'
" Plug 'tpope/vim-eunuch'
" Plug 'tpope/vim-fugitive'
Plug 'bkad/camelcasemotion'
Plug 'tpope/vim-projectionist'
" Plug 'inkarkat/vim-ingo-library'
" vim-mark depends on vim-ingo-library
" Plug 'inkarkat/vim-mark'
" Plug 'skywind3000/vim-preview'
" Plug 'terryma/vim-expand-region'
" Plug 'python-mode/python-mode', { 'branch': 'develop' }
" Plug 'Yggdroot/LeaderF', { 'do': './install.sh' }
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
Plug 'nvim-telescope/telescope-fzy-native.nvim'
Plug 'szw/vim-maximizer'
" Plug 'neomake/neomake'
" Plug 'ludovicchabant/vim-gutentags'
" Plug 'SeraphRoy/gutentags_plus.vim'
" Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
" Plug 'Valloric/YouCompleteMe', {'do': './install.py'}
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}  " We recommend updating the parsers on update

" Plug 'neovim/nvim-lspconfig'
" Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}
" Plug 'williamboman/nvim-lsp-installer'
" " current function/lsp status
" Plug 'nvim-lua/lsp-status.nvim'
" " icons
" Plug 'onsails/lspkind-nvim'
" " signature help for functions lsp
" Plug 'ray-x/lsp_signature.nvim'
" 
" Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}
" Plug 'ms-jpq/coq.artifacts', {'branch': 'artifacts'}
" Plug 'ms-jpq/coq.thirdparty', {'branch': '3p'}
" " java lsp client
" Plug 'mfussenegger/nvim-jdtls'

" Plug 'neovim/nvim-lspconfig'
" Plug 'kabouzeid/nvim-lspinstall'
" Plug 'hrsh7th/nvim-compe'
" Plug 'mfussenegger/nvim-jdtls'
Plug 'mhinz/vim-signify'
" Plugin 'airblade/vim-gitgutter'
" Plugin 'roxma/vim-paste-easy'
" " All of your Plugins must be added before the following line

" Always load the vim-devicons as the very last one.
Plug 'ryanoasis/vim-devicons'
call plug#end()
" " To ignore plugin indent changes, instead use:
" "filetype plugin on
" "
" " Brief help
" " :PluginList       - lists configured plugins
" " :PluginInstall    - installs plugins; append `!` to update or just
" :PluginUpdate
" " :PluginSearch foo - searches for foo; append `!` to refresh local cache
" " :PluginClean      - confirms removal of unused plugins; append `!` to
" auto-approve removal
" "
" " see :h vundle for more details or wiki for FAQ
" " Put your non-Plugin stuff after this line
" Include the system settings

" ------------below are my customized configs----------------------

"       ------------general vim settings-------------

" <Leader> = ' '
let mapleader=" "

" Syntax Highlight
syntax on

" 256 color
set termguicolors
let $NVIM_TUI_ENABLE_TRUE_COLOR=1
" let &t_Co=256

" color scheme/theme
syntax enable
set background=dark
let g:gruvbox_contrast_dark = 'soft'
let g:gruvbox_material_diagnostic_line_highlight = 1
let g:gruvbox_material_transparent_background = 0
let g:gruvbox_material_menu_selection_background = 'grey'
let g:gruvbox_material_visual = 'reverse'
let g:gruvbox_material_diagnostic_line_highlight = 0
let g:gruvbox_material_diagnostic_virtual_text = 'colored'
let g:gruvbox_material_better_performance = 1
let g:gruvbox_material_enable_italic = 1
let g:gruvbox_material_current_word = 'bold'
hi Search cterm=NONE ctermfg=grey ctermbg=blue
colorscheme one

" disable the “Press ENTER or type command to continue” prompt in Vim
" https://stackoverflow.com/questions/890802/how-do-i-disable-the-press-enter-or-type-command-to-continue-prompt-in-vim
set cmdheight=2

if !has('nvim')
    set shortmess=a
endif

set mouse=

" line number on
set number relativenumber
autocmd BufEnter * set number relativenumber
autocmd BufEnter term://* set nonumber norelativenumber

" scrolling minimun lines
set scrolloff=5

" bottom status bar
set laststatus=2

" forget
set hidden

" show matching braces
set showmatch

" smart case sensitive search
set ignorecase
set smartcase

" max length of code is 85
set cc=150
set tw=150
autocmd FileType go :set cc=100 tw=100
"match Error /\%86v.\+/

" only highlight the overlength but not auto-wrapped
" set tw=0

" maps : to ;
map ; :

set encoding=utf-8

" make .vimrc has effect immediately
autocmd BufWritePost $MYVIMRC source $MYVIMRC

" shortcut for inserting a new line without entering insert mode
nmap oo :normal o<CR>k
nmap OO :normal O<CR>

"map esc to jj use better-escape now
" imap jj <Esc>

" set to auto read when a file is changed from the outside
set autoread

" Better command-line completion
set wildmenu
set wildmode=list:longest,full

" Search related
set hlsearch
set incsearch

" indentation
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
" autocmd FileType python :set expandtab tabstop=3 shiftwidth=3 softtabstop=3
" autocmd FileType yaml :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
" autocmd FileType json :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType typescript :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType javascript :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType yaml :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType xml :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType groovy :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType json :set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType java :set expandtab tabstop=4 shiftwidth=4 softtabstop=4

" backspace
set backspace=indent,eol,start

" " page up/down for side window
" noremap <Leader>e <C-w>p<C-u><C-w>p
" noremap <Leader>d <C-w>p<C-d><C-w>p

" ctags file
set tags=./.tags;,.tags

" Allow saving of files as sudo when I forgot to start vim using sudo.
cmap w!! w !sudo tee > /dev/null %

" set clipboard=unnamed

" persistent undo history
silent !mkdir /tmp/.vim_backup > /dev/null 2>&1
set undofile
set undodir=/tmp/.vim_backup

" Search for selected text, forwards or backwards.
vnoremap <silent> * :<C-U>
         \let old_reg=getreg('"')<Bar>let old_regtype=getregtype('"')<CR>
         \gvy/<C-R><C-R>=substitute(
         \escape(@", '/\.*$^~['), '\_s\+', '\\_s\\+', 'g')<CR><CR>
         \gV:call setreg('"', old_reg, old_regtype)<CR>

" restore cursor position
if has("autocmd")
   au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
            \| exe "normal! g'\"" | endif
endif

" " toggle paste mode automatically when paste
" let &t_SI .= "\<Esc>[?2004h"
" let &t_EI .= "\<Esc>[?2004l"
" inoremap <special> <expr> <Esc>[200~ XTermPasteBegin()
" function! XTermPasteBegin()
"   set pastetoggle=<Esc>[201~
"   set paste
"   return ""
" endfunction

" Configure ALT key for vim
function! Terminal_MetaMode(mode)
   if has('nvim') || has('gui_running')
      return
   endif
   function! s:metacode(mode, key)
      if a:mode == 0
         exec "set <M-".a:key.">=\e".a:key
      else
         exec "set <M-".a:key.">=\e]{0}".a:key."~"
      endif
   endfunc
   for i in range(10)
      call s:metacode(a:mode, nr2char(char2nr('0') + i))
   endfor
   for i in range(26)
      call s:metacode(a:mode, nr2char(char2nr('a') + i))
      call s:metacode(a:mode, nr2char(char2nr('A') + i))
   endfor
   if a:mode != 0
      for c in [',', '.', '/', ';', '[', ']', '{', '}']
         call s:metacode(a:mode, c)
      endfor
      for c in ['?', ':', '-', '_']
         call s:metacode(a:mode, c)
      endfor
   else
      for c in [',', '.', '/', ';', '{', '}']
         call s:metacode(a:mode, c)
      endfor
      for c in ['?', ':', '-', '_']
         call s:metacode(a:mode, c)
      endfor
   endif
endfunc

call Terminal_MetaMode(0) 

" hightlight current line only in normal mode
set cursorline
autocmd InsertLeave,WinEnter * set cursorline
autocmd InsertEnter,WinLeave * set nocursorline

" map CTRL_HJKL to move cursor in all mode
noremap <C-h> <left>
noremap <C-j> <down>
noremap <C-k> <up>
noremap <C-l> <right>

" insert mode as emacs
inoremap <C-h> <left>
inoremap <C-j> <down>
inoremap <C-k> <up>
inoremap <C-l> <right>
" Not use M-* because it will capture <esc>
inoremap <c-f> <s-right>
inoremap <c-b> <s-left>
inoremap <c-a> <home>
inoremap <c-e> <end>
inoremap <c-d> <del>


" faster command mode
cnoremap <c-h> <left>
cnoremap <c-j> <down>
cnoremap <c-n> <down>
cnoremap <c-k> <up>
cnoremap <c-p> <up>
cnoremap <c-l> <right>
cnoremap <c-a> <home>
cnoremap <c-e> <end>
cnoremap <c-d> <del>
cnoremap <c-f> <s-right>
cnoremap <c-b> <s-left>

" terminal
nmap :term<CR> :term<CR><C-w>J

" set auto-completion option
set completeopt-=preview
" set completeopt=menuone,noselect
" set completeopt=noselect,noinsert,menuone

" shift blocks in insert mode
" inoremap >> <esc>>>
" inoremap << <esc><<

" replace highlighted block
map <Leader>re gny:%s`<C-R>"``g<left><left>

" Copy indent from current line when starting a new line
set autoindent

" When on, a <Tab> in front of a line inserts blanks according to
" 'shiftwidth'.  'tabstop' or 'softtabstop' is used in other places.  A
" <BS> will delete a 'shiftwidth' worth of space at the start of the line.
set smarttab

" Timeout for key mapping sequences.
set ttimeout
if $TMUX != ''
   set ttimeoutlen=30
elseif &ttimeoutlen > 80 || &ttimeoutlen <= 0
   set ttimeoutlen=50
endif

" Delete comment character when joining commented lines
set formatoptions+=jtl

" " Load matchit.vim, but only if the user hasn't installed a newer version.
" if !exists('g:loaded_matchit') && findfile('plugin/matchit.vim', &rtp) ==# ''
"    runtime! macros/matchit.vim
" endif

" Highlight matches without moving
nnoremap * :let @/='\<<C-R>=expand("<cword>")<CR>\>'<CR>:set hls<CR>

" viminfo
set viminfo+=!

" If this many milliseconds nothing is typed the swap file will be written to disk
"  Also used for the CursorHold autocommand event.
set updatetime=300

" spell checking
" setlocal spell
" set spelllang=en_us
" inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u

" show indentation for tabs
set list lcs=tab:\|\ " note a space at the end

if has('nvim')
    set inccommand=nosplit
endif

" nnoremap <M-t> :tabnew<CR>:term<CR>
" noremap <M-H> :tabm -1<CR>
" noremap <M-L> :tabm +1<CR>
" nnoremap <M-h> gT
" nnoremap <M-l> gt
" tnoremap <M-t> <c-\><c-n>:tabnew<CR>:term<CR>
" tnoremap <M-h> <c-\><c-n>gT
" tnoremap <M-l> <c-\><c-n>gt
" tnoremap <M-H> <c-\><c-n>:tabm -1<CR>:startinsert<CR>
" tnoremap <M-L> <c-\><c-n>:tabm +1<CR>:startinsert<CR>

tnoremap <C-w>k <c-\><c-n><C-w>k
tnoremap <C-w><C-k> <c-\><c-n><C-w>k
tnoremap <C-w>l <c-\><c-n><C-w>l
tnoremap <C-w><C-l> <c-\><c-n><C-w>l
tnoremap <C-w>j <c-\><c-n><C-w>j
tnoremap <C-w><C-j> <c-\><c-n><C-w>j
tnoremap <C-w>h <c-\><c-n><C-w>h
tnoremap <C-w><C-h> <c-\><c-n><C-w>h

" DO NOT use the following maps because it will cause issues when we are in a vim within a ssh
if has("macunix")
    tnoremap <esc> <c-\><c-n>
endif
nnoremap <M-w> :tabclose<CR>
inoremap <M-H> <esc>:tabm -1<CR>
inoremap <M-L> <esc>:tabm +1<CR>
inoremap <M-h> <esc>gT
inoremap <M-l> <esc>gt

vnoremap <S-y> "+y

autocmd BufEnter term://* startinsert

" Automatically removing all trailing whitespace
" autocmd FileType c,cpp,java autocmd BufWritePre <buffer> %s/\s\+$//e

"       ------------end of general vim settings-------------

"       -------------plugin vim settings--------------------

" better-escape
let g:better_escape_shortcut = 'jj'
let g:better_escape_interval = 300

" treesitter settings

" telescope.nvim settings
nnoremap <C-p> <cmd>lua require('telescope.builtin').find_files()<cr>
nnoremap <Leader>p <cmd>lua require('telescope.builtin').live_grep()<cr>
nnoremap <Leader>fd <cmd>lua require('telescope.builtin').grep_string()<cr>
highlight default link TelescopePreviewLine Search
lua << EOF
local actions = require('telescope.actions')
require('telescope').setup{
    extensions = {
        fzy_native = {
            override_generic_sorter = false,
            override_file_sorter = true,
        }
    },
    defaults = {
        file_sorter = require'telescope.sorters'.get_fzy_sorter,
    path_display={"smart"},
        mappings = {
            i = {
                ["<C-j>"] = actions.move_selection_next,
                ["<C-k>"] = actions.move_selection_previous,
                ["<esc>"] = actions.close
            },
        }
    }
}
require('telescope').load_extension('fzy_native')
EOF

" LeaderF settings
" let g:Lf_ShortcutF = '<C-P>'
" let g:Lf_WindowHeight = 0.13
" let g:Lf_CacheDirectory = expand('~/.vim/cache')
" let g:Lf_ShowRelativePath = 0
" let g:Lf_DefaultMode = 'FullPath'
" let g:Lf_HideHelp = 1
" nmap <M-p> :LeaderfFunction<CR>
" nmap <Leader>p :Leaderf rg -e ''
" map <Leader>s <Plug>LeaderfRgBangCwordLiteralBoundary<CR>
" vmap <Leader>s <Plug>LeaderfRgBangVisualLiteralBoundary<CR>
" map <Leader>fd gny:<C-U><C-R>=printf("Leaderf! rg -F -e %s ", leaderf#Rg#visual())<CR>
" let g:Lf_WindowPosition = 'popup'
" let g:Lf_PreviewInPopup = 1
" let g:Lf_PreviewResult = {'Function':0, 'Colorscheme':1}
" let g:Lf_NormalMap = {
"          \ "File":   [["<ESC>", ':exec g:Lf_py "fileExplManager.quit()"<CR>']],
"          \ "Buffer": [["<ESC>", ':exec g:Lf_py "bufExplManager.quit()"<CR>']],
"          \ "Mru":    [["<ESC>", ':exec g:Lf_py "mruExplManager.quit()"<CR>']],
"          \ "Tag":    [["<ESC>", ':exec g:Lf_py "tagExplManager.quit()"<CR>']],
"          \ "Function":    [["<ESC>", ':exec g:Lf_py "functionExplManager.quit()"<CR>']],
"          \ "Colorscheme":    [["<ESC>", ':exec g:Lf_py "colorschemeExplManager.quit()"<CR>']],
"          \ }
" let g:Lf_WildIgnore = {
"          \ 'dir': ['.svn','.git','.hg', '.idea', '.bemol'],
"          \ 'file': ['*.sw?', '*.class']
"      \}

" auto pair
let g:AutoPairsShortcutToggle = ''
let g:AutoPairsShortcutJump = ''
let g:AutoPairsMapSpace = 0
let g:AutoPairsMultilineClose = 0

" vim-devicons and lightline.vim integration
function! DeviconsFiletype()
  return winwidth(0) > 70 ? (strlen(&filetype) ? &filetype . ' ' . WebDevIconsGetFileTypeSymbol() : 'no ft') : ''
endfunction

function! DeviconsFileformat()
  return winwidth(0) > 70 ? (&fileformat . ' ' . WebDevIconsGetFileFormatSymbol()) : ''
endfunction

" lightline.vim
let g:lightline = {
         \ 'colorscheme': 'one',
     \ 'active': {
         \   'left': [ [ 'mode', 'paste' ],
         \             [ 'cocstatus', 'readonly', 'filename', 'modified' ] ]
         \ },
         \ 'component_function': {
         \   'cocstatus': 'coc#status',
         \   'filetype': 'DeviconsFiletype',
         \   'fileformat': 'DeviconsFileformat',
         \ },
     \ }

" youcompleteme settings
let g:ycm_complete_in_comments=1
let g:enable_numbers = 0
let g:ycm_semantic_triggers =  {
         \ 'c,cpp,python,java,go,erlang,perl': ['re!\w{2}'],
         \ 'cs,lua,javascript': ['re!\w{2}'],
         \ }
let g:ycm_autoclose_preview_window_after_insertion = 1

" deoplete
let g:deoplete#enable_at_startup = 1

" ConqueTerm settings
let g:ConqueTerm_CWInsert = 1
let g:ConqueTerm_InsertOnEnter = 1
nmap :cv :ConqueTermVSplit bash

" shortcut for Undotree
nmap :undo :UndotreeToggle<CR>:UndotreeFocus<CR>

" turn off trailing whitespace detection
" autocmd VimEnter * AirlineToggleWhitespace

" easymotion settings
map <Leader>l <Plug>(easymotion-lineforward)
map <Leader>j <Plug>(easymotion-j)
map <Leader>k <Plug>(easymotion-k)
map <Leader>h <Plug>(easymotion-linebackward)
let g:EasyMotion_startofline = 0 " keep cursor column when JK motion

" vim-latex-live-preview settings
let g:livepreview_previewer = 'open -a Preview'
autocmd Filetype tex setl updatetime=5000
let g:which_bibliography = 'biber'
"let g:which_bibliography = 'bibtex'

" vim-latex settings
let g:Tex_CompileRule_pdf = 'pdflatex $*'
let g:Imap_UsePlaceHolders = 0

" vimtex settings
let g:tex_flavor = 'latex'
let g:vimtex_quickfix_enabled = 0

" tex-conceal.vim settings
set conceallevel=2
let g:tex_conceal="abdgms"

" Rainbow Paranthesis
let g:rainbow_active = 1
" au VimEnter * RainbowParenthesesToggle
" au Syntax * RainbowParenthesesLoadRound
" au Syntax * RainbowParenthesesLoadSquare
" au Syntax * RainbowParenthesesLoadBraces

" indent-guides
" let g:indent_guides_auto_colors = 0
" autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd ctermbg=236
" autocmd VimEnter,Colorscheme * :hi IndentGuidesEven ctermbg=237
" let g:indent_guides_guide_size = 1
" let g:indent_guides_enable_on_vim_startup =1
" let g:indent_guides_soft_pattern = ' '

" delimitMate
let delimitMate_balance_matchpairs = 1

" copy to clipboard no matter where you are
" nnoremap <leader>y :call system('nc localhost 9999', @0)<CR>
" nmap yy yy<leader>y
" nmap dd dd<leader>y
" vmap y y<leader>y
" vmap d d<leader>y

" camelcasemotion
call camelcasemotion#CreateMotionMappings('<leader>')

" vim-signify
nmap - <plug>(signify-prev-hunk)
nmap = <plug>(signify-next-hunk)
let g:signify_vcs_cmds = {
         \ 'git':      'git diff --no-color --no-ext-diff -U0 -- %f'
         \ }
nmap :diff :SignifyDiff
let g:signify_vcs_cmds_diffmode = {
         \ 'git':      'git show HEAD:./%f',
         \ 'hg':       'hg cat %f',
         \ 'svn':      'svn cat %f',
         \ 'bzr':      'bzr cat %f',
         \ 'darcs':    'darcs show contents -- %f',
         \ 'cvs':      'cvs up -p -- %f 2>%n'
         \ }
<
let g:signify_sign_add               = '+'
let g:signify_sign_delete            = '_'
let g:signify_sign_delete_first_line = '‾'
let g:signify_sign_change            = '!'

" vim-gutentags
" gutentags 搜索工程目录的标志，碰到这些文件/目录名就停止向上一级目录递归
let g:gutentags_project_root = ['.root', '.svn', '.git', '.hg', '.project', 'Makefile.am']
" 所生成的数据文件的名称
let g:gutentags_ctags_tagfile = '.tags'
" 同时开启 ctags 和 gtags 支持：
let g:gutentags_modules = []
if executable('ctags')
   let g:gutentags_modules += ['ctags']
endif
if executable('gtags-cscope') && executable('gtags')
   let g:gutentags_modules += ['gtags_cscope']
endif
" if executable('gtags-cscope') && executable('gtags')
" 	let g:gutentags_modules += ['gtags_cscope']
" endif
" 将自动生成的 tags 文件全部放入 ~/.cache/tags 目录中，避免污染工程目录
let s:vim_tags = expand('~/.cache/tags')
let g:gutentags_cache_dir = s:vim_tags
" 配置 ctags 的参数
let g:gutentags_ctags_extra_args = ['--fields=+niazS', '--extra=+q']
let g:gutentags_ctags_extra_args += ['--c++-kinds=+px']
let g:gutentags_ctags_extra_args += ['--c-kinds=+px']
" 如果使用 universal ctags 需要增加下面一行
let g:gutentags_ctags_extra_args += ['--output-format=e-ctags']
" 检测 ~/.cache/tags 不存在就新建
if !isdirectory(s:vim_tags)
   silent! call mkdir(s:vim_tags, 'p')
endif
"  禁用 gutentags 自动加载 gtags 数据库的行为
let g:gutentags_auto_add_gtags_cscope = 0
let $GTAGSLABEL = 'native-pygments'
let $GTAGSCONF = '/usr/local/share/gtags/gtags.conf'
" let g:gutentags_trace = 1

" asyncrun.vim
let g:asyncrun_status = ''
" let g:airline_section_error = airline#section#create_right(['%{g:asyncrun_status}'])

let g:asyncrun_open = 8
let g:asyncrun_bell = 1
nmap :Run :AsyncRun
nmap :Stop :AsyncStop

" Neomake
" if v:version >= 800
"    call neomake#configure#automake({
"       \ 'TextChanged': {'delay': 500},
"       \ 'InsertLeave': {},
"       \ 'BufWritePost': {'delay': 0},
"       \ 'BufWinEnter': {},
"       \ }, 100)
"    let g:neomake_open_list = 2
"    let g:neomake_python_enabled_makers = ['pyflakes']
"    let g:neomake_go_enabled_makers = ['go', 'golint', 'govet']
"    let g:neomake_tex_enabled_makers = []
"    let g:neomake_yaml_enabled_makers = []
"    let g:neomake_javascript_enabled_makers = []
"    let g:neomake_python_enabled_makers = []
" endif


" vim-qf
let g:qf_loclist_window_bottom=0
let g:qf_window_bottom = 0

" gutentas_plus.vim
if get(g:, 'gutentags_plus_nomap', 0) == 0
   " 查看光标下符号的引用
   noremap <silent> <leader>cs :GscopeFind s <C-R><C-W><cr>
   " 查看光标下符号的定义
   noremap <silent> <leader>cg :GscopeFind g <C-R><C-W><cr>
   " 查看有哪些函数调用了该函数
   noremap <silent> <leader>cc :GscopeFind c <C-R><C-W><cr>
   noremap <silent> <leader>ct :GscopeFind t <C-R><C-W><cr>
   noremap <silent> <leader>ce :GscopeFind e <C-R><C-W><cr>
   " 查找光标下的文件
   noremap <silent> <leader>cf :GscopeFind f <C-R>=expand("<cfile>")<cr><cr>
   " 查找哪些文件 include 了本文件
   noremap <silent> <leader>ci :GscopeFind i <C-R>=expand("<cfile>")<cr><cr>
   noremap <silent> <leader>cd :GscopeFind d <C-R><C-W><cr>
   noremap <silent> <leader>ca :GscopeFind a <C-R><C-W><cr>
   noremap <silent> <leader>ck :GscopeKill<cr>
endif

" vim-echodoc
set noshowmode
let g:echodoc_enable_at_startup = 1

" vim-go
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_metalinter_autosave = 1
let g:go_metalinter_enabled = ['vet', 'golint', 'ineffassign']
let g:go_fmt_command = "goimports"
let g:go_jump_to_error = 0

" python-mode
let g:pymode_trim_whitespaces = 0
" let g:pymode_python = 'python'
let g:pymode_rope = 1
let g:pymode_rope_completion = 0
let g:pymode_rope_goto_definition_bind = 'gd'
let g:pymode_rope_goto_definition_cmd = 'new'
let g:pymode_lint = 0
let g:pymode_lint_on_write = 0
let g:pymode_indent = 0

" vim-fzf
" --column: Show column number
" --line-number: Show line number
" --no-heading: Do not show file headings in results
" --ignore-case: Case insensitive search
" --no-ignore: Do not respect .gitignore, etc...
" --hidden: Search hidden files and folders
" --follow: Follow symlinks
" --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
" --color: Search color options
" command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --ignore-case --no-ignore --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>).'| tr -d "\017"', 1, <bang>0)

" vim-LanguageClient
let g:LanguageClient_serverCommands = {
         \ 'go': ['go-langserver'],
         \ }

" nnoremap <silent> K :call LanguageClient#textDocument_hover()<CR>
" nnoremap <silent> gd :call LanguageClient#textDocument_definition()<CR>

" coc-nvim
" Some servers have issues with backup files, see #649.
set nobackup
set nowritebackup
" Don't pass messages to |ins-completion-menu|.
set shortmess+=c
" Always show the signcolumn, otherwise it would shift the text each time
" diagnostics appear/become resolved.
if has("patch-8.1.1564")
  " Recently vim can merge signcolumn and number column into one
  set signcolumn=number
else
  set signcolumn=yes
endif
" disable coc in git commits
autocmd BufRead,BufNewFile COMMIT_EDITMSG let b:coc_enabled=0
" inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
" inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"
inoremap <silent><expr> <cr> coc#pum#visible() && coc#pum#info()['index'] != -1 ? coc#pum#confirm() : "\<C-g>u\<CR>"
" inoremap <silent><expr> <cr> coc#pum#visible() ? coc#_select_confirm() : "\<C-g>u\<CR>"

inoremap <silent><expr> <C-x><C-z> coc#pum#visible() ? coc#pum#stop() : "\<C-x>\<C-z>"
" remap for complete to use tab and <cr>
inoremap <silent><expr> <TAB>
    \ coc#pum#visible() ? coc#pum#next(1):
    \ <SID>check_back_space() ? "\<Tab>" :
    \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"
inoremap <silent><expr> <C-j> coc#pum#visible() ? coc#pum#next(1) : "\<C-j>"
inoremap <silent><expr> <C-k> coc#pum#visible() ? coc#pum#prev(1) : "\<C-k>"
inoremap <silent><expr> <c-space> coc#refresh()
function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> <C-w>] :sp<CR><Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
nmap <leader>rn <Plug>(coc-rename)
nmap <leader>ca <Plug>(coc-codeaction)
let g:coc_auto_copen = 0
nnoremap <silent> K :call <SID>show_documentation()<CR>
nmap <silent> [v <Plug>(coc-diagnostic-prev)
nmap <silent> ]v <Plug>(coc-diagnostic-next)
nmap <silent> [c <Plug>(coc-diagnostic-prev-error)
nmap <silent> ]c <Plug>(coc-diagnostic-next-error)
set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
" autocmd BufWritePre *.go :call CocActionAsync('runCommand', 'editor.action.organizeImport')
" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction

" markdown-preview-nvim
" let vim_markdown_preview_github=1
let g:mkdp_echo_preview_url = 1
let g:mkdp_preview_options = {
    \ 'mkit': {},
    \ }

" vim-maximizer
map <Leader>m :MaximizerToggle<CR>
tnoremap <Leader>m <c-\><c-n>:MaximizerToggle<CR>

" vim-mark
let g:mw_no_mappings = 1
nmap # <Plug>MarkSet
xmap # <Plug>MarkSet
nmap <C-n> <Plug>MarkSearchCurrentNext
nmap <M-n> <Plug>MarkSearchCurrentPrev

" vim-projectionist
let g:projectionist_heuristics = {}
let g:projectionist_heuristics["Config"] = {
    \ "src/*.java": {"alternate": "tst/{}Test.java"},
    \ "tst/*Test.java": {"alternate": "src/{}.java"},
    \ "lib/*.ts": {"alternate": "tst/{}.test.ts"},
    \ "tst/*.test.ts": {"alternate": "lib/{}.ts"},
\ }

" defx
" call defx#custom#option('_', {
"       \ 'winwidth': 70,
"       \ 'split': 'vertical',
"       \ 'direction': 'botright',
"       \ 'show_ignored_files': 0,
"       \ 'buffer_name': '',
"       \ 'toggle': 1,
"       \ 'resume': 1,
"       \ 'columns': 'git:mark:indent:icons:filename:type',
"   \ })
" 
" autocmd FileType defx call s:defx_my_settings()
" function! s:defx_my_settings() abort
"   " Define mappings
"   " nnoremap <silent><buffer><expr> <CR> 
"   " \ defx#do_action('drop')
"   nnoremap <silent><buffer><expr> <CR>
"   \ defx#is_directory() ?
"   \ defx#do_action('open_or_close_tree') :
"   \ defx#do_action('drop')
"   nnoremap <silent><buffer><expr> <M-CR>
"   \ defx#do_action('open_tree_recursive')
"   " nnoremap <silent><buffer><expr> l
"   " \ defx#do_action('open_tree')
"   " nnoremap <silent><buffer><expr> <S-l>
"   " \ defx#do_action('open_tree_recursive')
"   nnoremap <silent><buffer><expr> h
"   \ defx#do_action('cd', ['..'])
"   nnoremap <silent><buffer><expr> <C-l>
"   \ defx#do_action('redraw')
"   nnoremap <silent><buffer><expr> > defx#do_action('resize',
"   \ defx#get_context().winwidth - 10)
"   nnoremap <silent><buffer><expr> < defx#do_action('resize',
"   \ defx#get_context().winwidth + 10)
"   nnoremap <silent><buffer><expr> cd
"   \ defx#do_action('change_vim_cwd')
"   nnoremap <silent><buffer><expr> d
"   \ defx#do_action('remove')
"   " nnoremap <silent><buffer><expr> c
"   " \ defx#do_action('copy')
"   " nnoremap <silent><buffer><expr> m
"   " \ defx#do_action('move')
" " nnoremap <silent><buffer><expr> p
"   " \ defx#do_action('paste')
"   " nnoremap <silent><buffer><expr> E
"   " \ defx#do_action('open', 'vsplit')
"   " nnoremap <silent><buffer><expr> P
"   " \ defx#do_action('open', 'pedit')
"   " nnoremap <silent><buffer><expr> K
"   " \ defx#do_action('new_directory')
"   " nnoremap <silent><buffer><expr> N
"   " \ defx#do_action('new_file')
"   " nnoremap <silent><buffer><expr> M
"   " \ defx#do_action('new_multiple_files')
"   " nnoremap <silent><buffer><expr> C
"   " \ defx#do_action('toggle_columns',
"   " \                'mark:indent:icon:filename:type:size:time')
"   " nnoremap <silent><buffer><expr> S
"   " \ defx#do_action('toggle_sort', 'time')
"   " nnoremap <silent><buffer><expr> r
"   " \ defx#do_action('rename')
"   " nnoremap <silent><buffer><expr> !
"   " \ defx#do_action('execute_command')
"   " nnoremap <silent><buffer><expr> x
"   " \ defx#do_action('execute_system')
"   " nnoremap <silent><buffer><expr> yy
"   " \ defx#do_action('yank_path')
"   " nnoremap <silent><buffer><expr> .
"   " \ defx#do_action('toggle_ignored_files')
"   " nnoremap <silent><buffer><expr> ;
"   " \ defx#do_action('repeat')
"   " nnoremap <silent><buffer><expr> ~
"   " \ defx#do_action('cd')
"   " nnoremap <silent><buffer><expr> q
"   " \ defx#do_action('quit')
"   " nnoremap <silent><buffer><expr> <Space>
"   " \ defx#do_action('toggle_select') . 'j'
"   " nnoremap <silent><buffer><expr> *
"   " \ defx#do_action('toggle_select_all')
"   " nnoremap <silent><buffer><expr> j
"   " \ line('.') == line('$') ? 'gg' : 'j'
"   " nnoremap <silent><buffer><expr> k
"   " \ line('.') == 1 ? 'G' : 'k'
"   " nnoremap <silent><buffer><expr> <C-g>
"   " \ defx#do_action('print')
" endfunction

" terminal_help aka skywind3000/vim-terminal-help settings
let g:terminal_cwd = 2
let g:terminal_key = '<C-\>' "

" vim-rooter
let g:rooter_patterns = ['Config', '.git/']
let g:rooter_cd_cmd="lcd"

" Make cursor return back to main window
" autocmd VimEnter,TabNewEntered * Defx | wincmd w
" autocmd bufenter * if (winnr("$") == 1 && &filetype == "defx") | q | endif

let g:vimspector_enable_mappings='HUMAN'
let $VIMSPECTOR_PROJECT_NAME = fnamemodify(getcwd(), ':t')

" Snipmate
let g:snipMate = { 'snippet_version' : 1 }

" bemol
au FileType java call SetWorkspaceFolders()

function! SetWorkspaceFolders() abort
    " Only set g:WorkspaceFolders if it is not already set
    " if exists("g:WorkspaceFolders") | return | endif

    if executable("findup")
        let l:ws_dir = trim(system("cd '" . expand("%:h") . "' && findup packageInfo"))
        " Bemol conveniently generates a '$WS_DIR/.bemol/ws_root_folders' file, so let's leverage it
        let l:folders_file = l:ws_dir . "/.bemol/ws_root_folders"
        if filereadable(l:folders_file)
            " echo readfile(l:folders_file)
            " let l:ws_folders = readfile(l:folders_file)
            " let g:WorkspaceFolders = filter(l:ws_folders, "isdirectory(v:val)")
            let g:WorkspaceFolders = readfile(l:folders_file)
        endif
        set sessionoptions+=globals
    endif
endfunction

" Ultest
nmap ]t <Plug>(ultest-next-fail)
nmap [t <Plug>(ultest-prev-fail)


"       -------------end of plugin vim settings--------------

"       ------------platform-specific vim settings-------------

" vim-test
let test#java#runner = 'gradletest'

if exists('g:gui_oni')
   set nocompatible              " be iMproved, required
   filetype off                  " required

   set number
   set noswapfile
   set smartcase

   " Enable GUI mouse behavior
   set mouse=a

   " If using Oni's externalized statusline, hide vim's native statusline, 
   set noshowmode
set noruler
   set laststatus=0
   set noshowcmd
   " tabs
   map ¬ :tabn<CR>
   map ˙ :tabp<CR>
   map † :tabnew<CR>
   map ∑ :tabclose<CR>
endif

"       -------------end of platform-specific vim settings--------------

"        ------------end of my customized settings---------------------
