" vim-yagi - AI assistant using yagi
" Maintainer: Yasuhiro Matsumoto
" License: MIT

if exists('g:loaded_yagi')
  finish
endif
let g:loaded_yagi = 1

let g:yagi_executable = get(g:, 'yagi_executable', 'yagi')

" Get default model from YAGI_MODEL env var or default to 'openai'
let s:default_model = exists('$YAGI_MODEL') ? $YAGI_MODEL : 'openai'
let g:yagi_model = get(g:, 'yagi_model', s:default_model)

let g:yagi_show_prompt = get(g:, 'yagi_show_prompt', 1)

command! -range -nargs=* Yagi call yagi#chat(<q-args>, <line1>, <line2>)
command! -nargs=* YagiPrompt call yagi#prompt(<q-args>)
command! -range YagiExplain call yagi#explain(<line1>, <line2>)
command! -range YagiRefactor call yagi#refactor(<line1>, <line2>)
command! -range YagiComment call yagi#comment(<line1>, <line2>)
command! -range YagiFix call yagi#fix(<line1>, <line2>)

" Default keymaps (optional, users can override)
if !exists('g:yagi_no_default_mappings')
  xnoremap <silent> <Leader>yc :Yagi<Space>
  nnoremap <silent> <Leader>yp :YagiPrompt<Space>
  xnoremap <silent> <Leader>ye :YagiExplain<CR>
  xnoremap <silent> <Leader>yr :YagiRefactor<CR>
  xnoremap <silent> <Leader>ym :YagiComment<CR>
  xnoremap <silent> <Leader>yf :YagiFix<CR>
endif
