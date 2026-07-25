# Amnesia (anon) shell profile — RAM-only home, no persistence.

# No shell history anywhere.
unset HISTFILE
export HISTSIZE=0
export HISTFILESIZE=0
export LESSHISTFILE=/dev/null

# Sane interactive defaults
[ -z "$PS1" ] && return
export PS1='\[\e[1;31m\](anon)\[\e[0m\] \w \$ '
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Route common CLI tools through Tor's SOCKS as well (belt-and-braces on top of
# the transparent firewall). Uncomment torsocks wrappers if you prefer explicit.
# alias curl='torsocks curl'
# alias wget='torsocks wget'

echo "Amnesia mode: this home lives in RAM and is wiped on reboot."
echo "All your traffic is forced through Tor. See ~/README-anon.txt."
