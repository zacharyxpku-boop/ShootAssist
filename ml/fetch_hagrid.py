"""
fetch_hagrid.py — 从 HaGRID 数据集下载手势图片，用 MediaPipe 提取关键点
HaGRID: 552K 手势图片，18类。我们只取与小白快门重叠的类别。

映射关系:
  HaGRID "call"        → 不用
  HaGRID "dislike"     → 不用
  HaGRID "fist"        → cross_arms (近似：手臂紧缩)
  HaGRID "like"        → point_up (近似：竖拇指≈指向上)
  HaGRID "ok"          → heart (近似：手指圈→比心)
  HaGRID "peace"       → spread_arms (近似：V字→展开)
  HaGRID "rock"        → raise_both_hands (近似：摇滚手势)
  HaGRID "stop"        → hands_on_hips (近似：手掌张开)
  HaGRID "no_gesture"  → neutral

用法:
  1. pip install mediapipe opencv-python requests
  2. python ml/fetch_hagrid.py

注意: HaGRID 子集下载约 500MB-1GB。脚本会用 HuggingFace datasets API。
如果网络不通，可以手动下载到 data/hagrid/ 再运行。
"""

import os, json, random
import cv2
import numpy as np
from pathlib import Path

try:
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision as mp_vision
except ImportError:
    print("需要安装 mediapipe: pip install mediapipe")
    exit(1)

# ── 配置 ────────────────────────────────────────────
BASE_DIR   = Path(__file__).parent
DATA_DIR   = BASE_DIR / 'data' / 'keypoints'
HAGRID_DIR = BASE_DIR / 'data' / 'hagrid'
MODEL_PATH = str(BASE_DIR / 'pose_landmarker_lite.task')

SEQ_LEN  = 15
FEAT_DIM = 18
USED_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24]  # 9 joints

# HaGRID 类别 → 小白快门类别映射
HAGRID_MAP = {
    'no_gesture': 'neutral',
    'stop':       'hands_on_hips',
    'like':       'point_up',
    'peace':      'spread_arms',
    'ok':         'heart',
    'rock':       'raise_both_hands',
}

SAMPLES_PER_CLASS = 100  # 每类取多少张图

# ── MediaPipe 关键点提取 ───────────────────────────
def extract_keypoints_from_image(landmarker, image_path: str) -> np.ndarray | None:
    """从单张图片提取 9 关节 (18,) 向量"""
    img = cv2.imread(image_path)
    if img is None:
        return None
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect(mp_image)

    if not result.pose_landmarks:
        return None

    lm = result.pose_landmarks[0]
    kp = []
    for i in USED_INDICES:
        pt = lm[i]
        vis = pt.visibility if hasattr(pt, 'visibility') else 1.0
        if vis < 0.3:
            kp.extend([0.0, 0.0])
        else:
            kp.extend([pt.x, pt.y])
    return np.array(kp, dtype=np.float32)


def images_to_pseudo_sequences(keypoints_list: list, seq_len=SEQ_LEN) -> np.ndarray:
    """
    将静态图片关键点转为伪时间序列。
    策略: 每张图复制 seq_len 帧，加逐帧微抖动模拟真实视频。
    """
    sequences = []
    for kp in keypoints_list:
        frames = []
        for t in range(seq_len):
            jittered = kp.copy()
            # 逐帧加小幅高斯噪声模拟自然抖动
            jittered += np.random.normal(0, 0.008, kp.shape).astype(np.float32)
            frames.append(jittered)
        sequences.append(np.stack(frames))  # (seq_len, 18)
    return np.stack(sequences) if sequences else np.array([])


# ── 下载 HaGRID 子集 ────────────────────────────────
def download_hagrid_subset():
    """尝试用 HuggingFace datasets 下载，失败则给手动指引"""
    try:
        from datasets import load_dataset
        print("通过 HuggingFace datasets 下载 HaGRID 子集...")
        for hagrid_class, our_class in HAGRID_MAP.items():
            out_dir = HAGRID_DIR / hagrid_class
            out_dir.mkdir(parents=True, exist_ok=True)

            existing = list(out_dir.glob("*.jpg")) + list(out_dir.glob("*.png"))
            if len(existing) >= SAMPLES_PER_CLASS:
                print(f"  {hagrid_class}: 已有 {len(existing)} 张，跳过下载")
                continue

            print(f"  下载 {hagrid_class} (目标 {SAMPLES_PER_CLASS} 张)...")
            try:
                ds = load_dataset(
                    "cj-mills/hagrid-sample-500k-384p",
                    split=f"train[:{SAMPLES_PER_CLASS}]",
                )
                for i, item in enumerate(ds):
                    img = item['image']
                    img.save(str(out_dir / f"{hagrid_class}_{i:04d}.jpg"))
                print(f"    [OK] {hagrid_class}: {len(ds)} images")
            except Exception as e:
                print(f"    [FAIL] {hagrid_class} download failed: {e}")
                print(f"    → 请手动下载到 {out_dir}/")

        return True
    except ImportError:
        print("未安装 datasets 库。两种方案：")
        print("  方案A: pip install datasets  (然后重新运行)")
        print("  方案B: 手动下载图片到 ml/data/hagrid/<类名>/ 文件夹")
        print(f"  需要的类: {list(HAGRID_MAP.keys())}")
        return False


# ── 主流程 ──────────────────────────────────────────
def main():
    print("\n" + "=" * 55)
    print("  HaGRID → 小白快门 数据转换")
    print("=" * 55)

    # Step 1: 确保有图片
    has_data = False
    for hagrid_class in HAGRID_MAP:
        d = HAGRID_DIR / hagrid_class
        if d.exists() and len(list(d.glob("*.*"))) > 0:
            has_data = True
            break

    if not has_data:
        print("\n未找到 HaGRID 图片，尝试自动下载...")
        download_hagrid_subset()

    # Step 2: 用 MediaPipe 提取关键点
    if not Path(MODEL_PATH).exists():
        print(f"\n[ERROR] 缺少 pose 模型: {MODEL_PATH}")
        print("请先从 ml/ 目录获取 pose_landmarker_lite.task")
        return

    base_options = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
    options = mp_vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=mp_vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.4,
    )

    total_generated = 0
    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        for hagrid_class, our_class in HAGRID_MAP.items():
            img_dir = HAGRID_DIR / hagrid_class
            if not img_dir.exists():
                print(f"\n  [SKIP] {hagrid_class}: 目录不存在")
                continue

            images = sorted(img_dir.glob("*.*"))[:SAMPLES_PER_CLASS]
            if not images:
                print(f"\n  [SKIP] {hagrid_class}: 没有图片")
                continue

            print(f"\n  处理 {hagrid_class} → {our_class} ({len(images)} 张)...")

            keypoints = []
            for img_path in images:
                kp = extract_keypoints_from_image(landmarker, str(img_path))
                if kp is not None:
                    keypoints.append(kp)

            if not keypoints:
                print(f"    [FAIL] no valid keypoints extracted")
                continue

            # 转为伪序列
            sequences = images_to_pseudo_sequences(keypoints)
            if sequences.size == 0:
                continue

            # 保存（追加到已有数据）
            out_dir = DATA_DIR / our_class
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / 'sequences.npy'

            if out_path.exists():
                existing = np.load(str(out_path))
                if existing.shape[1:] == sequences.shape[1:]:
                    sequences = np.concatenate([existing, sequences])
                    print(f"    合并已有 {existing.shape[0]} + 新增 {sequences.shape[0] - existing.shape[0]}")

            np.save(str(out_path), sequences)
            print(f"    [OK] {our_class}: {sequences.shape[0]} sequences -> {out_path}")
            total_generated += sequences.shape[0]

    print(f"\n{'=' * 55}")
    print(f"  完成！共 {total_generated} 条训练序列")
    print(f"  接下来: python ml/train.py")


if __name__ == '__main__':
    main()
