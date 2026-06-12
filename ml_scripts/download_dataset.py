"""
Step 1 — Dataset Collection
Downloads Indian currency images from Kaggle + scrapes extra images via Google.

Run: python3 scripts/download_dataset.py
"""

import os
import sys

DATASET_DIR = os.path.join(os.path.dirname(__file__), "..", "dataset")

# ─── Option A: Kaggle Download (Recommended — best quality) ───────────────────
def download_from_kaggle():
    """
    Requires kaggle.json in ~/.kaggle/
    Get it from: https://www.kaggle.com/settings → API → Create New Token
    """
    try:
        import kaggle
        print("📥 Downloading from Kaggle...")

        datasets = [
            "harunshimanto/indian-currency-note-dataset",
            "aniruddha15/indian-currency-dataset",
        ]

        raw_dir = os.path.join(DATASET_DIR, "raw", "kaggle")
        os.makedirs(raw_dir, exist_ok=True)

        for ds in datasets:
            print(f"  Downloading: {ds}")
            os.system(f"kaggle datasets download -d {ds} -p {raw_dir} --unzip")

        print(f"✅ Kaggle data saved to {raw_dir}")
        return True

    except Exception as e:
        print(f"⚠️  Kaggle failed: {e}")
        print("   Make sure ~/.kaggle/kaggle.json exists")
        return False


# ─── Option B: Google Image Scraper (Supplement with extra images) ────────────
def scrape_google_images():
    """
    Scrapes Google Images for additional training data.
    Adds variety: different lighting, angles, phone camera quality.
    """
    try:
        from icrawler.builtin import GoogleImageCrawler
    except ImportError:
        print("⚠️  icrawler not installed. Run: pip install icrawler")
        return

    queries = {
        # Genuine notes — different angles, lighting, quality
        "genuine": [
            "Indian 500 rupee note front genuine high resolution",
            "Indian 500 rupee note back genuine",
            "Indian 200 rupee note front genuine",
            "Indian 100 rupee note front genuine",
            "500 rupee note RBI official",
        ],
        # Fake notes — counterfeits, poor quality prints, photocopies
        "fake": [
            "counterfeit Indian currency note 500",
            "fake Indian rupee note photocopy",
            "duplicate Indian 500 rupee note",
            "poor quality Indian currency print",
            "Indian currency forgery detected",
        ],
    }

    for label, query_list in queries.items():
        for query in query_list:
            folder_name = query.replace(" ", "_")[:40]
            save_dir = os.path.join(DATASET_DIR, "raw", "scraped", label, folder_name)
            os.makedirs(save_dir, exist_ok=True)

            print(f"  Scraping ({label}): {query[:50]}...")
            try:
                crawler = GoogleImageCrawler(
                    storage={"root_dir": save_dir},
                    log_level=50  # suppress logs
                )
                crawler.crawl(keyword=query, max_num=100)
            except Exception as e:
                print(f"    ⚠️  Failed: {e}")

    print("✅ Scraping complete")


# ─── Option C: Manual Instructions ───────────────────────────────────────────
def print_manual_instructions():
    print("""
╔══════════════════════════════════════════════════════════════╗
║           MANUAL DATASET COLLECTION GUIDE                    ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  GENUINE NOTES:                                              ║
║  1. Photograph actual ₹500, ₹200, ₹100 notes                ║
║     • Front and back                                         ║
║     • Multiple lighting conditions                           ║
║     • Slightly different angles                              ║
║     • Some blurry shots (real world use case)                ║
║                                                              ║
║  2. Download from RBI website:                               ║
║     https://www.rbi.org.in/currency/                         ║
║                                                              ║
║  FAKE NOTES (for training):                                  ║
║  • Print a black & white photocopy of a note image           ║
║  • Take photos of low-res currency images from internet      ║
║  • Use images that are blurry / have wrong colors            ║
║  • Missing security thread, wrong watermark position         ║
║                                                              ║
║  TARGET: 500+ genuine + 500+ fake = 1000 images minimum     ║
║                                                              ║
║  DROP FILES INTO:                                            ║
║  dataset/raw/manual/genuine/  ← genuine note photos         ║
║  dataset/raw/manual/fake/     ← fake/photocopy photos        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
    """)


if __name__ == "__main__":
    print("=== CashGuard Dataset Collection ===\n")

    # Create raw directories
    os.makedirs(os.path.join(DATASET_DIR, "raw", "manual", "genuine"), exist_ok=True)
    os.makedirs(os.path.join(DATASET_DIR, "raw", "manual", "fake"), exist_ok=True)

    print("Choose collection method:")
    print("  1. Kaggle download (best quality — needs kaggle.json)")
    print("  2. Google image scraper (supplement)")
    print("  3. Manual instructions (photograph real notes)")
    print("  4. All of the above")

    choice = input("\nEnter choice (1/2/3/4): ").strip()

    if choice in ("1", "4"):
        download_from_kaggle()
    if choice in ("2", "4"):
        scrape_google_images()
    if choice in ("3", "4"):
        print_manual_instructions()

    print("\n📁 Next step: run python3 scripts/prepare_dataset.py")
