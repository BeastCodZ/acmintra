from fastapi import (
    FastAPI,
    UploadFile,
    File,
    HTTPException
)
from fastapi.middleware.cors import (
    CORSMiddleware
)
from parser import parse_statement
from categorizer import categorize
from statement_profile import build_profile
from risk import calculate_scores
from scoring import calculate_financial_health
from pydantic import BaseModel
import rag
import ai



class ChatRequest(BaseModel):
    query: str

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {
        "status": "running"
    }

@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...)
):
    try:
        content = await file.read()
        transactions = parse_statement(content, file.filename)

        if not transactions:
            raise HTTPException(status_code=422, detail="No transactions found. Make sure you uploaded a BHIM UPI HTML or bank PDF statement.")

        entity_stats = {}
        for tx in transactions:
            other_party_id = tx.get("receiver", "")
            other_party_name = tx.get("display_name") or other_party_id
            if other_party_name not in entity_stats:
                entity_stats[other_party_name] = {"total_dr": 0, "total_cr": 0, "tx_count": 0, "id": other_party_id}
            if tx.get("status", "").upper() == "SUCCESS":
                if tx.get("drcr", "").upper() == "DR":
                    entity_stats[other_party_name]["total_dr"] += tx.get("amount", 0)
                else:
                    entity_stats[other_party_name]["total_cr"] += tx.get("amount", 0)
                entity_stats[other_party_name]["tx_count"] += 1

        for tx in transactions:
            other_party_name = tx.get("display_name") or tx.get("receiver", "")
            tx["category"] = categorize(
                tx.get("receiver", ""),
                tx.get("display_name"),
                entity_stats.get(other_party_name)
            )

        profile = build_profile(transactions)
        risk = calculate_scores(transactions)
        health = calculate_financial_health(profile, risk)

        rag.index_intelligence(profile.get("rag_docs", {"summaries": [], "profiles": [], "observations": []}))
        risk_explanations = rag.batch_ask(risk.get("flags", []))

        return {
            "transactions": transactions,
            "profile": profile,
            "risk": risk,
            "health": health,
            "risk_explanations": risk_explanations
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    answer = rag.query_chat(request.query)
    return {"answer": answer}

@app.post("/analyze/ai")
async def analyze_ai(
    data: dict
):
    transactions = data.get("transactions", [])

    full_history = {}
    for tx in transactions:
        name = tx["display_name"] or tx["receiver"]
        if name not in full_history:
            full_history[name] = {"stream": [], "receiver": tx["receiver"], "is_unknown": False}
        
        if tx["category"] == "unknown":
            full_history[name]["is_unknown"] = True
            
        if len(full_history[name]["stream"]) < 15:
            sign = "-" if tx["drcr"].upper() == "DR" else "+"
            full_history[name]["stream"].append(f"{tx['date']}: {sign}₹{tx['amount']}")

    results = []
    processed_count = 0
    for name, data in full_history.items():
        if data["is_unknown"] and processed_count < 30:
            guess = ai.get_individual_forensic_guess(name, data["stream"])
            results.append({
                "receiver": data["receiver"],
                "display_name": name,
                "ai_guess": guess
            })
            processed_count += 1

    return {"results": results}
