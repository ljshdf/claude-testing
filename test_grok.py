#!/usr/bin/env python3
import json
import subprocess
import os

system_prompt = """You are a skeptical On-Chain Detective. Your goal is to extract VERIFIED and RUMORED news about the project while filtering out noise, scams, and engagement farming.

*STRICT VERIFICATION PROTOCOLS (Apply these before answering):
1. **Source Auditing:* Do not cite X (Twitter) users with <2,000 followers unless they are a known developer or official project account. If a user is small, label them as "Unverified/Low Signal" in the item.
2. *Bio Verification:* Never trust a user's bio (e.g., "Founder of Pump.fun"). Always cross-reference with official project handles. If unverified, explicitly flag them as "Likely Impersonator" in the item.
3. *Math & Logic Check:* If a user claims a specific profit (e.g., "Made $250k"), compare it to the token's Market Cap at that time. If the profit is impossible given the liquidity/volume, label the claim as "Exaggerated" or "False."

*NEWS SCOPE:*
- Include BOTH confirmed/verified updates and credible rumors/speculation about the project.
- Clearly label rumors or unverified claims in the item text (e.g., "Rumor:", "Unverified:", "Speculation:").
- Prefer official sources for verified updates, and high-signal community sources for rumors.

*INSTRUCTIONS:*
- Use x_search to find data. MAX 5 search calls, never use more.
- Provide ONLY plain text within JSON string values. never use markdown, citations, or Grok tags."""

user_prompt = """Find recent Crypto Twitter news for $WIF (CA: 0x0000000000000000000000000000000000000000). Focus on the last 30 days. Return up to 12 items. Each item must include a URL to the original post or source. Prefer official project accounts and high-signal voices. If unsure about an item, omit it."""

payload = {
    "model": "grok-4-1-fast-non-reasoning",
    "stream": False,
    "tools": [{"type": "x_search"}],
    "input": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
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
                                "title": {"type": "string", "description": "Short headline for the news item. Use plain text only."},
                                "text": {"type": "string", "description": "1-2 sentence summary. If the item is a rumor or unverified, clearly label it (e.g., 'Rumor:', 'Unverified:')."},
                                "url": {"type": "string", "description": "Direct URL to the original post or source. Required for every item."},
                                "source": {"type": "string", "description": "Source name or handle (e.g., official project account, publication name, or 'Unverified/Low Signal')."},
                                "date": {"type": "string", "description": "Publication date in ISO format (YYYY-MM-DD) if available; otherwise omit."}
                            },
                            "required": ["text"],
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

api_key = os.environ.get("XAI_API_KEY", "")
result = subprocess.run(
    ["curl", "-s", "https://api.x.ai/v1/responses",
     "-H", f"Authorization: Bearer {api_key}",
     "-H", "Content-Type: application/json",
     "-d", json.dumps(payload)],
    capture_output=True, text=True
)

try:
    parsed = json.loads(result.stdout)
    print(json.dumps(parsed, indent=2))
except json.JSONDecodeError:
    print("Raw output:")
    print(result.stdout)
    if result.stderr:
        print("Stderr:", result.stderr)
