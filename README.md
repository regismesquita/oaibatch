# OaiBatch (Swift)

A macOS app for OpenAI's Batch API (Responses API). Create batch requests, monitor status, and fetch/copy responses when they complete (up to 24h turnaround).

## Warning: Use at Your Own Risk

**This software interacts with OpenAI's Batch API, which may have bugs that can result in unexpected charges.**

I experienced an issue where a single batch job triggered multiple executions on OpenAI's side. The batch listing showed only one job, but the logs revealed multiple complete executions (each with full input and successful output). I was charged for all of them, and the batch never completed. This appears to be an OpenAI bug, not an issue with this tool.

- I contacted OpenAI about the above and I noticed that on the next day I was billed the right amount, so apparently they have a cron or something fixing the batch cost overnight... so you might expect to see a single batch job listed, lot of requests on the logs, usage will show a higher than expected billing cost, it should be fixed overnight and everything will be back to normal. I am still keeping a close eye on it.

**Recommendations:**
- Monitor your OpenAI usage dashboard while jobs are running
- Set up billing alerts on your OpenAI account
- Be cautious with expensive models (`gpt-5.2-pro`, `o3-pro`) and high token limits
- Check logs for duplicate executions if a batch takes unusually long
- Start with smaller/cheaper requests to verify everything works as expected

This tool is provided as-is with no guarantees. You are responsible for any charges incurred.

## Screenshots
<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/32f5f88c-5a44-4bcb-a32c-651fb5021bbb" />
<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/bdb07bd3-edb5-44ca-83d8-e75079082ff3" />


## Requirements

- macOS 14+
- Xcode 15+ (to build from source)
- OpenAI API key via `OPENAI_API_KEY` or `~/.oaibatch/config.json`

## Build & Run

### Xcode

Open `OaiBatch-Swift/OaiBatch.xcodeproj` and run the `OaiBatch` scheme.

### Scripted build (app + DMG)

```bash
cd OaiBatch-Swift
./build.sh all
```

Outputs:
- `OaiBatch-Swift/build/export/OaiBatch.app`
- `OaiBatch-Swift/OaiBatch.dmg`

## Usage

1. Launch the app.
2. In **Settings**, save your API key (stored at `~/.oaibatch/config.json`). `OPENAI_API_KEY` overrides the saved key.
3. Create a request (model, reasoning effort, max output tokens, optional web search).
4. Refresh statuses and fetch/copy responses when completed.

## How it works

1. **Create**: Uploads a JSONL file with your request to OpenAI and creates a batch job
2. **Requests**: Refreshes status of your batches from the API
3. **Response**: Downloads the output file and extracts your request's response text

Requests are stored locally in `~/.oaibatch/requests.json` for tracking.

## Configuration

- **Model**: Selectable per request (default: `gpt-5.2-pro`)
- **Reasoning effort**: `none`, `low`, `medium`, `high`, `xhigh` (`none` disables reasoning)
- **Web search**: Optional `web_search` tool (context size: `low` / `medium` / `high`)
- **Endpoint**: `/v1/responses`
- **Completion window**: 24 hours

### Batch pricing (per 1M tokens)

| Model         | Input / 1M | Output / 1M |
|--------------|-----------:|------------:|
| `gpt-5.2`      | $0.875     | $7.00       |
| `o4-mini`      | $0.55      | $2.20       |
| `o3`           | $5.00      | $20.00      |
| `o3-pro`       | $10.00     | $40.00      |
| `gpt-5.2-pro`  | $10.50     | $84.00      |

Cost estimates shown in the app use the model stored on each request.

## License

MIT
