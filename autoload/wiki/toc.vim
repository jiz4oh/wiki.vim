" A wiki plugin for Vim
"
" Maintainer: Karl Yngve Lervåg
" Email:      karl.yngve@gmail.com
"

function! wiki#toc#create(local) abort " {{{1
  try
    let l:filetype = !empty(&filetype) ? &filetype : 'wiki'
    call s:toc_create_{l:filetype}(a:local)
  catch /E117:/
    call wiki#log#error("No TOC support for filetype: " . &filetype . "!")
  endtry
endfunction

" }}}1

function! wiki#toc#get_page_title(...) abort " {{{1
  let l:filename = wiki#u#eval_filename(a:0 > 0 ? a:1 : '')
  if !filereadable(l:filename) | return '' | endif

  let l:opts = #{ first_only: v:true }
  if l:filename !=# expand('%:p')
    let l:opts.lines = readfile(l:filename)
  endif

  let l:toc = wiki#toc#gather_entries(l:opts)
  return empty(l:toc) ? '' : l:toc[0].header
endfunction

function! wiki#toc#get_section_at(lnum) abort " {{{1
  let l:toc = wiki#toc#gather_entries(#{ at_lnum: a:lnum })
  return empty(l:toc) ? {} : l:toc[-1]
endfunction

" }}}1

function! wiki#toc#gather_entries(...) abort " {{{1
  " Gather ToC entries from list of lines
  "
  " Input:  Options dictionary with following keys
  "   lines:      List of lines to parse
  "   first_only: Return only first ToC entry
  "   at_lnum:    Return the entry that covers specified line
  " Output: ToC entries

  let l:filetype = !empty(&filetype) ? &filetype : 'wiki'
  let l:hd = get(s:header_spec, l:filetype, {})
  if empty(l:hd)
    call wiki#log#error("No TOC support for filetype: " . l:filetype . "!")
    return []
  endif

  let l:opts = extend(a:0 > 0 ? a:1 : {}, #{
        \ first_only: v:false
        \}, 'keep')
  if !has_key(l:opts, 'lines')
    let l:opts.lines = getline(1, '$')
  endif

  let l:entries = []
  let l:lnum = 0
  let l:preblock = v:false
  let l:anchors = ['', '', '', '', '', '', '']
  for l:line in l:opts.lines
    " Optional: Return current section
    if has_key(l:opts, 'at_lnum') && l:lnum >= l:opts.at_lnum
      return l:entries[-1:]
    endif
    let l:lnum += 1

    " Ignore fenced code blocks
    if l:line =~# '^\s*```'
      let l:preblock = !l:preblock
    endif
    if l:preblock | continue | endif

    " Get line - check for hd
    if l:line !~# l:hd.regex | continue | endif

    " Parse current hd
    let l:level = len(matchstr(l:line, '^' . l:hd.anchor_re . '*'))
    let l:header = matchlist(l:line, l:hd.items)[2]
    let l:anchors[l:level] = l:header

    " Add the new entry
    call add(l:entries, {
          \ 'anchor' : join(l:anchors[:l:level], l:hd.anchor_char),
          \ 'anchors' : copy(l:anchors[1:l:level]),
          \ 'header': l:header,
          \ 'level' : l:level,
          \ 'lnum' : l:lnum,
          \})

    " Optional: Return first section only
    if l:opts.first_only
      return l:entries[:0]
    endif
  endfor

  return l:entries
endfunction

let s:header_spec = {
      \ 'asciidoc': {
      \   'anchor_char': '=',
      \   'anchor_re': '=',
      \   'regex': g:wiki#rx#header_adoc,
      \   'items': g:wiki#rx#header_adoc_items,
      \ },
      \ 'markdown': {
      \   'anchor_char': '#',
      \   'anchor_re': '#',
      \   'regex': g:wiki#rx#header_md_atx,
      \   'items': g:wiki#rx#header_md_atx_items,
      \ },
      \ 'wiki': {
      \   'anchor_char': '#',
      \   'anchor_re': '#',
      \   'regex': g:wiki#rx#header_md_atx,
      \   'items': g:wiki#rx#header_md_atx_items,
      \ },
      \ 'org': {
      \   'anchor_char': '*',
      \   'anchor_re': '\*',
      \   'regex': g:wiki#rx#header_org,
      \   'items': g:wiki#rx#header_org_items,
      \ },
      \}

" }}}1
function! wiki#toc#gather_anchors(...) abort " {{{1
  let l:cache = wiki#cache#open('anchors', {
        \ 'local': 1,
        \ 'default': { 'ftime': -1 },
        \})

  let l:filename = wiki#u#eval_filename(a:0 > 0 ? a:1 : '')
  let l:current = l:cache.get(l:filename)
  let l:ftime = getftime(l:filename)
  if l:ftime > l:current.ftime
    let l:cache.modified = 1
    let l:current.ftime = l:ftime
    let l:current.anchors = map(
          \ wiki#toc#gather_entries(#{lines: readfile(l:filename)}),
          \ 'v:val.anchor')
  endif
  call l:cache.write()

  return copy(l:current.anchors)
endfunction

" }}}1

function! s:toc_create_asciidoc(...) abort " {{{1
  let l:entries = wiki#toc#gather_entries()
  if empty(l:entries) | return | endif

  if l:entries[0].level != 1
    let l:page_name = expand('%:t:r')
    call append(0, "= " . l:page_name)
    let l:toc = {'exists' : 0, 'lnum' : 1}
  else
    let l:toc = {'exists' : 0, 'lnum' : l:entries[0].lnum}
  endif

  let l:toctitle = {'exists' : 0, 'lnum' : l:toc.lnum + 1}
  let l:toclevels = {'exists' : 0, 'lnum' : l:toc.lnum + 2}

  " Loops over the first two heading if there are already toc keywords
  for l:lnum in range(l:entries[0].lnum, l:entries[1].lnum)
    let l:line = getline(l:lnum)
    if match(l:line, ':toc:') > -1
      let l:toc.exists = 1
      let l:toc.lnum = l:lnum
    elseif match(l:line, ':toc-title:') > -1
      let l:toctitle.exists = 1
      let l:toctitle.lnum = l:lnum
    elseif match(l:line, ':toclevels:') > -1
      let l:toclevels.exists = 1
      let l:toclevels.lnum = l:lnum
    endif
  endfor

  if !l:toc.exists
    call append(l:toc.lnum, ':toc:')
    let l:toc.lnum += 1
  endif
  if !l:toctitle.exists
    call append(l:toc.lnum, ':toc-title: ' . g:wiki_toc_title)
    let l:toc.lnum += 1
  endif
  if !l:toclevels.exists
    call append(l:toc.lnum, ':toclevels: ' . g:wiki_toc_depth)
  endif
endfunction

" }}}1
function! s:toc_create_org(...) abort " {{{1
  let l:entries = wiki#toc#gather_entries()
  if empty(l:entries) | return | endif

  let l:found = 0
  for l:lnum in range(1, l:entries[0].lnum)
    let l:line = getline(l:lnum)
    if match(l:line, 'toc') > -1
      let l:found = 1
    endif
  endfor

  if !l:found
    if match(getline(1), '^\*') > -1
      call append(0, '')
    endif
    call append(0, '#+OPTIONS: toc: ' . g:wiki_toc_depth)
  endif
endfunction

" }}}1
function! s:toc_create_markdown(local) abort " {{{1
  let l:entries = wiki#toc#gather_entries()
  if empty(l:entries) | return | endif

  if a:local
    let [l:entries, l:local] = s:get_local_toc(l:entries, line('.'))
    if empty(l:entries) | return | endif

    let l:level = l:local.level
    let l:lnum_top = l:local.lnum_top
    let l:lnum_bottom = l:local.lnum_bottom
    let l:print_depth = g:wiki_toc_depth + l:level - 1
  else
    let l:level = 1
    let l:lnum_top = 1
    let l:lnum_bottom = get(get(l:entries, 1, {}), 'lnum', line('$'))
    let l:print_depth = g:wiki_toc_depth
  endif

  " Only print entries to the desired depth
  call filter(l:entries, 'v:val.level <= l:print_depth')

  let l:start = max([l:entries[0].lnum, 0])
  let l:title = '*' . g:wiki_toc_title . '*'
  let l:re = printf(
        \ '\v^%(%s %s|\*%s\*)$',
        \ repeat('\=', l:level), g:wiki_toc_title, g:wiki_toc_title)

  " Save the window view and syntax setting and disable syntax (makes things
  " much faster)
  let l:winsave = winsaveview()
  let l:syntax = &l:syntax
  setlocal syntax=off

  " Delete TOC if it exists
  for l:lnum in range(l:lnum_top, l:lnum_bottom)
    if getline(l:lnum) =~# l:re
      let l:title = getline(l:lnum)
      let l:start = l:lnum
      let l:end = l:start + (getline(l:lnum+1) =~# '^\s*$' ? 2 : 1)
      while l:end <= l:lnum_bottom && getline(l:end) =~# '^\s*[*-] '
        let l:end += 1
      endwhile

      let l:foldenable = &l:foldenable
      setlocal nofoldenable
      silent execute printf('%d,%ddelete _', l:start, l:end - 1)
      let &l:foldenable = l:foldenable

      break
    endif
  endfor

  " Remove the first entry if it is "trivial"
  if !a:local
    let l:count = -1
    for l:e in l:entries
      let l:count += 1
      if (l:e.level == 1 && l:e.lnum > l:start) || l:count > 1 | break | endif
    endfor
    if l:count == 1
      let l:entries = l:entries[1:]
    endif
  endif

  " Add updated TOC
  call append(l:start - 1, l:title)
  let l:i = 0
  for l:e in l:entries
    call append(l:start + l:i,
          \ repeat(' ', shiftwidth()*(l:e.level - l:level))
          \ . '* ' . wiki#link#template(l:e.anchor, l:e.header))
    let l:i += 1
  endfor
  let l:length = len(l:entries)
  if getline(l:start + l:length + 1) !=# ''
    call append(l:start + l:length, '')
  endif
  if l:title =~# '^#'
    call append(l:start, '')
  endif

  " Restore syntax and view
  let &l:syntax = l:syntax
  call winrestview(l:winsave)
endfunction

" }}}1
function! s:toc_create_wiki(local) abort " {{{1
  call s:toc_create_markdown(a:local)
endfunction

" }}}1

function! s:get_local_toc(entries, lnum_current) abort " {{{1
    " Get ToC for the section for lnum_current
    "
    " Input: List of entries and a current line number
    " Output: Current section entries and some metadata

    let l:i_parent = -1
    for l:e in a:entries
      if l:e.lnum > a:lnum_current | break | endif
      let l:i_parent += 1
    endfor

    let l:level = a:entries[l:i_parent].level
    let l:i_first = l:i_parent+1
    let l:i_last = l:i_parent
    for l:e in a:entries[l:i_first:]
      if l:e.level <= l:level | break | endif
      let l:i_last += 1
    endfor

    return l:i_last < l:i_first
          \ ? [[], {}]
          \ : [
          \    a:entries[l:i_first : l:i_last],
          \    {
          \      'level': l:level + 1,
          \      'lnum_top': a:entries[l:i_parent].lnum,
          \      'lnum_bottom': a:entries[l:i_first].lnum,
          \    }
          \   ]
endfunction

" }}}1
