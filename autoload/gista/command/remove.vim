let s:save_cpo = &cpo
set cpo&vim

let s:V = gista#vital()
let s:A = s:V.import('ArgumentParser')

function! gista#command#remove#call(...) abort
  let options = extend({
        \ 'gist': {},
        \ 'gistid': '',
        \ 'filename': '',
        \ 'force': 0,
        \ 'confirm': 1,
        \}, get(a:000, 0, {}))
  let gistid = ''
  let filename = ''
  try
    let client = gista#client#get()
    let gistid = gista#resource#local#get_valid_gistid(empty(options.gist)
          \ ? options.gistid
          \ : options.gist.id
          \)
    let gist = gista#resource#remote#get(gistid, options)
    let filename = gista#resource#local#get_valid_filename(gist, options.filename)
    if options.confirm
      if !gista#util#prompt#confirm(printf(
            \ 'Remove %s of %s in %s? ',
            \ filename, gistid, client.apiname,
            \))
        call gista#throw('Cancel')
      endif
    endif
    call gista#resource#remote#patch(gistid, {
          \ 'force': options.force,
          \ 'filenames': [filename],
          \ 'contents': [{}],
          \})
    silent call gista#util#doautocmd('CacheUpdatePost')
    call gista#util#prompt#indicate(options, printf(
          \ 'A %s is removed from a gist %s in %s',
          \ filename, gistid, client.apiname,
          \))
    return [gistid, filename]
  catch /^vim-gista:/
    call gista#util#handle_exception(v:exception)
    return [gistid, filename]
  endtry
endfunction

function! s:get_parser() abort
  if !exists('s:parser') || g:gista#develop
    let s:parser = s:A.new({
          \ 'name': 'Gista remove',
          \ 'description': 'Remove a file of a gist',
          \})
    call s:parser.add_argument(
          \ '--force',
          \ 'Delete a file even a remote content of the gist is modified', {
          \   'default': 0,
          \   'deniable': 1,
          \})
    call s:parser.add_argument(
          \ '--confirm',
          \ 'Confirm before delete', {
          \   'default': 1,
          \   'deniable': 1,
          \})
    call s:parser.add_argument(
          \ 'gistid',
          \ 'A gist ID', {
          \   'complete': function('g:gista#option#complete_gistid'),
          \})
    call s:parser.add_argument(
          \ 'filename',
          \ 'A filename', {
          \   'complete': function('g:gista#option#complete_filename'),
          \})
  endif
  return s:parser
endfunction
function! gista#command#remove#command(...) abort
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if empty(options)
    return
  endif
  call gista#option#assign_gistid(options, '%')
  call gista#option#assign_filename(options, '%')
  " extend default options
  let options = extend(
        \ deepcopy(g:gista#command#remove#default_options),
        \ options,
        \)
  call gista#command#remove#call(options)
endfunction
function! gista#command#remove#complete(...) abort
  let parser = s:get_parser()
  return call(parser.complete, a:000, parser)
endfunction

call gista#define_variables('command#remove', {
      \ 'default_options': {},
      \})

let &cpo = s:save_cpo
unlet! s:save_cpo
" vim:set et ts=2 sts=2 sw=2 tw=0 fdm=marker:
