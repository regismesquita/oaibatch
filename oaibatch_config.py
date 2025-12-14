#!/usr/bin/env python3
"""
oaibatch_config

Shared configuration utilities for oaibatch CLI and GUI.

Centralizes:
- Supported models and their Batch API token pricing (per 1M tokens)
- Reasoning effort choices
- Helpers for normalizing reasoning settings and estimating cost from usage
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

OAIBATCH_DIR: Path = Path.home() / ".oaibatch"
CONFIG_FILE: Path = OAIBATCH_DIR / "config.json"

@dataclass(frozen=True)
class ModelPricing:
    input_per_1m: float
    output_per_1m: float


# (model, input and output price per million tokens)
MODEL_PRICING: Dict[str, ModelPricing] = {
    "gpt-5.2": ModelPricing(input_per_1m=0.875, output_per_1m=7.00),
    "o3-pro": ModelPricing(input_per_1m=10.00, output_per_1m=40.00),
    "gpt-5.2-pro": ModelPricing(input_per_1m=10.50, output_per_1m=84.00),
}

DEFAULT_MODEL: str = "gpt-5.2-pro"

# Responses API reasoning.effort commonly supports: low/medium/high/xhigh
# We also support "none" to omit the reasoning block entirely.
REASONING_EFFORT_CHOICES = ["none", "low", "medium", "high", "xhigh"]
DEFAULT_REASONING_EFFORT: str = "xhigh"


def normalize_reasoning_effort(effort: Optional[str]) -> Optional[str]:
    """Normalize a user-provided reasoning effort string.

    Returns:
        - None if reasoning should be omitted/disabled
        - normalized effort string (lowercase) otherwise
    """
    if effort is None:
        return None
    value = str(effort).strip().lower()
    if value in ("", "none", "off", "false", "0", "disable", "disabled"):
        return None
    return value


def estimate_cost_from_usage(usage: Dict[str, Any], model: str) -> Optional[Tuple[float, float, float]]:
    """Estimate cost in USD from a Responses API usage object for a given model.

    Returns (input_cost, output_cost, total_cost) or None if pricing is unknown.
    """
    if not usage:
        return None
    pricing = MODEL_PRICING.get(model)
    if not pricing:
        return None

    input_tokens = int(usage.get("input_tokens", 0) or 0)
    output_tokens = int(usage.get("output_tokens", 0) or 0)

    input_cost = (input_tokens / 1_000_000) * pricing.input_per_1m
    output_cost = (output_tokens / 1_000_000) * pricing.output_per_1m
    total_cost = input_cost + output_cost
    return input_cost, output_cost, total_cost

def load_config() -> Dict[str, Any]:
    """Load persistent oaibatch configuration from :data:`CONFIG_FILE`.

    Returns an empty dict if the config file is missing or invalid.
    """
    try:
        raw = CONFIG_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}

    raw = raw.strip()
    if not raw:
        return {}

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}

    return data if isinstance(data, dict) else {}

def save_config(api_key: str) -> None:
    """Save an API key to :data:`CONFIG_FILE`. Overwrites any existing key."""
    key = (api_key or "").strip()
    if not key:
        raise ValueError("API key cannot be empty")

    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)

    tmp_path = CONFIG_FILE.with_suffix(CONFIG_FILE.suffix + ".tmp")
    tmp_path.write_text(json.dumps({"api_key": key}, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp_path, CONFIG_FILE)

    # Best-effort: restrict permissions (ignored on platforms that don't support it)
    try:
        os.chmod(CONFIG_FILE, 0o600)
    except Exception:
        pass

def get_api_key() -> Optional[str]:
    """Resolve an API key from environment or persistent config.

    Precedence:
      1) OPENAI_API_KEY environment variable (CLI override/backward compatibility)
      2) CONFIG_FILE (persistent)
    """
    env_key = os.environ.get("OPENAI_API_KEY")
    if env_key and env_key.strip():
        return env_key.strip()

    cfg = load_config()
    cfg_key = cfg.get("api_key")
    if isinstance(cfg_key, str) and cfg_key.strip():
        return cfg_key.strip()

    return None