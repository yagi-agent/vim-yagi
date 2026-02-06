# vim-yagi

Vim plugin for AI assistance using [yagi](https://github.com/mattn/yagi).

## Requirements

- Vim 8.0+ with job support
- yagi executable in PATH
- API key configured via environment variable

## Installation

### Using vim-plug

```vim
Plug 'mattn/vim-yagi'
```

### Manual

```bash
git clone https://github.com/mattn/vim-yagi ~/.vim/plugged/vim-yagi
```

Add to your `.vimrc`:
```vim
set runtimepath+=~/.vim/plugged/vim-yagi
```

## Configuration

### API Key (Required)

Set your API key in your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
export OPENAI_API_KEY="your-key-here"
# or
export ANTHROPIC_API_KEY="your-key-here"
# or
export GEMINI_API_KEY="your-key-here"
```

### Plugin Settings

```vim
" Path to yagi executable (default: 'yagi')
let g:yagi_executable = 'yagi'

" Model to use (default: 'openai')
" Can also be set via YAGI_MODEL environment variable
let g:yagi_model = 'openai'

" Disable default key mappings
let g:yagi_no_default_mappings = 1
```

## Commands

- `:Yagi [prompt]` - Chat with AI (with visual selection as context)
- `:YagiPrompt [prompt]` - Ask AI a question
- `:YagiExplain` - Explain selected code
- `:YagiRefactor` - Refactor selected code
- `:YagiComment` - Add comments to selected code
- `:YagiFix` - Fix bugs in selected code

## Default Key Mappings

- `<Leader>yc` - Chat with selection
- `<Leader>yp` - Prompt without selection
- `<Leader>ye` - Explain selection
- `<Leader>yr` - Refactor selection
- `<Leader>ym` - Add comments to selection
- `<Leader>yf` - Fix bugs in selection

## Usage Examples

1. Select code in visual mode and press `<Leader>ye` to explain it
2. Select code and run `:Yagi how can I improve this?`
3. Run `:YagiPrompt what is the time complexity of quicksort?`

## Troubleshooting

### Error: yagi exited with status 1

Make sure your API key environment variable is set:

```bash
# Check if key is set
echo $OPENAI_API_KEY

# If not set, add to your shell profile
export OPENAI_API_KEY="your-key-here"
```

### Yagi executable not found

Make sure yagi is installed and in your PATH:

```bash
# Install yagi
go install github.com/mattn/yagi@latest

# Or add to PATH
export PATH="$PATH:/path/to/yagi"
```

## License

MIT
