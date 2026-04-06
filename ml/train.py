"""
train.py
加载关键点序列数据，训练 LSTM 手势分类模型，保存为 Keras .h5。

运行: python train.py
输出: models/gesture_lstm.h5
      models/label_map.json   (标签→索引映射)
"""

import os
import json
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import pickle

# ── 配置（与 collect_data.py 一致） ──────────────────────
GESTURE_LABELS = [
    "raise_both_hands", "point_up", "heart", "clap",
    "spread_arms", "fly_kiss", "cover_face",
    "hands_on_hips", "cross_arms", "chin_rest", "neutral",
]
DATA_DIR   = "data/keypoints"
MODEL_DIR  = "models"
SEQ_LEN    = 15     # 帧数
FEAT_DIM   = 18     # 每帧特征维度（9关节 × 2坐标）
EPOCHS     = 80
BATCH_SIZE = 32
VAL_SPLIT  = 0.2


def load_data():
    X_list, y_list = [], []
    label_map = {}

    for idx, label in enumerate(GESTURE_LABELS):
        npy_path = os.path.join(DATA_DIR, label, "sequences.npy")
        if not os.path.exists(npy_path):
            print(f"  [SKIP] 缺少数据: {npy_path}")
            continue
        arr = np.load(npy_path)  # shape: (N, SEQ_LEN, FEAT_DIM)
        X_list.append(arr)
        y_list.extend([idx] * len(arr))
        label_map[idx] = label
        print(f"  {label}: {len(arr)} 样本")

    if not X_list:
        raise ValueError("没有训练数据！请先运行 collect_data.py")

    X = np.concatenate(X_list, axis=0)  # (total, SEQ_LEN, FEAT_DIM)
    y = np.array(y_list)
    return X, y, label_map


def augment_sequences(X: np.ndarray, y: np.ndarray, factor: int = 2) -> tuple:
    """简单数据增强：随机水平翻转 + 轻微噪声"""
    X_aug_list = [X]
    y_aug_list = [y]

    for _ in range(factor):
        # 水平翻转（x 坐标 = 1 - x）
        X_flip = X.copy()
        X_flip[:, :, 0::2] = 1.0 - X_flip[:, :, 0::2]  # 所有偶数位 = x 坐标
        X_aug_list.append(X_flip)
        y_aug_list.append(y)

        # 随机噪声
        noise = np.random.normal(0, 0.01, X.shape).astype(np.float32)
        X_aug_list.append(X + noise)
        y_aug_list.append(y)

    return np.concatenate(X_aug_list), np.concatenate(y_aug_list)


def build_model(num_classes: int, seq_len: int, feat_dim: int) -> keras.Model:
    """
    轻量级 LSTM + 1D-CNN 混合模型
    参数量约 50K，CoreML 推理 < 5ms
    """
    inp = keras.Input(shape=(seq_len, feat_dim), name="keypoints")

    # 局部时序特征提取
    x = keras.layers.Conv1D(32, kernel_size=3, activation="relu", padding="same")(inp)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.Conv1D(64, kernel_size=3, activation="relu", padding="same")(x)
    x = keras.layers.BatchNormalization()(x)

    # 全局时序建模
    x = keras.layers.LSTM(64, return_sequences=True)(x)
    x = keras.layers.Dropout(0.3)(x)
    x = keras.layers.LSTM(32)(x)
    x = keras.layers.Dropout(0.3)(x)

    # 分类头
    x = keras.layers.Dense(32, activation="relu")(x)
    out = keras.layers.Dense(num_classes, activation="softmax", name="gesture_prob")(x)

    model = keras.Model(inp, out, name="GestureClassifier")
    return model


def main():
    os.makedirs(MODEL_DIR, exist_ok=True)

    print("📥 加载数据...")
    X, y, label_map = load_data()
    num_classes = len(label_map)
    print(f"   总样本: {len(X)}, 类别数: {num_classes}")

    print("🔄 数据增强...")
    X, y = augment_sequences(X, y, factor=2)
    print(f"   增强后: {len(X)} 样本")

    # 归一化（每个特征独立 z-score）
    orig_shape = X.shape
    X_flat = X.reshape(-1, orig_shape[-1])
    scaler = StandardScaler()
    X_flat = scaler.fit_transform(X_flat)
    X = X_flat.reshape(orig_shape)

    # 保存 scaler 供推理时使用
    scaler_path = os.path.join(MODEL_DIR, "scaler.pkl")
    with open(scaler_path, "wb") as f:
        pickle.dump(scaler, f)

    # 打乱数据
    idx = np.random.permutation(len(X))
    X, y = X[idx], y[idx]

    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=VAL_SPLIT, stratify=y, random_state=42)

    print("🏗️  构建模型...")
    model = build_model(num_classes, SEQ_LEN, FEAT_DIM)
    model.summary()

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )

    callbacks = [
        keras.callbacks.EarlyStopping(patience=15, restore_best_weights=True, monitor="val_accuracy"),
        keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=7),
        keras.callbacks.ModelCheckpoint(
            os.path.join(MODEL_DIR, "best_gesture.h5"),
            save_best_only=True, monitor="val_accuracy"
        )
    ]

    print(f"🚀 开始训练 ({EPOCHS} epochs)...")
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        callbacks=callbacks,
        verbose=1
    )

    val_acc = max(history.history["val_accuracy"])
    print(f"\n✅ 最佳验证准确率: {val_acc * 100:.1f}%")

    # 保存最终模型
    model_path = os.path.join(MODEL_DIR, "gesture_lstm.h5")
    model.save(model_path)
    print(f"   模型已保存: {model_path}")

    # 保存标签映射
    label_map_path = os.path.join(MODEL_DIR, "label_map.json")
    with open(label_map_path, "w", encoding="utf-8") as f:
        json.dump({str(k): v for k, v in label_map.items()}, f, ensure_ascii=False, indent=2)
    print(f"   标签映射: {label_map_path}")

    print(f"\n🎉 训练完成！接下来运行: python convert_coreml.py")


if __name__ == "__main__":
    main()
