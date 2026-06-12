"""
Feature-aware counterfeit detection based on RBI security feature zones.
Crops each security region from the note and analyses them independently.

Regions defined for standard Indian currency note layout (front side):
All coordinates are in % of image dimensions (works for any resolution)
"""

import numpy as np
from PIL import Image, ImageFilter, ImageEnhance
from pathlib import Path

# ── Security Feature Regions (% of width/height) ─────────────────────────────
# Format: (left%, top%, right%, bottom%)
# Defined for ₹500 front face — same proportions work for ₹100, ₹200 too

REGIONS = {
    "watermark": {
        "crop": (0.02, 0.10, 0.22, 0.90),   # left strip — Gandhi watermark zone
        "description": "Gandhi watermark",
        "rbi_genuine":  "Clear Gandhi portrait with light/shade effect",
        "rbi_fake":     "Blurry, cartoon-like image",
        "weight": 0.30,   # how much this region contributes to final score
    },
    "security_thread": {
        "crop": (0.20, 0.05, 0.32, 0.95),   # vertical thread strip
        "description": "Security thread",
        "rbi_genuine":  "Continuous line, green→blue colour shift",
        "rbi_fake":     "Pasted silver paint, broken or missing",
        "weight": 0.25,
    },
    "number_panel": {
        "crop": (0.02, 0.02, 0.45, 0.20),   # top-left serial number area
        "description": "Number panel",
        "rbi_genuine":  "Fluorescent ink, bold, evenly spaced, unique font",
        "rbi_fake":     "Small size, uneven spacing, wrong font",
        "weight": 0.20,
    },
    "latent_image": {
        "crop": (0.55, 0.10, 0.72, 0.90),   # vertical band right of Gandhi portrait
        "description": "Latent image zone",
        "rbi_genuine":  "Clear denomination value visible at eye level",
        "rbi_fake":     "Missing or unclear denomination",
        "weight": 0.15,
    },
    "gandhi_portrait": {
        "crop": (0.30, 0.10, 0.65, 0.90),   # centre — Gandhi portrait
        "description": "Gandhi portrait",
        "rbi_genuine":  "Sharp intaglio print, raised texture",
        "rbi_fake":     "Flat printed, slightly blurry",
        "weight": 0.10,
    },
}


def crop_region(img: Image.Image, region_key: str) -> Image.Image:
    """Crop a security feature region from the note image."""
    region = REGIONS[region_key]
    l, t, r, b = region["crop"]
    w, h = img.size
    box = (int(l*w), int(t*h), int(r*w), int(b*h))
    return img.crop(box).resize((224, 224), Image.LANCZOS)


def preprocess_for_model(img: Image.Image) -> np.ndarray:
    """Convert PIL image to float32 numpy array for ONNX inference."""
    arr = np.array(img.convert("RGB"), dtype=np.float32)   # [224, 224, 3]
    return np.expand_dims(arr, axis=0)                      # [1, 224, 224, 3]


def analyse_regions(img: Image.Image, ort_session) -> dict:
    """
    Run the ONNX model on each security region separately.
    Returns per-region scores and a weighted final verdict.
    """
    results = {}
    weighted_sum = 0.0

    for region_key, region_info in REGIONS.items():
        # Crop and preprocess
        crop    = crop_region(img, region_key)
        tensor  = preprocess_for_model(crop)

        # Run inference
        input_name  = ort_session.get_inputs()[0].name
        output_name = ort_session.get_outputs()[0].name
        raw = float(ort_session.run([output_name], {input_name: tensor})[0][0][0])

        # raw: 0 = fake, 1 = genuine
        confidence  = raw if raw >= 0.5 else 1 - raw
        label       = "genuine" if raw >= 0.5 else "fake"

        results[region_key] = {
            "label":       label,
            "raw":         raw,
            "confidence":  confidence,
            "description": region_info["description"],
            "rbi_genuine": region_info["rbi_genuine"],
            "rbi_fake":    region_info["rbi_fake"],
            "weight":      region_info["weight"],
        }

        weighted_sum += raw * region_info["weight"]

    # Final verdict from weighted combination
    # Lower threshold since crops are noisier than full note
    THRESHOLD = 0.58
    if weighted_sum >= THRESHOLD:
        final_label = "genuine"
        final_conf  = weighted_sum
    elif weighted_sum <= (1 - THRESHOLD):
        final_label = "fake"
        final_conf  = 1 - weighted_sum
    else:
        final_label = "uncertain"
        final_conf  = max(weighted_sum, 1 - weighted_sum)

    # Which regions failed? (lower confidence bar for explanation)
    failed_regions = [
        k for k, v in results.items()
        if v["label"] == "fake" and v["confidence"] > 0.55
    ]

    return {
        "final_label":    final_label,
        "final_conf":     final_conf,
        "weighted_score": weighted_sum,
        "regions":        results,
        "failed_regions": failed_regions,
    }


def format_verdict(analysis: dict) -> str:
    """Human-readable verdict for terminal testing."""
    label = analysis["final_label"].upper()
    conf  = analysis["final_conf"] * 100
    score = analysis["weighted_score"]

    lines = [
        f"\n{'='*55}",
        f"  VERDICT: {label}  ({conf:.1f}% confidence)",
        f"  Weighted score: {score:.3f}  (>0.75 = genuine)",
        f"{'='*55}",
    ]

    for key, r in analysis["regions"].items():
        icon  = "✅" if r["label"] == "genuine" else "❌"
        lines.append(
            f"  {icon} {r['description']:<22} {r['label'].upper():<10} {r['confidence']*100:.1f}%"
        )

    if analysis["failed_regions"]:
        lines.append(f"\n  ⚠️  Failed features: {', '.join(analysis['failed_regions'])}")

    lines.append("="*55)
    return "\n".join(lines)


# ── CLI test ──────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import sys, onnxruntime as rt

    if len(sys.argv) < 2:
        print("Usage: python3 scripts/region_analysis.py <image_path>")
        sys.exit(1)

    model_path = Path(__file__).parent.parent / "models" / "currency_classifier.onnx"
    if not model_path.exists():
        print(f"❌ Model not found: {model_path}")
        sys.exit(1)

    print("Loading model...")
    session = rt.InferenceSession(str(model_path))

    img = Image.open(sys.argv[1]).convert("RGB")
    print(f"Image: {sys.argv[1]}  ({img.size})")

    analysis = analyse_regions(img, session)
    print(format_verdict(analysis))
