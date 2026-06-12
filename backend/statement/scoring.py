def calculate_financial_health(profile, risk_data):
    score = 100
    insights = []
    score -= risk_data["risk_score"] * 0.5
    score -= risk_data["account_takeover_score"] * 0.5
    total_dr = profile.get("total_dr", 0)
    total_cr = profile.get("total_cr", 0)
    if total_cr > 0:
        ratio = total_dr / total_cr
        if ratio > 0.95:
            score -= 20
            insights.append("You are spending almost everything you receive. Consider saving more.")
        elif ratio > 0.8:
            score -= 10
            insights.append("Your spending is high relative to your income.")
        else:
            insights.append("Your spending-to-income ratio is healthy.")
    else:
        insights.append("No income detected in this statement period.")
    if profile.get("transaction_count", 0) > 200:
        score -= 5
        insights.append("High transaction volume detected. This might make tracking expenses difficult.")
    if profile.get("avg_transaction", 0) > 5000:
        score -= 10
        insights.append("Average transaction size is high. Watch out for large impulsive purchases.")
    contribution_flags = [f for f in risk_data["flags"] if "split payments" in f.lower()]
    if contribution_flags:
        score += 5
        insights.append("Detected split payments (contributions). This reduces your net personal expenditure.")
    for flag in risk_data["flags"]:
        insights.append(f"Notice: {flag}")
    return {
        "health_score": max(0, int(score)),
        "insights": insights
    }
