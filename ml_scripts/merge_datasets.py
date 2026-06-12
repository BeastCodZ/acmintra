"""
Merges all new fake/genuine images from extra datasets into the main dataset.
Run: python3 scripts/merge_datasets.py
"""
import os, shutil, random
from pathlib import Path
from PIL import Image

BASE_DIR   = Path(__file__).parent.parent
DATASET    = BASE_DIR / "dataset"
VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
random.seed(42)

def copy_images(src_dir, label, tag):
    """Copy all valid images from src_dir into train/val/test splits."""
    images = []
    for root, _, files in os.walk(src_dir):
        for f in files:
            if Path(f).suffix.lower() in VALID_EXTS:
                images.append(Path(root) / f)

    # Validate
    valid = []
    for p in images:
        try:
            with Image.open(p) as img:
                img.verify()
            valid.append(p)
        except:
            pass

    if not valid:
        print(f"  No valid images in {src_dir}")
        return 0

    random.shuffle(valid)
    n = len(valid)
    splits = {
        "train": valid[:int(n*0.70)],
        "val":   valid[int(n*0.70):int(n*0.85)],
        "test":  valid[int(n*0.85):]
    }

    for split, imgs in splits.items():
        dest = DATASET / split / label
        dest.mkdir(parents=True, exist_ok=True)
        for i, img in enumerate(imgs):
            ext  = img.suffix.lower()
            name = f"{tag}_{i:04d}{ext}"
            shutil.copy2(img, dest / name)

    print(f"  ✅ {src_dir.name}: {len(valid)} images → train:{len(splits['train'])} val:{len(splits['val'])} test:{len(splits['test'])}")
    return len(valid)


if __name__ == "__main__":
    print("=== Merging New Datasets ===\n")
    total_fake = 0
    total_genuine = 0

    # ── Extra 500 dataset ────────────────────────────────────────────────────
    print("📦 extra_500 dataset:")
    fake_500_dir = BASE_DIR / "dataset/raw/extra_500/indian currency/FAKE 500"
    fake_500_aug = BASE_DIR / "dataset/raw/extra_500/indian currency/FAKE 500  AUGUMENTED"
    real_500_dir = BASE_DIR / "dataset/raw/extra_500/indian currency/REAL 500"
    real_500_aug = BASE_DIR / "dataset/raw/extra_500/indian currency/real 500 AUGUMENTED"

    total_fake    += copy_images(fake_500_dir, "fake",    "extra500_fake")
    total_fake    += copy_images(fake_500_aug, "fake",    "extra500_fake_aug")
    total_genuine += copy_images(real_500_dir, "genuine", "extra500_real")
    total_genuine += copy_images(real_500_aug, "genuine", "extra500_real_aug")

    # ── Extra detection dataset ───────────────────────────────────────────────
    print("\n📦 extra_detection dataset:")
    for split in ["training", "testing", "validation"]:
        fake_dir = BASE_DIR / f"dataset/raw/extra_detection/dataset/{split}/fake"
        real_dir = BASE_DIR / f"dataset/raw/extra_detection/dataset/{split}/real"
        if fake_dir.exists():
            total_fake    += copy_images(fake_dir, "fake",    f"det_{split}_fake")
        if real_dir.exists():
            total_genuine += copy_images(real_dir, "genuine", f"det_{split}_real")

    # ── Manual novelty notes (if any) ────────────────────────────────────────
    manual_dir = BASE_DIR / "dataset/raw/manual_fakes"
    if manual_dir.exists() and any(manual_dir.iterdir()):
        print("\n📦 Manual novelty fakes:")
        total_fake += copy_images(manual_dir, "fake", "novelty_manual")

    # ── Clear balanced cache ─────────────────────────────────────────────────
    balanced = DATASET / "balanced"
    if balanced.exists():
        shutil.rmtree(balanced)
        print("\n🗑️  Cleared balanced cache")

    print(f"\n{'='*45}")
    print(f"Total new fake images added:    {total_fake}")
    print(f"Total new genuine images added: {total_genuine}")

    # Final dataset count
    for split in ["train", "val", "test"]:
        f = len(list((DATASET / split / "fake").glob("*")))    if (DATASET / split / "fake").exists()    else 0
        g = len(list((DATASET / split / "genuine").glob("*"))) if (DATASET / split / "genuine").exists() else 0
        print(f"  {split}: {f} fake + {g} genuine = {f+g}")

    print("\n✅ Ready to retrain: python3 scripts/train.py")
