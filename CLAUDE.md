# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

oaibatch is a CLI tool for OpenAI's Batch API. It submits prompts for asynchronous processing at 50% cost savings with 24-hour turnaround.

## Commands

```bash
# Install dependencies
pip install openai rich customtkinter

# Set API key (required)
export OPENAI_API_KEY="your-key-here"

# Run CLI
./oaibatch create "prompt"          # Create batch request
./oaibatch create -g                # Create via macOS GUI dialog
./oaibatch list                     # List all requests
./oaibatch read req-abc123          # Read response (full details)
./oaibatch read -r req-abc123       # Response text only (for piping)

# Run Tkinter GUI
./oaibatch gui
```

## Architecture

- **oaibatch.py** - Main CLI: argparse-based with create/list/read/gui subcommands. Uses `rich` for formatted output when available.
- **oaibatch_gui.py** - Modern dark-themed GUI built with CustomTkinter. Features sidebar navigation, card-based request list with hover effects, and async API calls.
- **oaibatch** - Bash wrapper that invokes oaibatch.py

## Data Storage

Requests are persisted to `~/.oaibatch/requests.json`. Each record tracks:
- Request ID (custom_id: `req-{uuid}`)
- Batch ID (from OpenAI API)
- Prompt, system prompt, status, timestamps
- Cached response (once fetched)

## API Configuration

- **Model**: `gpt-5.2-pro` (hardcoded in both files)
- **Endpoint**: `/v1/responses` (OpenAI Responses API)
- **Completion window**: 24 hours
- **Default max tokens**: 100,000

## Key Implementation Details

- Batch requests are uploaded as JSONL files to OpenAI, then a batch job is created
- Status is fetched live from the API on `list` and `read` commands
- Response extraction handles the Responses API format: `body.output[].content[].text` or `body.output_text`
- The `-r/--response-only` flag outputs raw text to stdout with errors to stderr (exit 1 if not completed)
