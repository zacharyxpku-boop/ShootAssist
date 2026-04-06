"""
mac_convert_coreml.py — 在 Mac 上将 gesture_lstm.h5 转为 CoreML
需要 macOS + coremltools 7.x

使用: python ml/mac_convert_coreml.py
输出: ml/models/GestureClassifier.mlpackage  ← 拖入 Xcode
"""
import json, pickle
import numpy as np
import tensorflow as tf
import coremltools as ct
from pathlib import Path

MODEL_DIR = Path(__file__).parent / "models"
SEQ_LEN = 15
FEAT_DIM = 18

model = tf.keras.models.load_model(str(MODEL_DIR / "gesture_lstm.h5"))
with open(MODEL_DIR / "label_map.json") as f:
    label_map = {int(k): v for k, v in json.load(f).items()}
with open(MODEL_DIR / "scaler.pkl", "rb") as f:
    scaler = pickle.load(f)

labels = [label_map[i] for i in sorted(label_map.keys())]
print(f"Labels: {labels}")

# iOS GestureClassifierService already applies StandardScaler normalization before inference.
# Export raw model (no normalization baked in) — input expects already-normalized keypoints.
full_model = model

mlmodel = ct.convert(
    full_model,
    inputs=[ct.TensorType(name="keypoints", shape=(1, SEQ_LEN, FEAT_DIM))],
    outputs=[ct.TensorType(name="gesture_prob")],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS15,
)

mlmodel.short_description = "ShootAssist gesture classifier (LSTM+CNN, 7 classes)"
out = str(MODEL_DIR / "GestureClassifier.mlpackage")
mlmodel.save(out)
print(f"Saved: {out}")
print(f"Classes: {labels}")
