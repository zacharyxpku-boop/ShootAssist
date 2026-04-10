"""
convert_coreml.py
将训练好的 Keras .h5 模型转换为 CoreML .mlmodel，供 iOS 直接调用。

运行: python convert_coreml.py
输出: models/GestureClassifier.mlmodel   ← 拖入 Xcode 项目

环境要求:
  pip install coremltools tensorflow
"""

import json
import os
import pickle

import coremltools as ct
import numpy as np
import tensorflow as tf

MODEL_DIR    = "models"
H5_PATH      = os.path.join(MODEL_DIR, "gesture_lstm.h5")
LABEL_MAP    = os.path.join(MODEL_DIR, "label_map.json")
SCALER_PATH  = os.path.join(MODEL_DIR, "scaler.pkl")
OUTPUT_PATH  = os.path.join(MODEL_DIR, "GestureClassifier.mlmodel")

SEQ_LEN  = 15
FEAT_DIM = 18


def load_label_map() -> dict:
    with open(LABEL_MAP, "r", encoding="utf-8") as f:
        raw = json.load(f)
    return {int(k): v for k, v in raw.items()}


def load_scaler():
    if not os.path.exists(SCALER_PATH):
        return None
    with open(SCALER_PATH, "rb") as f:
        return pickle.load(f)


def main():
    print("Loading Keras model...")
    model = tf.keras.models.load_model(H5_PATH)
    label_map = load_label_map()
    scaler = load_scaler()

    class_labels = [label_map[i] for i in sorted(label_map.keys())]
    print(f"   类别: {class_labels}")

    # ── 验证输出格式 ──
    dummy_input = np.random.rand(1, SEQ_LEN, FEAT_DIM).astype(np.float32)
    if scaler is not None:
        dummy_flat = dummy_input.reshape(-1, FEAT_DIM)
        dummy_flat = scaler.transform(dummy_flat)
        dummy_input = dummy_flat.reshape(1, SEQ_LEN, FEAT_DIM).astype(np.float32)

    pred = model.predict(dummy_input)
    print(f"   模型输出 shape: {pred.shape}")

    # ── 转换为 CoreML ──
    print("Converting to CoreML...")

    # 将 scaler 参数导出为 JSON，供 iOS 端做预处理（CoreML 不支持 sklearn scaler）
    if scaler is not None:
        mean = scaler.mean_.astype(np.float32)
        std  = scaler.scale_.astype(np.float32)
        scaler_json = {
            "mean": mean.tolist(),
            "std":  std.tolist(),
            "feat_dim": FEAT_DIM,
            "seq_len":  SEQ_LEN,
        }
        scaler_json_path = os.path.join(MODEL_DIR, "scaler_params.json")
        with open(scaler_json_path, "w", encoding="utf-8") as f:
            json.dump(scaler_json, f, indent=2)
        print(f"   Scaler params saved: {scaler_json_path}")

    full_model = model

    # 使用 coremltools 转换
    # TF 2.21 + coremltools 直接转换有 LSTM 兼容性问题
    # 绕路：TF → SavedModel → ONNX → CoreML
    import subprocess, sys

    saved_model_dir = os.path.join(MODEL_DIR, "gesture_saved_model")
    onnx_path = os.path.join(MODEL_DIR, "GestureClassifier.onnx")

    # Step A: 导出为 SavedModel（Keras 3 用 export）
    print("  Step A: exporting TF SavedModel...")
    full_model.export(saved_model_dir)

    # Step B: SavedModel → ONNX
    print("  Step B: converting to ONNX...")
    subprocess.run([
        sys.executable, "-m", "tf2onnx.convert",
        "--saved-model", saved_model_dir,
        "--output", onnx_path,
        "--opset", "13",
    ], check=True, capture_output=True)
    print(f"  ONNX saved: {onnx_path}")

    # Step C: ONNX → CoreML
    print("  Step C: converting ONNX to CoreML...")
    mlmodel = ct.converters.onnx.convert(
        model=onnx_path,
        minimum_ios_deployment_target="15",
    ) if hasattr(ct.converters, 'onnx') else ct.convert(
        onnx_path,
        inputs=[ct.TensorType(name="keypoints", shape=(1, SEQ_LEN, FEAT_DIM))],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS15,
    )

    # 添加元数据
    mlmodel.short_description = "ShootAssist 手势分类器（LSTM+CNN）"
    mlmodel.input_description["keypoints"] = (
        f"关键点序列 [{SEQ_LEN} 帧 × {FEAT_DIM} 特征] — "
        f"9 个关节点 (鼻子/双肩/双肘/双腕/双臀) 的归一化 (x,y) 坐标"
    )
    mlmodel.output_description["gesture_prob"] = f"各手势类别概率 [{len(class_labels)} 类]"

    # 保存
    mlmodel.save(OUTPUT_PATH)
    print(f"\n[OK] CoreML model saved: {OUTPUT_PATH}")
    print(f"   类别顺序: {class_labels}")

    # ── 生成 iOS 用的 Swift 常量文件 ──
    swift_constants = generate_swift_constants(class_labels)
    swift_path = os.path.join(MODEL_DIR, "GestureLabels.swift")
    with open(swift_path, "w", encoding="utf-8") as f:
        f.write(swift_constants)
    print(f"   Swift 常量: {swift_path}")

    print("\nNext steps:")
    print(f"   1. 把 {OUTPUT_PATH} 拖入 Xcode 项目（Target → ShootAssist）")
    print(f"   2. 把 {swift_path} 复制到 ShootAssist/Services/")
    print("   3. GestureClassifierService.swift 会自动加载该模型")


def generate_swift_constants(labels: list) -> str:
    """生成 Swift 标签映射，供 GestureClassifierService 使用。"""
    emoji_map = {
        "raise_both_hands": ("🙌", "双手举高"),
        "point_up":         ("☝️", "指天"),
        "heart":            ("🫶", "比心"),
        "clap":             ("👏", "拍手"),
        "spread_arms":      ("🤸", "展开双臂"),
        "fly_kiss":         ("😘", "飞吻"),
        "cover_face":       ("🤭", "捂脸卖萌"),
        "hands_on_hips":    ("🤗", "叉腰"),
        "cross_arms":       ("🙅", "双手交叉"),
        "chin_rest":        ("🤔", "托腮"),
        "neutral":          (nil_str := "nil", ""),
    }

    lines = [
        "// GestureLabels.swift — 由 convert_coreml.py 自动生成，请勿手动修改",
        "// 将此文件和 GestureClassifier.mlmodel 一起拖入 Xcode",
        "",
        "import Foundation",
        "",
        "enum GestureLabel: Int, CaseIterable {",
    ]
    for i, label in enumerate(labels):
        lines.append(f"    case {label} = {i}")
    lines += [
        "}",
        "",
        "extension GestureLabel {",
        "    var emoji: String? {",
        "        switch self {",
    ]
    for label in labels:
        info = emoji_map.get(label, (None, ""))
        emoji = info[0]
        if emoji == "nil":
            lines.append(f'        case .{label}: return nil')
        else:
            lines.append(f'        case .{label}: return "{emoji}"')
    lines += [
        "        }",
        "    }",
        "",
        "    var description: String {",
        "        switch self {",
    ]
    for label in labels:
        info = emoji_map.get(label, (None, ""))
        desc = info[1]
        lines.append(f'        case .{label}: return "{desc}"')
    lines += [
        "        }",
        "    }",
        "}",
    ]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
