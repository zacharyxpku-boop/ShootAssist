"""
generate_synthetic.py — 为空类别生成合成关键点序列
基于每个手势的解剖学约束，程序化生成骨架数据，不依赖视频。

使用方法: python ml/generate_synthetic.py
输出: data/keypoints/<label>/sequences.npy (与 collect_data.py 同格式)
"""

import os, json, random
import numpy as np
from pathlib import Path

np.random.seed(42)
random.seed(42)

SEQ_LEN  = 15
FEAT_DIM = 18  # 9 joints × (x, y)
SAMPLES_PER_CLASS = 80  # 每类生成 80 条序列

DATA_DIR  = Path(__file__).parent / 'data' / 'keypoints'
DATA_DIR.mkdir(parents=True, exist_ok=True)

# 9 关节索引: nose(0), L_sh(1), R_sh(2), L_el(3), R_el(4), L_wr(5), R_wr(6), L_hp(7), R_hp(8)
# 坐标归一化: x ∈ [0,1], y ∈ [0,1], (0,0)=左上, (1,1)=右下

def make_base_skeleton():
    """生成标准站立骨架（归一化坐标）"""
    return {
        'nose':  (0.50, 0.15),
        'L_sh':  (0.42, 0.28),
        'R_sh':  (0.58, 0.28),
        'L_el':  (0.35, 0.42),
        'R_el':  (0.65, 0.42),
        'L_wr':  (0.32, 0.55),
        'R_wr':  (0.68, 0.55),
        'L_hp':  (0.45, 0.55),
        'R_hp':  (0.55, 0.55),
    }


def skeleton_to_array(skel: dict) -> np.ndarray:
    """dict → (18,) array"""
    keys = ['nose', 'L_sh', 'R_sh', 'L_el', 'R_el', 'L_wr', 'R_wr', 'L_hp', 'R_hp']
    arr = []
    for k in keys:
        arr.extend(skel[k])
    return np.array(arr, dtype=np.float32)


def add_jitter(arr: np.ndarray, sigma: float = 0.01) -> np.ndarray:
    """加微小抖动模拟真实运动"""
    return arr + np.random.normal(0, sigma, arr.shape).astype(np.float32)


def generate_sequence(pose_fn, n_frames=SEQ_LEN, jitter=0.008) -> np.ndarray:
    """生成一条时间序列 (SEQ_LEN, FEAT_DIM)"""
    frames = []
    for t in range(n_frames):
        phase = t / max(n_frames - 1, 1)  # 0→1 过渡
        skel = pose_fn(phase)
        arr = skeleton_to_array(skel)
        arr = add_jitter(arr, sigma=jitter)
        frames.append(arr)
    return np.stack(frames)


def vary_body(base_fn, n_samples=SAMPLES_PER_CLASS):
    """对同一姿势生成多个变体（位移/缩放/倾斜）"""
    sequences = []
    for _ in range(n_samples):
        dx = random.uniform(-0.08, 0.08)  # 水平位移
        dy = random.uniform(-0.05, 0.05)  # 垂直位移
        scale = random.uniform(0.85, 1.15)
        jitter = random.uniform(0.005, 0.015)

        def varied_fn(phase, _dx=dx, _dy=dy, _s=scale, _base=base_fn):
            skel = _base(phase)
            cx, cy = 0.5, 0.35  # 身体中心近似
            return {k: (cx + (x - cx) * _s + _dx, cy + (y - cy) * _s + _dy)
                    for k, (x, y) in skel.items()}

        seq = generate_sequence(varied_fn, jitter=jitter)
        sequences.append(seq)
    return np.stack(sequences)


# ── 手势定义 ──────────────────────────────────────────

def pose_cross_arms(phase):
    """双手交叉抱胸：手腕交叉到对侧肩膀前方"""
    base = make_base_skeleton()
    # 手肘向内收，手腕交叉
    t = min(phase * 1.5, 1.0)  # 前2/3完成动作
    base['L_el'] = (0.42 + t * 0.06, 0.36 + t * 0.02)
    base['R_el'] = (0.58 - t * 0.06, 0.36 + t * 0.02)
    base['L_wr'] = (0.42 + t * 0.15, 0.32 + t * 0.02)  # 左手到右侧
    base['R_wr'] = (0.58 - t * 0.15, 0.34 + t * 0.02)  # 右手到左侧
    return base


def pose_fly_kiss(phase):
    """飞吻：一只手从嘴边向前伸出"""
    base = make_base_skeleton()
    t = min(phase * 1.8, 1.0)
    # 右手从体侧抬到嘴边，再往前推
    if t < 0.5:
        p = t * 2
        base['R_el'] = (0.60 - p * 0.05, 0.38 - p * 0.10)
        base['R_wr'] = (0.60 - p * 0.08, 0.35 - p * 0.18)
    else:
        p = (t - 0.5) * 2
        base['R_el'] = (0.55, 0.28 + p * 0.02)
        base['R_wr'] = (0.52 - p * 0.05, 0.17 + p * 0.03)  # 向前推出
    # 嘴巴微动（nose 微移表示表情变化）
    base['nose'] = (0.50, 0.15 - t * 0.005)
    return base


def pose_hands_on_hips(phase):
    """叉腰：双手放在髋部两侧"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.36 - t * 0.02, 0.38 + t * 0.08)
    base['R_el'] = (0.64 + t * 0.02, 0.38 + t * 0.08)
    base['L_wr'] = (0.38 - t * 0.02, 0.48 + t * 0.05)
    base['R_wr'] = (0.62 + t * 0.02, 0.48 + t * 0.05)
    return base


def pose_neutral(phase):
    """自然站立：手臂自然下垂，轻微晃动"""
    base = make_base_skeleton()
    sway = np.sin(phase * np.pi * 2) * 0.01
    base['L_wr'] = (0.32 + sway, 0.55)
    base['R_wr'] = (0.68 - sway, 0.55)
    base['nose'] = (0.50 + sway * 0.5, 0.15)
    return base


def pose_neutral_walking(phase):
    """走路：手臂前后摆动"""
    base = make_base_skeleton()
    swing = np.sin(phase * np.pi * 2) * 0.04
    base['L_wr'] = (0.32, 0.55 - swing)
    base['R_wr'] = (0.68, 0.55 + swing)
    base['L_el'] = (0.35, 0.42 - swing * 0.5)
    base['R_el'] = (0.65, 0.42 + swing * 0.5)
    return base


def pose_neutral_phone(phase):
    """看手机：一只手举在面前"""
    base = make_base_skeleton()
    base['R_el'] = (0.58, 0.32)
    base['R_wr'] = (0.54, 0.22)
    base['nose'] = (0.50, 0.16 + phase * 0.01)  # 低头看
    return base


# ── 生成 & 保存 ──────────────────────────────────────

def pose_raise_both_hands(phase):
    """双手举高：从体侧到头顶"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.38 - t * 0.02, 0.38 - t * 0.15)
    base['R_el'] = (0.62 + t * 0.02, 0.38 - t * 0.15)
    base['L_wr'] = (0.35 - t * 0.03, 0.45 - t * 0.35)
    base['R_wr'] = (0.65 + t * 0.03, 0.45 - t * 0.35)
    return base


def pose_raise_both_hands_v2(phase):
    """双手举高变体：V字形"""
    base = make_base_skeleton()
    t = min(phase * 1.3, 1.0)
    base['L_el'] = (0.35 - t * 0.05, 0.35 - t * 0.10)
    base['R_el'] = (0.65 + t * 0.05, 0.35 - t * 0.10)
    base['L_wr'] = (0.30 - t * 0.08, 0.40 - t * 0.30)
    base['R_wr'] = (0.70 + t * 0.08, 0.40 - t * 0.30)
    return base


def pose_point_up(phase):
    """指天：右手伸直指向上方"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['R_el'] = (0.58 + t * 0.02, 0.35 - t * 0.12)
    base['R_wr'] = (0.58 + t * 0.03, 0.30 - t * 0.22)
    return base


def pose_point_up_left(phase):
    """指天变体：左手"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.42 - t * 0.02, 0.35 - t * 0.12)
    base['L_wr'] = (0.42 - t * 0.03, 0.30 - t * 0.22)
    return base


def pose_heart(phase):
    """比心：双手在头顶交叉成心形"""
    base = make_base_skeleton()
    t = min(phase * 1.4, 1.0)
    base['L_el'] = (0.42 + t * 0.04, 0.35 - t * 0.10)
    base['R_el'] = (0.58 - t * 0.04, 0.35 - t * 0.10)
    base['L_wr'] = (0.45 + t * 0.04, 0.28 - t * 0.12)
    base['R_wr'] = (0.55 - t * 0.04, 0.28 - t * 0.12)
    return base


def pose_heart_small(phase):
    """比心变体：胸前小心"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.42 + t * 0.03, 0.36 - t * 0.02)
    base['R_el'] = (0.58 - t * 0.03, 0.36 - t * 0.02)
    base['L_wr'] = (0.46 + t * 0.02, 0.32 - t * 0.04)
    base['R_wr'] = (0.54 - t * 0.02, 0.32 - t * 0.04)
    return base


def pose_clap(phase):
    """拍手：双手在胸前反复靠拢"""
    base = make_base_skeleton()
    clap_cycle = np.sin(phase * np.pi * 4) * 0.5 + 0.5  # 0→1 反复
    sep = 0.12 * (1 - clap_cycle)  # 拍手时间隙为0
    base['L_el'] = (0.40, 0.34)
    base['R_el'] = (0.60, 0.34)
    base['L_wr'] = (0.50 - sep, 0.30)
    base['R_wr'] = (0.50 + sep, 0.30)
    return base


def pose_spread_arms(phase):
    """展开双臂：T-pose"""
    base = make_base_skeleton()
    t = min(phase * 1.3, 1.0)
    base['L_el'] = (0.35 - t * 0.08, 0.36 - t * 0.06)
    base['R_el'] = (0.65 + t * 0.08, 0.36 - t * 0.06)
    base['L_wr'] = (0.32 - t * 0.15, 0.40 - t * 0.10)
    base['R_wr'] = (0.68 + t * 0.15, 0.40 - t * 0.10)
    return base


def pose_cover_face(phase):
    """捂脸：双手遮住脸部"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.40 + t * 0.02, 0.34 - t * 0.06)
    base['R_el'] = (0.60 - t * 0.02, 0.34 - t * 0.06)
    base['L_wr'] = (0.45 + t * 0.02, 0.25 - t * 0.08)
    base['R_wr'] = (0.55 - t * 0.02, 0.25 - t * 0.08)
    return base


def pose_cover_face_single(phase):
    """捂脸变体：单手遮"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['R_el'] = (0.56 - t * 0.02, 0.34 - t * 0.08)
    base['R_wr'] = (0.52 - t * 0.01, 0.28 - t * 0.12)
    return base


def pose_chin_rest(phase):
    """托腮：一只手托住下巴"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['R_el'] = (0.55, 0.35 - t * 0.06)
    base['R_wr'] = (0.52, 0.30 - t * 0.13)
    base['nose'] = (0.50, 0.15 + t * 0.01)  # 微低头
    return base


def pose_chin_rest_left(phase):
    """托腮变体：左手"""
    base = make_base_skeleton()
    t = min(phase * 1.5, 1.0)
    base['L_el'] = (0.45, 0.35 - t * 0.06)
    base['L_wr'] = (0.48, 0.30 - t * 0.13)
    base['nose'] = (0.50, 0.15 + t * 0.01)
    return base


GESTURE_GENERATORS = {
    'raise_both_hands': [pose_raise_both_hands, pose_raise_both_hands_v2],
    'point_up':         [pose_point_up, pose_point_up_left],
    'heart':            [pose_heart, pose_heart_small],
    'clap':             [pose_clap],
    'spread_arms':      [pose_spread_arms],
    'fly_kiss':         [pose_fly_kiss],
    'cover_face':       [pose_cover_face, pose_cover_face_single],
    'hands_on_hips':    [pose_hands_on_hips],
    'cross_arms':       [pose_cross_arms],
    'chin_rest':        [pose_chin_rest, pose_chin_rest_left],
    'neutral':          [pose_neutral, pose_neutral_walking, pose_neutral_phone],
}


def main():
    total = 0
    for label, generators in GESTURE_GENERATORS.items():
        out_dir = DATA_DIR / label
        out_dir.mkdir(parents=True, exist_ok=True)

        all_seqs = []
        samples_per_gen = SAMPLES_PER_CLASS // len(generators)

        for gen_fn in generators:
            seqs = vary_body(gen_fn, n_samples=samples_per_gen)
            all_seqs.append(seqs)

        data = np.concatenate(all_seqs)
        np.save(str(out_dir / 'sequences.npy'), data)
        print(f'  {label}: {data.shape[0]} 条合成序列 → {out_dir}/sequences.npy')
        total += data.shape[0]

    print(f'\n  共生成 {total} 条合成数据')
    print(f'  现在可以运行: python ml/train.py')


if __name__ == '__main__':
    main()
