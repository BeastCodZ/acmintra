# CashGuard — Trust your cash. Understand your money. Privately.

CashGuard is a privacy-first mobile companion for India that combines real-time counterfeit currency detection with on-device financial health analysis. No accounts. No cloud. Everything runs on your phone.

Built at ACM Intra Hackathon 2026.

---

## The Problem

India handles billions of cash transactions daily, yet counterfeit notes continue to circulate undetected at the point of exchange. At the same time, existing financial tools require cloud accounts and data-sharing — forcing users to choose between insights and privacy. CashGuard solves both without compromise.

---

## Two Pillars

### Pillar 1 — Counterfeit Detection

Point your camera at any Indian currency note. CashGuard returns a **Genuine / Fake / Uncertain** verdict in under 1 second — fully offline.

**How it works:**
- **EfficientNet-B0 CNN** trained on genuine and counterfeit Indian currency images, exported to ONNX and run on-device via `onnxruntime`
- **Occlusion heatmap** (explainable AI): 100 forward passes masking a 10×10 grid of regions — highlights which parts of the note (watermark, security thread, microprint) drove the verdict
- **GLCM texture forensics**: Gray-Level Co-occurrence Matrix extracts Haralick texture fingerprints at 3 distances × 4 angles on 128×128 grayscale patches — corroborates printing anomalies
- **On-device OCR** via Google ML Kit: detects novelty/prop-money signatures — mismatched serial fonts, missing microtext, suspicious typography
- **Cash calculator**: break any denomination into note and coin combinations

### Pillar 2 — Financial Health Analysis

Upload a bank or UPI statement PDF. Everything — parsing, classification, scoring — runs locally on your device.

**How it works:**
- **Balance-arithmetic parser**: reconstructs debit/credit direction from running balance deltas — works across all Indian bank statement formats including Kotak's cell-per-line Syncfusion extraction
- **Flow classification** (`income`, `refund`, `spend`, `transfer`, `investment`) with investment keyword matching for ASBA, AMC, broker names
- **0–100 health score** with a confidence rating derived from data coverage and parser certainty
- **Cash-flow breakdown**: animated income vs spend dual-tone bar, savings rate, net this period
- **Spend categories** with proportion bars, animated donut chart, and Catmull-Rom smooth trend chart
- **Recurring payment detection**, risk flags (overdraft risk, income instability, subscription leakage), and personalised insights
- **Staged 5-step loading screen** with animated checklist — parsing happens synchronously; the animation reflects real processing steps

**Privacy guarantee:** statement bytes never leave the device. No network call is made during analysis. Only public crypto prices are fetched (with explicit user intent).

---

## Repo Structure

```
acmintra/
├── cashguard_app/          # Flutter iOS app (primary deliverable)
│   ├── lib/
│   │   ├── screens/        # All app screens
│   │   ├── services/       # On-device inference, PDF parsing, crypto, invest
│   │   └── widgets/        # Custom charts, animations, loaders
│   ├── assets/
│   │   └── currency_classifier.onnx   # Quantised EfficientNet-B0
│   └── ios/                # Xcode project (signed for standalone deployment)
│
├── ml_models/              # Training outputs — confusion matrix, eval metrics, logs
├── ml_scripts/             # Dataset prep, training, evaluation, region analysis
│   ├── train.py            # EfficientNet-B0 fine-tune (PyTorch)
│   ├── evaluate.py         # Accuracy / F1 / confusion matrix
│   └── smart_merge_and_retrain.py   # Incremental dataset merge + retrain
│
├── backend/
│   ├── statement/          # FastAPI financial analysis backend (Python reference)
│   │   ├── parser.py       # PDF → transaction list
│   │   ├── categorizer.py  # Spend category classifier
│   │   ├── scoring.py      # Health score computation
│   │   ├── risk.py         # Risk flag detection
│   │   └── ai.py           # RAG-powered insight generation (Ollama)
│   ├── planner/            # Financial planner backend
│   └── reciept/            # Receipt AI parser
│
├── frontend/               # Next.js web companion (informational)
├── currency_classifier.onnx   # Model at repo root (mirror)
└── index.html              # Landing page
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart), iOS deployment |
| ML inference | ONNX Runtime (`onnxruntime` Flutter package) |
| PDF parsing | Syncfusion Flutter PDF |
| OCR | Google ML Kit Text Recognition |
| Camera | Flutter Camera + Image Picker |
| Model training | PyTorch, EfficientNet-B0, torchvision |
| Backend (reference) | FastAPI, pdfplumber, sentence-transformers, Ollama |
| Web frontend | Next.js, TypeScript |
| Charts | Custom `CustomPainter` — no chart library |

---

## Custom UI Components

All charts and animations are hand-coded — no third-party chart libraries.

| Widget | Description |
|---|---|
| `GaugeRing` | 270° animated arc with SweepGradient shader and glowing tip dot |
| `TrendAreaChart` | Catmull-Rom smooth dual-series area chart with animated draw-on reveal |
| `AnimatedDonut` | Sweeps on from top with rounded segment caps |
| `AnalysingView` | Staged 5-step checklist loader with pending → spinner → checkmark transitions |
| `FadeSlideIn` | Reusable fade + slide-up entry with configurable delay for staggered cascades |
| `CountUp` | Tween-driven number roll-up animation |
| `GrowBar` | Animated horizontal proportion bar |

---

## Getting Started

### Flutter App (iOS)

```bash
cd cashguard_app
flutter pub get
flutter run --release    # debug builds crash on device — always use release
```

Requires:
- Flutter 3.x
- Xcode 15+
- iOS device or simulator (primary target: iPhone)
- `onnxruntime` CocoaPod resolves via `pod install` automatically

### ML Training

```bash
pip install torch torchvision onnx onnxruntime pillow scikit-learn matplotlib
cd ml_scripts
python download_dataset.py    # pull training data
python train.py               # fine-tune EfficientNet-B0
python evaluate.py            # accuracy, F1, confusion matrix
```

Model achieves **94.6% accuracy** on the held-out test set.

### Backend (Reference)

```bash
cd backend/statement
pip install -r requirements.txt
uvicorn main:app --reload
```

The Python backend was the original parsing reference. All parsing logic has since been ported to Dart and runs fully on-device in the Flutter app.

---

## Privacy

CashGuard is designed to be compliant with India's **Digital Personal Data Protection Act 2023 (DPDP Act)**:

- No mandatory account or sign-up
- Bank statements are parsed in-memory on the device and never transmitted
- No analytics, crash reporting, or telemetry
- Only public cryptocurrency prices are fetched from CoinGecko — and only when the user opens the Finance tab
- Paper-trading invest feature is fully simulated — no real brokerage or money movement

---

## Model Performance

| Metric | Value |
|---|---|
| Test accuracy | 94.6% |
| Architecture | EfficientNet-B0 (quantised) |
| Input | 224×224 RGB |
| Output | Genuine / Fake / Uncertain |
| Inference time | < 1s on-device |

Confusion matrix and training logs are in `ml_models/`.

---

## Team

Built at ACM Intra Hackathon 2026.

- **ML & iOS integration** — Trained EfficientNet-B0, ONNX export, and wired the model into the Flutter inference pipeline
- **Financial analysis & PDF parsing** — Built the balance-arithmetic transaction parser, flow classifier, health scoring engine, and all on-device analysis logic
- **Frontend design & presentation** — Designed the app's UI/UX, dark design system, custom animated charts, and the hackathon pitch deck
