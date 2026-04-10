"""
collect_data.py
从手势视频中提取 MediaPipe 姿势关键点序列，保存为 .npy 供训练使用。

使用方法:
  1. 把手势视频放入 data/raw_videos/<gesture_name>/ 文件夹
     例: data/raw_videos/heart/clip1.mp4, clip2.mp4 ...
  2. 运行: python collect_data.py
  3. 输出保存到 data/keypoints/<gesture_name>/
"""

import os
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from pathlib import Path

# ── 配置 ─────────────────────────────────────────────
GESTURE_LABELS = [
    "raise_both_hands",  # 🙌 双手举高
    "point_up",          # ☝️ 指天
    "heart",             # 🫶 比心
    "clap",              # 👏 拍手
    "spread_arms",       # 🤸 展开双臂
    "fly_kiss",          # 😘 飞吻
    "cover_face",        # 🤭 捂脸卖萌
    "hands_on_hips",     # 🤗 叉腰
    "cross_arms",        # 🙅 双手交叉
    "chin_rest",         # 🤔 托腮
    "neutral",           # 普通站立
]

SEQUENCE_LENGTH = 15    # 每个样本帧数
FEAT_DIM        = 18    # 9 关节点 × (x, y)
FRAME_SKIP      = 2     # 每隔 N 帧采样（从3改为2，提取更密）
MIN_CONFIDENCE  = 0.35  # 关键点最低置信度阈值（从0.4降低，容纳更多样本）

BASE_DIR = Path(__file__).parent
RAW_DIR  = BASE_DIR / "data" / "raw_videos"
OUT_DIR  = BASE_DIR / "data" / "keypoints"
MODEL_PATH = str(BASE_DIR / "pose_landmarker_lite.task")

# ── MediaPipe 关节索引（9 关节）────────────────────────
# 0=nose, 11=left_shoulder, 12=right_shoulder
# 13=left_elbow, 14=right_elbow
# 15=left_wrist, 16=right_wrist
# 23=left_hip, 24=right_hip
USED_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24]


def extract_keypoints(pose_landmarks_list) -> np.ndarray | None:
    """从 MediaPipe Tasks 结果中提取归一化关键点，返回 shape (18,) 或 None。"""
    if not pose_landmarks_list:
        return None
    lm = pose_landmarks_list
    kp = []
    for i in USED_INDICES:
        pt = lm[i]
        vis = pt.visibility if hasattr(pt, 'visibility') else 1.0
        if vis < MIN_CONFIDENCE:
            kp.extend([0.0, 0.0])
        else:
            kp.extend([pt.x, pt.y])
    return np.array(kp, dtype=np.float32)


def sliding_window_sequences(frames: list, seq_len: int, stride: int = 5):
    """滑动窗口切割，扩充样本数量。"""
    sequences = []
    for start in range(0, max(1, len(frames) - seq_len + 1), stride):
        seg = frames[start: start + seq_len]
        if len(seg) == seq_len:
            sequences.append(np.stack(seg))
    return sequences


def process_video(video_path: str) -> list:
    """从单个视频提取多个关键点序列样本。"""
    base_options = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
    options = mp_vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=mp_vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  [SKIP] 无法打开视频: {video_path}")
        return []

    all_frames = []
    frame_idx = 0

    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % FRAME_SKIP != 0:
                frame_idx += 1
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect(mp_image)

            if result.pose_landmarks:
                kp = extract_keypoints(result.pose_landmarks[0])
                if kp is not None:
                    all_frames.append(kp)

            frame_idx += 1

    cap.release()

    if len(all_frames) < SEQUENCE_LENGTH:
        print(f"  [WARN] 视频帧数不足 ({len(all_frames)}帧 < {SEQUENCE_LENGTH}): {video_path}")
        while len(all_frames) < SEQUENCE_LENGTH:
            all_frames.append(all_frames[-1] if all_frames else np.zeros(FEAT_DIM))

    # stride=2 产出更多序列（原 stride=3 太稀疏）
    return sliding_window_sequences(all_frames, SEQUENCE_LENGTH, stride=2)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total_samples = 0

    if not Path(MODEL_PATH).exists():
        print(f"[ERROR] 找不到 pose 模型: {MODEL_PATH}")
        print("请先运行 auto_detect_label.py（会自动下载模型）")
        return

    for label in GESTURE_LABELS:
        raw_dir = RAW_DIR / label
        out_dir = OUT_DIR / label

        if not raw_dir.exists():
            print(f"[MISS] 目录不存在，跳过: {raw_dir}")
            out_dir.mkdir(parents=True, exist_ok=True)
            continue

        out_dir.mkdir(parents=True, exist_ok=True)
        video_files = [f for f in raw_dir.iterdir()
                       if f.suffix.lower() in (".mp4", ".mov", ".avi", ".m4v")]

        if not video_files:
            print(f"[EMPTY] {label}: 没有视频文件")
            continue

        label_sequences = []
        for vf in video_files:
            print(f"  处理: {vf.name}")
            seqs = process_video(str(vf))
            label_sequences.extend(seqs)
            print(f"    → {len(seqs)} 个序列样本")

        if label_sequences:
            arr = np.stack(label_sequences)  # (N, seq_len, feat_dim)
            out_path = out_dir / "sequences.npy"
            np.save(str(out_path), arr)
            print(f"  ✅ {label}: {arr.shape[0]} 个样本 → {out_path}")
            total_samples += arr.shape[0]
        else:
            print(f"  ❌ {label}: 没有有效样本")

    print(f"\n🎉 完成！共 {total_samples} 个训练样本。")
    print(f"   接下来运行: python train.py")


if __name__ == "__main__":
    main()
