#!/bin/bash

# ─────────────────────────────────────────
# Grok /responses API — Crypto News Scanner
# Usage: ./test_grok.sh
# Requires: XAI_API_KEY env var
# ─────────────────────────────────────────

set -euo pipefail

# ─────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────
TOKEN_TICKER='$WIF'
TOKEN_NAME='dogwifhat'
DAYS_BACK=7

# ─────────────────────────────────────────

python3 << 'PYEOF'
import json, os, subprocess, sys
from datetime import datetime, timedelta

ticker = os.environ.get("TOKEN_TICKER", "$WIF")
name   = os.environ.get("TOKEN_NAME", "dogwifhat")
days   = int(os.environ.get("DAYS_BACK", "7"))

api_key = os.environ.get("XAI_API_KEY", "")
if not api_key:
    print("ERROR: XAI_API_KEY not set", file=sys.stderr)
    sys.exit(1)

to_date   = datetime.utcnow().strftime("%Y-%m-%d")
from_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")

system_prompt = f"""You are a crypto news aggregator. Find news about {ticker} ({name}) from the last {days} days.

RULES:
- Use exactly 2 x_search calls. No more.
- Call 1: broad search for "{ticker}" OR "{name}" news, limit 10.
- Call 2: search for official/high-signal accounts discussing "{ticker}", limit 10.
- Ignore accounts with <2k followers unless they are verified project devs.
- If a claim is unverified or a rumor, prefix the text with "Rumor:" or "Unverified:".
- Return up to 10 items, sorted by date (newest first).
- Every item MUST have a url. If you cannot find a url, skip the item.
- Plain text only in all JSON string values. No markdown, no citations, no special formatting."""

user_prompt = f"Find crypto twitter news for {ticker} ({name}) from {from_date} to {to_date}."

payload = {
    "model": "grok-4-1-fast-non-reasoning",
    "stream": False,
    "tools": [{"type": "x_search"}],
    "max_tool_calls": 3,
    "input": [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": user_prompt}
    ],
    "text": {
        "format": {
            "type": "json_schema",
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
                                "date":   {"type": "string"}
                            },
                            "required": ["title", "text", "url", "source", "date"],
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
    capture_output=True, text=True, timeout=120
)

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
print(f"Cost:           ${cost_ticks / 1_000_000_000:.4f}")
PYEOF
