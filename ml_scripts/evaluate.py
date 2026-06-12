"""
Evaluate the saved model on the test set.
Run this instead of retraining when train.py crashes at evaluation.

Run: python3 scripts/evaluate.py
"""

import json
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from pathlib import Path

BASE_DIR    = Path(__file__).parent.parent
DATASET_DIR = BASE_DIR / "dataset"
MODEL_DIR   = BASE_DIR / "models"

IMG_SIZE             = (224, 224)
BATCH_SIZE           = 32
CONFIDENCE_THRESHOLD = 0.85
CLASS_NAMES          = ["fake", "genuine"]


def load_test_set():
    ds = tf.keras.utils.image_dataset_from_directory(
        str(DATASET_DIR / "test"),
        labels="inferred",
        label_mode="binary",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=False
    )
    AUTOTUNE = tf.data.AUTOTUNE
    return ds.map(lambda x, y: (tf.cast(x, tf.float32) / 255.0, y)).prefetch(AUTOTUNE)


def find_best_model():
    # Try stage2 first, then stage1, then final
    candidates = [
        MODEL_DIR / "best_stage2.keras",
        MODEL_DIR / "best_stage1.keras",
        MODEL_DIR / "currency_classifier_final.keras",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


if __name__ == "__main__":
    model_path = find_best_model()
    if not model_path:
        print("❌ No saved model found. Run train.py first.")
        exit(1)

    print(f"Loading model: {model_path.name}")
    model = tf.keras.models.load_model(model_path)

    print("Loading test set...")
    test_ds = load_test_set()

    print("Running evaluation...\n")
    results = model.evaluate(test_ds, verbose=1)
    metrics = dict(zip(model.metrics_names, results))
    print(f"\nMetric keys: {list(metrics.keys())}")
    for k, v in metrics.items():
        if "loss" in k:
            print(f"  {k}: {v:.4f}")
        else:
            print(f"  {k}: {v*100:.2f}%")

    # Full classification report
    y_true, y_pred_prob = [], []
    for images, labels in test_ds:
        probs = model.predict(images, verbose=0)
        y_pred_prob.extend(probs.flatten())
        y_true.extend(labels.numpy().astype(int).flatten())

    y_pred = [1 if p >= 0.5 else 0 for p in y_pred_prob]

    print("\nClassification Report:")
    print(classification_report(y_true, y_pred, target_names=CLASS_NAMES))

    # Confusion matrix
    cm = confusion_matrix(y_true, y_pred)
    plt.figure(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
                xticklabels=CLASS_NAMES, yticklabels=CLASS_NAMES)
    plt.title("CashGuard — Confusion Matrix")
    plt.ylabel("Actual"), plt.xlabel("Predicted")
    plt.tight_layout()
    plt.savefig(MODEL_DIR / "confusion_matrix.png", dpi=150)
    print(f"Saved: {MODEL_DIR}/confusion_matrix.png")

    # Save metrics
    uncertain = sum(1 for p in y_pred_prob if (1-CONFIDENCE_THRESHOLD) < p < CONFIDENCE_THRESHOLD)
    eval_out = {k: float(v) for k, v in metrics.items()}
    eval_out["uncertain_rate"] = uncertain / len(y_pred_prob)
    with open(MODEL_DIR / "eval_metrics.json", "w") as f:
        json.dump(eval_out, f, indent=2)
    print(f"Saved: {MODEL_DIR}/eval_metrics.json")

    # Also save final model
    final_path = MODEL_DIR / "currency_classifier_final.keras"
    if not final_path.exists():
        model.save(final_path)
        print(f"Saved: {final_path}")
