"""
mac_convert_coreml.py — 在 macOS 上运行（本地 Mac 或 Codemagic CI）
将 ONNX/H5 模型转为 CoreML .mlpackage

Windows 上 coremltools 缺 libcoremlpython 且 TF2.21 LSTM 转换有 bug。
此脚本专供 macOS 使用。

用法 (macOS):
  pip install coremltools onnx
  python ml/mac_convert_coreml.py

Codemagic pre-build:
  python3 ml/mac_convert_coreml.py
"""

import os, json
from pathlib import Path

MODEL_DIR = Path(__file__).parent / "models"
ONNX_PATH = MODEL_DIR / "GestureClassifier.onnx"
MOBILENET_ONNX = MODEL_DIR / "MobileNet_Gesture.onnx"
H5_PATH   = MODEL_DIR / "gesture_lstm.h5"
LABEL_MAP = MODEL_DIR / "label_map.json"
MOBILENET_LABEL_MAP = MODEL_DIR / "mobilenet_label_map.json"
OUTPUT    = MODEL_DIR / "GestureClassifier.mlpackage"
MOBILENET_OUTPUT = MODEL_DIR / "MobileNetGesture.mlpackage"

SEQ_LEN  = 15
FEAT_DIM = 18
MN_FRAMES = 4
MN_CROP = 96


def main():
    import coremltools as ct
    # Convert MobileNet ONNX (primary model, 98.5% accuracy)
    convert_mobilenet(ct)
    # Also convert LSTM ONNX as fallback
    convert_lstm(ct)


def convert_mobilenet(ct):
    if not MOBILENET_ONNX.exists():
        print(f"  [SKIP] MobileNet ONNX not found: {MOBILENET_ONNX}")
        return

    label_path = MOBILENET_LABEL_MAP if MOBILENET_LABEL_MAP.exists() else LABEL_MAP
    with open(label_path, "r", encoding="utf-8") as f:
        label_map = {int(k): v for k, v in json.load(f).items()}
    labels = [label_map[i] for i in sorted(label_map.keys())]
    print(f"MobileNet labels ({len(labels)}): {labels}")

    try:
        mlmodel = ct.convert(
            str(MOBILENET_ONNX),
            inputs=[ct.TensorType(name="video", shape=(1, MN_FRAMES, 3, MN_CROP, MN_CROP))],
            outputs=[ct.TensorType(name="gesture")],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS15,
        )
        mlmodel.short_description = f"ShootAssist MobileNet gesture classifier ({len(labels)} classes, 98.5%)"
        mlmodel.save(str(MOBILENET_OUTPUT))
        print(f"[OK] {MOBILENET_OUTPUT}")
    except Exception as e:
        print(f"[FAIL] MobileNet conversion: {e}")

    swift = gen_swift(labels)
    swift_path = MODEL_DIR / "GestureLabels.swift"
    swift_path.write_text(swift, encoding="utf-8")
    print(f"[OK] {swift_path}")


def convert_lstm(ct):

    with open(LABEL_MAP, "r", encoding="utf-8") as f:
        label_map = {int(k): v for k, v in json.load(f).items()}
    labels = [label_map[i] for i in sorted(label_map.keys())]
    print(f"Labels ({len(labels)}): {labels}")

    mlmodel = None

    # Path 1: ONNX (preferred, no TF dependency)
    if ONNX_PATH.exists():
        print(f"Source: {ONNX_PATH}")
        try:
            mlmodel = ct.convert(
                str(ONNX_PATH),
                inputs=[ct.TensorType(name="keypoints", shape=(1, SEQ_LEN, FEAT_DIM))],
                outputs=[ct.TensorType(name="gesture_prob")],
                convert_to="mlprogram",
                minimum_deployment_target=ct.target.iOS15,
            )
        except Exception as e:
            print(f"ONNX failed: {e}, trying H5...")

    # Path 2: Keras H5
    if mlmodel is None and H5_PATH.exists():
        print(f"Source: {H5_PATH}")
        import tensorflow as tf
        model = tf.keras.models.load_model(str(H5_PATH))
        mlmodel = ct.convert(
            model,
            source="tensorflow",
            inputs=[ct.TensorType(name="keypoints", shape=(1, SEQ_LEN, FEAT_DIM))],
            outputs=[ct.TensorType(name="gesture_prob")],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS15,
        )

    if mlmodel is None:
        print("ERROR: no model file found")
        return

    mlmodel.short_description = f"ShootAssist gesture classifier ({len(labels)} classes)"
    mlmodel.save(str(OUTPUT))
    print(f"[OK] {OUTPUT}")

    # Swift constants
    swift = gen_swift(labels)
    swift_path = MODEL_DIR / "GestureLabels.swift"
    swift_path.write_text(swift, encoding="utf-8")
    print(f"[OK] {swift_path}")


def gen_swift(labels):
    sf = {
        "raise_both_hands": "hands.sparkles",
        "point_up": "hand.point.up",
        "heart": "heart.fill",
        "clap": "hands.clap",
        "spread_arms": "figure.arms.open",
        "fly_kiss": "mouth",
        "cover_face": "theatermask.and.paintbrush",
        "hands_on_hips": "figure.stand",
        "cross_arms": "xmark",
        "chin_rest": "hand.raised",
        "neutral": "figure.stand",
    }
    cn = {
        "raise_both_hands": "hands up",
        "point_up": "point up",
        "heart": "heart",
        "clap": "clap",
        "spread_arms": "spread arms",
        "fly_kiss": "fly kiss",
        "cover_face": "cover face",
        "hands_on_hips": "hands on hips",
        "cross_arms": "cross arms",
        "chin_rest": "chin rest",
        "neutral": "neutral",
    }
    lines = [
        "// GestureLabels.swift - auto-generated",
        "import Foundation",
        "",
        "enum GestureLabel: Int, CaseIterable {",
    ]
    for i, l in enumerate(labels):
        lines.append(f"    case {l} = {i}")
    lines += ["}", "", "extension GestureLabel {",
              "    var sfSymbol: String {", "        switch self {"]
    for l in labels:
        lines.append(f'        case .{l}: return "{sf.get(l, "questionmark")}"')
    lines += ["        }", "    }", "",
              "    var displayName: String {", "        switch self {"]
    for l in labels:
        lines.append(f'        case .{l}: return "{cn.get(l, l)}"')
    lines += ["        }", "    }", "}"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
