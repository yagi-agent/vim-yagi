" autoload/yagi.vim
let s:save_cpo = &cpo
set cpo&vim

function! s:get_visual_selection(line1, line2) abort
  let lines = getline(a:line1, a:line2)
  return join(lines, "\n")
endfunction

function! s:show_in_preview(content) abort
  let bufnr = bufnr('__yagi_response__', v:true)
  call setbufvar(bufnr, '&buftype', 'nofile')
  call setbufvar(bufnr, '&bufhidden', 'hide')
  call setbufvar(bufnr, '&swapfile', 0)
  call setbufvar(bufnr, '&filetype', 'markdown')
  
  let winid = bufwinid(bufnr)
  if winid == -1
    execute 'rightbelow vsplit'
    execute 'buffer ' . bufnr
  else
    call win_gotoid(winid)
  endif
  
  call setbufline(bufnr, 1, split(a:content, "\n"))
  normal! gg
endfunction

function! s:send_request(messages, callback) abort
  let request = {
    \ 'messages': a:messages,
    \ 'stream': v:false
    \ }
  let json_request = json_encode(request) . "\n"
  
  let s:yagi_response = ''
  let cmd = [g:yagi_executable, '-stdio', '-model', g:yagi_model]
  
  if !executable(g:yagi_executable)
    call a:callback({'error': 'yagi executable not found: ' . g:yagi_executable})
    return
  endif
  
  " Prepare environment variables - pass through all potential API keys
  let env = {}
  for key in ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 
        \ 'DEEPSEEK_API_KEY', 'GROQ_API_KEY', 'XAI_API_KEY', 
        \ 'MISTRAL_API_KEY', 'PERPLEXITY_API_KEY', 'CEREBRAS_API_KEY',
        \ 'COHERE_API_KEY', 'OPENROUTER_API_KEY', 'SAMBANOVA_API_KEY',
        \ 'GLM_API_KEY', 'YAGI_MODEL']
    if exists('$' . key)
      let env[key] = eval('$' . key)
    endif
  endfor
  
  let job_opts = {
    \ 'in_mode': 'nl',
    \ 'out_mode': 'nl',
    \ 'err_mode': 'nl',
    \ 'out_cb': function('s:on_stdout', [a:callback]),
    \ 'err_cb': function('s:on_stderr', [a:callback]),
    \ 'exit_cb': function('s:on_exit', [a:callback])
    \ }
  
  if !empty(env)
    let job_opts.env = env
  endif
  
  let job = job_start(cmd, job_opts)
  
  let channel = job_getchannel(job)
  call ch_sendraw(channel, json_request)
  call ch_close_in(channel)
endfunction

function! s:on_stdout(callback, channel, msg) abort
  if a:msg =~ '^\s*$'
    return
  endif
  
  try
    let response = json_decode(a:msg)
    if has_key(response, 'error')
      call a:callback({'error': response.error})
    elseif has_key(response, 'content')
      let s:yagi_response .= response.content
    endif
  catch
    echohl ErrorMsg
    echomsg 'Failed to parse response: ' . a:msg
    echohl None
  endtry
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
    let error_msg = 'yagi exited with status ' . a:status
    if !empty(s:yagi_error)
      let error_msg .= ': ' . s:yagi_error
    endif
    call a:callback({'error': error_msg})
  endif
  let s:yagi_error = ''
endfunction

function! yagi#chat(prompt, line1, line2) abort
  let selection = s:get_visual_selection(a:line1, a:line2)
  
  let prompt = a:prompt
  if empty(prompt)
    let prompt = input('Yagi> ')
    if empty(prompt)
      return
    endif
  endif
  
  let messages = []
  if !empty(selection)
    let filetype = &filetype
    let filename = expand('%:t')
    let context = "File: " . filename
    if !empty(filetype)
      let context .= " (" . filetype . ")"
    endif
    let context .= "\n\n```" . filetype . "\n" . selection . "\n```\n\n" . prompt
    call add(messages, {'role': 'user', 'content': context})
  else
    call add(messages, {'role': 'user', 'content': prompt})
  endif
  
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_response'))
endfunction

function! yagi#prompt(prompt) abort
  if empty(a:prompt)
    let prompt = input('Yagi> ')
    if empty(prompt)
      return
    endif
  else
    let prompt = a:prompt
  endif
  
  let messages = [{'role': 'user', 'content': prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_response'))
endfunction

function! yagi#explain(line1, line2) abort
  let selection = s:get_visual_selection(a:line1, a:line2)
  let filetype = &filetype
  let filename = expand('%:t')
  
  let prompt = "Explain the following code.\n\n"
  let prompt .= "File: " . filename . "\n"
  if !empty(filetype)
    let prompt .= "Language: " . filetype . "\n"
  endif
  let prompt .= "\n```" . filetype . "\n" . selection . "\n```"
  
  let messages = [{'role': 'user', 'content': prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_response'))
endfunction

function! yagi#refactor(line1, line2) abort
  let selection = s:get_visual_selection(a:line1, a:line2)
  let filetype = &filetype
  let filename = expand('%:t')
  let full_content = join(getline(1, '$'), "\n")
  
  let prompt = "Refactor and improve the following code.\n\n"
  let prompt .= "File: " . filename . "\n"
  if !empty(filetype)
    let prompt .= "Language: " . filetype . "\n"
  endif
  let prompt .= "Selected lines: " . a:line1 . "-" . a:line2 . "\n\n"
  let prompt .= "Full file for context:\n```" . filetype . "\n" . full_content . "\n```\n\n"
  let prompt .= "Selected code to refactor:\n```" . filetype . "\n" . selection . "\n```\n\n"
  let prompt .= "Return ONLY the refactored code for the selected portion, without markdown formatting or explanations."
  
  let messages = [{'role': 'user', 'content': prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_refactor_response', [a:line1, a:line2]))
endfunction

function! s:handle_refactor_response(line1, line2, result) abort
  if has_key(a:result, 'error')
    echohl ErrorMsg
    echomsg 'Error: ' . a:result.error
    echohl None
    return
  endif
  
  if has_key(a:result, 'content')
    " Extract code from response
    let content = a:result.content
    let lines = split(content, "\n")
    
    let code_lines = []
    let in_code_block = 0
    for line in lines
      if line =~# '^```'
        let in_code_block = !in_code_block
        continue
      endif
      if in_code_block || !match(content, '^```')
        call add(code_lines, line)
      endif
    endfor
    
    if empty(code_lines)
      let code_lines = lines
    endif
    
    " Show in preview for review
    call s:show_in_preview("# Refactored Code\n\n```" . &filetype . "\n" . join(code_lines, "\n") . "\n```\n\nUse :YagiApply to apply changes")
  endif
endfunction

function! yagi#comment(line1, line2) abort
  let selection = s:get_visual_selection(a:line1, a:line2)
  let filetype = &filetype
  let filename = expand('%:t')
  
  let prompt = "Add helpful comments to the following code.\n\n"
  let prompt .= "File: " . filename . "\n"
  if !empty(filetype)
    let prompt .= "Language: " . filetype . "\n"
  endif
  let prompt .= "\n```" . filetype . "\n" . selection . "\n```\n\n"
  let prompt .= "Return the code with comments added. Use appropriate comment syntax for " . filetype . "."
  
  let messages = [{'role': 'user', 'content': prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_response'))
endfunction

function! yagi#fix(line1, line2) abort
  let selection = s:get_visual_selection(a:line1, a:line2)
  let filetype = &filetype
  let filename = expand('%:t')
  
  " Get full file content for context
  let full_content = join(getline(1, '$'), "\n")
  
  " Build context-rich prompt
  let prompt = "Fix bugs or issues in the following code.\n\n"
  let prompt .= "File: " . filename . "\n"
  if !empty(filetype)
    let prompt .= "Language: " . filetype . "\n"
  endif
  let prompt .= "Selected lines: " . a:line1 . "-" . a:line2 . "\n\n"
  let prompt .= "Full file for context:\n```" . filetype . "\n" . full_content . "\n```\n\n"
  let prompt .= "Selected code to fix:\n```" . filetype . "\n" . selection . "\n```\n\n"
  let prompt .= "Return ONLY the fixed code for the selected portion, without markdown formatting or explanations."
  
  let messages = [{'role': 'user', 'content': prompt}]
  redraw
  echo 'Thinking...'
  call s:send_request(messages, function('s:handle_fix_response', [a:line1, a:line2]))
endfunction

function! s:handle_fix_response(line1, line2, result) abort
  if has_key(a:result, 'error')
    echohl ErrorMsg
    echomsg 'Error: ' . a:result.error
    echohl None
    return
  endif
  
  if has_key(a:result, 'content')
    " Extract code from response (handle markdown code blocks)
    let content = a:result.content
    let lines = split(content, "\n")
    
    " Remove markdown code fences if present
    let code_lines = []
    let in_code_block = 0
    for line in lines
      if line =~# '^```'
        let in_code_block = !in_code_block
        continue
      endif
      if in_code_block || !match(content, '^```')
        call add(code_lines, line)
      endif
    endfor
    
    " If no code block was found, use all content
    if empty(code_lines)
      let code_lines = lines
    endif
    
    " Ask for confirmation
    let preview = join(code_lines[0:5], "\n")
    if len(code_lines) > 5
      let preview .= "\n..."
    endif
    
    echohl Question
    echo "Replace selection with fixed code? (y/n)\n" . preview
    echohl None
    
    let choice = nr2char(getchar())
    if choice ==# 'y' || choice ==# 'Y'
      " Replace the selected lines
      call deletebufline('%', a:line1, a:line2)
      call append(a:line1 - 1, code_lines)
      echomsg 'Code fixed!'
    else
      " Show in preview window
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
