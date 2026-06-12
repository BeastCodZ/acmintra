"""
Scrapes novelty/play money/fake note images and adds them to the fake training folder.
Run: python3 scripts/scrape_novelty.py
"""

from icrawler.builtin import GoogleImageCrawler, BingImageCrawler
import os, shutil, random
from pathlib import Path
from PIL import Image

BASE_DIR    = Path(__file__).parent.parent
SAVE_DIR    = BASE_DIR / "dataset" / "raw" / "novelty"
FAKE_TRAIN  = BASE_DIR / "dataset" / "train" / "fake"
FAKE_VAL    = BASE_DIR / "dataset" / "val"   / "fake"
FAKE_TEST   = BASE_DIR / "dataset" / "test"  / "fake"
VALID_EXTS  = {".jpg", ".jpeg", ".png", ".webp"}

QUERIES = [
    "manoranjan bank india fake currency note",
    "Indian play money novelty note 500 rupee",
    "Indian children bank novelty currency",
    "fake Indian rupee novelty note fun",
    "Indian souvenir currency note fake",
    "prop money Indian rupee fake note",
    "Indian fake currency note clearly fake",
    "novelty Indian 500 rupee banknote",
    "Indian toy money currency note",
    "counterfeit rupee note obvious fake",
]

def scrape():
    SAVE_DIR.mkdir(parents=True, exist_ok=True)

    for i, query in enumerate(QUERIES):
        folder = SAVE_DIR / f"query_{i:02d}"
        folder.mkdir(exist_ok=True)
        print(f"\n[{i+1}/{len(QUERIES)}] Scraping: {query}")
        try:
            crawler = GoogleImageCrawler(
                storage={"root_dir": str(folder)},
                log_level=50
            )
            crawler.crawl(keyword=query, max_num=50)
            count = len(list(folder.glob("*.*")))
            print(f"  Got {count} images")
        except Exception as e:
            print(f"  Google failed: {e}, trying Bing...")
            try:
                crawler = BingImageCrawler(
                    storage={"root_dir": str(folder)},
                    log_level=50
                )
                crawler.crawl(keyword=query, max_num=50)
            except Exception as e2:
                print(f"  Bing also failed: {e2}")

def validate_and_split():
    # Collect all scraped images
    all_images = []
    for root, _, files in os.walk(SAVE_DIR):
        for f in files:
            if Path(f).suffix.lower() in VALID_EXTS:
                path = Path(root) / f
                try:
                    with Image.open(path) as img:
                        img.verify()
                    all_images.append(path)
                except:
                    pass  # skip corrupt

    print(f"\nValid novelty images found: {len(all_images)}")

    if len(all_images) == 0:
        print("No images scraped. Check your internet connection.")
        return

    # Shuffle and split 70/15/15
    random.seed(99)
    random.shuffle(all_images)
    n         = len(all_images)
    train_end = int(n * 0.70)
    val_end   = int(n * 0.85)

    splits = {
        "train": (FAKE_TRAIN, all_images[:train_end]),
        "val":   (FAKE_VAL,   all_images[train_end:val_end]),
        "test":  (FAKE_TEST,  all_images[val_end:]),
    }

    for split_name, (dest_dir, imgs) in splits.items():
        dest_dir.mkdir(parents=True, exist_ok=True)
        for i, img in enumerate(imgs):
            ext  = img.suffix.lower()
            dest = dest_dir / f"novelty_{i:04d}{ext}"
            shutil.copy2(img, dest)
        print(f"  Added to {split_name}/fake: {len(imgs)} images")

    # Also clear the balanced/ folder so it gets rebuilt on next train
    balanced = BASE_DIR / "dataset" / "balanced"
    if balanced.exists():
        shutil.rmtree(balanced)
        print("\nCleared balanced/ folder — will rebuild on next train")

    print("\n✅ Done. Now run: python3 scripts/train.py")


if __name__ == "__main__":
    print("=== Scraping Novelty/Play Money Images ===\n")
    scrape()
    validate_and_split()
