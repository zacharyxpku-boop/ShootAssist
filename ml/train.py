"""
train.py — 手势识别 LSTM 训练
输入: data/keypoints/<label>/sequences.npy  shape=(N, 15, 18)
输出: models/gesture_lstm.h5 + models/label_map.json + models/scaler.pkl

使用方法: python ml/train.py
"""

import os, json, pickle, random
import numpy as np
from pathlib import Path
from collections import Counter

np.random.seed(42)
random.seed(42)

# ── 配置 ──────────────────────────────────────────────
SEQ_LEN    = 15
FEAT_DIM   = 18    # 9 关节 × (x, y)
BATCH_SIZE = 8
EPOCHS     = 200
PATIENCE   = 40
DATA_DIR   = Path(__file__).parent / 'data' / 'keypoints'
MODEL_DIR  = Path(__file__).parent / 'models'
MODEL_DIR.mkdir(parents=True, exist_ok=True)

LABELS = [
    "raise_both_hands", "point_up", "heart", "clap", "spread_arms",
    "fly_kiss", "cover_face", "hands_on_hips", "cross_arms", "chin_rest", "neutral"
]

# ── 数据增强 ──────────────────────────────────────────
def augment(x: np.ndarray) -> np.ndarray:
    """x: (15, 18)"""
    x = x.copy()
    # 水平翻转（x 坐标取反）
    if random.random() < 0.5:
        x[:, 0::2] = -x[:, 0::2]
    # 高斯噪声
    if random.random() < 0.5:
        x += np.random.normal(0, 0.012, x.shape)
    # 时间拉伸 (0.8x / 1.2x → resize back to SEQ_LEN)
    if random.random() < 0.5:
        rate = random.choice([0.8, 1.2])
        new_len = max(4, int(SEQ_LEN * rate))
        old_idx = np.linspace(0, SEQ_LEN - 1, SEQ_LEN)
        new_idx = np.linspace(0, SEQ_LEN - 1, new_len)
        stretched = np.array([np.interp(new_idx, old_idx, x[:, i]) for i in range(FEAT_DIM)]).T
        back_idx = np.linspace(0, new_len - 1, SEQ_LEN)
        src_idx  = np.linspace(0, new_len - 1, new_len)
        x = np.array([np.interp(back_idx, src_idx, stretched[:, i]) for i in range(FEAT_DIM)]).T
    # 随机裁剪 → resize 回 SEQ_LEN
    if random.random() < 0.5 and SEQ_LEN > 4:
        crop = random.randint(SEQ_LEN * 7 // 10, SEQ_LEN - 1)
        start = random.randint(0, SEQ_LEN - crop)
        seg = x[start:start + crop]
        old_idx = np.linspace(0, crop - 1, crop)
        new_idx = np.linspace(0, crop - 1, SEQ_LEN)
        x = np.array([np.interp(new_idx, old_idx, seg[:, i]) for i in range(FEAT_DIM)]).T
    return x.astype(np.float32)


def augment_dataset(X, y, factor=8):
    Xa, ya = [X], [y]
    for _ in range(factor):
        Xa.append(np.stack([augment(x) for x in X]))
        ya.append(y)
    return np.concatenate(Xa), np.concatenate(ya)


# ── 加载数据 ──────────────────────────────────────────
def load_data():
    X_all, y_all = [], []
    present_labels = []

    for label in LABELS:
        npy_path = DATA_DIR / label / 'sequences.npy'
        if not npy_path.exists():
            print(f'  [MISS] {label}: 无 sequences.npy，跳过')
            continue
        seqs = np.load(str(npy_path))
        if seqs.ndim != 3 or seqs.shape[1] != SEQ_LEN or seqs.shape[2] != FEAT_DIM:
            print(f'  [WARN] {label}: shape {seqs.shape} 不符合预期，尝试 reshape')
            try:
                seqs = seqs.reshape(-1, SEQ_LEN, FEAT_DIM)
            except Exception as e:
                print(f'  [ERROR] 无法处理 {label}: {e}')
                continue
        X_all.append(seqs)
        y_all.extend([len(present_labels)] * len(seqs))
        print(f'  ✅ {label}: {len(seqs)} 个样本')
        present_labels.append(label)

    if not X_all:
        raise RuntimeError('没有任何有效数据！请先运行 auto_label.py + collect_data.py')

    label_map = {i: l for i, l in enumerate(present_labels)}
    return np.concatenate(X_all), np.array(y_all, dtype=np.int32), label_map


# ── 构建模型 ──────────────────────────────────────────
def build_model(seq_len, feat_dim, num_classes):
    import tensorflow as tf
    from tensorflow.keras import layers, models

    inp = layers.Input(shape=(seq_len, feat_dim))
    x = layers.Conv1D(32, 3, activation='relu', padding='same')(inp)
    x = layers.BatchNormalization()(x)
    x = layers.Conv1D(64, 3, activation='relu', padding='same')(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.LSTM(64, return_sequences=True, dropout=0.3)(x)
    x = layers.LSTM(32, dropout=0.3)(x)
    x = layers.Dense(32, activation='relu')(x)
    x = layers.Dropout(0.4)(x)
    out = layers.Dense(num_classes, activation='softmax')(x)

    return models.Model(inp, out)


# ── 主训练流程 ────────────────────────────────────────
def main():
    import tensorflow as tf
    from tensorflow.keras import callbacks
    from tensorflow.keras.optimizers import Adam
    from sklearn.preprocessing import StandardScaler
    from sklearn.utils.class_weight import compute_class_weight
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import classification_report

    tf.random.set_seed(42)

    print('\n' + '='*55)
    print('  手势识别 LSTM 训练')
    print('='*55)

    X, y, label_map = load_data()
    num_classes = len(label_map)
    print(f'\n  样本总数: {len(X)}, 类别数: {num_classes}')
    print(f'  类别分布: {dict(Counter(y.tolist()))}')

    # 标准化
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X.reshape(-1, FEAT_DIM)).reshape(X.shape)
    with open(MODEL_DIR / 'scaler.pkl', 'wb') as f:
        pickle.dump(scaler, f)

    # Train/Val split
    if len(X) >= num_classes * 2:
        X_tr, X_val, y_tr, y_val = train_test_split(
            X_scaled, y, test_size=0.2, stratify=y, random_state=42)
    else:
        print('  [INFO] 样本少，全量训练，validation = train')
        X_tr, y_tr = X_scaled, y
        X_val, y_val = X_scaled, y

    # 增强
    print(f'\n  数据增强 ×8 中...')
    X_tr_aug, y_tr_aug = augment_dataset(X_tr, y_tr, factor=8)
    print(f'  增强后训练样本: {len(X_tr_aug)}')

    # Class weight
    cw = compute_class_weight('balanced', classes=np.unique(y_tr_aug), y=y_tr_aug)
    class_weight = {i: w for i, w in enumerate(cw)}

    y_tr_oh  = tf.keras.utils.to_categorical(y_tr_aug, num_classes)
    y_val_oh = tf.keras.utils.to_categorical(y_val,    num_classes)

    model = build_model(SEQ_LEN, FEAT_DIM, num_classes)
    model.compile(optimizer=Adam(1e-3), loss='categorical_crossentropy', metrics=['accuracy'])
    model.summary()

    ckpt = str(MODEL_DIR / 'gesture_lstm_best.h5')
    cb = [
        callbacks.ModelCheckpoint(ckpt, monitor='val_accuracy', save_best_only=True, verbose=0),
        callbacks.EarlyStopping(monitor='val_accuracy', patience=PATIENCE,
                                restore_best_weights=True, verbose=1),
        callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=15,
                                    min_lr=1e-6, verbose=1),
    ]

    history = model.fit(
        X_tr_aug, y_tr_oh,
        validation_data=(X_val, y_val_oh),
        batch_size=BATCH_SIZE, epochs=EPOCHS,
        class_weight=class_weight, callbacks=cb, verbose=1,
    )

    model.save(str(MODEL_DIR / 'gesture_lstm.h5'))
    with open(MODEL_DIR / 'label_map.json', 'w', encoding='utf-8') as f:
        json.dump(label_map, f, ensure_ascii=False, indent=2)

    # 评估
    y_pred = np.argmax(model.predict(X_val, verbose=0), axis=1)
    names = [label_map[i] for i in range(num_classes)]
    print('\n' + '='*55)
    print(classification_report(y_val, y_pred, target_names=names, zero_division=0))
    print(f'  最佳 val_accuracy: {max(history.history.get("val_accuracy", [0])):.4f}')
    print(f'\n  ✅ models/gesture_lstm.h5')
    print(f'  ✅ models/label_map.json')
    print(f'  ✅ models/scaler.pkl')
    print('  下一步: python ml/convert_coreml.py')


if __name__ == '__main__':
    main()
