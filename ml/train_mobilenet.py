"""
train_mobilenet.py — 轻量视频手势分类器（CPU 友好）
用 MobileNetV3-Small 提取每帧特征 → 时序平均池化 → 分类头
比 X3D 轻 20 倍，CPU 上能跑。

Usage: python ml/train_mobilenet.py
"""

import os, json, random
import numpy as np
import cv2
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from torchvision import models
from pathlib import Path

NUM_CLASSES = 11
NUM_FRAMES = 4
CROP_SIZE = 96        # MobileNet 最小 96 就能跑
BATCH_SIZE = 8
EPOCHS = 20
LR = 1e-3

BASE_DIR = Path(__file__).parent
MODEL_DIR = BASE_DIR / 'models'
MODEL_DIR.mkdir(exist_ok=True)
AIST_DIR = BASE_DIR / 'data' / 'aist_clips'
HAGRID_DIR = BASE_DIR / 'data' / 'hagrid_clips'
CUSTOM_DIR = BASE_DIR / 'data' / 'raw_videos'

GESTURE_CLASSES = [
    'raise_both_hands', 'point_up', 'heart', 'clap', 'spread_arms',
    'fly_kiss', 'cover_face', 'hands_on_hips', 'cross_arms',
    'chin_rest', 'neutral'
]

# COCO 17-joint skeleton edges
SKELETON_EDGES = [
    (0, 1), (0, 2), (1, 3), (2, 4),
    (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
    (5, 11), (6, 12), (11, 12),
    (11, 13), (13, 15), (12, 14), (14, 16),
]


class SkeletonVideoModel(nn.Module):
    """MobileNetV3-Small per-frame encoder + temporal average pooling + classifier."""

    def __init__(self, num_classes):
        super().__init__()
        backbone = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.IMAGENET1K_V1)
        # Remove classifier, keep features (output: 576-dim)
        self.features = backbone.features
        self.pool = nn.AdaptiveAvgPool2d(1)
        self.classifier = nn.Sequential(
            nn.Linear(576, 128),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(128, num_classes),
        )

    def forward(self, x):
        # x: (B, T, 3, H, W)
        B, T = x.shape[0], x.shape[1]
        x = x.view(B * T, *x.shape[2:])      # (B*T, 3, H, W)
        x = self.features(x)                   # (B*T, 576, h, w)
        x = self.pool(x).flatten(1)            # (B*T, 576)
        x = x.view(B, T, -1)                   # (B, T, 576)
        x = x.mean(dim=1)                      # (B, 576) temporal avg pool
        return self.classifier(x)              # (B, num_classes)


class GestureDataset(Dataset):
    def __init__(self, samples, num_frames=NUM_FRAMES, crop_size=CROP_SIZE, augment=True):
        self.samples = samples
        self.num_frames = num_frames
        self.crop_size = crop_size
        self.augment = augment

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label, stype = self.samples[idx]
        if stype == 'skeleton':
            frames = self._render_skeleton(path)
        elif stype == 'image':
            frames = self._load_image(path)
        else:
            frames = self._load_video(path)

        # Normalize ImageNet style
        frames = frames / 255.0
        mean = np.array([0.485, 0.456, 0.406]).reshape(1, 3, 1, 1)
        std = np.array([0.229, 0.224, 0.225]).reshape(1, 3, 1, 1)
        frames = (frames - mean) / std
        return torch.from_numpy(frames).float(), label

    def _render_skeleton(self, npy_path):
        kp3d = np.load(str(npy_path))  # (T, 17, 3)
        T = kp3d.shape[0]
        indices = np.linspace(0, T - 1, self.num_frames, dtype=int)
        frames = []
        for i in indices:
            frames.append(self._draw_skeleton(kp3d[i]))
        return np.stack(frames)  # (T, 3, H, W)

    def _draw_skeleton(self, kp):
        img = np.zeros((self.crop_size, self.crop_size, 3), dtype=np.uint8)
        xs, ys = kp[:, 0].copy(), kp[:, 1].copy()

        # Handle NaN/Inf
        valid = np.isfinite(xs) & np.isfinite(ys)
        if valid.sum() < 3:
            return img.transpose(2, 0, 1).astype(np.float32)

        xs[~valid] = xs[valid].mean()
        ys[~valid] = ys[valid].mean()

        x_min, x_max = xs.min(), xs.max()
        y_min, y_max = ys.min(), ys.max()
        x_range = max(x_max - x_min, 0.01)
        y_range = max(y_max - y_min, 0.01)
        scale = min((self.crop_size - 10) / x_range, (self.crop_size - 10) / y_range)

        px = ((xs - x_min) * scale + 5).astype(int)
        py = self.crop_size - ((ys - y_min) * scale + 5).astype(int)
        px = np.clip(px, 0, self.crop_size - 1)
        py = np.clip(py, 0, self.crop_size - 1)

        for i, j in SKELETON_EDGES:
            cv2.line(img, (px[i], py[i]), (px[j], py[j]), (0, 200, 100), 2)
        for k in range(17):
            cv2.circle(img, (px[k], py[k]), 2, (255, 100, 50), -1)

        return img.transpose(2, 0, 1).astype(np.float32)  # (3, H, W)

    def _load_image(self, path):
        img = cv2.imread(str(path))
        if img is None:
            img = np.zeros((self.crop_size, self.crop_size, 3), dtype=np.uint8)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (self.crop_size, self.crop_size))
        frames = []
        for _ in range(self.num_frames):
            f = img.copy()
            if self.augment:
                dx, dy = np.random.randint(-3, 4, 2)
                M = np.float32([[1, 0, dx], [0, 1, dy]])
                f = cv2.warpAffine(f, M, (self.crop_size, self.crop_size))
            frames.append(f.transpose(2, 0, 1).astype(np.float32))
        return np.stack(frames)

    def _load_video(self, path):
        cap = cv2.VideoCapture(str(path))
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        indices = np.linspace(0, max(total - 1, 0), self.num_frames, dtype=int)
        frames = []
        for i in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ret, f = cap.read()
            if ret:
                f = cv2.cvtColor(f, cv2.COLOR_BGR2RGB)
                f = cv2.resize(f, (self.crop_size, self.crop_size))
                frames.append(f.transpose(2, 0, 1).astype(np.float32))
        cap.release()
        while len(frames) < self.num_frames:
            frames.append(frames[-1] if frames else np.zeros((3, self.crop_size, self.crop_size), dtype=np.float32))
        return np.stack(frames[:self.num_frames])


def collect_samples():
    samples = []
    for idx, label in enumerate(GESTURE_CLASSES):
        for d in [AIST_DIR, HAGRID_DIR, CUSTOM_DIR]:
            ld = d / label
            if not ld.exists():
                continue
            for f in sorted(ld.glob('*.npy'))[:500]:
                samples.append((str(f), idx, 'skeleton'))
            for f in sorted(ld.glob('*.mp4'))[:200]:
                samples.append((str(f), idx, 'video'))
            for f in sorted(ld.glob('*.jpg'))[:500]:
                samples.append((str(f), idx, 'image'))
            for f in sorted(ld.glob('*.png'))[:500]:
                samples.append((str(f), idx, 'image'))
    return samples


def main():
    print("=" * 55)
    print("  MobileNet Gesture Classifier Training")
    print("=" * 55)

    samples = collect_samples()
    if not samples:
        print("  [ERROR] No data found!")
        return

    from collections import Counter
    counts = Counter(s[1] for s in samples)
    print(f"\n  Samples: {len(samples)}")
    for i, l in enumerate(GESTURE_CLASSES):
        print(f"    {l:25s} {counts.get(i, 0):5d}")

    random.shuffle(samples)
    split = int(len(samples) * 0.85)
    train_ds = GestureDataset(samples[:split])
    val_ds = GestureDataset(samples[split:], augment=False)
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, num_workers=0)

    print(f"\n  Train: {len(train_ds)}, Val: {len(val_ds)}")
    print("  Loading MobileNetV3-Small...")

    model = SkeletonVideoModel(NUM_CLASSES)
    # Freeze backbone, train classifier only
    for p in model.features.parameters():
        p.requires_grad = False

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(filter(lambda p: p.requires_grad, model.parameters()), lr=LR)

    best_acc = 0
    for epoch in range(EPOCHS):
        model.train()
        total_loss, correct, total = 0, 0, 0
        for batch_idx, (clips, labels) in enumerate(train_loader):
            out = model(clips)
            loss = criterion(out, labels)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * clips.size(0)
            correct += (out.argmax(1) == labels).sum().item()
            total += clips.size(0)
            if batch_idx % 50 == 0:
                print(f"    batch {batch_idx}/{len(train_loader)}", flush=True)

        model.eval()
        val_correct, val_total = 0, 0
        with torch.no_grad():
            for clips, labels in val_loader:
                out = model(clips)
                val_correct += (out.argmax(1) == labels).sum().item()
                val_total += clips.size(0)

        train_acc = correct / max(total, 1)
        val_acc = val_correct / max(val_total, 1)
        print(f"  Epoch {epoch+1:2d}/{EPOCHS}  loss={total_loss/max(total,1):.4f}  "
              f"train={train_acc:.3f}  val={val_acc:.3f}", flush=True)

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(model.state_dict(), str(MODEL_DIR / 'mobilenet_gesture_best.pt'))

    torch.save(model.state_dict(), str(MODEL_DIR / 'mobilenet_gesture.pt'))
    print(f"\n  Best val: {best_acc:.3f}")
    print(f"  [OK] models/mobilenet_gesture.pt")

    # ONNX export
    model.eval()
    dummy = torch.randn(1, NUM_FRAMES, 3, CROP_SIZE, CROP_SIZE)
    try:
        torch.onnx.export(model, dummy, str(MODEL_DIR / 'MobileNet_Gesture.onnx'),
                          input_names=['video'], output_names=['gesture'], opset_version=13)
        print(f"  [OK] models/MobileNet_Gesture.onnx")
    except Exception as e:
        print(f"  [WARN] ONNX export: {e}")

    with open(MODEL_DIR / 'mobilenet_label_map.json', 'w') as f:
        json.dump({i: l for i, l in enumerate(GESTURE_CLASSES)}, f, indent=2)
    print(f"  [OK] models/mobilenet_label_map.json")


if __name__ == '__main__':
    main()
