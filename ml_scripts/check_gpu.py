"""
Run this first to confirm M4 GPU is detected by TensorFlow.
Expected output: [PhysicalDevice(name='/physical_device:GPU:0', device_type='GPU')]
"""
import tensorflow as tf

print("TensorFlow version:", tf.__version__)
print("GPUs found:", tf.config.list_physical_devices('GPU'))
print("CPUs found:", tf.config.list_physical_devices('CPU'))

# Quick GPU smoke test
import time
with tf.device('/GPU:0'):
    a = tf.random.normal([1000, 1000])
    start = time.time()
    for _ in range(100):
        a = tf.matmul(a, a)
    elapsed = time.time() - start

print(f"\nGPU matrix multiply benchmark: {elapsed:.2f}s")
print("✅ GPU is working!" if elapsed < 5 else "⚠️  GPU may not be active")
