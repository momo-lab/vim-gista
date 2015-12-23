let s:save_cpo = &cpo
set cpo&vim
scriptencoding utf-8

let s:V = gista#vital()
let s:S = s:V.import('Data.String')
let s:A = s:V.import('ArgumentParser')

let s:PRIVATE_GISTID = repeat('*', 20)
let s:LABEL_MODES = [
      \ 'created_at',
      \ 'updated_at',
      \]

function! s:truncate(str, width) abort " {{{
  let suffix = strdisplaywidth(a:str) > a:width ? '...' : '   '
  return s:S.truncate(a:str, a:width - 4) . suffix
endfunction " }}}
function! s:format_entry(entry) abort " {{{
  let gistid = a:entry.public
        \ ? 'gistid:' . a:entry.id
        \ : 'gistid:' . s:PRIVATE_GISTID
  let fetched  = gista#gist#is_fetched(a:entry)  ? '=' : '-'
  let modified = gista#gist#is_modified(a:entry) ? '*' : ' '
  let label    = s:get_current_label(a:entry)
  let prefix = fetched . ' ' . label . ' ' . modified . ' '
  let suffix = ' ' . gistid
  let width = winwidth(0) - strdisplaywidth(prefix . suffix)
  let description = empty(a:entry.description)
        \ ? join(keys(a:entry.files), ', ')
        \ : a:entry.description
  let description = substitute(description, "[\r\n]", ' ', 'g')
  let description = printf('[%d] %s', len(a:entry.files), description)
  let description = s:truncate(description, width)
  return prefix . description . suffix
endfunction " }}}
function! s:get_entry(index, ...) abort " {{{
  let offset = get(a:000, 0, 0)
  return get(b:gista.entries, a:index + offset, {})
endfunction " }}}
function! s:set_content(content) abort " {{{
  let client = gista#api#get_current_client()
  let apiname = client.apiname
  redraw
  call gista#util#prompt#echo('Formatting gist entries to display...')
  let content = map(copy(a:content.entries), 's:format_entry(v:val)')
  call gista#util#buffer#edit_content(content)
  let b:gista = {
        \ 'winwidth': winwidth(0),
        \ 'apiname': client.apiname,
        \ 'username': client.get_authorized_username(),
        \ 'lookup': a:content.lookup,
        \ 'since': a:content.since,
        \ 'entries': a:content.entries,
        \}
endfunction " }}}
function! s:get_current_datetime() abort " {{{
  if !exists('s:current_datetime')
    call s:set_current_datetime(g:gista#command#list#default_datetime)
  endif
  return s:current_datetime
endfunction " }}}
function! s:set_current_datetime(datetime) abort " {{{
  if a:datetime !~# '^\%(updated_at\|created_at\)$'
    call gista#util#prompt#warn(
          \ '"%s" is not available datetime for g:gista#command#list#default_datetime'
          \)
    let s:current_datetime = get(s:, 'current_datetime', 'updated_at')
  else
    let s:current_datetime = a:datetime
  endif
endfunction " }}}

function! s:get_current_label_index() abort " {{{
  if !exists('s:current_label_index')
    let index = index(s:LABEL_MODES, g:gista#command#list#default_label)
    if index == -1
      call gista#util#prompt#throw(printf(
            \ 'An invalid label "%s" is specified to g:gista#command#list#default_label',
            \ g:gista#command#list#default_label,
            \))
    endif
    let s:current_label_index = index
  endif
  return s:current_label_index
endfunction " }}}
function! s:set_current_label_index(index) abort " {{{
  let s:current_label_index = a:index
endfunction " }}}
function! s:get_current_label(entry) abort " {{{
  let lmode = s:LABEL_MODES[s:get_current_label_index()]
  if lmode ==# 'created_at' || lmode ==# 'updated_at'
    let datetime = a:entry[lmode]
    let label = substitute(
          \ datetime,
          \ '\v\d{2}(\d{2})-(\d{2})-(\d{2})T(\d{2}:\d{2}:\d{2})Z',
          \ '\1/\2/\3(\4)',
          \ ''
          \)
    return label
  endif
endfunction " }}}

function! s:handle_exception(exception) abort " {{{
  redraw
  let canceled_by_user_patterns = [
        \ '^vim-gista: Login canceled',
        \ '^vim-gista: Canceled',
        \]
  for pattern in canceled_by_user_patterns
    if a:exception =~# pattern
      call gista#util#prompt#warn('Canceled')
      return
    endif
  endfor
  " else
  call gista#util#prompt#error(a:exception)
endfunction " }}}
function! gista#command#list#call(...) abort " {{{
  let options = extend({
        \ 'lookup': '',
        \}, get(a:000, 0, {}),
        \)
  try
    return gista#api#gists#list(options.lookup, options)
  catch /^vim-gista:/
    call s:handle_exception(v:exception)
    return []
  endtry
endfunction " }}}
function! gista#command#list#open(...) abort " {{{
  let options = extend({
        \ 'lookup': '',
        \ 'opener': '',
        \}, get(a:000, 0, {})
        \)
  try
    let content = gista#api#gists#list(options.lookup, options)
    let client = gista#api#get_current_client()
    if !len(content.entries)
      redraw
      call gista#util#prompt#warn(printf(
            \ 'No gist entries are exists for a lookup "%s" on "%s".',
            \ content.lookup, client.apiname,
            \))
      return
    endif
  catch /^vim-gista:/
    call s:handle_exception(v:exception)
    return
  endtry
  " Open a list window
  let opener = empty(options.opener)
        \ ? g:gista#command#list#default_opener
        \ : options.opener
  let bufname = printf('gista-list:%s:%s', client.apiname, content.lookup)
  let ret = gista#util#buffer#open(bufname, {
        \ 'group': 'manipulation_panel',
        \ 'opener': opener,
        \})
  call s:set_content(content)
  noremap <buffer><silent> <Plug>(gista-quit)
        \ :<C-u>q<CR>
  noremap <buffer><silent> <Plug>(gista-update)
        \ :call <SID>action('update')<CR>
  noremap <buffer><silent> <Plug>(gista-UPDATE)
        \ :call <SID>action('update', 1)<CR>
  noremap <buffer><silent> <Plug>(gista-next-label)
        \ :call <SID>action('next_label')<CR>
  noremap <buffer><silent> <Plug>(gista-prev-label)
        \ :call <SID>action('prev_label')<CR>
  noremap <buffer><silent> <Plug>(gista-edit)
        \ :call <SID>action('edit')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-above)
        \ :call <SID>action('edit', 'above')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-below)
        \ :call <SID>action('edit', 'below')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-left)
        \ :call <SID>action('edit', 'left')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-right)
        \ :call <SID>action('edit', 'right')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-tab)
        \ :call <SID>action('edit', 'tab')<CR>
  noremap <buffer><silent> <Plug>(gista-edit-preview)
        \ :call <SID>action('edit', 'preview')<CR>
  noremap <buffer><silent> <Plug>(gista-json)
        \ :call <SID>action('json')<CR>
  noremap <buffer><silent> <Plug>(gista-json-above)
        \ :call <SID>action('json', 'above')<CR>
  noremap <buffer><silent> <Plug>(gista-json-below)
        \ :call <SID>action('json', 'below')<CR>
  noremap <buffer><silent> <Plug>(gista-json-left)
        \ :call <SID>action('json', 'left')<CR>
  noremap <buffer><silent> <Plug>(gista-json-right)
        \ :call <SID>action('json', 'right')<CR>
  noremap <buffer><silent> <Plug>(gista-json-tab)
        \ :call <SID>action('json', 'tab')<CR>
  noremap <buffer><silent> <Plug>(gista-json-preview)
        \ :call <SID>action('json', 'preview')<CR>
  map <buffer> q <Plug>(gista-quit)
  map <buffer> <C-n> <Plug>(gista-next-label)
  map <buffer> <C-p> <Plug>(gista-prev-label)
  map <buffer> <C-l> <Plug>(gista-update)
  map <buffer> <Return> <Plug>(gista-edit)
  map <buffer> ee <Plug>(gista-edit)
  map <buffer> EE <Plug>(gista-edit-right)
  map <buffer> tt <Plug>(gista-edit-tab)
  map <buffer> pp <Plug>(gista-edit-preview)
  map <buffer> ej <Plug>(gista-json)
  map <buffer> Ej <Plug>(gista-json-right)
  map <buffer> tj <Plug>(gista-json-tab)
  map <buffer> pj <Plug>(gista-json-preview)
  augroup vim_gista_list
    autocmd! * <buffer>
    autocmd VimResized <buffer> call s:on_VimResized()
    autocmd WinEnter <buffer> call s:on_WinEnter()
  augroup END
  setlocal nonumber nolist nowrap nospell nofoldenable textwidth=0
  setlocal foldcolumn=0 colorcolumn=0
  setlocal cursorline
  setlocal buftype=nofile nobuflisted
  setlocal nomodifiable
  setlocal isfname& isfname+=:
  setlocal filetype=gista-list
endfunction " }}}
function! gista#command#list#update_if_necessary(...) abort " {{{
  let fresh = get(a:000, 0)
  let saved_winnum = winnr()
  for winnum in range(1, winnr('$'))
    if gista#util#compat#getbufvar(winbufnr(winnum), '&filetype') ==# 'gista-list'
      silent execute printf('keepjumps %dwincmd w', winnum)
      call s:action_update(fresh)
      silent execute printf('keepjumps %dwincmd w', saved_winnum)
      return
    endif
  endfor
endfunction " }}}

function! s:on_VimResized() abort " {{{
  call s:action_update()
endfunction " }}}
function! s:on_WinEnter() abort " {{{
  if b:gista.winwidth != winwidth(0)
    call s:action_update()
  endif
endfunction " }}}

function! s:action(name, ...) range abort " {{{
  let fname = printf('s:action_%s', a:name)
  if !exists('*' . fname)
    throw printf('vim-gista: Unknown action name "%s" is called.', a:name)
  endif
  " Call action function with a:firstline and a:lastline propagation
  execute printf(
        \ '%d,%dcall call("%s", a:000)',
        \ a:firstline, a:lastline, fname
        \)
endfunction " }}}
function! s:action_edit(...) range abort " {{{
  let opener = get(a:000, 0, '')
  let opener = empty(opener)
        \ ? g:gista#command#list#default_entry_opener
        \ : opener
  let [opener, anchor] = get(
        \ g:gista#command#list#entry_openers,
        \ opener, ['edit', 1],
        \)
  try
    call gista#api#session_enter({
          \ 'apiname': b:gista.apiname,
          \ 'username': b:gista.username,
          \})
    for n in range(a:firstline, a:lastline)
      let entry = s:get_entry(n - 1)
      if empty(entry)
        continue
      endif
      if anchor
        call gista#util#anchor#focus()
      endif
      call gista#command#open#edit({
            \ 'gistid': entry.id,
            \ 'opener': opener,
            \})
    endfor
  finally
    call gista#api#session_exit()
  endtry
endfunction " }}}
function! s:action_json(...) range abort " {{{
  let opener = get(a:000, 0, '')
  let opener = empty(opener)
        \ ? g:gista#command#list#default_entry_opener
        \ : opener
  let [opener, anchor] = get(
        \ g:gista#command#list#entry_openers,
        \ opener, ['edit', 1],
        \)
  try
    call gista#api#session_enter({
          \ 'apiname': b:gista.apiname,
          \ 'username': b:gista.username,
          \})
    for n in range(a:firstline, a:lastline)
      let entry = s:get_entry(n - 1)
      if empty(entry)
        continue
      endif
      if anchor
        call gista#util#anchor#focus()
      endif
      call gista#command#json#edit({
            \ 'gistid': entry.id,
            \ 'opener': opener,
            \})
    endfor
  finally
    call gista#api#session_exit()
  endtry
endfunction " }}}
function! s:action_update(...) range abort " {{{
  let fresh = get(a:000, 0)
  let options = {
        \ 'verbose': 1,
        \ 'apiname': b:gista.apiname,
        \ 'username': b:gista.username,
        \ 'lookup': b:gista.lookup,
        \ 'fresh': fresh,
        \}
  let content = gista#command#list#call(options)
  call s:set_content(content)
endfunction " }}}
function! s:action_next_label(...) range abort " {{{
  let index = s:get_current_label_index() + 1
  let index = index >= len(s:LABEL_MODES) ? 0 : index
  call s:set_current_label_index(index)
  call s:action_update()
endfunction " }}}
function! s:action_prev_label(...) range abort " {{{
  let index = s:get_current_label_index() - 1
  let index = index < 0 ? len(s:LABEL_MODES) - 1 : index
  call s:set_current_label_index(index)
  call s:action_update()
endfunction " }}}

function! s:get_parser() abort " {{{
  if !exists('s:parser') || g:gista#develop
    let s:parser = s:A.new({
          \ 'name': 'Gista[!] list',
          \ 'description': [
          \   'List gists of a paricular lookup.',
          \   'A bang (!) is a short form of "--fresh --no-since".',
          \ ],
          \})
    call s:parser.add_argument(
          \ 'lookup',
          \ 'Gists lookup', {
          \   'complete': function('gista#api#gists#complete_lookup'), 
          \})
    call s:parser.add_argument(
          \ 'fresh',
          \ 'Request new/updated gists from API',
          \)
    call s:parser.add_argument(
          \ '--since', [
          \   'Request gists created/updated later than a paricular timestamp',
          \   'in ISO 8601 format:YYYY-MM-DDTHH:MM:SSZ',
          \ ], {
          \   'type': s:A.types.any,
          \   'deniable': 1,
          \   'pattern': '\%(\|\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\%(Z\|\[+-]\d{4}\)\)',
          \ })
    if has('python') || has('python3')
      call s:parser.add_argument(
            \ '--python', [
            \   'Use python to request gists (Default)',
            \ ], {
            \   'deniable': 1,
            \ })
    endif
  endif
  return s:parser
endfunction " }}}
function! gista#command#list#command(...) abort " {{{
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if empty(options)
    return
  endif
  " extend default options
  let options = extend(
        \ deepcopy(g:gista#command#list#default_options),
        \ options,
        \)
  if options.__bang__
    let options.fresh = 1
    let options.since = ''
  endif
  call gista#command#list#open(options)
endfunction " }}}
function! gista#command#list#complete(...) abort " {{{
  let parser = s:get_parser()
  return call(parser.complete, a:000, parser)
endfunction " }}}

function! gista#command#list#define_highlights() abort " {{{
  " TODO: Add 'default' keyword when development has reached stable phase
  " e.g. highlight default link GistaPartialMarker    Constant
  highlight link GistaPartialMarker    Comment
  highlight link GistaDownloadedMarker Special
  highlight link GistaModifiedMarker   WarningMsg
  highlight link GistaLastModified     Comment
  highlight link GistaGistIDPublic     Tag
  highlight link GistaGistIDPrivate    Constant
endfunction " }}}
function! gista#command#list#define_syntax() abort " {{{
  syntax match GistaLine /^[=\-].*gistid:.\{,20}\%(\/[a-zA-Z0-9]\+\)\?$/
  syntax match GistaGistIDPublic /gistid:[a-zA-Z0-9_\-]\{,20}\%(\/[a-zA-Z0-9]\+\)\?$/
        \ display contained containedin=GistaLine
  syntax match GistaGistIDPrivate /gistid:\*\{20}$/
        \ display contained containedin=GistaLine
  syntax match GistaMeta /^[=\-] \d\{2}\/\d\{2}\/\d\{2}(\d\{2}:\d\{2}:\d\{2}) [ \*]/
        \ display contained containedin=GistaLine
  syntax match GistaPartialMarker /^-/
        \ display contained containedin=GistaMeta
  syntax match GistaDownloadedMarker /^=/
        \ display contained containedin=GistaMeta
  syntax match GistaLastModified /\d\{2}\/\d\{2}\/\d\{2}(\d\{2}:\d\{2}:\d\{2})/
        \ display contained containedin=GistaMeta
  syntax match GistaModifiedMarker /[ \*]/
        \ display contained containedin=GistaMeta
endfunction " }}}
function! gista#command#list#get_status_string(...) abort " {{{
  let lookup = get(a:000, 0, '')
  if empty(lookup)
    return printf('Gist entries of %s in %s (Mode: %s)',
          \ b:gista.lookup,
          \ b:gista.apiname,
          \ s:LABEL_MODES[s:get_current_label_index()]
          \)
  elseif lookup ==# 'apiname'
    return b:gista.apiname
  elseif lookup ==# 'lookup'
    return b:gista.lookup
  else
    return printf('Invalid lookup "%s" is specified', lookup)
  endif
endfunction " }}}

call gista#define_variables('command#list', {
      \ 'default_options': {},
      \ 'default_label': 'updated_at',
      \ 'default_datetime': 'updated_at',
      \ 'default_opener': 'topleft 15 split',
      \ 'default_entry_opener': 'edit',
      \ 'entry_openers': {
      \   'edit':    ['edit', 1],
      \   'above':   ['leftabove new', 1],
      \   'below':   ['rightbelow new', 1],
      \   'left':    ['leftabove vnew', 1],
      \   'right':   ['rightbelow vnew', 1],
      \   'tab':     ['tabnew', 0],
      \   'preview': ['pedit', 0],
      \ },
      \})

let &cpo = s:save_cpo
" vim:set et ts=2 sts=2 sw=2 tw=0 fdm=marker:
