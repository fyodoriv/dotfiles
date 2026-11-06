#!/bin/zsh -df
# Load the system auditor before restoring the inherited completion paths.
typeset -a audit_paths
audit_paths=("${fpath[@]}")
fpath=(/usr/share/zsh/$ZSH_VERSION/functions)
autoload -Uz +X compaudit || exit 1
fpath=("${audit_paths[@]}")
PATH=/usr/bin:/bin:/usr/sbin:/sbin
compaudit
