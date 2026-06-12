"""
Step 2 — Dataset Preparation
Scans all raw images, validates them, removes corrupt files,
and splits into train/val/test sets.

Run: python3 scripts/prepare_dataset.py
"""

import os
import shutil
import random
from pathlib import Path
from PIL import Image

DATASET_DIR = Path(__file__).parent.parent / "dataset"
RAW_DIR     = DATASET_DIR / "raw"

SPLIT_RATIOS = (0.70, 0.15, 0.15)   # train / val / test
MIN_IMAGES   = 300                   # warn if below this per class
VALID_EXTS   = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

random.seed(42)


def collect_images(label: str) -> list[Path]:
    """Recursively collect all images for a label across all raw subdirs."""
    images = []

    # Map our labels to the Kaggle dataset folder names
    kaggle_label_map = {
        "genuine": "real",
        "fake": "fake",
    }
    kaggle_label = kaggle_label_map.get(label, label)

    for root, _, files in os.walk(RAW_DIR):
        root_path = Path(root)
        root_str  = str(root_path).lower()

        # Match Kaggle structure: data/data/real/* or data/data/fake/*
        # Also match manual/genuine or manual/fake as fallback
        is_match = (
            (f"/data/data/{kaggle_label}" in root_str and
             root_str != str(RAW_DIR / "kaggle" / "data" / "data" / kaggle_label).lower())
            or f"/data/data/{kaggle_label}/" in root_str   # sub-denomination folders
            or f"/manual/{label}" in root_str
            or f"/scraped/{label}" in root_str
        )

        # Simpler: just check if the immediate parent is the label folder
        if root_path.parent.name == kaggle_label or root_path.name == kaggle_label:
            is_match = True

        if is_match:
            for f in files:
                if Path(f).suffix.lower() in VALID_EXTS:
                    images.append(root_path / f)

    return images


def validate_image(path: Path) -> bool:
    """Return True if image can be opened and is not corrupt."""
    try:
        with Image.open(path) as img:
            img.verify()
        return True
    except Exception:
        return False


def split_and_copy(images: list[Path], label: str):
    random.shuffle(images)
    n         = len(images)
    train_end = int(n * SPLIT_RATIOS[0])
    val_end   = int(n * (SPLIT_RATIOS[0] + SPLIT_RATIOS[1]))

    splits = {
        "train": images[:train_end],
        "val":   images[train_end:val_end],
        "test":  images[val_end:],
    }

    counts = {}
    for split, imgs in splits.items():
        dest = DATASET_DIR / split / label
        dest.mkdir(parents=True, exist_ok=True)
        for i, img in enumerate(imgs):
            # Rename to avoid collisions from multiple sources
            ext  = img.suffix.lower()
            dest_file = dest / f"{label}_{i:04d}{ext}"
            shutil.copy2(img, dest_file)
        counts[split] = len(imgs)

    return counts


def print_stats():
    print("\n📊 Final Dataset Stats:")
    print(f"{'Split':<10} {'Genuine':<12} {'Fake':<12} {'Total':<10}")
    print("-" * 45)
    total_all = 0
    for split in ["train", "val", "test"]:
        g = len(list((DATASET_DIR / split / "genuine").glob("*"))) if (DATASET_DIR / split / "genuine").exists() else 0
        f = len(list((DATASET_DIR / split / "fake").glob("*"))) if (DATASET_DIR / split / "fake").exists() else 0
        total_all += g + f
        print(f"{split:<10} {g:<12} {f:<12} {g+f:<10}")
    print("-" * 45)
    print(f"{'TOTAL':<10} {'':<12} {'':<12} {total_all:<10}")


if __name__ == "__main__":
    print("=== CashGuard Dataset Preparation ===\n")

    for label in ["genuine", "fake"]:
        print(f"Processing '{label}' images...")

        # Collect
        all_images = collect_images(label)
        print(f"  Found: {len(all_images)} raw images")

        # Validate — remove corrupt files
        valid_images = []
        corrupt = 0
        for img in all_images:
            if validate_image(img):
                valid_images.append(img)
            else:
                corrupt += 1

        if corrupt > 0:
            print(f"  ⚠️  Removed {corrupt} corrupt images")

        if len(valid_images) < MIN_IMAGES:
            print(f"  ⚠️  WARNING: Only {len(valid_images)} valid '{label}' images.")
            print(f"     Recommend at least {MIN_IMAGES}. Add more via download_dataset.py")

        # Split and copy
        counts = split_and_copy(valid_images, label)
        print(f"  ✅ Split → train:{counts['train']} | val:{counts['val']} | test:{counts['test']}")

    print_stats()
    print("\n📁 Next step: run python3 scripts/train.py")
