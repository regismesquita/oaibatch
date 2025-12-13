# oaibatch

A CLI tool for OpenAI's Batch API. Submit prompts for asynchronous processing at 50% cost savings with 24-hour turnaround.

## Warning: Use at Your Own Risk

**This software interacts with OpenAI's Batch API, which may have bugs that can result in unexpected charges.**

I experienced an issue where a single batch job triggered multiple executions on OpenAI's side. The batch listing showed only one job, but the logs revealed multiple complete executions (each with full input and successful output). I was charged for all of them, and the batch never completed. This appears to be an OpenAI bug, not an issue with this tool.

**Recommendations:**
- Monitor your OpenAI usage dashboard while jobs are running
- Set up billing alerts on your OpenAI account
- Be cautious with expensive models (`gpt-5.2-pro`, `o3-pro`) and high token limits
- Check logs for duplicate executions if a batch takes unusually long
- Start with smaller/cheaper requests to verify everything works as expected

This tool is provided as-is with no guarantees. You are responsible for any charges incurred.

## Installation

```bash
pip install openai rich customtkinter
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

# Choose model and reasoning effort
./oaibatch create "Summarize this text" --model gpt-5.2 --reasoning-effort medium
./oaibatch create "Deep analysis of X" --model o3-pro --reasoning-effort xhigh

# Using GUI dialog (macOS)
./oaibatch create --gui
./oaibatch create -g -s "You are a scientist"
```

**Options:**
- `-s, --system` - System prompt (default: "You are a helpful assistant.")
- `-m, --max-tokens` - Max output tokens (default: 100000)
- `--model` - Model to use (`gpt-5.2`, `o3-pro`, `gpt-5.2-pro`)
- `--reasoning-effort, --effort` - Reasoning effort (`none`, `low`, `medium`, `high`, `xhigh`). Use `none` to disable reasoning.
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

### Desktop GUI

A modern dark-themed desktop application for managing batch requests:

```bash
./oaibatch gui
```

**Features:**
- **Sidebar navigation** - Switch between New Request, Requests list, and Response views
- **Card-based request list** - Click any request card to view details and fetch responses
- **Live status refresh** - Pull latest status from the API with one click
- **Copy to clipboard** - Easily copy responses for use elsewhere

**Notes:**
- Requires `OPENAI_API_KEY` in your environment
- The `./oaibatch create --gui` option is a separate macOS-only prompt dialog
- Built with CustomTkinter for a modern look across platforms

## How it works

1. **Create**: Uploads a JSONL file with your request to OpenAI, creates a batch job
2. **List**: Fetches current status of all your batches from the API
3. **Read**: Retrieves the response once the batch is completed

Requests are stored locally in `~/.oaibatch/requests.json` for tracking.

## Configuration

- **Model**: Selectable per request (default: `gpt-5.2-pro`)
  - CLI: `--model`
  - GUI: model dropdown on the New Request screen
- **Reasoning effort**: Selectable per request (default: `xhigh`)
  - CLI: `--reasoning-effort` / `--effort`
  - GUI: reasoning dropdown on the New Request screen (`none` disables reasoning)
- **Endpoint**: `/v1/responses`
- **Completion window**: 24 hours

### Batch pricing (per 1M tokens)

| Model        | Input / 1M | Output / 1M |
|-------------|------------:|------------:|
| `gpt-5.2`     | $0.875      | $7.00       |
| `o3-pro`      | $10.00      | $40.00      |
| `gpt-5.2-pro` | $10.50      | $84.00      |

Cost estimates shown in the GUI (and in CLI `read` usage output) use the model stored on each request.

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
- `rich` >= 13.0.0 (optional, for pretty CLI output)
- `customtkinter` >= 5.2.0 (for desktop GUI)
- macOS (for `--gui` create dialog only)

## License

MIT
