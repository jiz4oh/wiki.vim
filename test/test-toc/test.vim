source ../init.vim
runtime plugin/wiki.vim

set shiftwidth=2
set expandtab

" Open ToC test page, update ToC and test against reference
silent edit ../wiki-basic/ToC.wiki

WikiTocGenerate
call assert_equal(
      \ readfile('../wiki-basic/ToC-reference.wiki'),
      \ getline(1, '$'))

call wiki#test#finished()
