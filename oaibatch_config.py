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

from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple


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