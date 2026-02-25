# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="devcontainers"

# Plugins
plugins=(git)

# Disable auto-updates (managed manually)
zstyle ':omz:update' mode disabled

source $ZSH/oh-my-zsh.sh

# ------------------- Antigen Setup ------------------------

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
        return 1
    fi
    if [ ! $? -eq 0 ]; then
        echo "ERROR: downloading antigen.zsh ($URL) failed !!"
        return 1
    fi
    mv "$TMPFILE" "$ANTIGEN"
fi

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
antigen theme romkatv/powerlevel10k
antigen apply

# ------------------- Environment Variables ------------------------

export TERM='xterm-256color'
export LANG=en_US.UTF-8
export EDITOR=nvim
export VISUAL=nvim

# Go
export GOPATH="$HOME/go"

# z.lua enhanced matching
export _ZL_MATCH_MODE=1

# FZF
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!.git/*"'

# ------------------- PATH ------------------------

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.rvm/bin:$PATH"
export PATH="$GOPATH/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/go/bin:$PATH"

# Java (cross-platform)
if [[ "$OSTYPE" == darwin* ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
elif command -v javac >/dev/null 2>&1; then
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
[ -n "$JAVA_HOME" ] && export PATH="$JAVA_HOME/bin:$PATH"

# ------------------- Aliases ------------------------

# General
alias grep='grep -n --color=always'
alias grepjs='grep -n --color=always --exclude-dir node_modules --exclude-dir build --exclude package-lock.json'
alias python="python3"
alias pip="pip3"
alias findp="ps aux | grep"
alias ku="kubectl"
alias lc="leetcode"

# Editor - prefer nvim, fall back to vim
if command -v nvim >/dev/null 2>&1; then
    alias vi='nvim'
elif command -v vim >/dev/null 2>&1; then
    alias vi='vim'
fi

# macOS specific
if [[ "$OSTYPE" == darwin* ]]; then
    alias wifi_restart="networksetup -setairportpower Wi-Fi off && networksetup -setairportpower Wi-Fi on"
    export PATH="/usr/local/opt/openjdk@8/bin:$PATH"
fi

# ------------------- Custom Functions ------------------------

stress() {
    while $@; do :; done
}

gzip64() {
    base64 --decode <<<$@ | gzip -cd
}

escape() {
    python3 -c "import json; haha = input('Paste your string below:\n\n'); print('\n' + json.dumps(haha))"
}

moshtmux() {
    mosh $1 -- sh -c "tmux -CC"
}

# ------------------- Powerlevel10k Settings ------------------------

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

# zsh-autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=3'

# Disable magic functions (URL paste issues)
DISABLE_MAGIC_FUNCTIONS=true

# ------------------- Keybindings ------------------------

bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# ------------------- Completions ------------------------

autoload -Uz compinit
autoload bashcompinit && bashcompinit
for dump in ~/.zcompdump(N.mh+24); do
    compinit
done
compinit -C

# AWS CLI completion
[ -x /usr/local/bin/aws_completer ] && complete -C '/usr/local/bin/aws_completer' aws

# ------------------- Tool Integrations ------------------------

# iTerm2
[ -f "${HOME}/.iterm2_shell_integration.zsh" ] && source "${HOME}/.iterm2_shell_integration.zsh"

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# NVM (check multiple locations)
if [ -s "/usr/local/share/nvm/nvm.sh" ]; then
    export NVM_DIR="/usr/local/share/nvm"
    source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
fi

# opam (OCaml)
[ -r "$HOME/.opam/opam-init/init.zsh" ] && source "$HOME/.opam/opam-init/init.zsh" > /dev/null 2> /dev/null

# Powerlevel10k config
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ------------------- Local Overrides ------------------------
# Machine-specific config (not tracked in git)
# Use this for: WORK_MACHINE=1, API keys, local paths, etc.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# ------------------- Work Configuration ------------------------
# Load work-specific config if WORK_MACHINE=1
if [ "$WORK_MACHINE" = "1" ]; then
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Repos/Dotfiles}"
    [ -f "$DOTFILES_DIR/shell/work.sh" ] && source "$DOTFILES_DIR/shell/work.sh"
fi
