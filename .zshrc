# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="devcontainers"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME="devcontainers"
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
zstyle ':omz:update' mode disabled


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ------------------- necessary installations ------------------------

# Antigen: https://github.com/zsh-users/antigen
ANTIGEN="$HOME/.antigen.zsh"
# Install antigen.zsh if not exist
if [ ! -f "$ANTIGEN" ]; then
	echo "Installing antigen ..."
	[ ! -d "$HOME/.local" ] && mkdir -p "$HOME/.local" 2> /dev/null
	[ ! -d "$HOME/.local/bin" ] && mkdir -p "$HOME/.local/bin" 2> /dev/null
	[ ! -f "$HOME/.z" ] && touch "$HOME/.z"
	URL="http://git.io/antigen"
	TMPFILE="/tmp/antigen.zsh"
	if [ -x "$(which curl)" ]; then
		curl -L "$URL" -o "$TMPFILE" 
	elif [ -x "$(which wget)" ]; then
		wget "$URL" -O "$TMPFILE" 
	else
		echo "ERROR: please install curl or wget before installation !!"
		exit
	fi
	if [ ! $? -eq 0 ]; then
		echo ""
		echo "ERROR: downloading antigen.zsh ($URL) failed !!"
		exit
	fi;
	echo "move $TMPFILE to $ANTIGEN"
	mv "$TMPFILE" "$ANTIGEN"
fi

# ------------------- end of necessary installations ------------------------


# ------------------ custom functions ----------------------

stress() {
   while $@; do :; done
}

gzip64() {
    base64 --decode <<<$@ | gzip -cd
}

escape() {
    python3 -c "import json; haha = input('Paste your string below:\n\n'); print('\n' + json.dumps(haha))"
}

# ------------------ end of custom functions----------------------


# ------------- plugin settings that should come before the plugins ----------------

# powerlevel9k
export TERM='xterm-256color'
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_PROMPT_ON_NEWLINE=true
POWERLEVEL9K_TIME_FORMAT="\UF43A %D{%H:%M \uf073 %m/%d/%y}"
POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND='black'
POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND='blue'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs time)
POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=0
POWERLEVEL9K_DIR_SHOW_WRITABLE=true
POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last

# oh-my-zsh
# https://stackoverflow.com/questions/25614613/how-to-disable-zsh-substitution-autocomplete-with-url-and-backslashes
DISABLE_MAGIC_FUNCTIONS=true

# ------------------ end of plugin settings ----------------------


# ------------------ general zsh settings ----------------------

# # same effect as 'screen -R'
# tmuxr="( ( tmux ls | grep -v attached ) && tmux a ) || tmux new"
# tmuxr="tmux ls | grep -v attached | head -1 | cut -f2 -d: | xargs tmux attach -t || tmux new"
moshtmux() {
    # mosh $1 -- sh -c "tmux -CC ls | grep -vq attached && tmux -CC a || tmux -CC new"
    mosh $1 -- sh -c "tmux -CC"
}

alias lc="leetcode"

export ONI_NEOVIM_PATH=$(which nvim)
export EDITOR=vi
alias bb="brazil-build"
alias bbs="brazil-build server"
alias b="brazil"
alias grep='grep -n --color=always'
alias grepjs='grep -n --color=always --exclude-dir node_modules --exclude-dir build --exclude package-lock.json'
alias brb="brazil-recursive-cmd --allPackages brazil-build"
alias python="python3"
alias pip="pip3"
export VISUAL=nvim
if hash drop 2>/dev/null
then
    alias vi='drop'
    export VISUAL='drop'
else
    alias vi='nvim'
    if [ -x "$(which nvim)" ]; then
        alias vi='nvim'
    else
        alias vi='vim'
    fi
    # export VISUAL=vim
fi
# alias vi='vim'
export EDITOR="$VISUAL"
alias findp="ps aux | grep"
alias ku="kubectl"

export PATH=$PATH:/usr/local/go/bin
export PATH=/usr/local/bin:$PATH
export PATH=$HOME/bin:$HOME/.toolbox/bin:$PATH
export GOPATH="$HOME/go"
export PATH=$PATH:$GOPATH/bin
export PATH=$HOME/.toolbox/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/.cargo/env:$PATH
export LANG=en_US.UTF-8
# macOS vs Linux JAVA_HOME
if [[ "$OSTYPE" == darwin* ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  export JAVA_HOME="$("/usr/libexec/java_home")"
elif command -v javac >/dev/null 2>&1; then
  # Good default for Debian/Ubuntu images
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
export PATH=$JAVA_HOME/bin:$PATH

case "$(uname -s)" in

   Darwin)
    #echo 'Mac OS X'
    alias wifi_restart="networksetup -setairportpower Wi-Fi off && networksetup -setairportpower Wi-Fi on"
    export PATH="/usr/local/opt/openjdk@8/bin:$PATH"
     ;;
   Linux)
    #echo 'Linux'
    alias vim='/apollo/env/envImprovement/bin/vim'
    alias register_with_aaa="/apollo/env/AAAWorkspaceSupport/bin/register_with_aaa.py"
    alias bb="brazil-build"
    alias bbs="brazil-juild server"
    alias b="brazil"
    export PATH=$PATH:/apollo/env/envImprovement/bin
    export JAVA_HOME=/usr/lib/jvm/amazon-openjdk-8
     ;;
   CYGWIN*|MINGW32*|MSYS*)
     #echo 'MS Windows'
     ;;

   # Add here more strings to compare
   # See correspondence table at the bottom of this answer

   *)
    #echo 'other OS' 
     ;;
esac

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# ------------------ end of general zsh settings ----------------------


# ------------------- antigen plugins ------------------------

source "$ANTIGEN"
antigen use oh-my-zsh
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle git
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-completions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle MichaelAquilina/zsh-you-should-use
antigen bundle skywind3000/z.lua
antigen bundle Tarrasch/zsh-autoenv
# need to install nerd-fonts
# antigen theme bhilburn/powerlevel9k powerlevel9k
antigen theme romkatv/powerlevel10k
antigen apply

# ------------------- end of antigen plugins ------------------------


# ------------- plugin settings that should come after the plugins ----------------

# zsh-autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=3'

# --------------------- end of plugin settings ----------------------

# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --files: List files that would be searched but do not search
# --no-ignore: Do not respect .gitignore, etc...
# --hidden: Search hidden files and folders
# --follow: Follow symlinks
# --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!.git/*"'

# z.lua enhanced matching algorithm 
export _ZL_MATCH_MODE=1

# opam configuration
test -r /Users/yanxichen/.opam/opam-init/init.zsh && . /Users/yanxichen/.opam/opam-init/init.zsh > /dev/null 2> /dev/null || true

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down


# Geneate RDE autocompletion.
fpath=(~/.zsh/completion $fpath)
# autoload -Uz compinit && compinit -i

## aws autocompletion

# Use Codespaces' built-in NVM/Node
export NVM_DIR="/usr/local/share/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"      # loads nvm
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"


# export NVM_DIR="$HOME/.nvm"
# [ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
# [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && . "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

autoload -Uz compinit
autoload bashcompinit && bashcompinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C
complete -C '/usr/local/bin/aws_completer' aws


export PATH="/Users/yanxiche/Fortify/bin:$PATH"

# Agent SDK CLI
export PATH="$PATH:/Users/yanxiche/.ask/MagentaSDK-CLI-1.0/bin"
