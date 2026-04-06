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

# ── 配置 ─────────────────────────────────────────────────
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

SEQUENCE_LENGTH = 15    # 每个样本帧数（0.2s/帧 × 15 = 3 秒窗口）
KEYPOINT_DIM   = 16     # 每帧特征数：8 关节点 × (x, y)
FRAME_SKIP     = 3      # 每隔 N 帧采样一次（控制采样密度）
MIN_CONFIDENCE = 0.4    # 关键点最低置信度阈值
RAW_DIR  = "data/raw_videos"
OUT_DIR  = "data/keypoints"

# ── MediaPipe 关节索引（使用上半身：肩、肘、腕、鼻、臀） ──
# MediaPipe Pose 33 个关节点索引:
# 0=nose, 11=left_shoulder, 12=right_shoulder
# 13=left_elbow, 14=right_elbow
# 15=left_wrist, 16=right_wrist
# 23=left_hip, 24=right_hip
USED_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24]
# 9 关节 × 2 = 18 features（鼻子+两侧肩/肘/腕+两侧臀）
KEYPOINT_DIM_ACTUAL = len(USED_INDICES) * 2  # = 18


def extract_keypoints(results) -> np.ndarray | None:
    """从 MediaPipe 结果中提取归一化关键点，返回 shape (18,) 或 None。"""
    if not results.pose_landmarks:
        return None
    lm = results.pose_landmarks.landmark
    kp = []
    for i in USED_INDICES:
        pt = lm[i]
        if pt.visibility < MIN_CONFIDENCE:
            kp.extend([0.0, 0.0])  # 置信度不足填 0
        else:
            kp.extend([pt.x, pt.y])
    return np.array(kp, dtype=np.float32)


def sliding_window_sequences(frames: list[np.ndarray], seq_len: int, stride: int = 5):
    """滑动窗口切割，扩充样本数量。"""
    sequences = []
    for start in range(0, max(1, len(frames) - seq_len + 1), stride):
        seg = frames[start: start + seq_len]
        if len(seg) == seq_len:
            sequences.append(np.stack(seg))  # (seq_len, dim)
    return sequences


def process_video(video_path: str) -> list[np.ndarray]:
    """从单个视频提取多个关键点序列样本。"""
    mp_pose = mp.solutions.pose
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  [SKIP] 无法打开视频: {video_path}")
        return []

    all_frames = []
    frame_idx = 0

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    ) as pose:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % FRAME_SKIP != 0:
                frame_idx += 1
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb)
            kp = extract_keypoints(results)
            if kp is not None:
                all_frames.append(kp)
            frame_idx += 1

    cap.release()

    if len(all_frames) < SEQUENCE_LENGTH:
        print(f"  [WARN] 视频帧数不足 ({len(all_frames)}帧 < {SEQUENCE_LENGTH}): {video_path}")
        # 不足则填充最后一帧
        while len(all_frames) < SEQUENCE_LENGTH:
            all_frames.append(all_frames[-1] if all_frames else np.zeros(KEYPOINT_DIM_ACTUAL))

    return sliding_window_sequences(all_frames, SEQUENCE_LENGTH, stride=3)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total_samples = 0

    for label in GESTURE_LABELS:
        raw_dir = os.path.join(RAW_DIR, label)
        out_dir = os.path.join(OUT_DIR, label)

        if not os.path.exists(raw_dir):
            print(f"[MISS] 目录不存在，跳过: {raw_dir}")
            os.makedirs(raw_dir, exist_ok=True)
            continue

        os.makedirs(out_dir, exist_ok=True)
        video_files = [f for f in os.listdir(raw_dir) if f.lower().endswith((".mp4", ".mov", ".avi", ".m4v"))]

        if not video_files:
            print(f"[EMPTY] {label}: 没有视频文件")
            continue

        label_sequences = []
        for vf in video_files:
            vpath = os.path.join(raw_dir, vf)
            print(f"  处理: {vf}")
            seqs = process_video(vpath)
            label_sequences.extend(seqs)
            print(f"    → {len(seqs)} 个序列样本")

        if label_sequences:
            arr = np.stack(label_sequences)  # (N, seq_len, dim)
            out_path = os.path.join(out_dir, "sequences.npy")
            np.save(out_path, arr)
            print(f"  ✅ {label}: {arr.shape[0]} 个样本 → {out_path}")
            total_samples += arr.shape[0]
        else:
            print(f"  ❌ {label}: 没有有效样本")

    print(f"\n🎉 完成！共 {total_samples} 个训练样本。")
    print(f"   接下来运行: python train.py")


if __name__ == "__main__":
    main()
