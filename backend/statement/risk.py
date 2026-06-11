from collections import Counter

def calculate_scores(transactions):
    risk_score = 0
    account_takeover = 0
    flags = []
    successful = [tx for tx in transactions if tx["status"].upper() == "SUCCESS"]
    if not successful:
        return {"risk_score": 0, "account_takeover_score": 0, "flags": []}
    unknowns = [tx for tx in successful if tx["category"] == "unknown"]
    if len(unknowns) >= 5:
        risk_score += 15
        flags.append("Many unknown recipients")
    dates = Counter(tx["date"] for tx in successful)
    busiest = max(dates.values(), default=0)
    if busiest >= 15:
        risk_score += 20
        flags.append("High transaction frequency")
    large_unknowns = [tx for tx in unknowns if tx["amount"] > 10000]
    if large_unknowns:
        account_takeover += 30
        flags.append("Large unknown payments")
    structuring_candidates = [tx for tx in successful if 40000 <= tx["amount"] < 50000]
    if len(structuring_candidates) >= 3:
        risk_score += 40
        flags.append("Possible structuring detected (multiple payments near ₹50,000)")
    total_cr = sum(tx["amount"] for tx in successful if tx["drcr"].upper() == "CR")
    total_dr = sum(tx["amount"] for tx in successful if tx["drcr"].upper() == "DR")
    if total_cr > 10000 and total_dr > (total_cr * 0.9):
        risk_score += 25
        flags.append("Money mule pattern: Rapid movement of received funds")
    crypto_txs = [tx for tx in successful if tx["category"] == "crypto"]
    if crypto_txs:
        risk_score += 10
        flags.append("Cryptocurrency-related activity detected")
    debits = [tx for tx in successful if tx["drcr"].upper() == "DR"]
    credits = [tx for tx in successful if tx["drcr"].upper() == "CR"]
    contribution_count = 0
    for d_tx in debits:
        for c_tx in credits:
            if d_tx["date"] == c_tx["date"]:
                if 0.4 * d_tx["amount"] <= c_tx["amount"] <= 0.95 * d_tx["amount"]:
                    contribution_count += 1
                    break 
    if contribution_count >= 1:
        flags.append(f"Split payments detected ({contribution_count} contributions)")
    return {
        "risk_score": min(risk_score, 100),
        "account_takeover_score": min(account_takeover, 100),
        "flags": list(set(flags))
    }
