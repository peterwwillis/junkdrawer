#!/usr/bin/env sh
# load-vim-plugins.sh - Load VIM plugins

mkdir -p ~/.vim/pack/jvirtanen/start
cd ~/.vim/pack/jvirtanen/start
[ -d vim-hcl ] || git clone git://github.com/jvirtanen/vim-hcl.git
