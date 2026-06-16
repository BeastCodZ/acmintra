from ollama import chat
import re
import json

def parse_receipt_with_llm(ocr_text: str):
    prompt = f"""
You are parsing OCR output from receipts.

Correct obvious OCR mistakes in merchant names and item names when you are highly confident.

Examples:
- "Starlurcks" → "Starbucks"
- "Waff le" → "Waffle"

Do not invent information.
If uncertain, keep the original text.

Rules:

- Use the FINAL amount paid as total_bill.
- Do NOT sum item prices yourself if a total is printed.
- Preserve item prices exactly as shown.
- If an item's price is 0.00 on the receipt, return 0.00.
- Exclude non-food options like "No, Thanks" from the items list.
- Correct obvious OCR mistakes in merchant names only when highly confident.
- Return ONLY valid JSON.
- Do NOT wrap it in markdown.
- Do NOT use ```json fences.
- Do NOT include explanations or extra text.

Schema:
{{
  "merchant": "",
  "date": "",
  "currency": "",
  "total_bill": 0,
  "item_count": 0,
  "items": [],
  "confidence": 0.0
}}

OCR TEXT:
{ocr_text}
"""

    response = chat(
        model="llama3.1:8b",
        messages=[
            {
                "role": "user",
                "content": prompt,
            }
        ],
    )

  

    content = response.message.content.strip()

    # Remove ```json and ``` fences if present
    content = response.message.content.strip()

    # Extract the first JSON object from the response
    match = re.search(r"\{.*\}", content, re.DOTALL)

    if match:
        content = match.group(0)

    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return {
            "merchant": None,
            "date": None,
            "currency": None,
            "total_bill": None,
            "item_count": None,
            "items": [],
            "confidence": 0.0,
            "raw_response": response.message.content,
        }