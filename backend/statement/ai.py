from __future__ import annotations
import json
import logging
import re
from pathlib import Path
from typing import Any, Dict, List, Optional
from ollama import chat

DEFAULT_MODEL = "llama3.2"
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)
BASE_DIR = Path(__file__).parent
DATA_PATH = BASE_DIR / "data" / "categories.json"

def load_keywords():
    try:
        with open(DATA_PATH) as f:
            data = json.load(f)
            return {
                "aggregators": set(k.lower() for k in data.get("aggregators", [])),
                "others": set(k.lower() for k in data.get("others", [])),
                "merchants": set(k.lower() for k in data.get("merchant", [])),
                "legal_suffixes": set(k.lower() for k in data.get("legal_suffixes", []))
            }
    except Exception as e:
        logger.error("Failed to load keywords from %s: %s", DATA_PATH, e)
        return {"aggregators": set(), "others": set(), "merchants": set(), "legal_suffixes": set()}

KEYWORDS = load_keywords()

def count_keyword_matches(text, keywords):
    text = text.lower()
    count = 0
    for kw in keywords:
        kw = kw.lower()
        if len(kw) <= 3:
            if re.search(rf"\b{re.escape(kw)}\b", text):
                count += 1
        else:
            if kw in text:
                count += 1
            elif len(kw) > 6:
                for i in range(3, len(kw)-3):
                    split_kw = kw[:i] + " " + kw[i:]
                    if split_kw in text:
                        count += 1
                        break
    return count

def extract_json(text: str) -> Optional[Dict[str, Any]]:
    try:
        matches = re.findall(r"\{.*?\}", text, re.DOTALL)
        if not matches: return None
        for match in matches:
            try:
                json_str = re.sub(r",\s*([\]\}])", r"\1", match)
                return json.loads(json_str)
            except: continue
        return None
    except: return None

VALID_TYPES = {"person", "merchant", "others"}

def validate_classification(data: Dict[str, Any]) -> bool:
    if not isinstance(data, dict): return False
    if data.get("type") not in VALID_TYPES: return False
    confidence = data.get("confidence")
    if not isinstance(confidence, (int, float)): return False
    return 0 <= confidence <= 100

def looks_like_person(name: str) -> bool:
    name = name.strip()
    if not name: return False
    noise = ["atm service branch", "service branch", "no remarks", "paid via", "sent using", "/branch :", "paytm", "upi"]
    clean_name = name.lower()
    for n in noise: clean_name = clean_name.replace(n, "")
    clean_name = clean_name.strip()
    words = [w for w in clean_name.split() if w]
    if not words: return False
    if count_keyword_matches(clean_name, KEYWORDS["merchants"]) > 0: return False
    if any(word.lower() in KEYWORDS["legal_suffixes"] for word in words): return False
    alpha_only = re.sub(r"[^a-zA-Z\s]", "", clean_name).strip()
    if not alpha_only: return False
    alpha_words = [w for w in alpha_only.split() if len(w) >= 2]
    if len(alpha_words) >= 2 and len(alpha_words) <= 4: return True
    return False

def analyze_transaction_patterns(tx_history: List[str]) -> Dict[str, Any]:
    sent_count = 0
    received_count = 0
    amounts = []
    for tx in tx_history:
        amount_match = re.search(r"₹\s*(\d+(?:\.\d+)?)", tx)
        if amount_match:
            try: amounts.append(float(amount_match.group(1)))
            except: pass
        if "-₹" in tx: sent_count += 1
        if "+₹" in tx: received_count += 1
    avg_amount = sum(amounts) / len(amounts) if amounts else 0
    return {
        "sent_count": sent_count,
        "received_count": received_count,
        "only_outflow": sent_count > 0 and received_count == 0,
        "mixed_flow": sent_count > 0 and received_count > 0,
        "avg_amount": round(avg_amount, 2),
        "transaction_count": len(tx_history),
    }

def deterministic_classify(name: str, tx_history: List[str]) -> Optional[Dict[str, Any]]:
    lower_name = name.lower()

    noise = [
        "atm service branch",
        "service branch",
        "no remarks",
        "paid via",
        "sent using",
        "/branch :"
    ]

    clean_name = lower_name

    for n in noise:
        clean_name = clean_name.replace(n, "")

    patterns = analyze_transaction_patterns(tx_history)

    merchant_hits = count_keyword_matches(
        clean_name,
        KEYWORDS["merchants"]
    )

    aggregator_hits = count_keyword_matches(
        clean_name,
        KEYWORDS["aggregators"]
    )

    other_hits = count_keyword_matches(
        clean_name,
        KEYWORDS["others"]
    )

    is_person_name = looks_like_person(name)

    print(
        f"DEBUG DET: '{name}' | "
        f"person={is_person_name} | "
        f"merchant_hits={merchant_hits} | "
        f"aggregator_hits={aggregator_hits} | "
        f"other_hits={other_hits}"
    )

    if aggregator_hits > 0:
        return {
            "type": "others",
            "confidence": 95,
            "source": "rules"
        }

    if other_hits > 0:
        return {
            "type": "others",
            "confidence": 90,
            "source": "rules"
        }

    if merchant_hits > 0:
        return {
            "type": "merchant",
            "confidence": 90,
            "source": "rules"
        }

    if patterns["mixed_flow"]:
        return {
            "type": "person",
            "confidence": 95,
            "source": "rules"
        }

    if is_person_name:
        return {
            "type": "person",
            "confidence": 80,
            "source": "rules"
        }

    if patterns["only_outflow"]:
        return {
            "type": "merchant",
            "confidence": 70,
            "source": "rules"
        }

    return None

def llm_classify(name: str, tx_history: List[str], model: str = DEFAULT_MODEL, max_retries: int = 2, ) -> Dict[str, Any]:
    patterns = analyze_transaction_patterns(tx_history)
    history_text = ", ".join(tx_history) if tx_history else "No history"
    prompt = f"""
FORENSIC CLASSIFICATION TASK: "{name}"
HISTORY: [{history_text}]

METRICS:
- Outflow transactions: {patterns["sent_count"]}
- Inflow transactions: {patterns["received_count"]}
- Back-and-forth transfers: {patterns["mixed_flow"]}
- One-way spending: {patterns["only_outflow"]}
- Average Amount: ₹{patterns["avg_amount"]}

INSTRUCTIONS:
1. person: MUST use for human-sounding names (e.g. "Rohan Sharma", "Chintu").
2. merchant: MUST use for Brands, Institutions, Shops, Apps, Services.
3. others: ONLY use as a last resort if it is neither a person nor a business.

Respond ONLY with RAW JSON:
{{"type": "person" | "merchant" | "others", "confidence": 0-100}}
"""
    print(f"\n--- SENT FOR '{name}' ---")
    print(prompt)
    for attempt in range(max_retries + 1):
        try:
            response = chat(
                model=model,
                messages=[
                    {"role": "system", "content": "You are a forensic accountant. Output RAW JSON only. Decide Person vs Merchant first. Others is last resort."},
                    {"role": "user", "content": prompt}
                ],
                options={"temperature": 0}
            )
            raw_content = response.message.content
            print(f"--- REPLY FOR '{name}' ---")
            print(raw_content)
            data = extract_json(raw_content)
            if data and validate_classification(data):
                if looks_like_person(name) and data["type"] == "others":
                    data["type"] = "person"
                    data["confidence"] = 70
                data["source"] = "llm"
                return data
        except Exception as e:
            logger.warning("LLM Error: %s", e)
    if looks_like_person(name): return {"type": "person", "confidence": 60, "source": "fallback"}
    return {"type": "others", "confidence": 10, "is_fallback": True}

def get_individual_forensic_guess(name: str, tx_history: List[str], model: str = DEFAULT_MODEL) -> Dict[str, Any]:
    if not name or not name.strip(): return {"type": "others", "confidence": 0}
    rule_result = deterministic_classify(name, tx_history)
    if rule_result:
        print(f"\n--- DETERMINISTIC MATCH FOR '{name}' ---")
        print(f"Result: {rule_result}")
        return rule_result
    return llm_classify(name, tx_history, model=model)
