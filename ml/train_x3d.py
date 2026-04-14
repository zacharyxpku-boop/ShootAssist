"""
train_x3d.py — X3D video model fine-tuning for gesture recognition
Replaces LSTM keypoint classifier with video-based X3D (Meta/Facebook)

Input: video clips from HaGRID (images->pseudo-clips) + AIST++ (dance video)
Output: models/x3d_gesture.pt + CoreML export

Usage:
  pip install torch torchvision pytorchvideo
  python ml/train_x3d.py
"""

import os, json, random, glob
import numpy as np
import cv2
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from pathlib import Path

# Config
NUM_CLASSES = 11
NUM_FRAMES = 4        # x3d_xs: only 4 frames (much lighter than x3d_s's 13)
CROP_SIZE = 160       # min viable for x3d_xs pooling kernel (4,5,5)
SAMPLING_RATE = 12
BATCH_SIZE = 2
EPOCHS = 15
LR_HEAD = 1e-2
LR_BACKBONE = 1e-4
MODEL_NAME = 'x3d_xs'  # xs=0.91 GFLOPs vs s=2.96 GFLOPs

BASE_DIR = Path(__file__).parent
MODEL_DIR = BASE_DIR / 'models'
MODEL_DIR.mkdir(exist_ok=True)

GESTURE_CLASSES = [
    'raise_both_hands', 'point_up', 'heart', 'clap', 'spread_arms',
    'fly_kiss', 'cover_face', 'hands_on_hips', 'cross_arms',
    'chin_rest', 'neutral'
]

# Data directories
HAGRID_DIR = BASE_DIR / 'data' / 'hagrid_clips'   # organized: hagrid_clips/<label>/<images>
AIST_DIR = BASE_DIR / 'data' / 'aist_clips'       # organized: aist_clips/<label>/<videos>
CUSTOM_DIR = BASE_DIR / 'data' / 'raw_videos'     # your own recorded videos


class GestureClipDataset(Dataset):
    """Unified dataset: loads video clips or converts images to pseudo-clips."""

    def __init__(self, samples, num_frames=NUM_FRAMES, crop_size=CROP_SIZE, augment=True):
        self.samples = samples  # list of (path, label_idx, type='image'|'video')
        self.num_frames = num_frames
        self.crop_size = crop_size
        self.augment = augment
        self.mean = np.array([0.45, 0.45, 0.45], dtype=np.float32)
        self.std = np.array([0.225, 0.225, 0.225], dtype=np.float32)

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label, source_type = self.samples[idx]

        if source_type == 'skeleton':
            clip = self._load_skeleton_clip(path)
        elif source_type == 'image':
            clip = self._load_image_clip(path)
        else:
            clip = self._load_video_clip(path)

        # Normalize
        clip = clip / 255.0
        clip = (clip - self.mean.reshape(3, 1, 1, 1)) / self.std.reshape(3, 1, 1, 1)

        return torch.from_numpy(clip).float(), label

    def _load_image_clip(self, image_path):
        """Single image -> pseudo video clip with spatial jitter."""
        img = cv2.imread(str(image_path))
        if img is None:
            img = np.zeros((self.crop_size, self.crop_size, 3), dtype=np.uint8)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (self.crop_size, self.crop_size))

        frames = []
        for i in range(self.num_frames):
            frame = img.copy()
            if self.augment and i > 0:
                dx, dy = np.random.randint(-4, 5, 2)
                M = np.float32([[1, 0, dx], [0, 1, dy]])
                frame = cv2.warpAffine(frame, M, (self.crop_size, self.crop_size))
            frames.append(frame)

        clip = np.stack(frames, axis=0)  # (T, H, W, 3)
        return clip.transpose(3, 0, 1, 2).astype(np.float32)  # (3, T, H, W)

    def _load_video_clip(self, video_path):
        """Load video, uniformly sample num_frames."""
        cap = cv2.VideoCapture(str(video_path))
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        if total <= 0:
            cap.release()
            return np.zeros((3, self.num_frames, self.crop_size, self.crop_size), dtype=np.float32)

        indices = np.linspace(0, total - 1, self.num_frames, dtype=int)

        frames = []
        for fidx in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, fidx)
            ret, frame = cap.read()
            if ret:
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                frame = cv2.resize(frame, (self.crop_size, self.crop_size))
                frames.append(frame)
            elif frames:
                frames.append(frames[-1].copy())

        cap.release()

        while len(frames) < self.num_frames:
            frames.append(frames[-1] if frames else np.zeros((self.crop_size, self.crop_size, 3), dtype=np.uint8))

        clip = np.stack(frames[:self.num_frames], axis=0)
        return clip.transpose(3, 0, 1, 2).astype(np.float32)

    # COCO 17-joint skeleton connections for rendering
    _SKELETON_EDGES = [
        (0, 1), (0, 2), (1, 3), (2, 4),  # head
        (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),  # arms
        (5, 11), (6, 12), (11, 12),  # torso
        (11, 13), (13, 15), (12, 14), (14, 16),  # legs
    ]

    def _load_skeleton_clip(self, npy_path):
        """Render 3D keypoints (T, 17, 3) as skeleton images for X3D input."""
        kp3d = np.load(str(npy_path))  # (T, 17, 3)
        T = kp3d.shape[0]
        # Sample num_frames uniformly
        indices = np.linspace(0, T - 1, self.num_frames, dtype=int)

        frames = []
        for fidx in indices:
            kp = kp3d[fidx]  # (17, 3)
            frame = self._render_skeleton(kp)
            frames.append(frame)

        clip = np.stack(frames, axis=0)  # (T, H, W, 3)
        return clip.transpose(3, 0, 1, 2).astype(np.float32)  # (3, T, H, W)

    def _render_skeleton(self, kp):
        """Render single frame of 17 COCO keypoints as RGB image."""
        img = np.zeros((self.crop_size, self.crop_size, 3), dtype=np.uint8)

        # Normalize 3D coords to image space (use x, y; ignore z)
        xs, ys = kp[:, 0], kp[:, 1]
        # Auto-scale to fit image with margin
        x_min, x_max = xs.min(), xs.max()
        y_min, y_max = ys.min(), ys.max()
        x_range = max(x_max - x_min, 0.01)
        y_range = max(y_max - y_min, 0.01)
        scale = min((self.crop_size - 20) / x_range, (self.crop_size - 20) / y_range)

        px = ((xs - x_min) * scale + 10).astype(int)
        py = ((ys - y_min) * scale + 10).astype(int)
        # Flip y (image coords: y-down)
        py = self.crop_size - py

        px = np.clip(px, 0, self.crop_size - 1)
        py = np.clip(py, 0, self.crop_size - 1)

        # Draw edges
        for i, j in self._SKELETON_EDGES:
            cv2.line(img, (px[i], py[i]), (px[j], py[j]), (0, 200, 100), 2)

        # Draw joints
        for k in range(17):
            cv2.circle(img, (px[k], py[k]), 3, (255, 100, 50), -1)

        # Augment: random bg color shift, small rotation
        if self.augment:
            bg_color = np.random.randint(0, 30, 3, dtype=np.uint8)
            mask = (img.sum(axis=2) == 0)
            img[mask] = bg_color

        return img


def collect_samples():
    """Scan all data directories and build sample list."""
    samples = []

    # 1. HaGRID images (organized by label)
    for label_idx, label in enumerate(GESTURE_CLASSES):
        img_dir = HAGRID_DIR / label
        if img_dir.exists():
            for img_path in sorted(img_dir.glob('*.*'))[:500]:  # cap per class
                if img_path.suffix.lower() in ('.jpg', '.jpeg', '.png'):
                    samples.append((str(img_path), label_idx, 'image'))

    # 2. AIST++ skeleton clips (npy) or video clips (mp4)
    for label_idx, label in enumerate(GESTURE_CLASSES):
        vid_dir = AIST_DIR / label
        if vid_dir.exists():
            # npy skeleton files (from fetch_aist.py auto-labeling)
            for npy_path in sorted(vid_dir.glob('*.npy'))[:500]:
                samples.append((str(npy_path), label_idx, 'skeleton'))
            # video files if any
            for vid_path in sorted(vid_dir.glob('*.mp4'))[:200]:
                samples.append((str(vid_path), label_idx, 'video'))

    # 3. Custom recorded videos
    for label_idx, label in enumerate(GESTURE_CLASSES):
        vid_dir = CUSTOM_DIR / label
        if vid_dir.exists():
            for vid_path in vid_dir.glob('*.*'):
                if vid_path.suffix.lower() in ('.mp4', '.mov', '.avi', '.m4v'):
                    samples.append((str(vid_path), label_idx, 'video'))

    return samples


def build_model(num_classes=NUM_CLASSES, freeze_backbone=True):
    """Load X3D-S and replace classification head."""
    model = torch.hub.load('facebookresearch/pytorchvideo', MODEL_NAME, pretrained=True)

    # Replace final projection: 2048 -> num_classes
    model.blocks[5].proj = nn.Linear(2048, num_classes)

    if freeze_backbone:
        for i in range(5):
            for param in model.blocks[i].parameters():
                param.requires_grad = False

    return model


def train():
    print("=" * 55)
    print("  X3D Gesture Recognition Training")
    print("=" * 55)

    # Collect data
    samples = collect_samples()
    if not samples:
        print("\n  [ERROR] No training data found!")
        print(f"  Put HaGRID images in: {HAGRID_DIR}/<label>/")
        print(f"  Put AIST++ clips in:  {AIST_DIR}/<label>/")
        print(f"  Put your videos in:   {CUSTOM_DIR}/<label>/")
        print(f"  Labels: {GESTURE_CLASSES}")
        return

    # Class distribution
    from collections import Counter
    label_counts = Counter(s[1] for s in samples)
    print(f"\n  Total samples: {len(samples)}")
    for idx, label in enumerate(GESTURE_CLASSES):
        print(f"    {label:25s} {label_counts.get(idx, 0):5d}")

    # Split train/val
    random.shuffle(samples)
    split = int(len(samples) * 0.85)
    train_samples = samples[:split]
    val_samples = samples[split:]

    train_ds = GestureClipDataset(train_samples, augment=True)
    val_ds = GestureClipDataset(val_samples, augment=False)
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False, num_workers=0)

    # Build model
    print("\n  Loading X3D-S pretrained on Kinetics-400...")
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"  Device: {device}")
    model = build_model(freeze_backbone=True).to(device)

    # Optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=LR_HEAD, weight_decay=1e-5
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)

    # Training loop
    best_val_acc = 0
    for epoch in range(EPOCHS):
        model.train()
        train_loss, train_correct, train_total = 0, 0, 0

        for clips, labels in train_loader:
            clips, labels = clips.to(device), labels.to(device)
            preds = model(clips)
            loss = criterion(preds, labels)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            train_loss += loss.item() * clips.size(0)
            train_correct += (preds.argmax(1) == labels).sum().item()
            train_total += clips.size(0)

        scheduler.step()

        # Validation
        model.eval()
        val_correct, val_total = 0, 0
        with torch.no_grad():
            for clips, labels in val_loader:
                clips, labels = clips.to(device), labels.to(device)
                preds = model(clips)
                val_correct += (preds.argmax(1) == labels).sum().item()
                val_total += clips.size(0)

        train_acc = train_correct / max(train_total, 1)
        val_acc = val_correct / max(val_total, 1)
        print(f"  Epoch {epoch+1:2d}/{EPOCHS}  "
              f"loss={train_loss/max(train_total,1):.4f}  "
              f"train_acc={train_acc:.3f}  val_acc={val_acc:.3f}")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), str(MODEL_DIR / 'x3d_gesture_best.pt'))

    # Save final
    torch.save(model.state_dict(), str(MODEL_DIR / 'x3d_gesture.pt'))
    print(f"\n  Best val_acc: {best_val_acc:.3f}")
    print(f"  [OK] models/x3d_gesture.pt")
    print(f"  [OK] models/x3d_gesture_best.pt")

    # Export ONNX
    print("\n  Exporting ONNX...")
    model.eval().cpu()
    dummy = torch.randn(1, 3, NUM_FRAMES, CROP_SIZE, CROP_SIZE)
    try:
        torch.onnx.export(
            model, dummy, str(MODEL_DIR / 'X3D_Gesture.onnx'),
            input_names=['video'], output_names=['gesture'],
            opset_version=13
        )
        print(f"  [OK] models/X3D_Gesture.onnx")
    except Exception as e:
        print(f"  [WARN] ONNX export failed: {e}")

    # Label map
    label_map = {i: l for i, l in enumerate(GESTURE_CLASSES)}
    with open(MODEL_DIR / 'x3d_label_map.json', 'w') as f:
        json.dump(label_map, f, indent=2)
    print(f"  [OK] models/x3d_label_map.json")


if __name__ == '__main__':
    train()
