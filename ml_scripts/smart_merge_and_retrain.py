"""
CashGuard — Smart Dataset Merge + Retrain
==========================================
1. Scans ALL data sources (old + new downloads)
2. Classifies each image as fake or genuine
3. Deduplicates by MD5 hash (removes exact copies)
4. Filters out tiny images (<150px)
5. Skips pre-augmented & PKR data
6. Rebuilds clean train/val/test splits
7. Retrains model with improved config
"""

import os
import sys
import shutil
import hashlib
import random
import json
import time
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path
from PIL import Image
import tensorflow as tf

# ── GPU config MUST happen before any TF operations ───────────────────────────
gpus = tf.config.list_physical_devices("GPU")
if gpus:
    for g in gpus:
        try:
            tf.config.experimental.set_memory_growth(g, True)
        except RuntimeError:
            pass
    print(f"✅ GPU: {gpus}")
else:
    print("⚠️  No GPU — training on CPU")
from tensorflow.keras import layers, callbacks
from tensorflow.keras.applications import EfficientNetB0
from sklearn.metrics import classification_report, confusion_matrix
import seaborn as sns

random.seed(42)
np.random.seed(42)

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE_DIR     = Path(__file__).parent.parent
RAW_DIR      = BASE_DIR / "dataset" / "raw"
DATASET_DIR  = BASE_DIR / "dataset"
CLEAN_DIR    = BASE_DIR / "dataset" / "clean"   # fresh clean dataset
MODEL_DIR    = BASE_DIR / "models"
DOWNLOADS    = RAW_DIR / "new_downloads"
MODEL_DIR.mkdir(exist_ok=True)

# ── Hyperparameters ───────────────────────────────────────────────────────────
IMG_SIZE    = (224, 224)
BATCH_SIZE  = 32
EPOCHS_HEAD = 10
EPOCHS_FINE = 20
MIN_DIM     = 150         # reject images smaller than this in any dimension
SPLIT       = (0.70, 0.15, 0.15)
FOCAL_GAMMA = 2.0
FOCAL_ALPHA = 0.6         # slightly biased to penalise missed fakes

print("=" * 60)
print("  CashGuard — Smart Dataset Merge + Retrain")
print("=" * 60)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: COLLECT ALL IMAGES WITH LABELS
# ─────────────────────────────────────────────────────────────────────────────

def is_image(p: Path) -> bool:
    return p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

def md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()

def valid_image(path: Path) -> bool:
    try:
        img = Image.open(path).convert("RGB")
        w, h = img.size
        if w < MIN_DIM or h < MIN_DIM:
            return False
        return True
    except:
        return False

print("\n📂 STEP 1: Collecting images from all sources...\n")

all_images = {"fake": [], "genuine": []}
source_counts = {}

def add_images(label: str, folder: Path, source_name: str, recursive: bool = True):
    """Add all valid images from folder to the collection."""
    if not folder.exists():
        return 0
    pat = "**/*" if recursive else "*"
    imgs = [p for p in folder.glob(pat) if p.is_file() and is_image(p)]
    added = 0
    for p in imgs:
        if valid_image(p):
            all_images[label].append(p)
            added += 1
    if added:
        key = f"{label}/{source_name}"
        source_counts[key] = source_counts.get(key, 0) + added
    return added

# ── OLD DATA ──────────────────────────────────────────────────────────────────

# Kaggle main dataset (7 denominations)
for denom in ["10", "20", "50", "100", "200", "500", "2000"]:
    add_images("genuine", RAW_DIR / "kaggle/data/data/real" / denom, f"kaggle_real_{denom}")
    add_images("fake",    RAW_DIR / "kaggle/data/data/fake" / denom, f"kaggle_fake_{denom}")

# Extra detection dataset (balanced, good quality)
for split in ["training", "testing", "validation"]:
    add_images("genuine", RAW_DIR / "extra_detection/dataset" / split / "real", f"detection_{split}_real")
    add_images("fake",    RAW_DIR / "extra_detection/dataset" / split / "fake", f"detection_{split}_fake")

# Extra 500 — ORIGINALS ONLY (skip pre-augmented folders)
add_images("genuine", RAW_DIR / "extra_500/indian currency/REAL 500",       "extra500_real")
add_images("fake",    RAW_DIR / "extra_500/indian currency/FAKE 500",        "extra500_fake")
# SKIP: "real 500 AUGUMENTED" and "FAKE 500  AUGUMENTED" — pre-augmented = noise

# Manual photos (small but authentic)
add_images("genuine", RAW_DIR / "manual/genuine", "manual_genuine")
add_images("fake",    RAW_DIR / "manual_fakes",   "manual_fake")

# SKIP: pkr_fake — Pakistani Rupees, wrong currency

# ── NEW DOWNLOADS ─────────────────────────────────────────────────────────────

# Gaurav — all genuine notes (Train + Test by denomination)
for split in ["Train", "Test"]:
    for denom_dir in (DOWNLOADS / "gaurav" / split).iterdir() if (DOWNLOADS / "gaurav" / split).exists() else []:
        if denom_dir.is_dir():
            add_images("genuine", denom_dir, f"gaurav_{split}_{denom_dir.name}")

# INR 500 originals only (new copy of same source — dedup will handle overlap)
add_images("genuine", DOWNLOADS / "inr500/indian currency/REAL 500",      "inr500_real")
add_images("fake",    DOWNLOADS / "inr500/indian currency/FAKE 500",       "inr500_fake")
# SKIP augmented variants

# Lekhan — 500_dataset and 2000_dataset (genuine scans, named *_s*.jpg)
add_images("genuine", DOWNLOADS / "lekhan/Dataset/500_dataset",  "lekhan_500_genuine")
add_images("genuine", DOWNLOADS / "lekhan/Dataset/2000_dataset", "lekhan_2000_genuine")
# SKIP Features Dataset folders — they're cropped feature patches, not whole notes

# Sreehari — 500_dataset / 2000_dataset = genuine; Fake Notes = fake
add_images("genuine", DOWNLOADS / "sreehari/Dataset/500_dataset",             "sreehari_500_genuine")
add_images("genuine", DOWNLOADS / "sreehari/Dataset/2000_dataset",            "sreehari_2000_genuine")
add_images("fake",    DOWNLOADS / "sreehari/Dataset/Fake Notes/500",          "sreehari_fake_500")
add_images("fake",    DOWNLOADS / "sreehari/Dataset/Fake Notes/2000",         "sreehari_fake_2000")
# SKIP Features Dataset — cropped patches

# Playatanu — YOLO detection dataset, all images are genuine notes
add_images("genuine", DOWNLOADS / "playatanu/Indian currency/train/images", "playatanu_genuine")
add_images("genuine", DOWNLOADS / "playatanu/Indian currency/valid/images", "playatanu_genuine")
add_images("genuine", DOWNLOADS / "playatanu/Indian currency/test/images",  "playatanu_genuine")

# ── PREETRANK (THE BIG ONE — 7.7GB) ──────────────────────────────────────────
# Auto-detect fake/genuine from folder names
preetrank_dir = DOWNLOADS / "preetrank"
if preetrank_dir.exists():
    for folder in sorted(preetrank_dir.rglob("*")):
        if not folder.is_dir():
            continue
        name_lower = folder.name.lower()
        parent_lower = str(folder.parent).lower()
        if any(x in name_lower for x in ["fake", "counterfeit", "forged", "false"]):
            add_images("fake", folder, f"preetrank_{folder.name}", recursive=False)
        elif any(x in name_lower for x in ["real", "genuine", "original", "authentic"]):
            add_images("genuine", folder, f"preetrank_{folder.name}", recursive=False)
        elif any(x in parent_lower for x in ["fake", "counterfeit"]):
            add_images("fake", folder, f"preetrank_sub_{folder.name}", recursive=False)
        elif any(x in parent_lower for x in ["real", "genuine"]):
            add_images("genuine", folder, f"preetrank_sub_{folder.name}", recursive=False)
    total_preet = sum(1 for k in source_counts if "preetrank" in k
                      for _ in range(source_counts[k]))
    print(f"  preetrank total: {total_preet} images added")
else:
    print("  ⏳ preetrank not downloaded yet — skipping")

print("Raw collection (before dedup):")
for label in ["genuine", "fake"]:
    print(f"  {label}: {len(all_images[label])} images")

print("\nBy source:")
for k, v in sorted(source_counts.items()):
    print(f"  {k}: {v}")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: DEDUPLICATE BY MD5 HASH
# ─────────────────────────────────────────────────────────────────────────────

print("\n🔍 STEP 2: Deduplicating by MD5 hash...")

deduped = {"fake": [], "genuine": []}
seen_hashes = set()
dupes_removed = 0

for label in ["genuine", "fake"]:
    for p in all_images[label]:
        h = md5(p)
        if h not in seen_hashes:
            seen_hashes.add(h)
            deduped[label].append(p)
        else:
            dupes_removed += 1

print(f"  Duplicates removed: {dupes_removed}")
print(f"  Genuine after dedup: {len(deduped['genuine'])}")
print(f"  Fake after dedup:    {len(deduped['fake'])}")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: BUILD CLEAN DATASET (train/val/test splits)
# ─────────────────────────────────────────────────────────────────────────────

print("\n🗂  STEP 3: Building clean dataset with train/val/test splits...")

# Wipe old clean dir
if CLEAN_DIR.exists():
    shutil.rmtree(CLEAN_DIR)

for split in ["train", "val", "test"]:
    for label in ["genuine", "fake"]:
        (CLEAN_DIR / split / label).mkdir(parents=True, exist_ok=True)

def split_and_copy(images, label):
    random.shuffle(images)
    n = len(images)
    t = int(n * SPLIT[0])
    v = int(n * (SPLIT[0] + SPLIT[1]))
    splits = {"train": images[:t], "val": images[t:v], "test": images[v:]}
    counts = {}
    for split_name, imgs in splits.items():
        dest = CLEAN_DIR / split_name / label
        for i, src in enumerate(imgs):
            ext = src.suffix.lower()
            dst = dest / f"{label}_{i:05d}{ext}"
            shutil.copy2(src, dst)
        counts[split_name] = len(imgs)
    return counts

counts_g = split_and_copy(deduped["genuine"], "genuine")
counts_f = split_and_copy(deduped["fake"], "fake")

print(f"\n  {'Split':<10} {'Genuine':<12} {'Fake':<12} {'Total':<10} {'Balance'}")
print("  " + "-" * 55)
for s in ["train", "val", "test"]:
    g, f = counts_g[s], counts_f[s]
    ratio = f"1:{g/f:.1f}" if f > 0 else "N/A"
    print(f"  {s:<10} {g:<12} {f:<12} {g+f:<10} {ratio}")
total_g = sum(counts_g.values())
total_f = sum(counts_f.values())
print(f"  {'TOTAL':<10} {total_g:<12} {total_f:<12} {total_g+total_f:<10}")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: COMPUTE CLASS WEIGHTS (no throwing away data)
# ─────────────────────────────────────────────────────────────────────────────

n_fake    = counts_f["train"]
n_genuine = counts_g["train"]
n_total   = n_fake + n_genuine

# class 0 = fake, class 1 = genuine
weight_fake    = n_total / (2.0 * n_fake)
weight_genuine = n_total / (2.0 * n_genuine)
class_weights  = {0: weight_fake, 1: weight_genuine}

print(f"\n⚖️  Class weights: fake={weight_fake:.3f}, genuine={weight_genuine:.3f}")
print("   (Model will pay more attention to underrepresented class)")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: BUILD TF DATASETS
# ─────────────────────────────────────────────────────────────────────────────

print("\n⚙️  STEP 5: Building TF datasets...")

AUTOTUNE  = tf.data.AUTOTUNE

def load_split_ds(split: str):
    return tf.keras.utils.image_dataset_from_directory(
        str(CLEAN_DIR / split),
        labels="inferred",
        label_mode="binary",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=(split == "train"),
        seed=42
    )

raw_train = load_split_ds("train")
raw_val   = load_split_ds("val")
raw_test  = load_split_ds("test")

class_names = raw_train.class_names
print(f"  Classes: {class_names}  (0={class_names[0]}, 1={class_names[1]})")
assert class_names[0] == "fake",    "Expected class 0 = fake"
assert class_names[1] == "genuine", "Expected class 1 = genuine"

# Augmentation
augment = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.15),
    layers.RandomZoom(0.15),
    layers.RandomBrightness(0.3),
    layers.RandomContrast(0.25),
    layers.RandomTranslation(0.1, 0.1),
    layers.GaussianNoise(0.02),
], name="augmentation")

def preprocess(x, y):
    return tf.cast(x, tf.float32), y

train_ds = (raw_train
    .map(preprocess, num_parallel_calls=AUTOTUNE)
    .map(lambda x, y: (augment(x, training=True), y), num_parallel_calls=AUTOTUNE)
    .cache().prefetch(AUTOTUNE))

val_ds = (raw_val
    .map(preprocess, num_parallel_calls=AUTOTUNE)
    .cache().prefetch(AUTOTUNE))

test_ds = (raw_test
    .map(preprocess, num_parallel_calls=AUTOTUNE)
    .prefetch(AUTOTUNE))

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6: MODEL + LOSS
# ─────────────────────────────────────────────────────────────────────────────

def focal_loss(gamma=FOCAL_GAMMA, alpha=FOCAL_ALPHA):
    def loss_fn(y_true, y_pred):
        y_pred  = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)
        # Label smoothing 0.05
        y_true  = y_true * 0.95 + 0.025
        bce     = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)
        p_t     = y_true * y_pred + (1 - y_true) * (1 - y_pred)
        fl      = alpha * tf.pow(1 - p_t, gamma) * bce
        return tf.reduce_mean(fl)
    return loss_fn

def build_model(trainable_base=False):
    base = EfficientNetB0(
        input_shape=(*IMG_SIZE, 3),
        include_top=False,
        weights="imagenet"
    )
    base.trainable = trainable_base
    inputs = tf.keras.Input(shape=(*IMG_SIZE, 3), name="input")
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(256, activation="relu")(x)
    out = layers.Dense(1, activation="sigmoid", name="output")(x)
    return tf.keras.Model(inputs, out, name="CashGuard_v2")

METRICS = [
    "accuracy",
    tf.keras.metrics.Recall(name="recall"),
    tf.keras.metrics.Precision(name="precision"),
    tf.keras.metrics.AUC(name="auc"),
]

def get_callbacks(stage):
    return [
        callbacks.EarlyStopping(monitor="val_loss", patience=6,
                                restore_best_weights=True, verbose=1),
        callbacks.ModelCheckpoint(
            str(MODEL_DIR / f"best_stage{stage}_v2.keras"),
            monitor="val_loss", save_best_only=True, verbose=0),
        callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.4,
                                    patience=3, min_lr=1e-7, verbose=1),
        callbacks.CSVLogger(str(MODEL_DIR / f"training_log_stage{stage}_v2.csv")),
    ]

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7: TRAIN
# ─────────────────────────────────────────────────────────────────────────────

print(f"\n🚀 Starting training...")


print(f"\n{'='*60}")
print("  STAGE 1 — Head only (base frozen)")
print(f"{'='*60}")
model = build_model(trainable_base=False)
model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
              loss=focal_loss(), metrics=METRICS)
model.summary(show_trainable=True)

t0 = time.time()
model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_HEAD,
          class_weight=class_weights, callbacks=get_callbacks(1), verbose=1)
print(f"Stage 1 done in {(time.time()-t0)/60:.1f} min")

print(f"\n{'='*60}")
print("  STAGE 2 — Fine-tune (last 50 layers unfrozen)")
print(f"{'='*60}")
model.layers[1].trainable = True
for layer in model.layers[1].layers[:-50]:
    layer.trainable = False

trainable_params = sum(v.numpy().size for v in model.trainable_variables)
print(f"Trainable params: {trainable_params:,}")

model.compile(
    optimizer=tf.keras.optimizers.AdamW(learning_rate=5e-5, weight_decay=1e-4),
    loss=focal_loss(), metrics=METRICS)

t0 = time.time()
model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_FINE,
          class_weight=class_weights, callbacks=get_callbacks(2), verbose=1)
print(f"Stage 2 done in {(time.time()-t0)/60:.1f} min")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8: EVALUATE
# ─────────────────────────────────────────────────────────────────────────────

print(f"\n{'='*60}")
print("  EVALUATION ON TEST SET")
print(f"{'='*60}")

y_true, y_prob = [], []
for imgs, labels in test_ds:
    probs = model.predict(imgs, verbose=0)
    y_prob.extend(probs.flatten())
    y_true.extend(labels.numpy().astype(int).flatten())

y_pred = [1 if p >= 0.5 else 0 for p in y_prob]

# Key metrics
fakes_total = y_true.count(0)
fn = sum(1 for t, p in zip(y_true, y_pred) if t == 0 and p == 1)
fp = sum(1 for t, p in zip(y_true, y_pred) if t == 1 and p == 0)
correct = sum(1 for t, p in zip(y_true, y_pred) if t == p)
uncertain = sum(1 for p in y_prob if 0.3 < p < 0.7)

fnr = fn / fakes_total * 100 if fakes_total else 0
fpr = fp / y_true.count(1) * 100 if y_true.count(1) else 0
acc = correct / len(y_true) * 100

print(f"\n  Overall Accuracy:     {acc:.1f}%")
print(f"  ❌ FALSE NEGATIVE RATE: {fnr:.1f}%  ← fake notes called genuine")
print(f"  ❌ False Positive Rate: {fpr:.1f}%  ← genuine notes called fake")
print(f"  ⚠️  Uncertain (0.3–0.7): {uncertain}/{len(y_prob)} ({uncertain/len(y_prob)*100:.1f}%)")

print("\n" + classification_report(y_true, y_pred, target_names=["fake", "genuine"]))

# Top false negatives
fn_list = [(y_prob[i], i) for i in range(len(y_true)) if y_true[i] == 0 and y_pred[i] == 1]
fn_list.sort(reverse=True)
if fn_list:
    print(f"\nTop worst false negatives (fake called genuine):")
    for prob, _ in fn_list[:10]:
        print(f"  {prob*100:.1f}% confident it's genuine")

# Confusion matrix
cm = confusion_matrix(y_true, y_pred)
plt.figure(figsize=(6, 5))
sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
            xticklabels=["fake","genuine"], yticklabels=["fake","genuine"])
plt.title("CashGuard v2 — Confusion Matrix")
plt.ylabel("Actual"); plt.xlabel("Predicted")
plt.tight_layout()
plt.savefig(MODEL_DIR / "confusion_matrix_v2.png", dpi=150)

# Confidence distribution
plt.figure(figsize=(8, 4))
genuine_confs = [p for p, t in zip(y_prob, y_true) if t == 1]
fake_confs    = [p for p, t in zip(y_prob, y_true) if t == 0]
plt.hist(genuine_confs, bins=30, alpha=0.7, color="green", label="Genuine")
plt.hist(fake_confs,    bins=30, alpha=0.7, color="red",   label="Fake")
plt.axvline(0.5, color="orange", linestyle="--", label="Threshold 0.5")
plt.title("CashGuard v2 — Confidence Distribution")
plt.xlabel("Model Output (0=Fake, 1=Genuine)")
plt.legend(); plt.tight_layout()
plt.savefig(MODEL_DIR / "confidence_distribution_v2.png", dpi=150)

# Save metrics
with open(MODEL_DIR / "eval_metrics_v2.json", "w") as f:
    json.dump({"accuracy": acc, "fnr": fnr, "fpr": fpr,
               "uncertain_rate": uncertain/len(y_prob)}, f, indent=2)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 9: SAVE + CONVERT TO ONNX
# ─────────────────────────────────────────────────────────────────────────────

final_path = MODEL_DIR / "currency_classifier_v2_final.keras"
model.save(final_path)
print(f"\n✅ Model saved: {final_path}")

print("\n📦 Converting to ONNX...")
try:
    import tf2onnx
    import onnx
    input_sig = [tf.TensorSpec([1, *IMG_SIZE, 3], tf.float32, name="input")]
    onnx_model, _ = tf2onnx.convert.from_keras(
        model, input_signature=input_sig,
        opset=13
    )
    onnx_out = BASE_DIR.parent.parent / "currency_classifier_v3.onnx"
    with open(onnx_out, "wb") as f:
        f.write(onnx_model.SerializeToString())
    size_mb = onnx_out.stat().st_size / 1e6
    print(f"✅ ONNX saved: {onnx_out}  ({size_mb:.1f} MB)")
    # Auto-copy to website
    website_onnx = BASE_DIR.parent.parent / "currency_classifier.onnx"
    import shutil as _sh
    _sh.copy2(onnx_out, website_onnx)
    print(f"✅ Auto-copied to website: {website_onnx}")
except Exception as e:
    print(f"⚠️  ONNX conversion: {e}")
    print("   Run manually: python3 scripts/convert_to_onnx.py")

print("\n" + "="*60)
print("  DONE")
print("="*60)
