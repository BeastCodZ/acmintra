from math import ceil, pow
from typing import Literal

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(title="Purchase Planner API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class PurchaseRequest(BaseModel):
    current_balance: float = Field(..., ge=0)
    monthly_income: float = Field(..., ge=0)
    monthly_expenses: float = Field(..., ge=0)

    item_name: str = Field(default="Unnamed Item")
    item_price: float = Field(..., gt=0)

    category: Literal["property", "vehicle", "electronics", "education", "misc"] = "misc"
    payment_type: Literal["cash", "emi"] = "cash"

    emi_months: int | None = Field(default=None, gt=0)
    interest_rate: float = Field(default=0.0, ge=0)
    down_payment: float = Field(default=0.0, ge=0)


def calculate_emi(principal: float, annual_interest_rate: float, months: int) -> tuple[float, float, float]:
    """
    Returns:
        monthly_emi, total_paid, total_interest
    """
    principal = max(0.0, principal)
    months = max(1, int(months))
    annual_interest_rate = max(0.0, annual_interest_rate)

    if principal == 0:
        return 0.0, 0.0, 0.0

    monthly_rate = annual_interest_rate / 12 / 100

    if monthly_rate == 0:
        monthly_emi = principal / months
    else:
        factor = (1 + monthly_rate) ** months
        denom = factor - 1
        if denom <= 0:
            monthly_emi = principal / months
        else:
            monthly_emi = principal * monthly_rate * factor / denom

    total_paid = monthly_emi * months
    total_interest = max(0.0, total_paid - principal)

    return monthly_emi, total_paid, total_interest


def score_to_recommendation(score: int) -> str:
    if score >= 85:
        return "BUY NOW"
    if score >= 60:
        return "WAIT"
    return "NOT RECOMMENDED"


@app.get("/")
def root():
    return {
        "service": "Purchase Planner",
        "status": "running",
    }


@app.post("/analyze")
def analyze(req: PurchaseRequest):
    reasons = []
    tips = []
    warnings = []

    score = 100

    def clamp(value: float, low: float, high: float) -> float:
        return max(low, min(high, value))

    def calculate_emi(principal: float, annual_interest_rate: float, months: int):
        principal = max(0.0, principal)
        months = max(1, int(months))
        annual_interest_rate = max(0.0, annual_interest_rate)

        if principal <= 0:
            return 0.0, 0.0, 0.0

        monthly_rate = annual_interest_rate / 12 / 100

        if monthly_rate == 0:
            monthly_emi = principal / months
        else:
            factor = pow(1 + monthly_rate, months)
            denom = factor - 1
            if denom <= 0:
                monthly_emi = principal / months
            else:
                monthly_emi = principal * monthly_rate * factor / denom

        total_paid = monthly_emi * months
        total_interest = max(0.0, total_paid - principal)
        return monthly_emi, total_paid, total_interest

    item_name = (req.item_name or "Unnamed Item").strip() or "Unnamed Item"
    category = (req.category or "misc").strip().lower()
    payment_type = (req.payment_type or "cash").strip().lower()

    current_balance = max(0.0, float(req.current_balance))
    monthly_income = max(0.0, float(req.monthly_income))
    monthly_expenses = max(0.0, float(req.monthly_expenses))
    item_price = max(0.0, float(req.item_price))
    interest_rate = max(0.0, float(req.interest_rate or 0.0))
    requested_down_payment = max(0.0, float(req.down_payment or 0.0))

    if monthly_income == 0:
        warnings.append(
            "Monthly income is zero or unknown, so some income-based checks were skipped."
        )

    if monthly_expenses == 0:
        warnings.append(
            "Monthly expenses are zero or unknown, so buffer checks were limited."
        )

    if item_price <= 0:
        return {
            "item": item_name,
            "category": category,
            "payment_type": payment_type,
            "recommendation": "NOT RECOMMENDED",
            "best_payment_option": "wait",
            "financial_readiness_score": 0,
            "current_balance": round(current_balance, 2),
            "monthly_income": round(monthly_income, 2),
            "monthly_expenses": round(monthly_expenses, 2),
            "monthly_savings": round(max(0.0, monthly_income - monthly_expenses), 2),
            "cash_affordable_now": False,
            "months_until_affordable": None,
            "monthly_emi": None,
            "total_interest": 0.0,
            "total_paid": 0.0,
            "effective_down_payment": 0.0,
            "remaining_price_financed": 0.0,
            "remaining_balance_after_cash_purchase": None,
            "cash_buffer_months_after_purchase": None,
            "warnings": ["Item price must be greater than zero."],
            "reasons": ["Invalid item price."],
            "tips": [],
        }

    down_payment = clamp(requested_down_payment, 0.0, item_price)
    if requested_down_payment > item_price:
        warnings.append(
            "Down payment exceeded item price, so it was capped to the item price."
        )

    financed_principal = max(0.0, item_price - down_payment)
    monthly_savings = max(0.0, monthly_income - monthly_expenses)
    disposable_income = monthly_savings

    cash_affordable_now = current_balance >= item_price
    months_until_affordable = None

    monthly_emi = None
    total_paid = item_price
    total_interest = 0.0
    cash_buffer_months_after_purchase = None
    remaining_balance_after_cash_purchase = None

    # -------------------------
    # CASH PATH
    # -------------------------
    if payment_type == "cash":
        if cash_affordable_now:
            remaining_balance_after_cash_purchase = current_balance - item_price
            reasons.append("Current balance is sufficient to buy this item outright.")

            if monthly_expenses > 0:
                cash_buffer_months_after_purchase = remaining_balance_after_cash_purchase / monthly_expenses

                if cash_buffer_months_after_purchase < 1:
                    score -= 30
                    reasons.append(
                        "Buying now would leave less than 1 month of expenses as a buffer."
                    )
                elif cash_buffer_months_after_purchase < 3:
                    score -= 15
                    reasons.append(
                        "Buying now would leave less than 3 months of expenses as a buffer."
                    )
                elif category in {"property", "vehicle"} and cash_buffer_months_after_purchase < 6:
                    score -= 10
                    reasons.append(
                        "This large purchase reduces your safety buffer more than ideal."
                    )
            else:
                warnings.append(
                    "Monthly expenses are zero or unknown, so emergency buffer checks were skipped."
                )

            months_until_affordable = 0
        else:
            score -= 35
            reasons.append("Current balance is insufficient for this purchase.")

            gap = item_price - current_balance
            if monthly_savings > 0:
                months_until_affordable = ceil(gap / monthly_savings)
                tips.append(
                    f"At your current savings rate, you could afford this in about {months_until_affordable} month(s)."
                )
            else:
                months_until_affordable = None
                score -= 15
                reasons.append(
                    "You do not currently have positive monthly savings, so there is no clear cash timeline."
                )
                tips.append(
                    "Increase savings or reduce expenses before considering this purchase."
                )

    # -------------------------
    # EMI PATH
    # -------------------------
    else:
        if financed_principal <= 0:
            monthly_emi = 0.0
            total_paid = down_payment
            total_interest = 0.0
            reasons.append("Down payment covers the full item price, so EMI is unnecessary.")
        else:
            months = req.emi_months if (req.emi_months and req.emi_months > 0) else 12
            if not req.emi_months or req.emi_months <= 0:
                warnings.append("No EMI tenure provided, so the analysis defaulted to 12 months.")

            monthly_emi, emi_total_paid, emi_interest = calculate_emi(
                principal=financed_principal,
                annual_interest_rate=interest_rate,
                months=months,
            )

            total_paid = down_payment + emi_total_paid
            total_interest = emi_interest

            if interest_rate > 0:
                tips.append(
                    f"This EMI plan adds about ₹{total_interest:.2f} in interest."
                )
            else:
                tips.append(
                    "This EMI plan appears to be interest-free."
                )

            if cash_affordable_now and total_interest > 0:
                score -= 10
                reasons.append("You can already afford this item in cash, so EMI would only add interest.")

            if disposable_income <= 0:
                score -= 40
                reasons.append("You have no positive monthly surplus, so EMI is not a safe option.")
            else:
                if monthly_emi > disposable_income:
                    score -= 35
                    reasons.append("Monthly EMI exceeds your monthly surplus.")
                elif monthly_emi > disposable_income * 0.7:
                    score -= 15
                    reasons.append("Monthly EMI uses a large share of your monthly surplus.")
                elif monthly_emi > disposable_income * 0.4:
                    score -= 5
                    reasons.append("Monthly EMI is fairly large relative to your monthly surplus.")

            if down_payment > 0:
                reasons.append(
                    f"Down payment of ₹{down_payment:.2f} reduces the financed amount."
                )

    # -------------------------
    # CATEGORY RULES
    # -------------------------
    if category == "electronics":
        if monthly_income > 0:
            if item_price > monthly_income * 2:
                score -= 10
                reasons.append("Electronics purchase exceeds roughly two months of income.")
            elif item_price > monthly_income:
                score -= 5
                reasons.append("Electronics purchase exceeds roughly one month of income.")
        else:
            tips.append("Electronics checks are more useful once monthly income is known.")

    elif category == "vehicle":
        if monthly_income > 0 and payment_type == "emi" and monthly_emi is not None:
            if monthly_emi > monthly_income * 0.15:
                score -= 15
                reasons.append("Vehicle EMI exceeds a comfortable share of monthly income.")
        if monthly_income > 0 and item_price > monthly_income * 24:
            score -= 10
            reasons.append("Vehicle price is very high relative to your income.")

    elif category == "property":
        if monthly_income > 0:
            annual_income = monthly_income * 12
            if item_price > annual_income * 3:
                score -= 20
                reasons.append("Property price exceeds the common 3× annual income guideline.")
            elif item_price > annual_income * 4:
                score -= 10
                reasons.append("Property price is high relative to annual income.")
        else:
            tips.append("Property checks are more useful once monthly income is known.")

    elif category == "education":
        reasons.append("Education spending may provide long-term value.")
        if monthly_income > 0 and item_price > monthly_income * 6:
            score -= 10
            reasons.append("Education expense is large relative to your monthly income.")

    elif category == "misc":
        if monthly_income > 0 and item_price > monthly_income * 1.5:
            score -= 5
            reasons.append("This miscellaneous purchase is relatively large compared to monthly income.")

    # -------------------------
    # FINAL DECISION
    # -------------------------
    score = int(clamp(score, 0, 100))

    if score >= 85:
        recommendation = "BUY NOW"
    elif score >= 60:
        recommendation = "WAIT"
    else:
        recommendation = "NOT RECOMMENDED"

    if cash_affordable_now:
        if payment_type == "emi" and interest_rate == 0 and monthly_emi is not None and disposable_income > 0:
            best_payment_option = "emi"
        else:
            best_payment_option = "cash"
    else:
        if payment_type == "emi" and monthly_emi is not None and monthly_emi <= disposable_income and score >= 60:
            best_payment_option = "emi"
        else:
            best_payment_option = "wait"

    if not reasons:
        reasons.append(
            "Purchase appears financially reasonable based on the information provided."
        )

    if recommendation == "BUY NOW" and payment_type == "emi" and total_interest > 0 and cash_affordable_now:
        tips.append("If possible, paying cash would avoid EMI interest.")

    if recommendation != "BUY NOW":
        if monthly_savings > 0 and months_until_affordable is not None and months_until_affordable > 0:
            tips.append(
                f"Saving at your current rate, you could buy this in about {months_until_affordable} month(s)."
            )
        elif monthly_savings <= 0:
            tips.append("A positive monthly surplus would make this much easier to afford.")

    return {
        "item": item_name,
        "category": category,
        "payment_type": payment_type,
        "recommendation": recommendation,
        "best_payment_option": best_payment_option,
        "financial_readiness_score": score,
        "current_balance": round(current_balance, 2),
        "monthly_income": round(monthly_income, 2),
        "monthly_expenses": round(monthly_expenses, 2),
        "monthly_savings": round(monthly_savings, 2),
        "cash_affordable_now": cash_affordable_now,
        "months_until_affordable": months_until_affordable,
        "monthly_emi": round(monthly_emi, 2) if monthly_emi is not None else None,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "effective_down_payment": round(down_payment, 2),
        "remaining_price_financed": round(financed_principal, 2),
        "remaining_balance_after_cash_purchase": round(remaining_balance_after_cash_purchase, 2)
        if remaining_balance_after_cash_purchase is not None
        else None,
        "cash_buffer_months_after_purchase": round(cash_buffer_months_after_purchase, 2)
        if cash_buffer_months_after_purchase is not None
        else None,
        "warnings": warnings,
        "reasons": reasons,
        "tips": tips,
    }
    reasons: list[str] = []
    tips: list[str] = []
    warnings: list[str] = []

    score = 100

    item_price = float(req.item_price)
    current_balance = float(req.current_balance)
    monthly_income = float(req.monthly_income)
    monthly_expenses = float(req.monthly_expenses)
    monthly_savings = max(0.0, monthly_income - monthly_expenses)
    disposable_income = monthly_savings

    if monthly_income == 0:
        warnings.append(
            "Monthly income is zero or unknown, so income-based checks were skipped where appropriate."
        )

    if monthly_expenses == 0:
        warnings.append(
            "Monthly expenses are zero or unknown, so emergency-fund checks were limited."
        )

    if req.down_payment > item_price:
        warnings.append(
            "Down payment exceeds item price, so it was capped to the item price."
        )

    effective_down_payment = min(max(0.0, req.down_payment), item_price)
    remaining_price = max(0.0, item_price - effective_down_payment)

    cash_affordable_now = current_balance >= item_price
    months_until_affordable: int | None = None

    monthly_emi: float | None = None
    total_paid = item_price
    total_interest = 0.0

    # --------------------------------------------------
    # CASH PATH
    # --------------------------------------------------
    if req.payment_type == "cash":
        if cash_affordable_now:
            reasons.append("Current balance is sufficient to buy this item outright.")

            remaining_after_purchase = current_balance - item_price

            if monthly_expenses > 0:
                emergency_months_after_purchase = remaining_after_purchase / monthly_expenses

                if emergency_months_after_purchase < 1:
                    score -= 30
                    reasons.append(
                        "Buying now would leave less than 1 month of expenses as a buffer."
                    )
                elif emergency_months_after_purchase < 3:
                    score -= 15
                    reasons.append(
                        "Buying now would leave less than 3 months of expenses as a buffer."
                    )
                elif emergency_months_after_purchase < 6 and req.category in {"property", "vehicle"}:
                    score -= 10
                    reasons.append(
                        "This purchase reduces your buffer more than is ideal for a large-ticket item."
                    )

            # Keep months_until_affordable = 0 because it is affordable now.
            months_until_affordable = 0
        else:
            score -= 35
            reasons.append("Current balance is insufficient for this purchase.")

            gap = item_price - current_balance
            if monthly_savings > 0:
                months_until_affordable = ceil(gap / monthly_savings)
                tips.append(
                    f"At your current savings rate, you could afford this in about {months_until_affordable} month(s)."
                )
            else:
                months_until_affordable = None
                score -= 15
                reasons.append("You do not currently have positive monthly savings, so there is no clear timeline to afford this in cash.")
                tips.append("Increase monthly savings or reduce expenses before considering this purchase.")

    # --------------------------------------------------
    # EMI PATH
    # --------------------------------------------------
    else:
        if remaining_price == 0:
            # Down payment already covers the full item.
            monthly_emi = 0.0
            total_paid = effective_down_payment
            total_interest = 0.0
            reasons.append("Down payment covers the full item price, so EMI is unnecessary.")
        else:
            months = req.emi_months if req.emi_months is not None else 12
            if req.emi_months is None:
                warnings.append("No EMI tenure provided; defaulted to 12 months.")

            monthly_emi, total_paid_emi, emi_interest = calculate_emi(
                principal=remaining_price,
                annual_interest_rate=req.interest_rate,
                months=months,
            )

            total_paid = effective_down_payment + total_paid_emi
            total_interest = emi_interest

            if req.interest_rate > 0:
                tips.append(
                    f"This EMI plan adds about ₹{total_interest:.2f} in interest."
                )

            if cash_affordable_now and req.interest_rate > 0:
                score -= 10
                reasons.append("You can already afford this item in cash, so EMI would only add interest.")

            if disposable_income <= 0:
                score -= 40
                reasons.append("You have no positive monthly surplus, so EMI is not a safe option.")
            else:
                if monthly_emi > disposable_income:
                    score -= 35
                    reasons.append("Monthly EMI exceeds your monthly surplus.")
                elif monthly_emi > disposable_income * 0.7:
                    score -= 15
                    reasons.append("Monthly EMI uses a large share of your monthly surplus.")
                elif monthly_emi > disposable_income * 0.4:
                    score -= 5
                    reasons.append("Monthly EMI is fairly large relative to your monthly surplus.")

            if req.down_payment > 0:
                reasons.append(
                    f"Down payment of ₹{effective_down_payment:.2f} reduces the financed amount."
                )

    # --------------------------------------------------
    # CATEGORY-SPECIFIC RULES
    # --------------------------------------------------
    if req.category == "electronics":
        if monthly_income > 0:
            if item_price > monthly_income * 2:
                score -= 10
                reasons.append("Electronics purchase exceeds roughly two months of income.")
            elif item_price > monthly_income:
                score -= 5
                reasons.append("Electronics purchase exceeds roughly one month of income.")
        else:
            tips.append("Electronics purchases are easier to judge once you provide monthly income.")

    elif req.category == "vehicle":
        if monthly_income > 0 and req.payment_type == "emi" and monthly_emi is not None:
            if monthly_emi > monthly_income * 0.15:
                score -= 15
                reasons.append("Vehicle EMI exceeds a comfortable share of monthly income.")
        if monthly_income > 0 and item_price > monthly_income * 24:
            score -= 10
            reasons.append("Vehicle price is very high relative to your income.")

    elif req.category == "property":
        if monthly_income > 0:
            annual_income = monthly_income * 12
            if item_price > annual_income * 3:
                score -= 20
                reasons.append("Property price exceeds the common 3× annual income guideline.")
            elif item_price > annual_income * 4:
                score -= 10
                reasons.append("Property price is high relative to annual income.")
        else:
            tips.append("Property checks are more useful once monthly income is known.")

    elif req.category == "education":
        reasons.append("Education spending may provide long-term value.")
        if monthly_income > 0 and item_price > monthly_income * 6:
            score -= 10
            reasons.append("Education expense is large relative to your monthly income.")

    elif req.category == "misc":
        if monthly_income > 0 and item_price > monthly_income * 1.5:
            score -= 5
            reasons.append("This miscellaneous purchase is relatively large compared to monthly income.")

    # --------------------------------------------------
    # FINAL CLEANUP
    # --------------------------------------------------
    score = max(0, min(100, score))

    recommendation = score_to_recommendation(score)

    best_payment_option = "cash" if cash_affordable_now else "emi" if req.payment_type == "emi" and score >= 60 else "wait"

    if not reasons:
        reasons.append("Purchase appears financially reasonable based on the information provided.")

    if recommendation == "BUY NOW" and req.payment_type == "emi" and total_interest > 0 and cash_affordable_now:
        tips.append("If possible, paying cash would avoid EMI interest.")

    if recommendation != "BUY NOW":
        if monthly_savings > 0 and months_until_affordable is not None and months_until_affordable > 0:
            tips.append(f"Saving at your current rate, you could buy this in about {months_until_affordable} month(s).")
        elif monthly_savings <= 0:
            tips.append("A positive monthly surplus would make this much easier to afford.")

    result = {
        "item": req.item_name,
        "category": req.category,
        "payment_type": req.payment_type,
        "recommendation": recommendation,
        "best_payment_option": best_payment_option,
        "financial_readiness_score": score,
        "current_balance": round(current_balance, 2),
        "monthly_income": round(monthly_income, 2),
        "monthly_expenses": round(monthly_expenses, 2),
        "monthly_savings": round(monthly_savings, 2),
        "cash_affordable_now": cash_affordable_now,
        "months_until_affordable": months_until_affordable,
        "monthly_emi": round(monthly_emi, 2) if monthly_emi is not None else None,
        "total_interest": round(total_interest, 2),
        "total_paid": round(total_paid, 2),
        "effective_down_payment": round(effective_down_payment, 2),
        "remaining_price_financed": round(remaining_price, 2),
        "warnings": warnings,
        "reasons": reasons,
        "tips": tips,
    }

    return result