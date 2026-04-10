"""
fetch_ntu_skeleton.py — 从 NTU RGB+D 骨架数据提取并转换为小白快门格式
NTU RGB+D 60: 25关节 Kinect 骨架，56K序列，60个动作类别

重叠的动作类别映射:
  A1  (drink water)     → neutral  (类似日常站立)
  A2  (eat meal)        → neutral
  A6  (pick up)         → neutral
  A10 (clapping)        → clap
  A11 (reading)         → neutral
  A23 (hand waving)     → raise_both_hands
  A24 (kicking)         → neutral (站立变体)
  A26 (hopping)         → neutral
  A28 (phone call)      → chin_rest (手靠脸)
  A29 (playing with phone) → neutral
  A35 (nod head/bow)    → neutral
  A38 (salute)          → point_up (手举向上)
  A47 (touch head)      → cover_face (手碰脸部区域)
  A48 (touch chest)     → cross_arms (手在胸前)

NTU 25 关节 → MediaPipe 9 关节映射:
  NTU  3 (head)        → nose (0)
  NTU  4 (left shoulder) → L_sh (1)
  NTU  8 (right shoulder) → R_sh (2)
  NTU  5 (left elbow)   → L_el (3)
  NTU  9 (right elbow)  → R_el (4)
  NTU  6 (left wrist)   → L_wr (5)
  NTU 10 (right wrist)  → R_wr (6)
  NTU 12 (left hip)     → L_hp (7)
  NTU 16 (right hip)    → R_hp (8)

用法:
  1. 从 https://rose1.ntu.edu.sg/dataset/actionRecognition/ 下载骨架数据
     文件名: nturgbd_skeletons_s001_to_s017.zip (约 5.8GB)
  2. 解压到 ml/data/ntu_skeletons/
  3. python ml/fetch_ntu_skeleton.py

如果没下载完整数据集，脚本会给出手动指引。
"""

import os, re, json
import numpy as np
from pathlib import Path
from collections import defaultdict

BASE_DIR = Path(__file__).parent
NTU_DIR  = BASE_DIR / 'data' / 'ntu_skeletons'
DATA_DIR = BASE_DIR / 'data' / 'keypoints'

SEQ_LEN  = 15
FEAT_DIM = 18

# NTU 动作ID → 小白快门类别
NTU_ACTION_MAP = {
    1:  'neutral',           # drink water
    2:  'neutral',           # eat meal
    6:  'neutral',           # pick up
    10: 'clap',              # clapping
    11: 'neutral',           # reading
    23: 'raise_both_hands',  # hand waving
    28: 'chin_rest',         # phone call (hand near face)
    29: 'neutral',           # playing with phone
    35: 'neutral',           # nod head
    38: 'point_up',          # salute (hand raised)
    47: 'cover_face',        # touch head
    48: 'cross_arms',        # touch chest
}

# NTU 25关节(0-indexed) → 我们的9关节
# NTU 关节编号从1开始，这里转为0-indexed
NTU_TO_OURS = {
    2:  0,  # head → nose
    3:  1,  # left shoulder → L_sh  (NTU的left shoulder是index 4, 0-indexed=3)
    7:  2,  # right shoulder → R_sh (NTU index 8, 0-indexed=7)
    4:  3,  # left elbow → L_el    (NTU index 5, 0-indexed=4)
    8:  4,  # right elbow → R_el   (NTU index 9, 0-indexed=8)
    5:  5,  # left wrist → L_wr    (NTU index 6, 0-indexed=5)
    9:  6,  # right wrist → R_wr   (NTU index 10, 0-indexed=9)
    11: 7,  # left hip → L_hp      (NTU index 12, 0-indexed=11)
    15: 8,  # right hip → R_hp     (NTU index 16, 0-indexed=15)
}

MAX_SAMPLES_PER_CLASS = 200


def parse_ntu_skeleton(filepath: str) -> list | None:
    """
    解析 NTU RGB+D .skeleton 文件
    返回: list of frames, 每帧是 (25, 3) 的 xyz 坐标
    """
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
    except Exception:
        return None

    idx = 0
    n_frames = int(lines[idx].strip()); idx += 1
    if n_frames < SEQ_LEN:
        return None

    frames = []
    for _ in range(n_frames):
        n_bodies = int(lines[idx].strip()); idx += 1
        if n_bodies == 0:
            continue

        # 取第一个人
        idx += 1  # body info line
        n_joints = int(lines[idx].strip()); idx += 1

        joints = []
        for j in range(n_joints):
            parts = lines[idx].strip().split()
            x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
            joints.append((x, y, z))
            idx += 1

        # 跳过其他身体
        for b in range(1, n_bodies):
            idx += 1  # body info
            nj = int(lines[idx].strip()); idx += 1
            idx += nj  # skip joints

        frames.append(joints)

    return frames if len(frames) >= SEQ_LEN else None


def ntu_frames_to_sequences(frames: list) -> list:
    """将 NTU 帧序列转为 (SEQ_LEN, 18) 的样本列表"""
    # 提取并归一化到 2D (只取 x, y)
    processed_frames = []
    for frame_joints in frames:
        kp = np.zeros(FEAT_DIM, dtype=np.float32)
        for ntu_idx, our_idx in NTU_TO_OURS.items():
            if ntu_idx < len(frame_joints):
                x, y, z = frame_joints[ntu_idx]
                # NTU 坐标是米为单位的3D坐标，我们归一化到 [0,1]
                # 简化处理：x 映射到水平，y 映射到垂直（翻转，因为NTU y轴向上）
                nx = (x + 1.5) / 3.0  # 近似归一化
                ny = 1.0 - (y + 0.5) / 2.5  # 翻转 + 归一化
                nx = max(0, min(1, nx))
                ny = max(0, min(1, ny))
                kp[our_idx * 2] = nx
                kp[our_idx * 2 + 1] = ny
        processed_frames.append(kp)

    # 滑窗切割
    sequences = []
    stride = max(1, len(processed_frames) // 20)  # 动态 stride
    for start in range(0, len(processed_frames) - SEQ_LEN + 1, stride):
        seq = np.stack(processed_frames[start:start + SEQ_LEN])
        sequences.append(seq)

    return sequences


def get_action_id(filename: str) -> int | None:
    """从 NTU 文件名提取动作ID: SsssCcccPpppRrrrAaaa.skeleton"""
    m = re.search(r'A(\d{3})', filename)
    return int(m.group(1)) if m else None


def main():
    print("\n" + "=" * 55)
    print("  NTU RGB+D → 小白快门 骨架数据转换")
    print("=" * 55)

    if not NTU_DIR.exists():
        print(f"\n  未找到 NTU 数据目录: {NTU_DIR}")
        print("  请下载 NTU RGB+D 骨架数据:")
        print("  1. 访问 https://rose1.ntu.edu.sg/dataset/actionRecognition/")
        print("  2. 下载 nturgbd_skeletons_s001_to_s017.zip")
        print(f"  3. 解压 .skeleton 文件到 {NTU_DIR}/")
        print(f"\n  需要的动作类别 (A编号): {list(NTU_ACTION_MAP.keys())}")
        return

    skeleton_files = sorted(NTU_DIR.glob("*.skeleton"))
    if not skeleton_files:
        print(f"\n  目录 {NTU_DIR} 中没有 .skeleton 文件")
        return

    print(f"\n  找到 {len(skeleton_files)} 个骨架文件")

    # 按类别分组
    class_sequences = defaultdict(list)
    processed = 0

    for sf in skeleton_files:
        action_id = get_action_id(sf.name)
        if action_id not in NTU_ACTION_MAP:
            continue

        our_class = NTU_ACTION_MAP[action_id]
        if len(class_sequences[our_class]) >= MAX_SAMPLES_PER_CLASS:
            continue

        frames = parse_ntu_skeleton(str(sf))
        if frames is None:
            continue

        seqs = ntu_frames_to_sequences(frames)
        class_sequences[our_class].extend(seqs[:5])  # 每个文件最多取5条
        processed += 1

        if processed % 100 == 0:
            print(f"    已处理 {processed} 个文件...")

    # 保存
    total = 0
    for our_class, seqs in class_sequences.items():
        if not seqs:
            continue

        seqs = seqs[:MAX_SAMPLES_PER_CLASS]
        data = np.stack(seqs)

        out_dir = DATA_DIR / our_class
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / 'sequences.npy'

        if out_path.exists():
            existing = np.load(str(out_path))
            if existing.shape[1:] == data.shape[1:]:
                data = np.concatenate([existing, data])
                print(f"  {our_class}: 合并已有 {existing.shape[0]} + 新增 {data.shape[0] - existing.shape[0]}")

        np.save(str(out_path), data)
        print(f"  ✅ {our_class}: {data.shape[0]} 条序列")
        total += data.shape[0]

    print(f"\n  共生成 {total} 条训练序列")
    print(f"  接下来: python ml/train.py")


if __name__ == '__main__':
    main()
