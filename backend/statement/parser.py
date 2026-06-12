from bs4 import BeautifulSoup
import re
import pdfplumber
import io

# ── Helpers ──────────────────────────────────────────────────────────────────

def clean_amount(amt_str):
    if not amt_str or str(amt_str).strip() in ["-", "", "None"]:
        return 0
    cleaned = re.sub(r"[^0-9.]", "", str(amt_str).replace(",", ""))
    try:
        return float(cleaned)
    except:
        return 0

def extract_display_name(desc):
    if not desc:
        return "Unknown"
    desc = desc.replace("\n", " ").strip()

    # UPI/NAME/ref → NAME
    upi = re.match(r"UPI[/ ]([^/\d][^/]+)/", desc, re.IGNORECASE)
    if upi:
        name = upi.group(1).strip()
        if name:
            return name[:40]

    # Recd:IMPS/ref/NAME/BANK → NAME
    imps = re.match(r"Recd:IMPS/\d+/([^/]+)/", desc, re.IGNORECASE)
    if imps:
        return imps.group(1).strip()[:40]

    # IFT-NAME -ref
    ift = re.match(r"IFT[- ](.+?)\s+-[A-Z]", desc, re.IGNORECASE)
    if ift:
        return ift.group(1).strip()[:40]

    # Interest
    if desc.lower().startswith("int.pd") or "interest" in desc.lower():
        return "Interest Income"

    # Generic: first slash part
    parts = desc.split("/")
    if len(parts) >= 2 and parts[1].strip():
        return parts[1].strip()[:40]

    return desc[:40]

# ── BHIM UPI HTML parser ──────────────────────────────────────────────────────

def parse_bhim_statement(html_content):
    soup = BeautifulSoup(html_content, "html.parser")
    transactions = []
    seen = set()
    for row in soup.find_all("tr"):
        cols = row.find_all("td")
        if len(cols) < 11:
            continue
        payment_id = cols[6].get_text(strip=True)
        if payment_id in seen:
            continue
        seen.add(payment_id)
        receiver = cols[5].get_text(strip=True)
        transactions.append({
            "payment_id": payment_id,
            "date": cols[0].get_text(strip=True),
            "time": cols[1].get_text(strip=True),
            "sender": cols[4].get_text(strip=True),
            "receiver": receiver,
            "amount": clean_amount(cols[8].get_text(strip=True)),
            "drcr": cols[9].get_text(strip=True),
            "status": cols[10].get_text(strip=True),
            "display_name": extract_display_name(receiver)
        })
    return transactions

# ── Kotak 7-column table parser ───────────────────────────────────────────────
# Columns: [#, Date, Description, Chq/Ref, Withdrawal(Dr), Deposit(Cr), Balance]

SKIP_ROWS = {"date", "description", "withdrawal", "deposit", "balance",
             "savings account transactions", "opening balance", "#"}

def parse_kotak_row(row):
    if not row or len(row) < 7:
        return None
    cells = [str(c or "").replace("\n", " ").strip() for c in row]
    # Skip header / section title rows
    if any(cells[i].lower() in SKIP_ROWS for i in [1, 2]):
        return None
    if cells[4].lower() in ("withdrawal (dr.)", "chq/ref. no."):
        return None

    date = cells[1]
    # Validate date format: DD Mon YYYY
    if not re.match(r"\d{1,2}\s+\w{3}\s+\d{4}", date):
        return None

    description = cells[2]
    ref_no      = cells[3]
    withdrawal  = clean_amount(cells[4])   # DR
    deposit     = clean_amount(cells[5])   # CR

    if withdrawal == 0 and deposit == 0:
        return None

    amount = withdrawal if withdrawal > 0 else deposit
    drcr   = "DR" if withdrawal > 0 else "CR"

    receiver = description
    display  = extract_display_name(description)

    return {
        "payment_id":   ref_no or f"TX-{date}-{amount}",
        "date":         date,
        "time":         "00:00:00",
        "sender":       "OWNER",
        "receiver":     receiver,
        "amount":       amount,
        "drcr":         drcr,
        "status":       "SUCCESS",
        "display_name": display,
    }

# ── Generic text-based fallback ───────────────────────────────────────────────

def parse_pdf_text_fallback(file_bytes):
    transactions = []
    row_re = re.compile(
        r"(?:\d+\s+)?(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4})"
        r"\s+(.+?)\s+([\d,]+\.\d{2}|-)\s+([\d,]+\.\d{2}|-)\s+([\d,]+\.\d{2})$",
        re.IGNORECASE
    )
    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        current_tx = None
        for page in pdf.pages:
            text = page.extract_text()
            if not text:
                continue
            for line in text.split("\n"):
                line = line.strip()
                if not line:
                    continue
                m = row_re.search(line)
                if m:
                    if current_tx:
                        transactions.append(current_tx)
                    date, desc, col1, col2, _ = m.groups()
                    dr = clean_amount(col1)
                    cr = clean_amount(col2)
                    amount = dr if dr > 0 else cr
                    drcr   = "DR" if dr > 0 else "CR"
                    current_tx = {
                        "payment_id":   f"PDF-{len(transactions)}",
                        "date":         date,
                        "time":         "00:00:00",
                        "sender":       "OWNER",
                        "receiver":     desc,
                        "amount":       amount,
                        "drcr":         drcr,
                        "status":       "SUCCESS",
                        "display_name": extract_display_name(desc),
                    }
                elif current_tx:
                    skip = ["Ending Balance","Total","Page","Statement Generated",
                            "Date","Description","Withdrawal","Deposit","Balance",
                            "Opening Balance","Account Summary","End of Statement"]
                    if not any(s.lower() in line.lower() for s in skip):
                        current_tx["receiver"] += " " + line
        if current_tx:
            transactions.append(current_tx)
    for tx in transactions:
        tx["display_name"] = extract_display_name(tx["receiver"])
    return transactions

# ── Main PDF entry point ──────────────────────────────────────────────────────

def parse_pdf_statement(file_bytes):
    transactions = []
    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        for page in pdf.pages:
            for table in page.extract_tables():
                for row in table:
                    tx = parse_kotak_row(row)
                    if tx:
                        transactions.append(tx)

    if not transactions:
        transactions = parse_pdf_text_fallback(file_bytes)

    return transactions

# ── Entry point ───────────────────────────────────────────────────────────────

def parse_statement(file_content, filename):
    if filename.lower().endswith(".pdf"):
        return parse_pdf_statement(file_content)
    else:
        return parse_bhim_statement(file_content.decode("utf-8", errors="ignore"))
