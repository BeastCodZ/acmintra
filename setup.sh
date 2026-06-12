#!/bin/bash
# CashGuard ML — Environment Setup for M4 MacBook
# Run this once: bash setup.sh

echo "🔧 Setting up CashGuard ML environment..."

# Create and activate venv
python3 -m venv venv
source venv/bin/activate

echo "📦 Installing dependencies..."

# Core ML stack — TensorFlow with Metal for M4 GPU
pip install --upgrade pip
pip install tensorflow-macos tensorflow-metal   # M4 GPU acceleration
pip install tensorflowjs                        # convert to browser model
pip install numpy pillow matplotlib             # basics
pip install scikit-learn seaborn                # evaluation
pip install opencv-python                       # image processing
pip install kaggle                              # dataset download
pip install icrawler                            # scrape extra images if needed
pip install split-folders                       # easy train/val/test split

echo ""
echo "✅ Done. Activate with: source venv/bin/activate"
echo "Then run: python3 scripts/check_gpu.py"
