let s:save_cpo = &cpo
set cpo&vim

let s:V = gista#vital()
let s:A = s:V.import('ArgumentParser')

function! s:handle_exception(exception) abort " {{{
  redraw
  let canceled_by_user_patterns = [
        \ '^vim-gista: Login canceled',
        \ '^vim-gista: ValidationError:',
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

function! gista#command#open#read(...) abort " {{{
  let options = extend({
        \ 'gistid': '',
        \ 'gist': {},
        \ 'filename': '',
        \}, get(a:000, 0, {}),
        \)
  try
    if !empty(options.gist)
      let gistid   = options.gist.id
      let filename = gista#meta#get_valid_filename(options.gist, options.filename)
    else
      let gistid   = gista#meta#get_valid_gistid(options.gistid)
      let filename = gista#meta#get_valid_filename(gistid, options.filename)
    endif
    let gist    = gista#api#gists#get(gistid, options)
    let content = gista#api#gists#content(gist, filename, options)
  catch /^vim-gista:/
    call s:handle_exception(v:exception)
  endtry
  call gista#util#buffer#read_content(
        \ content.content,
        \ printf('%s.%s', tempname(), fnamemodify(content.filename, ':e')),
        \)
endfunction " }}}
function! gista#command#open#edit(...) abort " {{{
  let options = extend({
        \ 'gistid': '',
        \ 'gist': {},
        \ 'filename': '',
        \}, get(a:000, 0, {})
        \)
  try
    if !empty(options.gist)
      let gistid   = options.gist.id
      let filename = gista#meta#get_valid_filename(options.gist, options.filename)
    else
      let gistid   = gista#meta#get_valid_gistid(options.gistid)
      let filename = gista#meta#get_valid_filename(gistid, options.filename)
    endif
    let gist    = gista#api#gists#get(gistid, options)
    let content = gista#api#gists#content(gist, filename, options)
  catch /^vim-gista:/
    call s:handle_exception(v:exception)
    return
  endtry
  let client = gista#api#get_current_client()
  let apiname = client.apiname
  let username = client.get_authorized_username()
  let b:gista = {
        \ 'apiname': apiname,
        \ 'username': username,
        \ 'gistid': gist.id,
        \ 'filename': content.filename,
        \ 'content_type': 'raw',
        \}
  call gista#util#buffer#edit_content(
        \ content.content,
        \ printf('%s.%s', tempname(), fnamemodify(content.filename, ':e')),
        \)
  if get(get(gist, 'owner', {}), 'login', '') ==# username
    " TODO
    " Add autocmd to write the changes
    setlocal buftype=acwrite
    setlocal modifiable
  else
    setlocal buftype=nowrite
    setlocal nomodifiable
  endif
  silent execute printf('file gista:%s:%s:%s',
        \ apiname,
        \ gist.id,
        \ content.filename,
        \)
  filetype detect
endfunction " }}}
function! gista#command#open#open(...) abort " {{{
  let options = extend({
        \ 'gistid': '',
        \ 'gist': {},
        \ 'filename': '',
        \ 'opener': '',
        \ 'cache': 1,
        \}, get(a:000, 0, {})
        \)
  try
    if !empty(options.gist)
      let gistid   = options.gist.id
      let filename = gista#meta#get_valid_filename(options.gist, options.filename)
    else
      let gistid   = gista#meta#get_valid_gistid(options.gistid)
      let filename = gista#meta#get_valid_filename(gistid, options.filename)
    endif
  catch /^vim-gista:/
    call s:handle_exception(v:exception)
    return
  endtry
  let client = gista#api#get_current_client()
  let apiname = client.apiname
  let opener = empty(options.opener)
        \ ? g:gista#command#open#default_opener
        \ : options.opener
  let bufname = printf('gista:%s:%s:%s',
        \ client.apiname, gistid, filename,
        \)
  call gista#util#buffer#open(bufname, {
        \ 'opener': opener . (options.cache ? '' : '!'),
        \})
  " BufReadCmd will execute gista#command#open#edit()
endfunction " }}}

function! s:get_parser() abort " {{{
  if !exists('s:parser') || g:gista#develop
    let s:parser = s:A.new({
          \ 'name': 'Gista open',
          \ 'description': 'Open a content of a particular gist',
          \})
    call s:parser.add_argument(
          \ 'gistid',
          \ 'A gist ID', {
          \   'complete': function('g:gista#meta#complete_gistid'),
          \   'type': s:A.types.value,
          \})
    call s:parser.add_argument(
          \ 'filename',
          \ 'A filename', {
          \   'complete': function('g:gista#meta#complete_filename'),
          \   'type': s:A.types.value,
          \})
    call s:parser.add_argument(
          \ '--opener', '-o',
          \ 'A way to open a new buffer such as "edit", "split", etc.', {
          \   'type': s:A.types.value,
          \})
    call s:parser.add_argument(
          \ '--cache',
          \ 'Use cached content whenever possible', {
          \   'default': 1,
          \   'deniable': 1,
          \})
  endif
  return s:parser
endfunction " }}}
function! gista#command#open#command(...) abort " {{{
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if empty(options)
    return
  endif
  " extend default options
  let options = extend(
        \ deepcopy(g:gista#command#open#default_options),
        \ options,
        \)
  call gista#command#open#open(options)
endfunction " }}}
function! gista#command#open#complete(...) abort " {{{
  let parser = s:get_parser()
  return call(parser.complete, a:000, parser)
endfunction " }}}

function! gista#command#open#parse_afile(afile) abort " {{{

endfunction " }}}

call gista#define_variables('command#open', {
      \ 'default_options': {},
      \ 'default_opener': 'edit',
      \})

let &cpo = s:save_cpo
unlet! s:save_cpo
" vim:set et ts=2 sts=2 sw=2 tw=0 fdm=marker:
