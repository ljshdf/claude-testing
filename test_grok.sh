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
export TOKEN_TICKER='$WIF'
export TOKEN_NAME='dogwifhat'
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

system_prompt = """You are a skeptical low/mid-cap crypto detective. Your job is to scan crypto Twitter for community-sourced intel about a given project — not hype, shills, or engagement farming.

IMPORTANT: Do NOT include posts from the project's own official X account. We already track that separately. Posts from team members, devs, or founders on their personal accounts ARE welcome.

WHAT TO LOOK FOR:
- On-chain detective findings (whale movements, deployer wallet activity, suspicious transfers)
- Community reports about partnerships, integrations, listings, or ecosystem updates
- Security warnings, exploit reports, or rugpull alerts
- Governance discussions or tokenomics debates
- Trader commentary with actual analysis or market structure observations
- Investigative threads from crypto researchers (e.g. ZachXBT, Lookonchain, etc.)
- Notable community discussions, memes-with-substance, or sentiment shifts
- Exchange listing or delisting news from credible sources

WHAT TO IGNORE:
- Posts from the project's own official X account
- Pure price predictions with no analysis ("about to go vertical")
- Engagement farming ("buy more!", emoji-heavy hype posts with no substance)
- Random influencers just listing the ticker among 10 other coins

OUTPUT RULES:
- If a claim is unverified or a rumor, prefix the text with "Rumor:" or "Unverified:".
- Return up to 10 items, sorted by date (newest first). Fewer is fine if there is not enough signal.
- Every item MUST have a url (link to the tweet). No url = skip the item.
- Every item MUST have a source_url (the poster's X profile URL, e.g. https://x.com/username).
- Plain text only in all JSON values. No markdown, citations, or special formatting."""

user_prompt = f"Find crypto twitter news for {ticker} ({name}) from {from_date} to {to_date}."

payload = {
    "model": "grok-4-1-fast-non-reasoning",
    "stream": False,
    "tools": [{"type": "x_search"}],
    "max_tool_calls": 5,
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
    capture_output=True, text=True, timeout=120
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
print(f"Cost:           ${cost_ticks / 1_000_000_000:.4f}")
PYEOF
