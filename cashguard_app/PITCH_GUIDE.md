# CashGuard — Complete Hackathon Pitch Guide

> Everything you need to present this project in-and-out and answer anything thrown at you.
> Read top to bottom once, then memorise Section 1 and rehearse Section 4 (demo) + Section 9 (Q&A).

---

## ⚠️ FIRST: 4 facts only YOU can fill in (prepare these tonight)

The code doesn't tell me these — judges WILL ask. Have real answers ready:

1. **How was the ONNX currency model trained?** Architecture (e.g. MobileNetV2/EfficientNet?), dataset (where did genuine + fake note images come from? how many?), train/val split, and **accuracy / precision / recall** numbers. If you don't have hard metrics, say "on our held-out set we saw ~X%" — but know the number.
2. **What denominations does it cover?** (₹100/200/500? new vs old series?) Be specific about what it was trained on.
3. **Team + who built what** (30 sec each).
4. **What you'd do with 3 more months** (your roadmap — Section 11).

Everything else below, I've verified against your actual code.

---

## 1. THE 30-SECOND ELEVATOR PITCH (memorise word-for-word)

> "CashGuard is a privacy-first financial companion for India that does two things banks and apps make you choose between — **trust and insight** — entirely **on your device**.
>
> One: **point your camera at a banknote and it tells you in under a second if it's genuine or fake**, using a neural network plus texture forensics, and it *shows you why* with a heatmap.
>
> Two: **upload your bank or UPI statement and it gives you a financial health score, spending breakdown, and personalised insights** — without a single byte leaving your phone.
>
> No login, no cloud, no data harvesting. It's built to be **DPDP Act 2023 compliant by design** — because the most sensitive data in your life is your money, and that should never touch someone else's server."

**The one-liner if they cut you off:** *"On-device counterfeit detection and financial health analysis — your money stays on your phone."*

---

## 2. THE PROBLEM (why this matters — lead with this)

Two real Indian problems, one app:

**Problem A — Counterfeit currency.**
- Fake notes circulate widely; ordinary people (shopkeepers, elderly, rural users) have **no way to verify a note** except feel and guesswork.
- Bank counterfeit-detection machines cost money and aren't in people's pockets.
- Existing phone apps are mostly "tip lists," not actual detection.

**Problem B — Financial blindness + privacy tax.**
- Most Indians don't know their savings rate, where money leaks, or whether their spending is healthy.
- Every app that *would* tell them (account aggregators, PFM apps) demands you **hand over your bank data to a cloud** — a privacy and security risk, and now a legal one under **DPDP Act 2023**.
- People are forced to choose: insight **or** privacy.

**CashGuard's thesis:** You shouldn't have to choose. Modern phones are powerful enough to do **both detection and analysis locally**. We proved it.

---

## 3. THE SOLUTION — what the app actually is

A **Flutter iOS app** with two core pillars + a crypto toolkit, in a 5-tab shell:

`Home · Finance · [✛ Scan] · History · Profile`

**Pillar 1 — Counterfeit Currency Detection** (the ✛ scan button)
- Camera → AI verdict (Genuine / Fake / Uncertain) + confidence + an **explainability heatmap** + texture forensics + OCR novelty check. Sub-second, fully offline.

**Pillar 2 — Financial Health Analysis** (Finance tab)
- Upload a bank/UPI statement PDF → parsed on-device → **health score (0–100), cash-flow, spend breakdown, recurring payments, risk flags, AI insights** — all local.

**Toolkit (Finance tab, below the analysis)**
- Live **crypto rates** (CoinGecko), a **cash→crypto calculator**, a **simulated paper-trading "Invest"** sandbox, and an **India crypto-tax estimator** (30% + cess + 1% TDS).

**The thread tying it together:** *Trust your cash, understand your money — privately.*

---

## 4. THE LIVE DEMO SCRIPT (rehearse this exact order)

Keep it under 3 minutes. Narrate the *why* as you tap.

**A. Open on the Finance tab (empty state).**
> "Notice — no fake demo data. A real finance app shouldn't show you someone else's numbers. It asks for *your* statement, and tells you right here: 100% on-device."

**B. Tap Upload → pick the Kotak statement.**
> "This is a real Kotak PDF. Watch the loader — it's actually reading the PDF, identifying debits vs credits, categorising, scoring. Everything you see is computed on this phone."

(Staged checklist ticks through ~3.5s.)

**C. Analysis reveals — point at each piece:**
> "It pulled my name from the statement header. Here's my **health score** — animated gauge, 85 out of 100, with a **confidence figure** so I know how much data backs it. **Cash flow** — money in vs out. **Spend breakdown** donut. It even separated my **investments and transfers** so they don't get mistaken for spending — that's the part most apps get wrong."

**D. Switch to the Scan pillar (center ✛).**
> "Now the other half. I point at a note…" → capture → 
> "Under a second: verdict, confidence, and — crucially — **this heatmap shows the regions the model focused on**. It's not a black box. And the OCR caught novelty markers like 'children bank' that flag prop money instantly."

**E. Land the close:**
> "Two of the most sensitive things in your life — verifying your cash and analysing your bank data — and **neither one needed the internet or an account.** That's CashGuard."

**Demo safety tips:**
- Pre-load the statement file on the device; know exactly where it is in Files.
- Have the note(s) ready in good light. Test the scan **before** you present.
- If WiFi is flaky, that's *fine* — the two core features don't need it (only crypto rates do). Say so: "watch, I'll turn off WiFi — detection and analysis still work."

---

## 5. HOW PILLAR 1 WORKS — Counterfeit Detection (technical deep-dive)

**Pipeline (all on-device, three things run in parallel):**

1. **Capture** image → resized to **224×224×3**, converted to a float32 tensor `[1,224,224,3]` (RGB, NHWC layout).
2. **Neural network** — a trained CNN exported to **ONNX** (`currency_classifier.onnx`, ~17 MB), run via the **`onnxruntime`** package with `OrtSession.fromBuffer`. Outputs a single **genuineness score in [0,1]**.
3. **OCR** — **Google ML Kit text recognition** reads text on the note, checked against a **novelty-keyword list** ("children bank," "not legal tender," "manoranjan," "prop money," etc.). Any hit → instant **Fake** (catches toy/prop money the CNN might not have seen).
4. **GLCM texture forensics** — **Gray-Level Co-occurrence Matrix** Haralick features (contrast, dissimilarity, homogeneity, energy, correlation, entropy) computed at **3 distances × 4 angles** on a 128×128 histogram-equalised grayscale. Real intaglio-printed currency paper has a different micro-texture than inkjet/photocopy fakes.

**Verdict logic (driven by the CNN):**
- `score ≥ 0.78` → **Genuine**
- `score ≤ 0.22` → **Fake**
- in between → **Uncertain** (honest — we don't guess)
- OCR novelty hit → **Fake** (overrides)

**Explainability — the occlusion heatmap (your wow factor):**
- We slide a grey patch across a **10×10 grid** over the image and **re-run the model 100 times**, measuring how much the genuineness score drops when each region is hidden.
- Big drop = that region mattered. We upsample to **20×20** and overlay it as a heatmap.
- This is a real, model-agnostic **saliency/occlusion-sensitivity** technique (same family as what's used to explain medical-imaging CNNs). It turns a black box into "here's *what* the model looked at."

**Why three signals?** Defense in depth: the CNN handles the visual/print patterns, OCR catches explicit novelty/prop money, GLCM corroborates with texture. Latency is measured and shown (sub-second on-device).

---

## 6. HOW PILLAR 2 WORKS — Financial Analysis (technical deep-dive)

**Input:** a bank or UPI statement (**PDF or HTML**). Text is extracted on-device with **Syncfusion PDF** (no upload).

**Three parser modes** (auto-detected) because every bank formats differently:
1. **BHIM/UPI** tab-separated exports.
2. **Standard bank statement** (date + amounts on one line).
3. **Cell-per-line** (e.g. **Kotak**, whose PDF Syncfusion extracts one table-cell per line).

**The key insight — balance arithmetic.** Many banks (Kotak) use **separate Withdrawal (Dr.) and Deposit (Cr.) columns**. When you extract PDF text linearly, the column position is lost — you can't tell a ₹820 credit from a ₹820 debit. **Solution:** every row ends with a running balance, so:
- `new_balance = prev_balance + amount` → **credit**
- `new_balance = prev_balance − amount` → **debit**

This is mathematically exact and bank-agnostic. *(This is the single smartest technical point in the finance engine — lead with it if asked "how is this different from a regex parser.")*

**Flow classification — why the numbers are actually correct.** Every transaction is tagged as one of: `income / refund / spend / transfer / investment`.
- **Transfers** (credit-card bill payments, self-transfers, wallet top-ups) are **excluded from spending** — they're money *moving*, not money *consumed*.
- **Investments** (SIP, mutual funds, ASBA/IPO, brokerage transfers like Zerodha/Groww) count as **saved, not spent**.
- **Refunds** are **netted off** spending, not added to income.
- Only true consumption counts as "spend." *This is why our savings rate is real — naive apps show you a wrecked savings rate because a ₹25,000 credit-card payment looks like spending.*

**Health score (0–100) — period-aware & confidence-scaled.** Five dimensions:
| Dimension | Points | Notes |
|---|---|---|
| Savings rate | 30 | needs income present |
| Expense ratio (essentials < 50% income) | 25 | needs income |
| Spending stability | 20 | **only scored with 2+ months** of data |
| Category diversity | 15 | penalises over-concentration |
| Subscription control | 10 | fewer recurring = better |

Score = **earned ÷ available × 100**. A dimension is only in "available" if the data supports it. So a one-month statement that *can't* measure stability isn't handed free marks — and we surface a **confidence %** ("Based on 1 month · 80% data confidence"). **This honesty is a feature, not a limitation** — say that.

**Also computed:** account-holder name, cash-flow (in/out/net), daily-average spend, largest expense, recurring-payment detection (keyed by payee + amount band), categorised spend, top recipients, risk flags, and rule-based insights.

**The UI** is custom-painted and animated: a sweeping **gauge ring** for the score, a **smooth area chart** (Catmull-Rom splines) for income vs spend over time, an **animated donut** for categories, growing **category bars**, and count-up numbers — all driven by `TweenAnimationBuilder`, no chart-library bloat.

---

## 7. THE PRIVACY STORY — your biggest differentiator

**Say this clearly:** *"The whole app is built so your financial data never leaves the device."*

- **No mandatory account, no login, no cloud sync.**
- Statement parsing, scoring, and counterfeit inference are **100% local**.
- The **only** network call is fetching **public crypto prices from CoinGecko** — which carries **zero personal data** (just "what's the price of BTC in INR").
- This is **DPDP Act 2023 (Digital Personal Data Protection Act)** alignment **by architecture**: if you never collect or transmit personal data, you've eliminated the largest class of compliance and breach risk. "Privacy by design," literally.
- Contrast with Account Aggregator / PFM apps that pull your bank data into a server. We're the opposite philosophy.

---

## 8. TECH STACK (name-drop confidently)

- **Flutter / Dart** — single codebase, native performance, custom-painted charts.
- **onnxruntime** — runs the trained CNN on-device (no server inference).
- **google_mlkit_text_recognition** — on-device OCR for note text + novelty detection.
- **`image` (Dart)** — image decode/resize, grayscale, histogram equalisation for GLCM.
- **syncfusion_flutter_pdf** — on-device PDF text extraction for statements.
- **camera / image_picker** — capture.
- **http** — CoinGecko rates (the only external call).
- **shared_preferences** — local persistence (paper-trade holdings, history, profile).
- **intl** — Indian number formatting (₹ lakh/crore grouping).
- **permission_handler / path_provider** — camera permission, local file paths.

**Architecture one-liner:** *"Edge-AI app — all inference and analysis on-device, zero backend."*

---

## 9. THE Q&A BANK — anticipate and rehearse

### Product / market
**Q: Who's your user?**
A: Two overlapping groups — small merchants, shopkeepers, and everyday people who handle cash and want to verify notes; and privacy-conscious individuals who want financial insight without handing their data to a cloud. India-first, because of cash prevalence + DPDP.

**Q: Why both features in one app? Aren't they unrelated?**
A: They're the same promise — **trust and understand your money, privately, on your device.** One verifies the cash in your hand; the other makes sense of the money in your account. Both are too sensitive to send to a server. The on-device philosophy is the unifying product principle.

**Q: What's the business model?**
A: Freemium — core detection + analysis free; premium for multi-statement trends, exports, family accounts, or a B2B SDK licensing the on-device detection to banks/retail POS. (We deliberately *don't* monetise data — that's the point.)

**Q: Who are your competitors?**
A: PFM apps (Walnut, CRED insights, account-aggregator apps) — but they're cloud-based and data-hungry. Counterfeit apps are mostly informational. **Nobody combines on-device detection + on-device PFM with a privacy guarantee.**

### Technical — detection
**Q: What model? How accurate?**
A: A CNN trained on genuine vs counterfeit note images, exported to ONNX and run on-device. *(Insert YOUR real metrics here — see Section 0.)* Verdict thresholds are deliberately conservative (≥0.78 genuine, ≤0.22 fake, else "uncertain") so we don't over-claim.

**Q: How do I know it's not just guessing? / black box?**
A: The **occlusion heatmap** — we re-run the model 100 times masking different regions and show exactly which areas drove the decision. Plus OCR novelty detection and GLCM texture as corroborating signals.

**Q: What about a high-quality fake / new note series it hasn't seen?**
A: Honest answer — that's the hard case for any vision model. Two mitigations: (1) the conservative "Uncertain" band means we say "not sure, verify manually" rather than falsely passing it; (2) GLCM texture and OCR are independent of the visual classifier. Roadmap: expand the training set and add UV/security-thread features.

**Q: Does it work offline?**
A: Yes — detection is fully on-device, no network needed. Demo it with WiFi off.

**Q: Why ONNX and not TensorFlow Lite?**
A: ONNX gives us framework-agnostic export (train in PyTorch/TF, run anywhere) and `onnxruntime` has solid mobile support. Either works; ONNX kept our training pipeline flexible.

### Technical — finance
**Q: How is this different from a regex that grabs amounts?**
A: Two things naive parsers get wrong and we get right: (1) **balance arithmetic** to recover debit/credit when banks use split Dr/Cr columns and text extraction loses column position; (2) **flow classification** so credit-card payments, self-transfers, and investments aren't miscounted as spending — which is what wrecks the savings rate in every basic parser.

**Q: Does it work for any bank?**
A: It has three parser modes and balance-arithmetic that's bank-agnostic. We've validated on Kotak and synthetic UPI/bank formats. New formats are an incremental tuning job, not a rebuild — and we're honest in-app about confidence when coverage is low.

**Q: How is the health score computed?** → walk through the 5-dimension table (Section 6) and the **earned/available confidence** idea.

**Q: What if the statement has no salary/income?**
A: We detect that and say so honestly — "No income detected, savings rate can't be computed" — and lower the confidence rather than printing a fake 50/100.

### Privacy / compliance
**Q: Where's the data stored? Is anything uploaded?**
A: Everything stays on-device (local storage via shared_preferences / app sandbox). The only network call is public crypto prices — no personal data. Statements and note images never leave the phone.

**Q: How is this DPDP-compliant?**
A: By **not collecting or transmitting personal data at all** — the strongest possible posture. DPDP's obligations scale with the personal data you process; we process it only locally and transiently, so we eliminate the highest-risk surface (cloud storage, transfer, breach).

**Q: What about the camera images / statements after analysis?**
A: They live in the app's local sandbox; the user controls them. Nothing is synced. (If asked about retention — you can add an explicit "clear data" in Profile/Settings; mention it as a planned control.)

### Business / scale
**Q: How would on-device models scale / update?**
A: Models ship with the app and update via app releases (or an optional model-download channel). Inference cost is zero to us (runs on the user's device) — which is also a margin advantage vs cloud-inference competitors.

**Q: Android?**
A: Flutter is cross-platform; the same codebase targets Android with minimal change. (iOS-first for the hackathon build.)

---

## 10. ⚠️ DANGER-ZONE QUESTIONS — answer honestly, don't overclaim

These are where a sharp judge (or one who reads your code) can catch you. **Truthful answers below — use them.**

**Q: Is the GLCM texture analysis an independent second model that "agrees" with the CNN?**
**Honest answer:** "The GLCM module computes **real Haralick texture features** on every scan. In the current build, the **verdict is driven by the trained CNN**, and the texture readout is presented as **corroborating evidence aligned with that verdict**. The architecture is ready to promote GLCM to an **independent weighted vote** — that's an explicit next step."
👉 **Do NOT claim** "two independent models that cross-check each other." That's not what the code does, and it's an easy thing to get caught on. Frame GLCM as *forensic corroboration + roadmap to independent fusion.*

**Q: Real accuracy numbers?**
Don't invent them. If you have a held-out test number, quote it. If you don't, say: "We validated qualitatively on our test images; rigorous benchmarking on a larger labelled set is our immediate next step." Honesty reads as competence; a made-up "99%" gets shredded on the follow-up.

**Q: Is the Invest feature real trading?**
A: **No — it's a simulated paper-trading sandbox**, holdings persisted locally. No real money, no brokerage, by design. (Important to say plainly — never imply real trades.)

**Q: How many statement formats have you really tested?**
A: Be honest — Kotak + synthetic formats. Don't claim "all banks." Claim "bank-agnostic *method* (balance arithmetic), validated on Kotak, incremental from there."

**Q: Could the heatmap be misleading?**
A: Occlusion sensitivity is a legitimate, widely-used saliency method, but like all saliency it's an approximation of model attention, not a ground-truth explanation. We present it as "what the model focused on," not "the security features."

---

## 11. ROADMAP (have this ready — judges love forward vision)

- **Promote GLCM to an independent weighted vote** fused with the CNN (true multi-signal verdict).
- **Expand training data** across denominations + new note series; publish accuracy/precision/recall.
- **Add security-feature checks** (UV thread, watermark, intaglio) via guided capture.
- **More bank formats** + auto-format learning for statements.
- **Multi-statement trends** (month-over-month health, goals, alerts).
- **Android release** + accessibility (voice verdict for low-vision/elderly users).
- **Optional encrypted local vault** + explicit data controls (clear/export).
- **B2B SDK** — license on-device detection to retail POS / banks.

---

## 12. THE CLOSE (land it with conviction)

> "Phones today are powerful enough that you shouldn't have to upload your most sensitive data — your cash and your bank statements — to anyone's cloud to get value from it. CashGuard proves that: real AI counterfeit detection and real financial analysis, **fully on your device, private by design.** We didn't just build features — we built a principle you can hold in your hand."

---

## 13. RAPID-FIRE CHEAT SHEET (glance before you walk in)

- **What is it?** On-device counterfeit detection + financial health analysis. Privacy by design.
- **2 pillars:** Scan a note (AI + heatmap + OCR + texture) · Upload a statement (score + insights).
- **Killer tech 1:** Occlusion heatmap = explainable AI, 100 forward passes, shows what the model saw.
- **Killer tech 2:** Balance arithmetic = exact debit/credit recovery; flow classification = real savings rate.
- **Verdict thresholds:** ≥0.78 genuine, ≤0.22 fake, else uncertain. Novelty OCR → fake.
- **Score:** 5 dimensions, earned/available × 100, with a confidence %.
- **Privacy:** no account, no cloud; only network call = public crypto prices. DPDP by design.
- **Stack:** Flutter, onnxruntime (CNN), ML Kit OCR, GLCM, Syncfusion PDF, CoinGecko.
- **Don't overclaim:** GLCM corroborates (not independent yet); Invest is paper-trading; quote real accuracy or say "next step."
- **Offline:** both core features work with WiFi off — show it.
