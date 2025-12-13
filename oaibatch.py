#!/usr/bin/env python3
"""
oaibatch - A CLI tool for OpenAI Batch API operations

Commands:
    create "prompt"  - Create a new batch request with the given prompt
    list             - List all batch requests
    read <batch_id>  - Read the results of a batch request
"""

import argparse
import json
import os
import sys
import tempfile
import uuid
from datetime import datetime
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    print("Error: openai package not installed. Run: pip install openai")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.syntax import Syntax
    from rich import box
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False

# Configuration
MODEL = "gpt-5.2-pro"
DATA_DIR = Path.home() / ".oaibatch"
REQUESTS_FILE = DATA_DIR / "requests.json"

console = Console() if RICH_AVAILABLE else None


def ensure_data_dir():
    """Ensure the data directory exists."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not REQUESTS_FILE.exists():
        REQUESTS_FILE.write_text("[]")


def load_requests():
    """Load saved requests from disk."""
    ensure_data_dir()
    try:
        return json.loads(REQUESTS_FILE.read_text())
    except (json.JSONDecodeError, FileNotFoundError):
        return []


def save_requests(requests):
    """Save requests to disk."""
    ensure_data_dir()
    REQUESTS_FILE.write_text(json.dumps(requests, indent=2))


def get_client():
    """Get OpenAI client."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("Error: OPENAI_API_KEY environment variable not set")
        sys.exit(1)
    return OpenAI(api_key=api_key)


def get_prompt_from_gui():
    """Open a macOS GUI dialog to get prompt input."""
    import subprocess

    script = '''
    tell application "System Events"
        activate
        set dialogResult to display dialog "Enter your prompt:" default answer "" with title "oaibatch" buttons {"Cancel", "OK"} default button "OK"
        return text returned of dialogResult
    end tell
    '''

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            # User cancelled or error
            if "User canceled" in result.stderr:
                print("Cancelled by user.")
                sys.exit(0)
            print(f"Error: {result.stderr}", file=sys.stderr)
            sys.exit(1)
        return result.stdout.strip()
    except FileNotFoundError:
        print("Error: osascript not found. --gui only works on macOS.")
        sys.exit(1)


def create_batch(prompt: str, system_prompt: str = "You are a helpful assistant.", max_tokens: int = 100000):
    """Create a new batch request with the given prompt."""
    client = get_client()

    # Generate a unique custom_id
    custom_id = f"req-{uuid.uuid4().hex[:8]}"

    # Create the batch request structure using Responses API format
    request = {
        "custom_id": custom_id,
        "method": "POST",
        "url": "/v1/responses",
        "body": {
            "model": MODEL,
            "instructions": system_prompt,
            "input": prompt,
            "max_output_tokens": max_tokens
        }
    }

    # Write to temporary JSONL file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        f.write(json.dumps(request) + "\n")
        temp_path = f.name

    try:
        # Upload the file
        if RICH_AVAILABLE:
            console.print("[dim]Uploading batch file...[/dim]")
        else:
            print("Uploading batch file...")

        with open(temp_path, 'rb') as f:
            file_response = client.files.create(file=f, purpose="batch")

        file_id = file_response.id

        # Create the batch
        if RICH_AVAILABLE:
            console.print("[dim]Creating batch job...[/dim]")
        else:
            print("Creating batch job...")

        batch = client.batches.create(
            input_file_id=file_id,
            endpoint="/v1/responses",
            completion_window="24h"
        )

        # Save request info locally
        requests = load_requests()
        request_record = {
            "id": custom_id,
            "batch_id": batch.id,
            "file_id": file_id,
            "prompt": prompt,
            "system_prompt": system_prompt,
            "model": MODEL,
            "max_tokens": max_tokens,
            "status": batch.status,
            "created_at": datetime.now().isoformat(),
            "output_file_id": None,
            "response": None
        }
        requests.append(request_record)
        save_requests(requests)

        # Display result
        if RICH_AVAILABLE:
            console.print(Panel(
                f"[green]Batch created successfully![/green]\n\n"
                f"[bold]Request ID:[/bold] {custom_id}\n"
                f"[bold]Batch ID:[/bold] {batch.id}\n"
                f"[bold]Status:[/bold] {batch.status}\n"
                f"[bold]Model:[/bold] {MODEL}",
                title="Batch Created",
                border_style="green"
            ))
        else:
            print(f"\nBatch created successfully!")
            print(f"  Request ID: {custom_id}")
            print(f"  Batch ID: {batch.id}")
            print(f"  Status: {batch.status}")
            print(f"  Model: {MODEL}")

        return custom_id

    finally:
        # Clean up temp file
        os.unlink(temp_path)


def list_batches():
    """List all batch requests."""
    client = get_client()
    requests = load_requests()

    # Fetch latest status from API
    try:
        api_batches = client.batches.list(limit=100)
        batch_status_map = {b.id: b for b in api_batches.data}
    except Exception as e:
        if RICH_AVAILABLE:
            console.print(f"[yellow]Warning: Could not fetch API status: {e}[/yellow]")
        else:
            print(f"Warning: Could not fetch API status: {e}")
        batch_status_map = {}

    # Update local records with API status
    for req in requests:
        if req["batch_id"] in batch_status_map:
            batch = batch_status_map[req["batch_id"]]
            req["status"] = batch.status
            if batch.output_file_id:
                req["output_file_id"] = batch.output_file_id
            if batch.completed_at:
                req["completed_at"] = batch.completed_at
            if batch.in_progress_at:
                req["in_progress_at"] = batch.in_progress_at
    save_requests(requests)

    if not requests:
        if RICH_AVAILABLE:
            console.print("[dim]No batch requests found.[/dim]")
        else:
            print("No batch requests found.")
        return

    if RICH_AVAILABLE:
        table = Table(title="Batch Requests", box=box.ROUNDED)
        table.add_column("Request ID", style="cyan")
        table.add_column("Batch ID", style="dim")
        table.add_column("Status", style="bold")
        table.add_column("Created", style="dim")
        table.add_column("Completed", style="green")
        table.add_column("Prompt", style="white", max_width=40)

        for req in reversed(requests):
            status = req.get("status", "unknown")
            status_style = {
                "completed": "[green]completed[/green]",
                "in_progress": "[yellow]in_progress[/yellow]",
                "validating": "[blue]validating[/blue]",
                "failed": "[red]failed[/red]",
                "expired": "[red]expired[/red]",
                "cancelled": "[dim]cancelled[/dim]"
            }.get(status, status)

            created = req.get("created_at", "")[:19].replace("T", " ")

            # Format completed_at timestamp
            completed_at = req.get("completed_at")
            if completed_at:
                completed_str = datetime.fromtimestamp(completed_at).strftime("%Y-%m-%d %H:%M:%S")
            else:
                completed_str = "-"

            prompt_preview = req.get("prompt", "")[:40]
            if len(req.get("prompt", "")) > 40:
                prompt_preview += "..."

            table.add_row(
                req["id"],
                req["batch_id"][:20] + "..." if len(req.get("batch_id", "")) > 20 else req.get("batch_id", ""),
                status_style,
                created,
                completed_str,
                prompt_preview
            )

        console.print(table)
    else:
        print("\nBatch Requests:")
        print("-" * 100)
        for req in reversed(requests):
            created = req.get("created_at", "")[:19].replace("T", " ")
            completed_at = req.get("completed_at")
            completed_str = datetime.fromtimestamp(completed_at).strftime("%Y-%m-%d %H:%M:%S") if completed_at else "-"
            print(f"  ID: {req['id']}")
            print(f"  Batch: {req['batch_id']}")
            print(f"  Status: {req.get('status', 'unknown')}")
            print(f"  Model: {req.get('model', MODEL)}")
            print(f"  Created: {created}")
            print(f"  Completed: {completed_str}")
            print(f"  Prompt: {req.get('prompt', '')[:60]}...")
            print("-" * 100)


def read_batch(request_id: str, response_only: bool = False):
    """Read the results of a batch request."""
    client = get_client()
    requests = load_requests()

    # Find the request
    req = None
    for r in requests:
        if r["id"] == request_id or r["batch_id"] == request_id:
            req = r
            break

    if not req:
        if response_only:
            print(f"Error: Request not found: {request_id}", file=sys.stderr)
        elif RICH_AVAILABLE:
            console.print(f"[red]Request not found: {request_id}[/red]")
        else:
            print(f"Error: Request not found: {request_id}")
        return

    # Get latest batch status
    try:
        batch = client.batches.retrieve(req["batch_id"])
        req["status"] = batch.status
        req["output_file_id"] = batch.output_file_id
        if batch.completed_at:
            req["completed_at"] = batch.completed_at
        if batch.in_progress_at:
            req["in_progress_at"] = batch.in_progress_at
        save_requests(requests)
    except Exception as e:
        if not response_only:
            if RICH_AVAILABLE:
                console.print(f"[yellow]Warning: Could not fetch batch status: {e}[/yellow]")
            else:
                print(f"Warning: Could not fetch batch status: {e}")

    # Response-only mode: just output the response and exit
    if response_only:
        # Check for cached response first
        if req.get("response"):
            print(req["response"])
            return

        # If completed, fetch response
        if req["status"] == "completed" and req.get("output_file_id"):
            try:
                content = client.files.content(req["output_file_id"])
                output_text = content.text
                for line in output_text.strip().split("\n"):
                    if line:
                        result = json.loads(line)
                        if result.get("custom_id") == req["id"]:
                            response = result.get("response", {})
                            body = response.get("body", {})
                            output = body.get("output", [])
                            text_content = None
                            for item in output:
                                if item.get("type") == "message":
                                    for c in item.get("content", []):
                                        if c.get("type") == "output_text":
                                            text_content = c.get("text", "")
                                            break
                            if not text_content:
                                output_text = body.get("output_text")
                                if isinstance(output_text, str):
                                    text_content = output_text
                            if text_content:
                                req["response"] = text_content
                                save_requests(requests)
                                print(text_content)
                            return
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"Error: Batch not completed (status: {req['status']})", file=sys.stderr)
            sys.exit(1)
        return

    # Format timestamps
    created_str = req.get('created_at', 'N/A')[:19].replace("T", " ") if req.get('created_at') else 'N/A'
    completed_at = req.get("completed_at")
    completed_str = datetime.fromtimestamp(completed_at).strftime("%Y-%m-%d %H:%M:%S") if completed_at else "N/A"

    # Display request info
    if RICH_AVAILABLE:
        console.print(Panel(
            f"[bold]Request ID:[/bold] {req['id']}\n"
            f"[bold]Batch ID:[/bold] {req['batch_id']}\n"
            f"[bold]Status:[/bold] {req['status']}\n"
            f"[bold]Model:[/bold] {req.get('model', MODEL)}\n"
            f"[bold]Created:[/bold] {created_str}\n"
            f"[bold]Completed:[/bold] {completed_str}\n\n"
            f"[bold]System Prompt:[/bold]\n{req.get('system_prompt', 'N/A')}\n\n"
            f"[bold]User Prompt:[/bold]\n{req.get('prompt', 'N/A')}",
            title="Request Details",
            border_style="blue"
        ))
    else:
        print(f"\nRequest Details:")
        print(f"  Request ID: {req['id']}")
        print(f"  Batch ID: {req['batch_id']}")
        print(f"  Status: {req['status']}")
        print(f"  Model: {req.get('model', MODEL)}")
        print(f"  Created: {created_str}")
        print(f"  Completed: {completed_str}")
        print(f"\n  System Prompt: {req.get('system_prompt', 'N/A')}")
        print(f"\n  User Prompt: {req.get('prompt', 'N/A')}")

    # If completed, fetch and display response
    if req["status"] == "completed" and req.get("output_file_id"):
        try:
            if RICH_AVAILABLE:
                console.print("\n[dim]Fetching response...[/dim]")
            else:
                print("\nFetching response...")

            content = client.files.content(req["output_file_id"])
            output_text = content.text

            # Parse the JSONL response
            for line in output_text.strip().split("\n"):
                if line:
                    result = json.loads(line)
                    if result.get("custom_id") == req["id"]:
                        response = result.get("response", {})
                        body = response.get("body", {})

                        # Handle Responses API format
                        output = body.get("output", [])
                        content = None

                        # Extract text from output array
                        for item in output:
                            if item.get("type") == "message":
                                for c in item.get("content", []):
                                    if c.get("type") == "output_text":
                                        content = c.get("text", "")
                                        break

                        # Fallback: try direct output_text field (must be string)
                        if not content:
                            output_text = body.get("output_text")
                            if isinstance(output_text, str):
                                content = output_text

                        # Last resort: stringify the body for debugging
                        if not content:
                            content = json.dumps(body, indent=2)

                        # Save response locally
                        req["response"] = content
                        save_requests(requests)

                        if RICH_AVAILABLE:
                            console.print(Panel(
                                content,
                                title="Response",
                                border_style="green"
                            ))

                            # Show usage stats
                            usage = body.get("usage", {})
                            if usage:
                                input_tokens = usage.get('input_tokens', 0)
                                output_tokens = usage.get('output_tokens', 0)
                                total = usage.get('total_tokens', input_tokens + output_tokens)
                                console.print(f"\n[dim]Tokens: {input_tokens} input + {output_tokens} output = {total} total[/dim]")
                        else:
                            print(f"\nResponse:\n{content}")
                            usage = body.get("usage", {})
                            if usage:
                                input_tokens = usage.get('input_tokens', 0)
                                output_tokens = usage.get('output_tokens', 0)
                                total = usage.get('total_tokens', input_tokens + output_tokens)
                                print(f"\nTokens: {input_tokens} input + {output_tokens} output = {total} total")

                        error = result.get("error")
                        if error:
                            if RICH_AVAILABLE:
                                console.print(f"[red]Error: {error}[/red]")
                            else:
                                print(f"Error: {error}")
                        break

        except Exception as e:
            if RICH_AVAILABLE:
                console.print(f"[red]Error fetching response: {e}[/red]")
            else:
                print(f"Error fetching response: {e}")
    elif req["status"] == "completed" and req.get("response"):
        # Show cached response
        if RICH_AVAILABLE:
            console.print(Panel(
                req["response"],
                title="Response (cached)",
                border_style="green"
            ))
        else:
            print(f"\nResponse (cached):\n{req['response']}")
    elif req["status"] in ["validating", "in_progress", "finalizing"]:
        if RICH_AVAILABLE:
            console.print(f"\n[yellow]Batch is still processing. Status: {req['status']}[/yellow]")
            console.print("[dim]Run 'oaibatch read' again later to check for results.[/dim]")
        else:
            print(f"\nBatch is still processing. Status: {req['status']}")
            print("Run 'oaibatch read' again later to check for results.")
    elif req["status"] in ["failed", "expired", "cancelled"]:
        if RICH_AVAILABLE:
            console.print(f"\n[red]Batch {req['status']}. No results available.[/red]")
        else:
            print(f"\nBatch {req['status']}. No results available.")


def main():
    parser = argparse.ArgumentParser(
        description="OpenAI Batch API CLI Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  oaibatch create "Hello world!"
  oaibatch create "Explain quantum computing" --system "You are a physics professor"
  oaibatch list
  oaibatch read req-abc12345
  oaibatch read batch_abc123
        """
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Create command
    create_parser = subparsers.add_parser("create", help="Create a new batch request")
    create_parser.add_argument("prompt", nargs="?", default=None,
                               help="The prompt to send (or read from stdin if not provided)")
    create_parser.add_argument("--system", "-s", default="You are a helpful assistant.",
                               help="System prompt (default: 'You are a helpful assistant.')")
    create_parser.add_argument("--max-tokens", "-m", type=int, default=100000,
                               help="Max output tokens (default: 100000)")
    create_parser.add_argument("--gui", "-g", action="store_true",
                               help="Open a GUI dialog to enter the prompt (macOS)")

    # List command
    subparsers.add_parser("list", help="List all batch requests")

    # Read command
    read_parser = subparsers.add_parser("read", help="Read batch request results")
    read_parser.add_argument("request_id", help="Request ID or Batch ID to read")
    read_parser.add_argument("--response-only", "-r", action="store_true",
                             help="Output only the response text (for piping)")

    subparsers.add_parser("gui", help="Launch the graphical user interface (Tkinter)")

    args = parser.parse_args()

    if args.command == "create":
        prompt = args.prompt
        if args.gui:
            # Get prompt from GUI dialog
            prompt = get_prompt_from_gui()
        elif prompt is None:
            # Read from stdin
            if sys.stdin.isatty():
                print("Error: No prompt provided. Pass a prompt as argument, use --gui, or pipe from stdin.")
                sys.exit(1)
            prompt = sys.stdin.read().strip()
        if not prompt:
            print("Error: Empty prompt.")
            sys.exit(1)
        create_batch(prompt, args.system, args.max_tokens)
    elif args.command == "list":
        list_batches()
    elif args.command == "read":
        read_batch(args.request_id, response_only=args.response_only)
    elif args.command == "gui":
        try:
            from oaibatch_gui import main as gui_main
        except Exception as e:
            print(f"Error: Could not launch GUI: {e}", file=sys.stderr)
            print("Tip: Ensure Tkinter is installed/enabled in your Python environment.", file=sys.stderr)
            sys.exit(1)
        gui_main()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
