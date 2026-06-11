import json
import re
from pathlib import Path

def matches_keyword(text, keywords):
    text = text.upper()
    for kw in keywords:
        kw = kw.upper()
        if len(kw) <= 3:
            if re.search(rf"\b{re.escape(kw)}\b", text):
                return True
        else:
            if kw in text:
                return True
            if len(kw) > 6:
                for i in range(3, len(kw)-3):
                    split_kw = kw[:i] + " " + kw[i:]
                    if split_kw in text:
                        return True
    return False

def categorize(receiver, display_name=None, entity_stats=None):
    BASE_DIR = Path(__file__).parent
    categories_path = BASE_DIR / "data" / "categories.json"
    with open(categories_path) as f:
        cats = json.load(f)
    name_upper = (display_name or "").upper()
    receiver_upper = receiver.upper()
    noise = ["ATM SERVICE BRANCH", "SERVICE BRANCH", "NO REMARKS", "PAID VIA", "SENT USING", "/BRANCH :"]
    clean_receiver = receiver_upper
    for n in noise:
        clean_receiver = clean_receiver.replace(n, "")
    others_check = cats["others"] + cats["aggregators"]
    if matches_keyword(name_upper, others_check) or matches_keyword(clean_receiver, others_check):
        return "others"
    if entity_stats:
        if entity_stats['total_dr'] > 0 and entity_stats['total_cr'] > 0:
            return "person"
    if matches_keyword(name_upper, cats["merchant"]):
        return "merchant"
    if any(h in clean_receiver for h in ["@RZP", "@OKBIZ", "@PAYTMQR", "@RAZORPAY", "@FREECHARGE", "@BHARATPE"]):
        return "merchant"
    if entity_stats and entity_stats['total_dr'] == 0 and entity_stats['total_cr'] > 0:
        return "person"
    return "unknown"
