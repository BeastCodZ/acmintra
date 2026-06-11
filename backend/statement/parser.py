from bs4 import BeautifulSoup
import re
import pdfplumber
import io

def clean_amount(amt_str):
    if not amt_str or str(amt_str).strip() in ["-", ""]:
        return 0
    cleaned = str(amt_str).replace("INR", "").replace(",", "").replace("+", "").replace("-", "").strip()
    try:
        return float(cleaned)
    except:
        return 0

def extract_display_name(details):
    if not details:
        return "Unknown"
    details = details.replace("\n", " ").strip()
    parts = details.split("/")
    if len(parts) >= 2:
        name = parts[1].strip()
        if name:
            return name
    return parts[0].strip()[:30]

def parse_bhim_statement(html_content):
    soup = BeautifulSoup(html_content, "html.parser")
    transactions = []
    seen = set()
    rows = soup.find_all("tr")
    for row in rows:
        cols = row.find_all("td")
        if len(cols) < 11:
            continue
        payment_id = cols[6].get_text(strip=True)
        if payment_id in seen:
            continue
        seen.add(payment_id)
        amount = clean_amount(cols[8].get_text(strip=True))
        receiver = cols[5].get_text(strip=True)
        transactions.append({
            "payment_id": payment_id,
            "date": cols[0].get_text(strip=True),
            "time": cols[1].get_text(strip=True),
            "sender": cols[4].get_text(strip=True),
            "receiver": receiver,
            "amount": amount,
            "drcr": cols[9].get_text(strip=True),
            "status": cols[10].get_text(strip=True),
            "display_name": extract_display_name(receiver)
        })
    return transactions

def parse_pdf_statement(file_bytes):
    transactions = []
    amt_p = r"(?:(?:INR\s*)?[\d,.]+(?:\.\d{2})?|-)"
    pattern = rf"^(\d{{1,2}} [A-Za-z]{{3}} \d{{4}})\s+(.*?)\s+({amt_p})\s+({amt_p})\s+({amt_p})$"
    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        current_tx = None
        for page in pdf.pages:
            text = page.extract_text()
            if not text:
                continue
            lines = text.split('\n')
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                match = re.match(pattern, line)
                if match:
                    if current_tx:
                        transactions.append(current_tx)
                    date, details, debit, credit, balance = match.groups()
                    debit_val = clean_amount(debit)
                    credit_val = clean_amount(credit)
                    amount = debit_val if debit_val > 0 else credit_val
                    drcr = "DR" if debit_val > 0 else "CR"
                    current_tx = {
                        "payment_id": f"PDF-{len(transactions)}",
                        "date": date,
                        "time": "00:00:00",
                        "sender": "OWNER",
                        "receiver": details,
                        "amount": amount,
                        "drcr": drcr,
                        "status": "SUCCESS",
                        "display_name": ""
                    }
                elif current_tx:
                    skip_keywords = [
                        "Ending Balance", "Total", "Page", 
                        "Date Transaction Details", "Debits Credits Balance",
                        "ACCOUNT ACTIVITY", "Customer's Address", "Branch Name"
                    ]
                    if any(key in line for key in skip_keywords):
                        continue
                    current_tx["receiver"] += " " + line
        if current_tx:
            transactions.append(current_tx)
    for tx in transactions:
        details = tx["receiver"]
        tx["display_name"] = extract_display_name(details)
        upi_match = re.search(r"UPI/(\d+)", details)
        if upi_match:
            tx["payment_id"] = upi_match.group(1)
    return transactions

def parse_statement(file_content, filename):
    if filename.lower().endswith(".pdf"):
        return parse_pdf_statement(file_content)
    else:
        html_str = file_content.decode("utf-8", errors="ignore")
        return parse_bhim_statement(html_str)
