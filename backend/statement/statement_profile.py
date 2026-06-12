from collections import Counter
import statistics
from datetime import datetime

def build_profile(transactions):
    successful = [tx for tx in transactions if tx["status"].upper() == "SUCCESS"]
    if not successful:
        return {
            "transaction_count": 0, "total_dr": 0, "total_cr": 0, "avg_transaction": 0,
            "monthly_trends": {}, "recurring_patterns": [],
            "rag_docs": {"summaries": [], "profiles": [], "observations": []}
        }
    monthly_data = {}
    for tx in successful:
        try:
            dt = None
            for fmt in ["%d/%m/%Y", "%d %b %Y"]:
                try:
                    dt = datetime.strptime(tx["date"], fmt)
                    break
                except: continue
            if not dt: continue
            month_key = dt.strftime("%B %Y")
            if month_key not in monthly_data:
                monthly_data[month_key] = {"dr": 0, "cr": 0, "count": 0, "categories": Counter()}
            amt = tx["amount"]
            if tx["drcr"].upper() == "DR":
                monthly_data[month_key]["dr"] += amt
                monthly_data[month_key]["categories"][tx["category"]] += amt
            else:
                monthly_data[month_key]["cr"] += amt
            monthly_data[month_key]["count"] += 1
        except: continue
    monthly_summaries = []
    for month, vals in monthly_data.items():
        summary = f"Summary for {month}: Total Spent ₹{round(vals['dr'], 2)}, Total Received ₹{round(vals['cr'], 2)}. "
        summary += f"Top spending categories: {', '.join([f'{c} (₹{round(a,2)})' for c, a in vals['categories'].most_common(3)])}."
        monthly_summaries.append(summary)
    entity_groups = {}
    for tx in successful:
        name = tx["display_name"] or "Unknown"
        if name not in entity_groups:
            entity_groups[name] = {"amounts": [], "dates": [], "type": tx["category"], "id": tx["receiver"]}
        entity_groups[name]["amounts"].append(tx["amount"])
        entity_groups[name]["dates"].append(tx["date"])
    entity_profiles = []
    for name, data in entity_groups.items():
        total = sum(data["amounts"])
        count = len(data["amounts"])
        avg = statistics.mean(data["amounts"])
        profile = f"Entity Profile: {name}. Category: {data['type']}. Interactions: {count}. Total Volume: ₹{round(total, 2)}. Average: ₹{round(avg, 2)}. "
        if count >= 3:
            profile += f"Pattern: Recurring frequent payments detected."
        entity_profiles.append(profile)
    observations = []
    sorted_months = sorted(monthly_data.keys(), key=lambda x: datetime.strptime(x, "%B %Y"))
    for i in range(1, len(sorted_months)):
        prev = monthly_data[sorted_months[i-1]]
        curr = monthly_data[sorted_months[i]]
        if curr["dr"] > prev["dr"] * 1.2:
            increase = round(((curr["dr"] - prev["dr"]) / prev["dr"]) * 100, 1)
            observations.append(f"Observation: Spending spike detected in {sorted_months[i]}. Outflow increased by {increase}% compared to {sorted_months[i-1]}.")
    recurring_patterns = []
    for name, data in entity_groups.items():
        if len(data["amounts"]) >= 3:
            recurring_patterns.append({
                "entity": name,
                "avg_amount": round(statistics.mean(data["amounts"]), 2),
                "frequency": len(data["amounts"]),
                "total_impact": round(sum(data["amounts"]), 2)
            })
    return {
        "transaction_count": len(successful),
        "total_dr": round(sum(tx["amount"] for tx in successful if tx["drcr"].upper() == "DR"), 2),
        "total_cr": round(sum(tx["amount"] for tx in successful if tx["drcr"].upper() == "CR"), 2),
        "avg_transaction": round(statistics.mean([tx["amount"] for tx in successful if tx["drcr"].upper() == "DR"]), 2) if successful else 0,
        "monthly_trends": monthly_data,
        "recurring_patterns": sorted(recurring_patterns, key=lambda x: x["total_impact"], reverse=True)[:5],
        "rag_docs": {
            "summaries": monthly_summaries,
            "profiles": entity_profiles,
            "observations": observations
        }
    }
