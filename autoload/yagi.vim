" autoload/yagi.vim
let s:save_cpo = &cpo
set cpo&vim

function! s:get_visual_selection(line1, line2) abort
  let l:lines = getline(a:line1, a:line2)
  return join(l:lines, "\n")
endfunction

function! s:show_in_preview(content) abort
  let l:bufnr = bufnr('__yagi_response__', v:true)
  call setbufvar(l:bufnr, '&buftype', 'nofile')
  call setbufvar(l:bufnr, '&bufhidden', 'hide')
  call setbufvar(l:bufnr, '&swapfile', 0)
  call setbufvar(l:bufnr, '&filetype', 'markdown')

  let l:winid = bufwinid(l:bufnr)
  if l:winid == -1
    execute 'rightbelow vsplit'
    execute 'buffer ' . l:bufnr
  else
    call win_gotoid(l:winid)
  endif

  call setbufline(l:bufnr, 1, split(a:content, "\n"))
  normal! gg
endfunction

function! s:send_request(messages, callback) abort
  let s:yagi_response = ''
  let l:cmd = [g:yagi_executable, '-stdio', '-model', g:yagi_model]

  if !executable(g:yagi_executable)
    call a:callback({'error': 'yagi executable not found: ' . g:yagi_executable})
    return
  endif

  " Prepare environment variables - pass through all potential API keys
  let l:env = {}
  for l:key in ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 
        \ 'DEEPSEEK_API_KEY', 'GROQ_API_KEY', 'XAI_API_KEY', 
        \ 'MISTRAL_API_KEY', 'PERPLEXITY_API_KEY', 'CEREBRAS_API_KEY',
        \ 'COHERE_API_KEY', 'OPENROUTER_API_KEY', 'SAMBANOVA_API_KEY',
        \ 'GLM_API_KEY', 'YAGI_MODEL']
    if exists('$' . l:key)
      let l:env[l:key] = eval('$' . l:key)
    endif
  endfor

  " Pass vim-specific environment variables
  let l:env['YAGI_VIM_BUFFER_PATH'] = expand('%:p')
  let l:env['YAGI_VIM_CURSOR_LINE'] = line('.')
  let l:env['YAGI_VIM_CURSOR_COL'] = col('.')

  let l:job_opts = {
    \ 'in_mode': 'nl',
    \ 'out_mode': 'nl',
    \ 'err_mode': 'nl',
    \ 'out_cb': function('s:on_stdout', [a:callback]),
    \ 'err_cb': function('s:on_stderr', [a:callback]),
    \ 'exit_cb': function('s:on_exit', [a:callback])
    \ }

  if !empty(l:env)
    let l:job_opts.env = l:env
  endif

  let l:job = job_start(l:cmd, l:job_opts)

  let l:channel = job_getchannel(l:job)

  " Prepend vim mode system message to messages
  let l:system_msg = {'role': 'system', 'content': 'You are an agent controlling a vim editor. You MUST call the "vim" tool to perform actions. NEVER respond with only text. ALWAYS make a tool call. Do NOT use any tool other than "vim". Available actions: get_buffer, get_cursor, execute, insert, search, replace. For text substitution use "replace" action (generates vim :%s command). The pattern uses vim regex syntax: \< and \> for word boundaries (NOT \b). Example replacing word "bar" with "バー": {"action":"replace","args":{"pattern":"\\<bar\\>","replace":"バー","flags":"g"}}. For arbitrary ex-commands use "execute" with {"command":":cmd"}.'}
  call insert(a:messages, l:system_msg)

  let l:request = {
    \ 'messages': a:messages,
    \ 'stream': v:false
    \ }
  let l:json_request = json_encode(l:request) . "\n"

  call ch_sendraw(l:channel, l:json_request)
  call ch_close_in(l:channel)
endfunction

function! s:on_stdout(callback, channel, msg) abort
  if a:msg =~ '^\s*$'
    return
  endif

  " Debug: show raw response
  echom 'Yagi raw: ' . a:msg

  try
    let l:response = json_decode(a:msg)
    if has_key(l:response, 'error')
      call a:callback({'error': l:response.error})
    elseif has_key(l:response, 'tool_result')
      let l:tr = l:response.tool_result
      if l:tr.name ==# 'vim'
        let l:tool_output = json_decode(l:tr.output)
        if has_key(l:tool_output, 'vim_command')
          call s:execute_vim_command(l:tool_output.vim_command)
        endif
      endif
    elseif has_key(l:response, 'content')
      if !empty(l:response.content)
        let s:yagi_response .= l:response.content
      endif
    endif
  catch
    echohl ErrorMsg
    echomsg 'Failed to parse response: ' . a:msg
    echohl None
  endtry
endfunction

function! s:execute_vim_command(cmd) abort
  if empty(a:cmd)
    return
  endif
  echom 'Executing vim command: ' . a:cmd
  call feedkeys(a:cmd, 'x')
endfunction

let s:yagi_error = ''

function! s:on_stderr(callback, channel, msg) abort
  " Collect stderr messages
  let s:yagi_error .= a:msg . "\n"
endfunction

function! s:on_exit(callback, job, status) abort
  if a:status == 0
    call a:callback({'content': s:yagi_response})
  else
    let l:error_msg = 'yagi exited with status ' . a:status
    if !empty(s:yagi_error)
      let l:error_msg .= ': ' . s:yagi_error
    endif
    call a:callback({'error': l:error_msg})
  endif
  let s:yagi_error = ''
endfunction

function! yagi#chat(prompt, line1, line2) abort
  let l:selection = s:get_visual_selection(a:line1, a:line2)

  let l:prompt = a:prompt
  if empty(l:prompt)
    let l:prompt = input('Yagi> ')
    if empty(l:prompt)
      return
    endif
  endif

  let l:messages = []
  if !empty(l:selection)
    let l:filetype = &filetype
    let l:filename = expand('%:t')
    let l:context = "/agent on\nFile: " . l:filename
    if !empty(l:filetype)
      let l:context .= " (" . l:filetype . ")"
    endif
    let l:context .= "\n\n```" . l:filetype . "\n" . l:selection . "\n```\n\n" . l:prompt
    call add(l:messages, {'role': 'user', 'content': l:context})
  else
    call add(l:messages, {'role': 'user', 'content': "/agent on\n" . l:prompt})
  endif

  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_response'))
endfunction

function! yagi#prompt(prompt) abort
  if empty(a:prompt)
    let l:prompt = input('Yagi> ')
    if empty(l:prompt)
      return
    endif
  else
    let l:prompt = a:prompt
  endif

  let l:messages = [{'role': 'user', 'content': l:prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_response'))
endfunction

function! yagi#explain(line1, line2) abort
  let l:selection = s:get_visual_selection(a:line1, a:line2)
  let l:filetype = &filetype
  let l:filename = expand('%:t')

  let l:prompt = "Explain the following code.\n\n"
  let l:prompt .= "File: " . l:filename . "\n"
  if !empty(l:filetype)
    let l:prompt .= "Language: " . l:filetype . "\n"
  endif
  let l:prompt .= "\n```" . l:filetype . "\n" . l:selection . "\n```"

  let l:messages = [{'role': 'user', 'content': l:prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_response'))
endfunction

function! yagi#refactor(line1, line2) abort
  let l:selection = s:get_visual_selection(a:line1, a:line2)
  let l:filetype = &filetype
  let l:filename = expand('%:t')
  let l:full_content = join(getline(1, '$'), "\n")

  let l:prompt = "Refactor and improve the following code.\n\n"
  let l:prompt .= "File: " . l:filename . "\n"
  if !empty(l:filetype)
    let l:prompt .= "Language: " . l:filetype . "\n"
  endif
  let l:prompt .= "Selected lines: " . a:line1 . "-" . a:line2 . "\n\n"
  let l:prompt .= "Full file for context:\n```" . l:filetype . "\n" . l:full_content . "\n```\n\n"
  let l:prompt .= "Selected code to refactor:\n```" . l:filetype . "\n" . l:selection . "\n```\n\n"
  let l:prompt .= "Return ONLY the refactored code for the selected portion, without markdown formatting or explanations."

  let l:messages = [{'role': 'user', 'content': l:prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_refactor_response', [a:line1, a:line2]))
endfunction

function! s:handle_refactor_response(line1, line2, result) abort
  if has_key(a:result, 'error')
    echohl ErrorMsg
    echomsg 'Error: ' . a:result.error
    echohl None
    return
  endif

  if has_key(a:result, 'content')
    let l:content = a:result.content
    let l:lines = split(l:content, "\n")

    let l:code_lines = []
    let l:in_code_block = 0
    for l:line in l:lines
      if l:line =~# '^```'
        let l:in_code_block = !l:in_code_block
        continue
      endif
      if l:in_code_block || !match(l:content, '^```')
        call add(l:code_lines, l:line)
      endif
    endfor

    if empty(l:code_lines)
      let l:code_lines = l:lines
    endif

    call s:show_in_preview("# Refactored Code\n\n```" . &filetype . "\n" . join(l:code_lines, "\n") . "\n```\n\nUse :YagiApply to apply changes")
  endif
endfunction

function! yagi#comment(line1, line2) abort
  let l:selection = s:get_visual_selection(a:line1, a:line2)
  let l:filetype = &filetype
  let l:filename = expand('%:t')

  let l:prompt = "Add helpful comments to the following code.\n\n"
  let l:prompt .= "File: " . l:filename . "\n"
  if !empty(l:filetype)
    let l:prompt .= "Language: " . l:filetype . "\n"
  endif
  let l:prompt .= "\n```" . l:filetype . "\n" . l:selection . "\n```\n\n"
  let l:prompt .= "Return the code with comments added. Use appropriate comment syntax for " . l:filetype . "."

  let l:messages = [{'role': 'user', 'content': l:prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_response'))
endfunction

function! yagi#fix(line1, line2) abort
  let l:selection = s:get_visual_selection(a:line1, a:line2)
  let l:filetype = &filetype
  let l:filename = expand('%:t')

  let l:full_content = join(getline(1, '$'), "\n")

  let l:prompt = "Fix bugs or issues in the following code.\n\n"
  let l:prompt .= "File: " . l:filename . "\n"
  if !empty(l:filetype)
    let l:prompt .= "Language: " . l:filetype . "\n"
  endif
  let l:prompt .= "Selected lines: " . a:line1 . "-" . a:line2 . "\n\n"
  let l:prompt .= "Full file for context:\n```" . l:filetype . "\n" . l:full_content . "\n```\n\n"
  let l:prompt .= "Selected code to fix:\n```" . l:filetype . "\n" . l:selection . "\n```\n\n"
  let l:prompt .= "Return ONLY the fixed code for the selected portion, without markdown formatting or explanations."

  let l:messages = [{'role': 'user', 'content': l:prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(l:messages, function('s:handle_fix_response', [a:line1, a:line2]))
endfunction

function! s:handle_fix_response(line1, line2, result) abort
  if has_key(a:result, 'error')
    echohl ErrorMsg
    echomsg 'Error: ' . a:result.error
    echohl None
    return
  endif

  if has_key(a:result, 'content')
    let l:content = a:result.content
    let l:lines = split(l:content, "\n")

    let l:code_lines = []
    let l:in_code_block = 0
    for l:line in l:lines
      if l:line =~# '^```'
        let l:in_code_block = !l:in_code_block
        continue
      endif
      if l:in_code_block || !match(l:content, '^```')
        call add(l:code_lines, l:line)
      endif
    endfor

    if empty(l:code_lines)
      let l:code_lines = l:lines
    endif

    let l:preview = join(l:code_lines[0:5], "\n")
    if len(l:code_lines) > 5
      let l:preview .= "\n..."
    endif

    echohl Question
    echo "Replace selection with fixed code? (y/n)\n" . l:preview
    echohl None

    let l:choice = nr2char(getchar())
    if l:choice ==# 'y' || l:choice ==# 'Y'
      call deletebufline('%', a:line1, a:line2)
      call append(a:line1 - 1, l:code_lines)
      echomsg 'Code fixed!'
    else
      call s:show_in_preview(a:result.content)
    endif
  endif
endfunction

function! s:handle_response(result) abort
  if has_key(a:result, 'error')
    echohl ErrorMsg
    echomsg 'Error: ' . a:result.error
    echohl None
    return
  endif

  if has_key(a:result, 'content')
    call s:show_in_preview(a:result.content)
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
