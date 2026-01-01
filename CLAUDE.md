# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OaiBatch is a macOS app (SwiftUI) for OpenAI's Batch API. It submits prompts for asynchronous processing at 50% cost savings with 24-hour turnaround.

## Commands

```bash
# Set API key (required)
export OPENAI_API_KEY="your-key-here"

# Open in Xcode
open OaiBatch-Swift/OaiBatch.xcodeproj

# Or build via script
cd OaiBatch-Swift
./build.sh build-debug
./build.sh all
```

## Architecture

- **OaiBatch-Swift/OaiBatch/Sources/Services/OpenAIService.swift** - OpenAI Batch API interactions.
- **OaiBatch-Swift/OaiBatch/Sources/Services/DataStore.swift** - Persistence for requests + config (API key).
- **OaiBatch-Swift/OaiBatch/Sources/Models/BatchRequest.swift** - Request model + status + usage.
- **OaiBatch-Swift/OaiBatch/Sources/Models/Config.swift** - Models, pricing, and API constants.
- **OaiBatch-Swift/OaiBatch/Sources/Views/** - SwiftUI UI (create, requests list, response, settings).

## Data Storage

Requests are persisted to `~/.oaibatch/requests.json`. Each record tracks:
- Request ID (custom_id: `req-{uuid}`)
- Batch ID (from OpenAI API)
- Prompt, system prompt, status, timestamps
- Cached response (once fetched)

## API Configuration

- **Model**: default `gpt-5.2-pro` (selectable per request)
- **Endpoint**: `/v1/responses` (OpenAI Responses API)
- **Completion window**: 24 hours
- **Default max tokens**: 100,000

## Key Implementation Details

- Batch requests are uploaded as JSONL files to OpenAI, then a batch job is created
- Status is refreshed from the Batch API (`/v1/batches`)
- Response extraction handles the Responses API format: `body.output[].content[].text` or `body.output_text`
