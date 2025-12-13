# oaibatch

A CLI tool for OpenAI's Batch API. Submit prompts for asynchronous processing at 50% cost savings with 24-hour turnaround.

## Installation

```bash
pip install openai rich
export OPENAI_API_KEY="your-key-here"
```

## Usage

### Create a batch request

```bash
# From argument
./oaibatch create "Explain quantum computing in simple terms"

# From file via stdin
./oaibatch create < prompt.txt

# From pipe
echo "Write a haiku about coding" | ./oaibatch create

# With custom system prompt and token limit
./oaibatch create "Write a poem" -s "You are a poet" -m 500

# Using GUI dialog (macOS)
./oaibatch create --gui
./oaibatch create -g -s "You are a scientist"
```

**Options:**
- `-s, --system` - System prompt (default: "You are a helpful assistant.")
- `-m, --max-tokens` - Max output tokens (default: 100000)
- `-g, --gui` - Open a macOS GUI dialog to enter the prompt

### List all requests

```bash
./oaibatch list
```

Shows a table with request ID, batch ID, status, created/completed timestamps, and prompt preview. Status is fetched live from the API.

### Read request details and response

```bash
# Full details with formatting
./oaibatch read req-abc123

# Response text only (for piping)
./oaibatch read -r req-abc123
./oaibatch read --response-only req-abc123

# Copy response to clipboard (macOS)
./oaibatch read -r req-abc123 | pbcopy

# Save response to file
./oaibatch read -r req-abc123 > response.txt
```

**Options:**
- `-r, --response-only` - Output only the raw response text (no panels, no metadata)

### GUI (Tkinter)

This project also includes a simple cross-platform desktop GUI (built with Python Tkinter) for:
- Creating batch requests
- Listing and refreshing request statuses
- Fetching and viewing responses

Launch it with:

```bash
./oaibatch gui
```

Notes:
- You still must set `OPENAI_API_KEY` in your environment.
- The existing `./oaibatch create --gui` option is **only** a macOS prompt input dialog; `./oaibatch gui` is the full multi-tab application.
- If you get an error about Tkinter not being available, install a Python distribution that includes Tk (common fix on macOS: use the official python.org installer).

## How it works

1. **Create**: Uploads a JSONL file with your request to OpenAI, creates a batch job
2. **List**: Fetches current status of all your batches from the API
3. **Read**: Retrieves the response once the batch is completed

Requests are stored locally in `~/.oaibatch/requests.json` for tracking.

## Configuration

- **Model**: `gpt-5.2-pro` (using the Responses API)
- **Endpoint**: `/v1/responses`
- **Completion window**: 24 hours

## Example workflow

```bash
# Submit a request
./oaibatch create "Analyze the pros and cons of microservices architecture"
# Output: Request ID: req-a1b2c3d4, Batch ID: batch_xyz...

# Check status
./oaibatch list

# Once completed, read the response
./oaibatch read req-a1b2c3d4

# Or pipe it somewhere
./oaibatch read -r req-a1b2c3d4 | pbcopy
```

## Response-only mode

The `-r` / `--response-only` flag is designed for scripting:
- Outputs **only** the raw response text
- Errors go to stderr (won't pollute pipes)
- Exit code 1 if batch isn't completed yet
- Exit code 0 on success

## Requirements

- Python 3.8+
- `openai` >= 1.0.0
- `rich` >= 13.0.0 (optional, for pretty output)
- macOS (for `--gui` feature)

## License

MIT
