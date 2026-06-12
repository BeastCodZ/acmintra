"""
Adds manually downloaded novelty/fake note images into the training set.

HOW TO USE:
1. Go to Google Images and search for:
   - "manoranjan bank india fake note"
   - "children bank of india novelty rupee"
   - "full of fun 500 rupee note"
   - "indian play money prop note"
   - "fake 500 rupee note joke"
2. Download 20-30 images
3. Drop them all into: dataset/raw/manual_fakes/
4. Run: python3 scripts/add_manual_fakes.py
"""

import os, shutil, random
from pathlib import Path
from PIL import Image

BASE_DIR   = Path(__file__).parent.parent
MANUAL_DIR = BASE_DIR / "dataset" / "raw" / "manual_fakes"
VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

MANUAL_DIR.mkdir(parents=True, exist_ok=True)

def run():
    images = [f for f in MANUAL_DIR.glob("*") if f.suffix.lower() in VALID_EXTS]

    if not images:
        print(f"""
No images found in: {MANUAL_DIR}

Please:
1. Search Google Images for: "manoranjan bank india fake note"
2. Download 20-30 images
3. Drop them into: {MANUAL_DIR}
4. Run this script again
        """)
        return

    # Validate
    valid = []
    for img_path in images:
        try:
            with Image.open(img_path) as img:
                img.verify()
            valid.append(img_path)
        except:
            print(f"  Skipping corrupt: {img_path.name}")

    print(f"Found {len(valid)} valid images")

    # Split 70/15/15
    random.seed(42)
    random.shuffle(valid)
    n = len(valid)
    splits = {
        "train": valid[:int(n*0.70)],
        "val":   valid[int(n*0.70):int(n*0.85)],
        "test":  valid[int(n*0.85):]
    }

    for split, imgs in splits.items():
        dest = BASE_DIR / "dataset" / split / "fake"
        dest.mkdir(parents=True, exist_ok=True)
        for i, img in enumerate(imgs):
            shutil.copy2(img, dest / f"novelty_manual_{i:04d}{img.suffix.lower()}")
        print(f"  Added to {split}/fake: {len(imgs)} images")

    # Clear balanced cache so it rebuilds
    balanced = BASE_DIR / "dataset" / "balanced"
    if balanced.exists():
        shutil.rmtree(balanced)
        print("\nCleared balanced cache — will rebuild on next train")

    print("\n✅ Done! Now run: python3 scripts/train.py")

if __name__ == "__main__":
    run()
