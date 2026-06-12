"""
Quick test — run inference on a single image to verify the model works.

Usage:
  python3 scripts/test_single_image.py path/to/note.jpg
  python3 scripts/test_single_image.py  ← tests on first image in test set
"""

import sys
import os
import numpy as np
import tensorflow as tf
from PIL import Image
from pathlib import Path

BASE_DIR  = Path(__file__).parent.parent
MODEL_DIR = BASE_DIR / "models"
DATASET_DIR = BASE_DIR / "dataset"

IMG_SIZE             = (224, 224)
CONFIDENCE_THRESHOLD = 0.85


def predict(image_path: str):
    # Load model
    model_path = MODEL_DIR / "currency_classifier_final.keras"
    if not model_path.exists():
        print(f"❌ Model not found at {model_path}")
        sys.exit(1)

    model = tf.keras.models.load_model(model_path)

    # Load and preprocess image
    img = Image.open(image_path).convert("RGB").resize(IMG_SIZE)
    tensor = np.expand_dims(np.array(img, dtype=np.float32) / 255.0, axis=0)

    # Run inference
    import time
    t0 = time.time()
    raw = float(model.predict(tensor, verbose=0)[0][0])
    latency_ms = (time.time() - t0) * 1000

    # Interpret
    # raw = 0.0 → definitely fake
    # raw = 1.0 → definitely genuine
    if raw >= CONFIDENCE_THRESHOLD:
        label      = "GENUINE"
        confidence = raw
        emoji      = "✅"
    elif raw <= (1 - CONFIDENCE_THRESHOLD):
        label      = "FAKE"
        confidence = 1 - raw
        emoji      = "❌"
    else:
        label      = "UNCERTAIN"
        confidence = max(raw, 1 - raw)
        emoji      = "⚠️ "

    print(f"\n{'='*45}")
    print(f"  Image:      {os.path.basename(image_path)}")
    print(f"  Result:     {emoji}  {label}")
    print(f"  Confidence: {confidence*100:.1f}%")
    print(f"  Raw output: {raw:.4f}  (0=fake, 1=genuine)")
    print(f"  Latency:    {latency_ms:.1f}ms")
    print(f"{'='*45}\n")

    return label, confidence


if __name__ == "__main__":
    if len(sys.argv) > 1:
        image_path = sys.argv[1]
    else:
        # Use first available test image
        for label in ["genuine", "fake"]:
            test_dir = DATASET_DIR / "test" / label
            if test_dir.exists():
                imgs = list(test_dir.glob("*.jpg")) + list(test_dir.glob("*.png"))
                if imgs:
                    image_path = str(imgs[0])
                    print(f"No image specified — using: {image_path}")
                    break
        else:
            print("No test images found. Run: python3 scripts/test_single_image.py <image_path>")
            sys.exit(1)

    predict(image_path)
