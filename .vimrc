" Initialize plugin manager
call plug#begin('~/.vim/plugged')

" Add Gruvbox plugin
Plug 'morhetz/gruvbox'

call plug#end()

set number

syntax on
set background=dark
silent! colorscheme gruvbox
set termguicolors

" Use spaces instead of tab characters
set expandtab

" Set the number of spaces per tab press (while editing)
set shiftwidth=4

" Set the width of an actual Tab character (displayed as spaces)
set tabstop=4

" Set the number of spaces used for <Tab> at the start of a line during editing
set softtabstop=4
