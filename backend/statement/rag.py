import torch
import json
import re
from pathlib import Path
from sentence_transformers import SentenceTransformer
from ollama import chat
import numpy as np

device = "cuda" if torch.cuda.is_available() else "cpu"
model = SentenceTransformer("all-MiniLM-L6-v2", device=device)
intelligence_docs = []
intelligence_embeddings = None

def index_intelligence(rag_data):
    global intelligence_docs, intelligence_embeddings
    intelligence_docs = []
    intelligence_docs.extend(rag_data.get("summaries", []))
    intelligence_docs.extend(rag_data.get("profiles", []))
    intelligence_docs.extend(rag_data.get("observations", []))
    if not intelligence_docs:
        intelligence_embeddings = None
        return
    intelligence_embeddings = model.encode(intelligence_docs, show_progress_bar=False, convert_to_tensor=True)

def query_chat(user_query):
    global intelligence_docs, intelligence_embeddings
    if intelligence_embeddings is None or not intelligence_docs:
        return "Intelligence Core is offline. Analyze a statement to initialize."
    query_embedding = model.encode(user_query, convert_to_tensor=True, show_progress_bar=False)
    similarities = torch.nn.functional.cosine_similarity(query_embedding, intelligence_embeddings)
    top_k = min(15, len(intelligence_docs))
    values, indices = torch.topk(similarities, k=top_k)
    context = "\n".join([intelligence_docs[idx] for idx in indices])
    prompt = f"""
[CONTEXT]
{context}

[QUESTION]
{user_query}

INSTRUCTIONS:
- Answer ONLY using the data in [CONTEXT].
- Provide a direct, factual answer.
- NO intro.
- NO conversational filler.
- If data is missing, say "Data unavailable".
- Format: Plain text.
"""
    try:
        response = chat(
            model="llama3.2",
            messages=[
                {"role": "system", "content": "Direct data analyzer. No intro. Just the facts."},
                {"role": "user", "content": prompt}
            ]
        )
        return response.message.content.strip()
    except Exception as e:
        return f"Audit Error: Neural link failure ({e})"

def batch_ask(flags):
    explanations = {}
    for flag in flags:
        explanations[flag] = "Pattern identified as high-risk by mathematical engine."
    return explanations
