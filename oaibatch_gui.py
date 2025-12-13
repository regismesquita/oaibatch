#!/usr/bin/env python3
"""
oaibatch_gui - Modern GUI for oaibatch

A sleek, dark-themed interface for OpenAI Batch API operations.

Features:
- Create batch requests with custom prompts and settings
- Monitor request statuses with live refresh
- Fetch and copy responses with one click

Requires:
- OPENAI_API_KEY set in environment
- openai, customtkinter packages installed
"""

from __future__ import annotations

import json
import os
import tempfile
import threading
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import customtkinter as ctk
    from customtkinter import CTkFont
except ImportError:
    raise SystemExit(
        "customtkinter is not installed.\n"
        "Run: pip install customtkinter\n"
    )

try:
    from openai import OpenAI
except ImportError:
    raise SystemExit("openai package not installed. Run: pip install openai")


# ═══════════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════════

MODEL = "gpt-5.2-pro"
DATA_DIR = Path.home() / ".oaibatch"
REQUESTS_FILE = DATA_DIR / "requests.json"

# Color Palette - Refined dark theme with cyan accent
COLORS = {
    "bg_dark": "#0d1117",
    "bg_card": "#161b22",
    "bg_input": "#21262d",
    "bg_hover": "#30363d",
    "border": "#30363d",
    "border_focus": "#58a6ff",
    "text_primary": "#f0f6fc",
    "text_secondary": "#8b949e",
    "text_muted": "#6e7681",
    "accent": "#58a6ff",
    "accent_hover": "#79c0ff",
    "success": "#3fb950",
    "warning": "#d29922",
    "error": "#f85149",
    "pending": "#8b949e",
}

# Status color mapping
STATUS_COLORS = {
    "completed": COLORS["success"],
    "in_progress": COLORS["warning"],
    "validating": COLORS["accent"],
    "finalizing": COLORS["accent"],
    "failed": COLORS["error"],
    "expired": COLORS["error"],
    "cancelled": COLORS["text_muted"],
}


# ═══════════════════════════════════════════════════════════════════════════════
# Data Layer
# ═══════════════════════════════════════════════════════════════════════════════

def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not REQUESTS_FILE.exists():
        REQUESTS_FILE.write_text("[]", encoding="utf-8")


def load_requests() -> List[Dict[str, Any]]:
    ensure_data_dir()
    try:
        return json.loads(REQUESTS_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, FileNotFoundError):
        return []


def save_requests(requests: List[Dict[str, Any]]) -> None:
    ensure_data_dir()
    REQUESTS_FILE.write_text(json.dumps(requests, indent=2), encoding="utf-8")


def get_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY environment variable not set")
    return OpenAI(api_key=api_key)


def _extract_text_from_responses_api_body(body: Dict[str, Any]) -> str:
    output = body.get("output", [])
    for item in output:
        if item.get("type") == "message":
            for c in item.get("content", []):
                if c.get("type") == "output_text":
                    return c.get("text", "") or ""
    output_text = body.get("output_text")
    if isinstance(output_text, str):
        return output_text
    return json.dumps(body, indent=2)


def create_batch_request(prompt: str, system_prompt: str, max_tokens: int) -> Dict[str, Any]:
    client = get_client()
    custom_id = f"req-{uuid.uuid4().hex[:8]}"
    request = {
        "custom_id": custom_id,
        "method": "POST",
        "url": "/v1/responses",
        "body": {
            "model": MODEL,
            "instructions": system_prompt,
            "input": prompt,
            "max_output_tokens": max_tokens,
            "reasoning": {"effort": "xhigh"},
        },
    }

    with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False, encoding="utf-8") as f:
        f.write(json.dumps(request) + "\n")
        temp_path = f.name

    try:
        with open(temp_path, "rb") as f:
            file_response = client.files.create(file=f, purpose="batch")
        file_id = file_response.id

        batch = client.batches.create(
            input_file_id=file_id,
            endpoint="/v1/responses",
            completion_window="24h",
        )

        record = {
            "id": custom_id,
            "batch_id": batch.id,
            "file_id": file_id,
            "prompt": prompt,
            "system_prompt": system_prompt,
            "model": MODEL,
            "max_tokens": max_tokens,
            "status": batch.status,
            "created_at": datetime.now().isoformat(),
            "output_file_id": getattr(batch, "output_file_id", None),
            "response": None,
        }

        requests = load_requests()
        requests.append(record)
        save_requests(requests)
        return record
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def refresh_statuses() -> List[Dict[str, Any]]:
    client = get_client()
    requests = load_requests()
    api_batches = client.batches.list(limit=100)
    batch_status_map = {b.id: b for b in api_batches.data}

    for req in requests:
        b = batch_status_map.get(req.get("batch_id"))
        if not b:
            continue
        req["status"] = getattr(b, "status", req.get("status", "unknown"))
        if getattr(b, "output_file_id", None):
            req["output_file_id"] = b.output_file_id
        if getattr(b, "completed_at", None):
            req["completed_at"] = b.completed_at
        if getattr(b, "in_progress_at", None):
            req["in_progress_at"] = b.in_progress_at

    save_requests(requests)
    return requests


def find_request(request_id_or_batch_id: str) -> Optional[Dict[str, Any]]:
    requests = load_requests()
    for r in requests:
        if r.get("id") == request_id_or_batch_id or r.get("batch_id") == request_id_or_batch_id:
            return r
    return None


def fetch_response_for_request(request_id_or_batch_id: str) -> Tuple[Dict[str, Any], str]:
    client = get_client()
    requests = load_requests()

    req = None
    idx = -1
    for i, r in enumerate(requests):
        if r.get("id") == request_id_or_batch_id or r.get("batch_id") == request_id_or_batch_id:
            req = r
            idx = i
            break
    if not req:
        raise KeyError(f"Request not found: {request_id_or_batch_id}")

    batch = client.batches.retrieve(req["batch_id"])
    req["status"] = getattr(batch, "status", req.get("status", "unknown"))
    req["output_file_id"] = getattr(batch, "output_file_id", req.get("output_file_id"))
    if getattr(batch, "completed_at", None):
        req["completed_at"] = batch.completed_at
    if getattr(batch, "in_progress_at", None):
        req["in_progress_at"] = batch.in_progress_at

    if req.get("response"):
        requests[idx] = req
        save_requests(requests)
        return req, req["response"]

    if req.get("status") != "completed":
        raise RuntimeError(f"Batch not completed (status: {req.get('status')})")

    if not req.get("output_file_id"):
        raise RuntimeError("Batch completed but no output_file_id was provided")

    content = client.files.content(req["output_file_id"])
    output_text = content.text or ""

    response_text: Optional[str] = None
    usage_data: Optional[Dict[str, Any]] = None
    for line in output_text.strip().split("\n"):
        if not line.strip():
            continue
        result = json.loads(line)
        if result.get("custom_id") != req.get("id"):
            continue
        response = result.get("response", {})
        body = response.get("body", {})
        response_text = _extract_text_from_responses_api_body(body)
        usage_data = body.get("usage", {})
        break

    if response_text is None:
        raise RuntimeError("Could not locate this request's response in the output JSONL")

    req["response"] = response_text
    if usage_data:
        req["usage"] = usage_data
    requests[idx] = req
    save_requests(requests)
    return req, response_text


def _fmt_created(req: Dict[str, Any]) -> str:
    created = (req.get("created_at") or "")[:19].replace("T", " ")
    return created or "-"


def _fmt_completed(req: Dict[str, Any]) -> str:
    completed_at = req.get("completed_at")
    if completed_at:
        try:
            return datetime.fromtimestamp(completed_at).strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            return str(completed_at)
    return "-"


def _fmt_usage(req: Dict[str, Any]) -> str:
    """Format token usage and estimated cost."""
    usage = req.get("usage", {})
    if not usage:
        return "-"

    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    total_tokens = usage.get("total_tokens", input_tokens + output_tokens)

    # Batch API pricing for gpt-5.2-pro (per million tokens)
    INPUT_COST_PER_1M = 10.50
    OUTPUT_COST_PER_1M = 84.00

    input_cost = (input_tokens / 1_000_000) * INPUT_COST_PER_1M
    output_cost = (output_tokens / 1_000_000) * OUTPUT_COST_PER_1M
    total_cost = input_cost + output_cost

    return f"{input_tokens:,} in + {output_tokens:,} out = {total_tokens:,} tokens (${total_cost:.2f})"


# ═══════════════════════════════════════════════════════════════════════════════
# Custom Widgets
# ═══════════════════════════════════════════════════════════════════════════════

class StatusBadge(ctk.CTkFrame):
    """A pill-shaped status badge with colored background."""

    def __init__(self, master, status: str = "unknown", **kwargs):
        color = STATUS_COLORS.get(status, COLORS["text_muted"])
        super().__init__(
            master,
            fg_color=color,
            corner_radius=12,
            height=24,
            **kwargs
        )

        self.label = ctk.CTkLabel(
            self,
            text=status.upper(),
            font=CTkFont(size=10, weight="bold"),
            text_color=COLORS["bg_dark"],
            padx=10,
            pady=2,
        )
        self.label.pack()

    def set_status(self, status: str):
        color = STATUS_COLORS.get(status, COLORS["text_muted"])
        self.configure(fg_color=color)
        self.label.configure(text=status.upper())


class RequestCard(ctk.CTkFrame):
    """A card displaying a single request with hover effects."""

    def __init__(self, master, req: Dict[str, Any], on_click=None, **kwargs):
        super().__init__(
            master,
            fg_color=COLORS["bg_card"],
            corner_radius=12,
            border_width=1,
            border_color=COLORS["border"],
            **kwargs
        )

        self.req = req
        self.on_click = on_click

        # Hover effects
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<Button-1>", self._on_click)

        # Content container
        content = ctk.CTkFrame(self, fg_color="transparent")
        content.pack(fill="both", expand=True, padx=16, pady=12)
        content.bind("<Button-1>", self._on_click)

        # Top row: ID and Status
        top_row = ctk.CTkFrame(content, fg_color="transparent")
        top_row.pack(fill="x")
        top_row.bind("<Button-1>", self._on_click)

        id_label = ctk.CTkLabel(
            top_row,
            text=req.get("id", "unknown"),
            font=CTkFont(family="SF Mono, Menlo, Monaco, monospace", size=14, weight="bold"),
            text_color=COLORS["accent"],
            anchor="w",
        )
        id_label.pack(side="left")
        id_label.bind("<Button-1>", self._on_click)

        self.status_badge = StatusBadge(top_row, req.get("status", "unknown"))
        self.status_badge.pack(side="right")

        # Batch ID (truncated)
        batch_id = req.get("batch_id", "")
        batch_display = batch_id[:30] + "..." if len(batch_id) > 30 else batch_id
        batch_label = ctk.CTkLabel(
            content,
            text=batch_display,
            font=CTkFont(size=11),
            text_color=COLORS["text_muted"],
            anchor="w",
        )
        batch_label.pack(fill="x", pady=(4, 8))
        batch_label.bind("<Button-1>", self._on_click)

        # Prompt preview
        prompt = req.get("prompt", "")
        preview = (prompt[:120] + "...") if len(prompt) > 120 else prompt
        preview = preview.replace("\n", " ")

        prompt_label = ctk.CTkLabel(
            content,
            text=preview,
            font=CTkFont(size=12),
            text_color=COLORS["text_secondary"],
            anchor="w",
            justify="left",
            wraplength=400,
        )
        prompt_label.pack(fill="x")
        prompt_label.bind("<Button-1>", self._on_click)

        # Bottom row: timestamps
        bottom_row = ctk.CTkFrame(content, fg_color="transparent")
        bottom_row.pack(fill="x", pady=(10, 0))
        bottom_row.bind("<Button-1>", self._on_click)

        created_label = ctk.CTkLabel(
            bottom_row,
            text=f"Created: {_fmt_created(req)}",
            font=CTkFont(size=10),
            text_color=COLORS["text_muted"],
        )
        created_label.pack(side="left")
        created_label.bind("<Button-1>", self._on_click)

        completed = _fmt_completed(req)
        if completed != "-":
            completed_label = ctk.CTkLabel(
                bottom_row,
                text=f"Completed: {completed}",
                font=CTkFont(size=10),
                text_color=COLORS["success"],
            )
            completed_label.pack(side="right")
            completed_label.bind("<Button-1>", self._on_click)

    def _on_enter(self, event):
        self.configure(border_color=COLORS["accent"])

    def _on_leave(self, event):
        self.configure(border_color=COLORS["border"])

    def _on_click(self, event):
        if self.on_click:
            self.on_click(self.req)


class GlowButton(ctk.CTkButton):
    """A button with a subtle glow effect on hover."""

    def __init__(self, master, **kwargs):
        # Set defaults for our style
        kwargs.setdefault("corner_radius", 8)
        kwargs.setdefault("height", 40)
        kwargs.setdefault("font", CTkFont(size=13, weight="bold"))
        kwargs.setdefault("fg_color", COLORS["accent"])
        kwargs.setdefault("hover_color", COLORS["accent_hover"])
        kwargs.setdefault("text_color", COLORS["bg_dark"])
        super().__init__(master, **kwargs)


class SecondaryButton(ctk.CTkButton):
    """A secondary/ghost button style."""

    def __init__(self, master, **kwargs):
        kwargs.setdefault("corner_radius", 8)
        kwargs.setdefault("height", 40)
        kwargs.setdefault("font", CTkFont(size=13))
        kwargs.setdefault("fg_color", "transparent")
        kwargs.setdefault("border_width", 1)
        kwargs.setdefault("border_color", COLORS["border"])
        kwargs.setdefault("hover_color", COLORS["bg_hover"])
        kwargs.setdefault("text_color", COLORS["text_primary"])
        super().__init__(master, **kwargs)


# ═══════════════════════════════════════════════════════════════════════════════
# Main Application
# ═══════════════════════════════════════════════════════════════════════════════

class OaiBatchGUI(ctk.CTk):
    def __init__(self):
        super().__init__()

        # Window setup
        self.title("oaibatch")
        self.geometry("1100x750")
        self.configure(fg_color=COLORS["bg_dark"])

        # Configure grid
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        self._build_sidebar()
        self._build_main_area()

        # Initial view
        self._show_create_view()
        self._load_requests()

    def _build_sidebar(self):
        """Build the navigation sidebar."""
        sidebar = ctk.CTkFrame(
            self,
            fg_color=COLORS["bg_card"],
            corner_radius=0,
            width=220,
        )
        sidebar.grid(row=0, column=0, sticky="nsw")
        sidebar.grid_propagate(False)

        # Logo/Title
        logo_frame = ctk.CTkFrame(sidebar, fg_color="transparent")
        logo_frame.pack(fill="x", padx=20, pady=(24, 8))

        title = ctk.CTkLabel(
            logo_frame,
            text="oaibatch",
            font=CTkFont(size=24, weight="bold"),
            text_color=COLORS["text_primary"],
        )
        title.pack(anchor="w")

        subtitle = ctk.CTkLabel(
            logo_frame,
            text="OpenAI Batch API",
            font=CTkFont(size=12),
            text_color=COLORS["text_muted"],
        )
        subtitle.pack(anchor="w")

        # Divider
        divider = ctk.CTkFrame(sidebar, fg_color=COLORS["border"], height=1)
        divider.pack(fill="x", padx=16, pady=16)

        # Navigation buttons
        nav_frame = ctk.CTkFrame(sidebar, fg_color="transparent")
        nav_frame.pack(fill="x", padx=12)

        self.nav_buttons = {}
        nav_items = [
            ("create", "✦  New Request", self._show_create_view),
            ("requests", "◉  Requests", self._show_requests_view),
            ("response", "◈  Response", self._show_response_view),
        ]

        for key, text, command in nav_items:
            btn = ctk.CTkButton(
                nav_frame,
                text=text,
                font=CTkFont(size=14),
                fg_color="transparent",
                hover_color=COLORS["bg_hover"],
                text_color=COLORS["text_secondary"],
                anchor="w",
                height=44,
                corner_radius=8,
                command=command,
            )
            btn.pack(fill="x", pady=2)
            self.nav_buttons[key] = btn

        # Spacer
        spacer = ctk.CTkFrame(sidebar, fg_color="transparent")
        spacer.pack(fill="both", expand=True)

        # Model info at bottom
        info_frame = ctk.CTkFrame(sidebar, fg_color=COLORS["bg_input"], corner_radius=8)
        info_frame.pack(fill="x", padx=16, pady=(0, 20))

        model_label = ctk.CTkLabel(
            info_frame,
            text=f"Model: {MODEL}",
            font=CTkFont(size=11),
            text_color=COLORS["text_muted"],
        )
        model_label.pack(padx=12, pady=8)

    def _set_active_nav(self, key: str):
        """Update navigation button states."""
        for nav_key, btn in self.nav_buttons.items():
            if nav_key == key:
                btn.configure(
                    fg_color=COLORS["bg_hover"],
                    text_color=COLORS["text_primary"],
                )
            else:
                btn.configure(
                    fg_color="transparent",
                    text_color=COLORS["text_secondary"],
                )

    def _build_main_area(self):
        """Build the main content area."""
        self.main_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=24, pady=24)
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(1, weight=1)

        # Status bar
        self.status_var = ctk.StringVar(value="Ready")
        self.status_label = ctk.CTkLabel(
            self.main_frame,
            textvariable=self.status_var,
            font=CTkFont(size=12),
            text_color=COLORS["text_muted"],
        )
        self.status_label.grid(row=2, column=0, sticky="w", pady=(16, 0))

        # Content container (will hold different views)
        self.content_frame = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        self.content_frame.grid(row=1, column=0, sticky="nsew")
        self.content_frame.grid_columnconfigure(0, weight=1)
        self.content_frame.grid_rowconfigure(0, weight=1)

    def _clear_content(self):
        """Clear the content frame."""
        for widget in self.content_frame.winfo_children():
            widget.destroy()

    # ═══════════════════════════════════════════════════════════════════════════
    # Create View
    # ═══════════════════════════════════════════════════════════════════════════

    def _show_create_view(self):
        """Show the create request view."""
        self._set_active_nav("create")
        self._clear_content()

        # Header
        header = ctk.CTkLabel(
            self.content_frame,
            text="New Batch Request",
            font=CTkFont(size=28, weight="bold"),
            text_color=COLORS["text_primary"],
            anchor="w",
        )
        header.pack(fill="x", pady=(0, 24))

        # Form card
        form_card = ctk.CTkFrame(
            self.content_frame,
            fg_color=COLORS["bg_card"],
            corner_radius=16,
            border_width=1,
            border_color=COLORS["border"],
        )
        form_card.pack(fill="both", expand=True)

        form_inner = ctk.CTkFrame(form_card, fg_color="transparent")
        form_inner.pack(fill="both", expand=True, padx=24, pady=24)

        # System prompt
        sys_label = ctk.CTkLabel(
            form_inner,
            text="System Prompt",
            font=CTkFont(size=13, weight="bold"),
            text_color=COLORS["text_secondary"],
            anchor="w",
        )
        sys_label.pack(fill="x")

        self.system_entry = ctk.CTkEntry(
            form_inner,
            placeholder_text="You are a helpful assistant.",
            font=CTkFont(size=14),
            fg_color=COLORS["bg_input"],
            border_color=COLORS["border"],
            text_color=COLORS["text_primary"],
            placeholder_text_color=COLORS["text_muted"],
            height=44,
            corner_radius=8,
        )
        self.system_entry.pack(fill="x", pady=(8, 16))
        self.system_entry.insert(0, "You are a helpful assistant.")

        # Settings row
        settings_row = ctk.CTkFrame(form_inner, fg_color="transparent")
        settings_row.pack(fill="x", pady=(0, 16))

        # Max tokens
        tokens_frame = ctk.CTkFrame(settings_row, fg_color="transparent")
        tokens_frame.pack(side="left")

        tokens_label = ctk.CTkLabel(
            tokens_frame,
            text="Max Output Tokens",
            font=CTkFont(size=13, weight="bold"),
            text_color=COLORS["text_secondary"],
            anchor="w",
        )
        tokens_label.pack(anchor="w")

        self.max_tokens_entry = ctk.CTkEntry(
            tokens_frame,
            width=160,
            font=CTkFont(size=14),
            fg_color=COLORS["bg_input"],
            border_color=COLORS["border"],
            text_color=COLORS["text_primary"],
            height=44,
            corner_radius=8,
        )
        self.max_tokens_entry.pack(pady=(8, 0))
        self.max_tokens_entry.insert(0, "100000")

        # User prompt
        prompt_label = ctk.CTkLabel(
            form_inner,
            text="Your Prompt",
            font=CTkFont(size=13, weight="bold"),
            text_color=COLORS["text_secondary"],
            anchor="w",
        )
        prompt_label.pack(fill="x")

        self.prompt_textbox = ctk.CTkTextbox(
            form_inner,
            font=CTkFont(size=14),
            fg_color=COLORS["bg_input"],
            border_color=COLORS["border"],
            text_color=COLORS["text_primary"],
            corner_radius=8,
            border_width=1,
            height=200,
        )
        self.prompt_textbox.pack(fill="both", expand=True, pady=(8, 20))

        # Submit button
        button_row = ctk.CTkFrame(form_inner, fg_color="transparent")
        button_row.pack(fill="x")

        self.create_btn = GlowButton(
            button_row,
            text="Create Batch Request",
            width=200,
            command=self._on_create,
        )
        self.create_btn.pack(side="left")

        self.create_status = ctk.CTkLabel(
            button_row,
            text="",
            font=CTkFont(size=13),
            text_color=COLORS["success"],
        )
        self.create_status.pack(side="left", padx=(16, 0))

    def _on_create(self):
        """Handle create request."""
        prompt = self.prompt_textbox.get("1.0", "end").strip()
        system = self.system_entry.get().strip() or "You are a helpful assistant."
        mt_raw = self.max_tokens_entry.get().strip()

        if not prompt:
            self.create_status.configure(text="Prompt cannot be empty", text_color=COLORS["error"])
            return

        try:
            max_tokens = int(mt_raw)
            if max_tokens <= 0:
                raise ValueError()
        except ValueError:
            self.create_status.configure(text="Invalid max tokens", text_color=COLORS["error"])
            return

        self._run_async(
            lambda: create_batch_request(prompt, system, max_tokens),
            self._on_create_success,
            self._on_create_error,
            "Creating request..."
        )

    def _on_create_success(self, record: Dict[str, Any]):
        self.create_status.configure(
            text=f"Created: {record['id']}",
            text_color=COLORS["success"]
        )
        self._load_requests()

    def _on_create_error(self, error: Exception):
        self.create_status.configure(
            text=f"Error: {str(error)[:50]}",
            text_color=COLORS["error"]
        )

    # ═══════════════════════════════════════════════════════════════════════════
    # Requests View
    # ═══════════════════════════════════════════════════════════════════════════

    def _show_requests_view(self):
        """Show the requests list view."""
        self._set_active_nav("requests")
        self._clear_content()

        # Header row
        header_row = ctk.CTkFrame(self.content_frame, fg_color="transparent")
        header_row.pack(fill="x", pady=(0, 20))

        header = ctk.CTkLabel(
            header_row,
            text="Batch Requests",
            font=CTkFont(size=28, weight="bold"),
            text_color=COLORS["text_primary"],
            anchor="w",
        )
        header.pack(side="left")

        self.refresh_btn = GlowButton(
            header_row,
            text="↻  Refresh",
            width=120,
            command=self._on_refresh,
        )
        self.refresh_btn.pack(side="right")

        # Scrollable requests container
        self.requests_scroll = ctk.CTkScrollableFrame(
            self.content_frame,
            fg_color="transparent",
            scrollbar_button_color=COLORS["bg_hover"],
            scrollbar_button_hover_color=COLORS["text_muted"],
        )
        self.requests_scroll.pack(fill="both", expand=True)

        self._populate_requests()

    def _populate_requests(self):
        """Populate the requests list."""
        # Clear existing
        for widget in self.requests_scroll.winfo_children():
            widget.destroy()

        requests = load_requests()

        if not requests:
            empty_label = ctk.CTkLabel(
                self.requests_scroll,
                text="No requests yet.\nCreate your first batch request!",
                font=CTkFont(size=16),
                text_color=COLORS["text_muted"],
            )
            empty_label.pack(pady=60)
            return

        # Show newest first
        for req in reversed(requests):
            card = RequestCard(
                self.requests_scroll,
                req,
                on_click=self._on_request_click,
            )
            card.pack(fill="x", pady=(0, 12))

    def _on_request_click(self, req: Dict[str, Any]):
        """Handle click on a request card."""
        self.selected_request = req
        self._show_response_view()
        self._load_response_details(req)

    def _on_refresh(self):
        """Handle refresh button click."""
        self._run_async(
            refresh_statuses,
            lambda _: self._populate_requests(),
            lambda e: self.status_var.set(f"Error: {e}"),
            "Refreshing..."
        )

    def _load_requests(self):
        """Load requests (used after creating a new one)."""
        if hasattr(self, 'requests_scroll'):
            self._populate_requests()

    # ═══════════════════════════════════════════════════════════════════════════
    # Response View
    # ═══════════════════════════════════════════════════════════════════════════

    def _show_response_view(self):
        """Show the response detail view."""
        self._set_active_nav("response")
        self._clear_content()

        # Header
        header = ctk.CTkLabel(
            self.content_frame,
            text="Response Details",
            font=CTkFont(size=28, weight="bold"),
            text_color=COLORS["text_primary"],
            anchor="w",
        )
        header.pack(fill="x", pady=(0, 20))

        # ID Entry row
        id_row = ctk.CTkFrame(self.content_frame, fg_color="transparent")
        id_row.pack(fill="x", pady=(0, 16))

        self.response_id_entry = ctk.CTkEntry(
            id_row,
            placeholder_text="Enter Request ID or Batch ID...",
            font=CTkFont(size=14),
            fg_color=COLORS["bg_input"],
            border_color=COLORS["border"],
            text_color=COLORS["text_primary"],
            placeholder_text_color=COLORS["text_muted"],
            height=44,
            corner_radius=8,
            width=300,
        )
        self.response_id_entry.pack(side="left")

        self.load_btn = SecondaryButton(
            id_row,
            text="Load",
            width=80,
            command=self._on_load_details,
        )
        self.load_btn.pack(side="left", padx=(12, 0))

        self.fetch_btn = GlowButton(
            id_row,
            text="Fetch Response",
            width=140,
            command=self._on_fetch_response,
        )
        self.fetch_btn.pack(side="left", padx=(12, 0))

        self.copy_btn = SecondaryButton(
            id_row,
            text="Copy",
            width=80,
            command=self._on_copy_response,
        )
        self.copy_btn.pack(side="left", padx=(12, 0))

        # Details card
        details_card = ctk.CTkFrame(
            self.content_frame,
            fg_color=COLORS["bg_card"],
            corner_radius=12,
            border_width=1,
            border_color=COLORS["border"],
        )
        details_card.pack(fill="x", pady=(0, 16))

        self.details_label = ctk.CTkLabel(
            details_card,
            text="Load a request to see details",
            font=CTkFont(size=13),
            text_color=COLORS["text_muted"],
            anchor="w",
            justify="left",
        )
        self.details_label.pack(fill="x", padx=20, pady=16)

        # Response text area
        response_label = ctk.CTkLabel(
            self.content_frame,
            text="Response",
            font=CTkFont(size=14, weight="bold"),
            text_color=COLORS["text_secondary"],
            anchor="w",
        )
        response_label.pack(fill="x", pady=(0, 8))

        self.response_textbox = ctk.CTkTextbox(
            self.content_frame,
            font=CTkFont(family="SF Mono, Menlo, Monaco, monospace", size=13),
            fg_color=COLORS["bg_card"],
            border_color=COLORS["border"],
            text_color=COLORS["text_primary"],
            corner_radius=12,
            border_width=1,
        )
        self.response_textbox.pack(fill="both", expand=True)

        # Load selected request if we have one
        if hasattr(self, 'selected_request'):
            self._load_response_details(self.selected_request)

    def _load_response_details(self, req: Dict[str, Any]):
        """Load details for a request."""
        self.response_id_entry.delete(0, "end")
        self.response_id_entry.insert(0, req.get("id", ""))

        status = req.get("status", "unknown")
        status_color = STATUS_COLORS.get(status, COLORS["text_muted"])

        details_text = (
            f"Request ID: {req.get('id', '-')}\n"
            f"Batch ID: {req.get('batch_id', '-')}\n"
            f"Status: {status.upper()}\n"
            f"Model: {req.get('model', MODEL)}\n"
            f"Created: {_fmt_created(req)}\n"
            f"Completed: {_fmt_completed(req)}\n"
            f"Usage: {_fmt_usage(req)}"
        )
        self.details_label.configure(text=details_text, text_color=COLORS["text_secondary"])

        self.response_textbox.delete("1.0", "end")
        if req.get("response"):
            self.response_textbox.insert("1.0", req["response"])

    def _on_load_details(self):
        """Load details for the entered ID."""
        rid = self.response_id_entry.get().strip()
        if not rid:
            self.status_var.set("Enter a request ID")
            return

        req = find_request(rid)
        if not req:
            self.status_var.set("Request not found")
            return

        self._load_response_details(req)

    def _on_fetch_response(self):
        """Fetch the response from API."""
        rid = self.response_id_entry.get().strip()
        if not rid:
            self.status_var.set("Enter a request ID")
            return

        def on_success(result: Tuple[Dict[str, Any], str]):
            req, text = result
            self._load_response_details(req)
            self.response_textbox.delete("1.0", "end")
            self.response_textbox.insert("1.0", text)

        self._run_async(
            lambda: fetch_response_for_request(rid),
            on_success,
            lambda e: self.status_var.set(f"Error: {e}"),
            "Fetching response..."
        )

    def _on_copy_response(self):
        """Copy response to clipboard."""
        text = self.response_textbox.get("1.0", "end").strip()
        if not text:
            self.status_var.set("No response to copy")
            return

        self.clipboard_clear()
        self.clipboard_append(text)
        self.status_var.set("Copied to clipboard!")

    # ═══════════════════════════════════════════════════════════════════════════
    # Async Helpers
    # ═══════════════════════════════════════════════════════════════════════════

    def _run_async(self, fn, on_success, on_error, busy_msg: str):
        """Run a function asynchronously."""
        self.status_var.set(busy_msg)

        def worker():
            try:
                result = fn()
                self.after(0, lambda: self._async_success(result, on_success))
            except Exception as e:
                self.after(0, lambda: self._async_error(e, on_error))

        threading.Thread(target=worker, daemon=True).start()

    def _async_success(self, result, on_success):
        self.status_var.set("Ready")
        on_success(result)

    def _async_error(self, error: Exception, on_error):
        self.status_var.set("Ready")
        on_error(error)


# ═══════════════════════════════════════════════════════════════════════════════
# Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    # Set appearance mode
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("blue")

    app = OaiBatchGUI()
    app.mainloop()


if __name__ == "__main__":
    main()
