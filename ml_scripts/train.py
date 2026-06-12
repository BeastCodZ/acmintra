"""
Step 3 — Model Training
Trains MobileNetV3-Small on currency dataset using M4 GPU (tensorflow-metal).
Two-stage training: head only → fine-tune.

Run: python3 scripts/train.py
Expected time on M4 16GB: 8–12 minutes
"""

import os
import sys
import json
import time
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import tensorflow as tf
from tensorflow.keras import layers, callbacks
from tensorflow.keras.applications import EfficientNetB0
from sklearn.metrics import classification_report, confusion_matrix
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR    = Path(__file__).parent.parent
DATASET_DIR = BASE_DIR / "dataset"
MODEL_DIR   = BASE_DIR / "models"
MODEL_DIR.mkdir(exist_ok=True)

# ── Hyperparameters ───────────────────────────────────────────────────────────
IMG_SIZE      = (224, 224)
BATCH_SIZE    = 32
EPOCHS_HEAD   = 8
EPOCHS_FINE   = 15
DROPOUT       = 0.4
DENSE_UNITS   = 256
CONFIDENCE_THRESHOLD = 0.80

# Focal loss gamma — higher = more focus on hard/misclassified examples
FOCAL_GAMMA = 2.0
FOCAL_ALPHA = 0.5   # 0.5 = equal weight to both classes


# ── GPU Check ─────────────────────────────────────────────────────────────────
def check_gpu():
    gpus = tf.config.list_physical_devices('GPU')
    if gpus:
        print(f"✅ M4 GPU detected: {gpus}")
        # Allow memory growth — prevents TF from grabbing all 16GB at once
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
    else:
        print("⚠️  No GPU found — training on CPU (slower but works)")
    print(f"TensorFlow: {tf.__version__}\n")


# ── Data Augmentation Pipeline ────────────────────────────────────────────────
# Simulates real-world phone camera conditions
def build_augmentation():
    return tf.keras.Sequential([
        layers.RandomFlip("horizontal"),
        layers.RandomRotation(0.12),          # phone held at angle
        layers.RandomZoom(0.10),              # zoom in/out
        layers.RandomBrightness(0.25),        # different lighting
        layers.RandomContrast(0.20),          # shadows, glare
        layers.GaussianNoise(0.015),          # camera sensor noise
    ], name="augmentation")


# ── Dataset Loaders ───────────────────────────────────────────────────────────
def load_split(split: str):
    path = DATASET_DIR / split
    if not path.exists():
        print(f"❌ Dataset split not found: {path}")
        print("   Run python3 scripts/prepare_dataset.py first")
        sys.exit(1)

    ds = tf.keras.utils.image_dataset_from_directory(
        str(path),
        labels="inferred",
        label_mode="binary",      # 0=fake, 1=genuine (alphabetical order)
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=(split == "train"),
        seed=42
    )
    return ds


def preprocess(image, label):
    """EfficientNet includes its own preprocessing — just cast to float32."""
    return tf.cast(image, tf.float32), label


def balance_directory():
    """
    Hard undersample: copy equal numbers of fake/genuine into dataset/balanced/
    so image_dataset_from_directory loads a perfectly 50/50 split.
    Only runs once — skips if already done.
    """
    import shutil, random
    balanced_dir = DATASET_DIR / "balanced" / "train"
    if (balanced_dir / "fake").exists() and len(list((balanced_dir / "fake").glob("*"))) > 100:
        print("  Balanced dataset already exists, skipping.")
        return

    fake_src    = DATASET_DIR / "train" / "fake"
    genuine_src = DATASET_DIR / "train" / "genuine"

    fake_imgs    = list(fake_src.glob("*.*"))
    genuine_imgs = list(genuine_src.glob("*.*"))

    n = min(len(fake_imgs), len(genuine_imgs))
    random.seed(42)
    fake_imgs    = random.sample(fake_imgs, n)
    genuine_imgs = random.sample(genuine_imgs, n)

    for label, imgs in [("fake", fake_imgs), ("genuine", genuine_imgs)]:
        dest = balanced_dir / label
        dest.mkdir(parents=True, exist_ok=True)
        for img in imgs:
            shutil.copy2(img, dest / img.name)

    print(f"  Balanced training set: {n} fake + {n} genuine = {n*2} total")


def build_datasets():
    AUTOTUNE = tf.data.AUTOTUNE
    augment  = build_augmentation()

    # Balance first
    print("Balancing dataset...")
    balance_directory()

    # Load balanced train, original val/test
    balanced_train_raw = tf.keras.utils.image_dataset_from_directory(
        str(DATASET_DIR / "balanced" / "train"),
        labels="inferred",
        label_mode="binary",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=True,
        seed=42
    )
    val_raw  = load_split("val")
    test_raw = load_split("test")

    class_names = balanced_train_raw.class_names
    print(f"Classes: {class_names}  (0={class_names[0]}, 1={class_names[1]})")
    assert class_names[0] == "fake",    "Expected class 0 = fake"
    assert class_names[1] == "genuine", "Expected class 1 = genuine"

    train_ds = (balanced_train_raw
        .map(preprocess, num_parallel_calls=AUTOTUNE)
        .map(lambda x, y: (augment(x, training=True), y), num_parallel_calls=AUTOTUNE)
        .cache()
        .prefetch(AUTOTUNE))

    val_ds = (val_raw
        .map(preprocess, num_parallel_calls=AUTOTUNE)
        .cache()
        .prefetch(AUTOTUNE))

    test_ds = (test_raw
        .map(preprocess, num_parallel_calls=AUTOTUNE)
        .prefetch(AUTOTUNE))

    return train_ds, val_ds, test_ds


# ── Focal Loss ────────────────────────────────────────────────────────────────
def focal_loss(gamma=FOCAL_GAMMA, alpha=FOCAL_ALPHA):
    """
    Focal loss: down-weights easy examples so the model focuses on hard ones.
    Critical when classes are visually similar (genuine vs high-quality fake notes).
    FL(p) = -alpha * (1-p)^gamma * log(p)
    """
    def loss_fn(y_true, y_pred):
        y_pred   = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)
        bce      = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)
        p_t      = y_true * y_pred + (1 - y_true) * (1 - y_pred)
        fl       = alpha * tf.pow(1 - p_t, gamma) * bce
        return tf.reduce_mean(fl)
    return loss_fn


# ── Model Architecture ────────────────────────────────────────────────────────
def build_model(trainable_base: bool = False) -> tf.keras.Model:
    """
    EfficientNetB0 backbone — better accuracy than MobileNetV3 for fine-grained
    visual tasks like currency authentication.
    Note: EfficientNet includes its own preprocessing (expects [0,255] inputs).
    """
    base = EfficientNetB0(
        input_shape=(*IMG_SIZE, 3),
        include_top=False,
        weights="imagenet"
        # No include_preprocessing param — EfficientNet handles it internally
    )
    base.trainable = trainable_base

    inputs = tf.keras.Input(shape=(*IMG_SIZE, 3), name="input_image")
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D(name="gap")(x)
    x = layers.BatchNormalization(name="bn")(x)
    x = layers.Dropout(DROPOUT, name="dropout_1")(x)
    x = layers.Dense(DENSE_UNITS, activation="relu", name="dense_features")(x)
    x = layers.Dropout(DROPOUT * 0.5, name="dropout_2")(x)
    output = layers.Dense(1, activation="sigmoid", name="output")(x)

    return tf.keras.Model(inputs, output, name="CashGuard_CurrencyClassifier")


# ── Callbacks ─────────────────────────────────────────────────────────────────
def get_callbacks(stage: int):
    monitor = "val_loss"
    return [
        callbacks.EarlyStopping(
            monitor=monitor,
            patience=4,
            restore_best_weights=True,
            mode="min",
            verbose=1
        ),
        callbacks.ModelCheckpoint(
            str(MODEL_DIR / f"best_stage{stage}.keras"),
            monitor=monitor,
            save_best_only=True,
            mode="min",
            verbose=0
        ),
        callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.4,
            patience=2,
            min_lr=1e-7,
            verbose=1
        ),
        callbacks.CSVLogger(str(MODEL_DIR / f"training_log_stage{stage}.csv")),
    ]


# ── Training ──────────────────────────────────────────────────────────────────
def train_stage1(train_ds, val_ds) -> tf.keras.Model:
    print("\n" + "="*55)
    print("  STAGE 1 — Training classifier head (base frozen)")
    print("="*55)

    model = build_model(trainable_base=False)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=5e-4),
        loss=focal_loss(),
        metrics=[
            "accuracy",
            tf.keras.metrics.Recall(name="recall"),
            tf.keras.metrics.Precision(name="precision"),
            tf.keras.metrics.AUC(name="auc"),
        ]
    )
    model.summary(show_trainable=True)

    t0 = time.time()
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS_HEAD,
        callbacks=get_callbacks(1),
        verbose=1
    )
    print(f"\nStage 1 done in {(time.time()-t0)/60:.1f} min")
    return model


def train_stage2(model: tf.keras.Model, train_ds, val_ds) -> tf.keras.Model:
    print("\n" + "="*55)
    print("  STAGE 2 — Fine-tuning (last 30 layers unfrozen)")
    print("="*55)

    # Unfreeze backbone
    model.layers[1].trainable = True
    # Re-freeze early layers (low-level features don't need updating)
    for layer in model.layers[1].layers[:-30]:
        layer.trainable = False

    trainable = sum(v.numpy().size for v in model.trainable_variables)
    print(f"Trainable parameters: {trainable:,}")

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=5e-5),
        loss=focal_loss(),
        metrics=[
            "accuracy",
            tf.keras.metrics.Recall(name="recall"),
            tf.keras.metrics.Precision(name="precision"),
            tf.keras.metrics.AUC(name="auc"),
        ]
    )

    t0 = time.time()
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS_FINE,
        callbacks=get_callbacks(2),
        verbose=1
    )
    print(f"\nStage 2 done in {(time.time()-t0)/60:.1f} min")
    return model


# ── Evaluation ────────────────────────────────────────────────────────────────
def evaluate(model: tf.keras.Model, test_ds, class_names):
    print("\n" + "="*55)
    print("  EVALUATION ON TEST SET")
    print("="*55)

    results = model.evaluate(test_ds, verbose=1)
    metrics = dict(zip(model.metrics_names, results))

    print(f"\nAll metrics returned: {list(metrics.keys())}")

    # Flexible key lookup — handles TF version differences
    def get_metric(d, *keys):
        for k in keys:
            for dk in d:
                if dk == k or dk.endswith(f"_{k}") or dk.endswith(f"/{k}"):
                    return d[dk]
        return None

    acc  = get_metric(metrics, "accuracy", "acc")
    rec  = get_metric(metrics, "recall")
    prec = get_metric(metrics, "precision")
    auc  = get_metric(metrics, "auc")

    if acc:  print(f"\n  Accuracy:  {acc*100:.2f}%")
    if rec:  print(f"  Recall:    {rec*100:.2f}%   ← catch fakes (most important)")
    if prec: print(f"  Precision: {prec*100:.2f}%")
    if auc:  print(f"  AUC:       {auc:.4f}")

    # Confusion matrix
    y_true, y_pred_prob = [], []
    for images, labels in test_ds:
        probs = model.predict(images, verbose=0)
        y_pred_prob.extend(probs.flatten())
        y_true.extend(labels.numpy().astype(int).flatten())

    y_pred = [1 if p >= 0.5 else 0 for p in y_pred_prob]

    print("\nClassification Report:")
    print(classification_report(y_true, y_pred, target_names=class_names))

    # Plot confusion matrix
    cm = confusion_matrix(y_true, y_pred)
    plt.figure(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
                xticklabels=class_names, yticklabels=class_names)
    plt.title("CashGuard — Confusion Matrix")
    plt.ylabel("Actual"), plt.xlabel("Predicted")
    plt.tight_layout()
    cm_path = MODEL_DIR / "confusion_matrix.png"
    plt.savefig(cm_path, dpi=150)
    print(f"\nSaved: {cm_path}")

    # Confidence distribution
    plt.figure(figsize=(8, 4))
    genuine_confs = [p for p, t in zip(y_pred_prob, y_true) if t == 1]
    fake_confs    = [p for p, t in zip(y_pred_prob, y_true) if t == 0]
    plt.hist(genuine_confs, bins=30, alpha=0.7, color="green", label="Genuine")
    plt.hist(fake_confs,    bins=30, alpha=0.7, color="red",   label="Fake")
    plt.axvline(x=CONFIDENCE_THRESHOLD, color="orange", linestyle="--",
                label=f"Threshold ({CONFIDENCE_THRESHOLD})")
    plt.axvline(x=1-CONFIDENCE_THRESHOLD, color="orange", linestyle="--")
    plt.title("Prediction Confidence Distribution")
    plt.xlabel("Model Output (0=Fake, 1=Genuine)")
    plt.ylabel("Count")
    plt.legend()
    plt.tight_layout()
    dist_path = MODEL_DIR / "confidence_distribution.png"
    plt.savefig(dist_path, dpi=150)
    print(f"Saved: {dist_path}")

    # Count uncertain predictions
    uncertain = sum(1 for p in y_pred_prob
                    if (1 - CONFIDENCE_THRESHOLD) < p < CONFIDENCE_THRESHOLD)
    print(f"\n  Uncertain predictions: {uncertain}/{len(y_pred_prob)} "
          f"({uncertain/len(y_pred_prob)*100:.1f}%) → shown as ⚠️  in UI")

    # Save metrics to JSON for later reference
    metrics["uncertain_rate"] = uncertain / len(y_pred_prob)
    with open(MODEL_DIR / "eval_metrics.json", "w") as f:
        json.dump({k: float(v) for k, v in metrics.items()}, f, indent=2)

    return metrics


# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    total_start = time.time()

    check_gpu()

    print("Loading datasets...")
    train_ds, val_ds, test_ds = build_datasets()

    # Stage 1 — head only
    model = train_stage1(train_ds, val_ds)

    # Stage 2 — fine-tune
    model = train_stage2(model, train_ds, val_ds)

    # Evaluate
    class_names = ["fake", "genuine"]
    metrics = evaluate(model, test_ds, class_names)

    # Save final model
    final_path = MODEL_DIR / "currency_classifier_final.keras"
    model.save(final_path)
    print(f"\n✅ Model saved: {final_path}")

    total_time = (time.time() - total_start) / 60
    print(f"⏱  Total training time: {total_time:.1f} minutes")
    print("\n📁 Next step: python3 scripts/convert_to_tfjs.py")
