#!/bin/bash

# ─────────────────────────────────────────
# Grok /responses API — Crypto News Scanner
# Usage: ./test_grok.sh
# Requires: XAI_API_KEY env var
# ─────────────────────────────────────────

set -euo pipefail

# Source .env if present
if [ -f .env ]; then
    set -a; source .env; set +a
fi

# ─────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────
export TOKEN_TICKER='$AVICI'
export TOKEN_NAME='AVICI'
export DAYS_BACK=7

# ─────────────────────────────────────────

python3 << 'PYEOF'
import json, os, subprocess, sys
from datetime import datetime, timedelta, timezone

ticker = os.environ.get("TOKEN_TICKER", "$WIF")
name   = os.environ.get("TOKEN_NAME", "dogwifhat")
days   = int(os.environ.get("DAYS_BACK", "7"))

api_key = os.environ.get("XAI_API_KEY", "")
if not api_key:
    print("ERROR: XAI_API_KEY not set", file=sys.stderr)
    sys.exit(1)

to_date   = datetime.now(timezone.utc).strftime("%Y-%m-%d")
from_date = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")

system_prompt = """Scan crypto Twitter for community intel about a given project. Exclude posts from the project's official X account. Team members' personal accounts are fine.

INCLUDE: on-chain findings, partnerships, listings, security alerts, governance, market structure commentary, researcher threads (ZachXBT, Lookonchain, etc.), sentiment shifts.
EXCLUDE: official project account posts, price predictions/targets, engagement farming, influencers just listing the ticker.

RULES:
- Prefix unverified claims with "Rumor:" or "Unverified:"
- Up to 10 items, newest first. Fewer is fine.
- Every item MUST have url (tweet link) and source_url (poster's profile). Skip items without.
- Plain text only in JSON values."""

user_prompt = f"Find crypto twitter news for {ticker} ({name}) from {from_date} to {to_date}."

payload = {
    "model": "grok-4-1-fast-non-reasoning",
    "stream": False,
    "tools": [{"type": "x_search"}],
    "max_turns": 1,
    "input": [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": user_prompt}
    ],
    "text": {
        "format": {
            "type": "json_schema",
            "name": "crypto_news",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "title":  {"type": "string"},
                                "text":   {"type": "string"},
                                "url":    {"type": "string"},
                                "source": {"type": "string"},
                                "source_url": {"type": "string"},
                                "date":   {"type": "string"}
                            },
                            "required": ["title", "text", "url", "source", "source_url", "date"],
                            "additionalProperties": False
                        }
                    }
                },
                "required": ["items"],
                "additionalProperties": False
            }
        }
    }
}

result = subprocess.run(
    ["curl", "-s", "https://api.x.ai/v1/responses",
     "-H", f"Authorization: Bearer {api_key}",
     "-H", "Content-Type: application/json",
     "-d", json.dumps(payload)],
    capture_output=True, text=True, timeout=300
)

if result.returncode != 0:
    print(f"curl failed (exit {result.returncode}): {result.stderr}", file=sys.stderr)
    sys.exit(1)

if not result.stdout.strip():
    print("Empty response from API", file=sys.stderr)
    sys.exit(1)

try:
    resp = json.loads(result.stdout)
except json.JSONDecodeError:
    print("Failed to parse response:", result.stdout, file=sys.stderr)
    sys.exit(1)

if resp.get("error"):
    print(f"API Error: {json.dumps(resp['error'], indent=2)}", file=sys.stderr)
    sys.exit(1)

# Extract the output text
for item in resp.get("output", []):
    if item.get("type") == "message":
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                news = json.loads(content["text"])
                print(json.dumps(news, indent=2))

# Print cost summary
usage = resp.get("usage", {})
tool_details = usage.get("server_side_tool_usage_details", {})
cost_ticks = usage.get("cost_in_usd_ticks", 0)
print(f"\n--- Cost ---")
print(f"Input tokens:   {usage.get('input_tokens', 0):,}")
print(f"Output tokens:  {usage.get('output_tokens', 0):,}")
print(f"X search calls: {tool_details.get('x_search_calls', 0)}")
print(f"Cost:           ${cost_ticks / 10_000_000_000:.4f}")
PYEOF
