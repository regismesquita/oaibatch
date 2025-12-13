#!/usr/bin/env python3
"""
oaibatch_gui - Tkinter GUI for oaibatch

Features:
- Create a batch request (prompt + system prompt + max tokens)
- List/refresh requests with live status from the API
- Read details and fetch/copy responses once completed

Requires:
- OPENAI_API_KEY set in environment
- openai Python package installed
- Tkinter available in the Python build
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
    import tkinter as tk
    from tkinter import ttk, messagebox
    from tkinter.scrolledtext import ScrolledText
except Exception as e:
    raise SystemExit(
        "Tkinter is not available in this Python environment. "
        "Install/enable Tkinter (e.g., python.org macOS installer) and try again.\n"
        f"Underlying error: {e}"
    )

try:
    from openai import OpenAI
except ImportError:
    raise SystemExit("openai package not installed. Run: pip install openai")


MODEL = "gpt-5.2-pro"
DATA_DIR = Path.home() / ".oaibatch"
REQUESTS_FILE = DATA_DIR / "requests.json"


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
    """
    Extract output text from Responses API body.
    Mirrors the extraction logic used by the CLI.
    """
    output = body.get("output", [])
    for item in output:
        if item.get("type") == "message":
            for c in item.get("content", []):
                if c.get("type") == "output_text":
                    return c.get("text", "") or ""

    output_text = body.get("output_text")
    if isinstance(output_text, str):
        return output_text

    # Last resort (debug-friendly)
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
    """
    Returns (updated_request_record, response_text).
    Raises if not completed or cannot fetch.
    """
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

    # Refresh single batch status
    batch = client.batches.retrieve(req["batch_id"])
    req["status"] = getattr(batch, "status", req.get("status", "unknown"))
    req["output_file_id"] = getattr(batch, "output_file_id", req.get("output_file_id"))
    if getattr(batch, "completed_at", None):
        req["completed_at"] = batch.completed_at
    if getattr(batch, "in_progress_at", None):
        req["in_progress_at"] = batch.in_progress_at

    # Cached response
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
    for line in output_text.strip().split("\n"):
        if not line.strip():
            continue
        result = json.loads(line)
        if result.get("custom_id") != req.get("id"):
            continue
        response = result.get("response", {})
        body = response.get("body", {})
        response_text = _extract_text_from_responses_api_body(body)
        break

    if response_text is None:
        raise RuntimeError("Could not locate this request's response in the output JSONL")

    req["response"] = response_text
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


class OaiBatchGUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("oaibatch GUI")
        self.root.geometry("1050x720")

        self._build_ui()

    def _build_ui(self) -> None:
        # Top bar
        top = ttk.Frame(self.root)
        top.pack(fill="x", padx=10, pady=(10, 6))

        self.status_var = tk.StringVar(value="Ready.")
        status_lbl = ttk.Label(top, textvariable=self.status_var)
        status_lbl.pack(side="left")

        help_btn = ttk.Button(top, text="API Key Help", command=self._show_api_help)
        help_btn.pack(side="right")

        # Notebook
        self.nb = ttk.Notebook(self.root)
        self.nb.pack(fill="both", expand=True, padx=10, pady=(0, 10))

        self._build_create_tab()
        self._build_requests_tab()
        self._build_read_tab()

        # Initial load
        self._populate_requests_table(load_requests())

    def _show_api_help(self) -> None:
        messagebox.showinfo(
            "OPENAI_API_KEY",
            "This app uses the OpenAI API.\n\n"
            "Set your API key in the environment before launching:\n"
            "  export OPENAI_API_KEY=\"your-key-here\"\n\n"
            "Then run:\n"
            "  ./oaibatch gui\n",
        )

    def _set_busy(self, busy: bool, msg: str = "") -> None:
        if msg:
            self.status_var.set(msg)
        # Disable/enable primary buttons
        state = "disabled" if busy else "normal"
        for btn in [self.create_btn, self.refresh_btn, self.load_btn, self.fetch_btn, self.copy_btn]:
            try:
                btn.configure(state=state)
            except Exception:
                pass

    def _run_bg(self, fn, on_ok, on_err, busy_msg: str) -> None:
        self._set_busy(True, busy_msg)

        def worker():
            try:
                res = fn()
            except Exception as e:
                self.root.after(0, lambda: self._on_bg_err(e, on_err))
            else:
                self.root.after(0, lambda: self._on_bg_ok(res, on_ok))

        threading.Thread(target=worker, daemon=True).start()

    def _on_bg_ok(self, res, on_ok) -> None:
        self._set_busy(False, "Ready.")
        on_ok(res)

    def _on_bg_err(self, err: Exception, on_err) -> None:
        self._set_busy(False, "Ready.")
        on_err(err)

    # -----------------------
    # Create tab
    # -----------------------
    def _build_create_tab(self) -> None:
        tab = ttk.Frame(self.nb)
        self.nb.add(tab, text="Create")

        frm = ttk.Frame(tab)
        frm.pack(fill="both", expand=True, padx=10, pady=10)

        # System prompt
        sys_row = ttk.Frame(frm)
        sys_row.pack(fill="x")
        ttk.Label(sys_row, text="System prompt:").pack(side="left")
        self.system_entry = ttk.Entry(sys_row)
        self.system_entry.insert(0, "You are a helpful assistant.")
        self.system_entry.pack(side="left", fill="x", expand=True, padx=(8, 0))

        # Max tokens
        mt_row = ttk.Frame(frm)
        mt_row.pack(fill="x", pady=(8, 0))
        ttk.Label(mt_row, text="Max output tokens:").pack(side="left")
        self.max_tokens_entry = ttk.Entry(mt_row, width=12)
        self.max_tokens_entry.insert(0, "100000")
        self.max_tokens_entry.pack(side="left", padx=(8, 0))
        ttk.Label(mt_row, text=f"Model: {MODEL}").pack(side="left", padx=(14, 0))

        # Prompt
        ttk.Label(frm, text="User prompt:").pack(anchor="w", pady=(12, 0))
        self.prompt_text = ScrolledText(frm, wrap="word", height=18)
        self.prompt_text.pack(fill="both", expand=True, pady=(6, 0))

        # Controls
        ctrl = ttk.Frame(frm)
        ctrl.pack(fill="x", pady=(10, 0))
        self.create_btn = ttk.Button(ctrl, text="Create Batch Request", command=self._on_create)
        self.create_btn.pack(side="left")

        self.create_result_var = tk.StringVar(value="")
        ttk.Label(ctrl, textvariable=self.create_result_var).pack(side="left", padx=(10, 0))

    def _on_create(self) -> None:
        prompt = self.prompt_text.get("1.0", "end").strip()
        system = self.system_entry.get().strip() or "You are a helpful assistant."
        mt_raw = self.max_tokens_entry.get().strip()

        if not prompt:
            messagebox.showerror("Validation error", "Prompt cannot be empty.")
            return

        try:
            max_tokens = int(mt_raw)
            if max_tokens <= 0:
                raise ValueError()
        except Exception:
            messagebox.showerror("Validation error", "Max output tokens must be a positive integer.")
            return

        def fn():
            return create_batch_request(prompt=prompt, system_prompt=system, max_tokens=max_tokens)

        def ok(record: Dict[str, Any]):
            self.create_result_var.set(f"Created: {record['id']} (batch {record['batch_id']})")
            # Refresh list and jump to Requests
            self._populate_requests_table(load_requests())
            self.nb.select(self.requests_tab)

        def err(e: Exception):
            messagebox.showerror("Create failed", str(e))

        self._run_bg(fn, ok, err, "Creating batch request...")

    # -----------------------
    # Requests tab
    # -----------------------
    def _build_requests_tab(self) -> None:
        tab = ttk.Frame(self.nb)
        self.requests_tab = tab
        self.nb.add(tab, text="Requests")

        outer = ttk.Frame(tab)
        outer.pack(fill="both", expand=True, padx=10, pady=10)

        toolbar = ttk.Frame(outer)
        toolbar.pack(fill="x", pady=(0, 8))

        self.refresh_btn = ttk.Button(toolbar, text="Refresh Statuses", command=self._on_refresh)
        self.refresh_btn.pack(side="left")

        open_btn = ttk.Button(toolbar, text="Open Selected in Read tab", command=self._open_selected_in_read)
        open_btn.pack(side="left", padx=(8, 0))

        # Table
        cols = ("id", "batch_id", "status", "created", "completed", "prompt")
        self.tree = ttk.Treeview(outer, columns=cols, show="headings", height=16)
        self.tree.heading("id", text="Request ID")
        self.tree.heading("batch_id", text="Batch ID")
        self.tree.heading("status", text="Status")
        self.tree.heading("created", text="Created")
        self.tree.heading("completed", text="Completed")
        self.tree.heading("prompt", text="Prompt")

        self.tree.column("id", width=120, stretch=False)
        self.tree.column("batch_id", width=200, stretch=False)
        self.tree.column("status", width=110, stretch=False)
        self.tree.column("created", width=150, stretch=False)
        self.tree.column("completed", width=150, stretch=False)
        self.tree.column("prompt", width=380, stretch=True)

        yscroll = ttk.Scrollbar(outer, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=yscroll.set)
        self.tree.pack(side="left", fill="both", expand=True)
        yscroll.pack(side="right", fill="y")

        self.tree.bind("<Double-1>", lambda _e: self._open_selected_in_read())

        # Bottom note
        ttk.Label(
            tab,
            text=f"Stored locally in {REQUESTS_FILE}. Refresh pulls latest statuses from the API.",
            foreground="#444",
        ).pack(anchor="w", padx=10, pady=(0, 10))

    def _populate_requests_table(self, requests: List[Dict[str, Any]]) -> None:
        # Clear existing
        for iid in self.tree.get_children():
            self.tree.delete(iid)

        # Newest first
        for req in reversed(requests):
            prompt = req.get("prompt", "") or ""
            preview = (prompt[:80] + "...") if len(prompt) > 80 else prompt

            batch_id = req.get("batch_id", "") or ""
            batch_disp = (batch_id[:20] + "...") if len(batch_id) > 23 else batch_id

            self.tree.insert(
                "",
                "end",
                values=(
                    req.get("id", ""),
                    batch_disp,
                    req.get("status", "unknown"),
                    _fmt_created(req),
                    _fmt_completed(req),
                    preview.replace("\n", " "),
                ),
            )

    def _on_refresh(self) -> None:
        def fn():
            return refresh_statuses()

        def ok(requests: List[Dict[str, Any]]):
            self._populate_requests_table(requests)

        def err(e: Exception):
            messagebox.showerror("Refresh failed", str(e))

        self._run_bg(fn, ok, err, "Refreshing statuses...")

    def _get_selected_request_id(self) -> Optional[str]:
        sel = self.tree.selection()
        if not sel:
            return None
        values = self.tree.item(sel[0], "values")
        if not values:
            return None
        return values[0]  # request id

    def _open_selected_in_read(self) -> None:
        rid = self._get_selected_request_id()
        if not rid:
            messagebox.showinfo("Select a request", "Select a request row first.")
            return
        self.read_id_entry.delete(0, "end")
        self.read_id_entry.insert(0, rid)
        self._load_details_local()
        self.nb.select(self.read_tab)

    # -----------------------
    # Read tab
    # -----------------------
    def _build_read_tab(self) -> None:
        tab = ttk.Frame(self.nb)
        self.read_tab = tab
        self.nb.add(tab, text="Read / Response")

        outer = ttk.Frame(tab)
        outer.pack(fill="both", expand=True, padx=10, pady=10)

        top = ttk.Frame(outer)
        top.pack(fill="x")

        ttk.Label(top, text="Request ID or Batch ID:").pack(side="left")
        self.read_id_entry = ttk.Entry(top, width=36)
        self.read_id_entry.pack(side="left", padx=(8, 0))

        self.load_btn = ttk.Button(top, text="Load Details", command=self._load_details_local)
        self.load_btn.pack(side="left", padx=(8, 0))

        self.fetch_btn = ttk.Button(top, text="Fetch Response (if completed)", command=self._on_fetch_response)
        self.fetch_btn.pack(side="left", padx=(8, 0))

        self.copy_btn = ttk.Button(top, text="Copy Response", command=self._copy_response)
        self.copy_btn.pack(side="left", padx=(8, 0))

        # Details
        details = ttk.LabelFrame(outer, text="Details")
        details.pack(fill="x", pady=(10, 0))

        self.details_var = tk.StringVar(value="(load a request to see details)")
        ttk.Label(details, textvariable=self.details_var, justify="left").pack(anchor="w", padx=10, pady=8)

        # Response
        ttk.Label(outer, text="Response:").pack(anchor="w", pady=(10, 0))
        self.response_text = ScrolledText(outer, wrap="word", height=18)
        self.response_text.pack(fill="both", expand=True, pady=(6, 0))

    def _load_details_local(self) -> None:
        rid = self.read_id_entry.get().strip()
        if not rid:
            messagebox.showerror("Validation error", "Enter a request id or batch id.")
            return

        req = find_request(rid)
        if not req:
            self.details_var.set("Request not found in local history. Try Refresh in Requests tab.")
            return

        created = _fmt_created(req)
        completed = _fmt_completed(req)
        self.details_var.set(
            f"Request ID: {req.get('id','')}\n"
            f"Batch ID: {req.get('batch_id','')}\n"
            f"Status: {req.get('status','unknown')}\n"
            f"Model: {req.get('model', MODEL)}\n"
            f"Created: {created}\n"
            f"Completed: {completed}\n"
            f"Output file id: {req.get('output_file_id','-') or '-'}\n"
            f"System prompt: {req.get('system_prompt','')[:200]}{'...' if len(req.get('system_prompt','') or '') > 200 else ''}\n"
            f"User prompt: {req.get('prompt','')[:200]}{'...' if len(req.get('prompt','') or '') > 200 else ''}"
        )

        self.response_text.delete("1.0", "end")
        if req.get("response"):
            self.response_text.insert("1.0", req["response"])

    def _on_fetch_response(self) -> None:
        rid = self.read_id_entry.get().strip()
        if not rid:
            messagebox.showerror("Validation error", "Enter a request id or batch id.")
            return

        def fn():
            return fetch_response_for_request(rid)

        def ok(result: Tuple[Dict[str, Any], str]):
            req, text = result
            self._load_details_local()
            self.response_text.delete("1.0", "end")
            self.response_text.insert("1.0", text)
            # Also refresh list tab view (status/complete time etc.)
            self._populate_requests_table(load_requests())

        def err(e: Exception):
            messagebox.showerror("Fetch failed", str(e))
            # Still update local details to show latest status if possible
            self._load_details_local()

        self._run_bg(fn, ok, err, "Fetching response...")

    def _copy_response(self) -> None:
        text = self.response_text.get("1.0", "end").strip()
        if not text:
            messagebox.showinfo("Nothing to copy", "Response is empty.")
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.status_var.set("Copied response to clipboard.")


def main() -> None:
    root = tk.Tk()
    # Use a themed look where available
    try:
        style = ttk.Style()
        if "clam" in style.theme_names():
            style.theme_use("clam")
    except Exception:
        pass

    app = OaiBatchGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()