"""
augment_videos.py — 视频数据增强（解决样本不足问题）
13个视频 → 增强后每类 20-30 个有效序列样本

策略：
  1. 速度变换（0.8x / 1.2x 播放速度）
  2. 水平翻转
  3. 随机裁剪（取视频前60% / 中间 / 后60%）
  4. 亮度/对比度扰动

运行: python ml/augment_videos.py
输出: data/raw_videos/<label>/aug_*.mp4（增强后视频）
"""

import os, cv2, numpy as np, random, shutil
from pathlib import Path

RAW_DIR = 'data/raw_videos'
AUG_SUFFIX = 'aug_'

GESTURE_LABELS = [
    'raise_both_hands', 'point_up', 'heart', 'clap',
    'spread_arms', 'fly_kiss', 'cover_face',
    'hands_on_hips', 'cross_arms', 'chin_rest', 'neutral',
]

TARGET_PER_CLASS = 8   # 每类目标视频数（增强后）
MIN_DURATION_SEC = 2.0  # 每个片段最少2秒


def read_frames(video_path: str) -> tuple[list, float]:
    """读取视频所有帧，返回 (frames, fps)"""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame)
    cap.release()
    return frames, fps


def write_frames(frames: list, out_path: str, fps: float):
    """写出帧序列为 mp4"""
    if not frames:
        return
    h, w = frames[0].shape[:2]
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(out_path, fourcc, fps, (w, h))
    for f in frames:
        writer.write(f)
    writer.release()


def aug_speed(frames: list, fps: float, factor: float) -> tuple[list, float]:
    """速度变换：factor>1 加速（抽帧），factor<1 减速（插帧）"""
    if factor >= 1.0:
        indices = [int(i * factor) for i in range(int(len(frames) / factor))]
        return [frames[min(i, len(frames)-1)] for i in indices], fps
    else:
        # 减速：重复帧
        out = []
        for f in frames:
            repeat = int(1.0 / factor)
            out.extend([f] * repeat)
        return out, fps


def aug_flip(frames: list) -> list:
    """水平翻转"""
    return [cv2.flip(f, 1) for f in frames]


def aug_brightness(frames: list, beta: int = 30) -> list:
    """亮度扰动"""
    return [cv2.convertScaleAbs(f, alpha=1.0, beta=random.randint(-beta, beta))
            for f in frames]


def aug_crop_segment(frames: list, seg: str) -> list:
    """取视频片段：'front' / 'mid' / 'back'"""
    n = len(frames)
    ratio = 0.6
    seg_len = int(n * ratio)
    if seg == 'front':
        return frames[:seg_len]
    elif seg == 'back':
        return frames[n - seg_len:]
    else:  # mid
        start = (n - seg_len) // 2
        return frames[start:start + seg_len]


def augment_video(src_path: str, label_dir: str, base_name: str, count: int) -> int:
    """对单个视频生成多种增强版本，返回生成数量"""
    frames, fps = read_frames(src_path)
    if len(frames) < 10:
        print(f'  [SKIP] 视频太短: {src_path}')
        return 0

    augmentations = [
        # (名称, 变换函数列表)
        ('flip',         [aug_flip]),
        ('speed_fast',   [lambda f, fp=fps: aug_speed(f, fp, 1.25)]),
        ('speed_slow',   [lambda f, fp=fps: aug_speed(f, fp, 0.8)]),
        ('bright',       [aug_brightness]),
        ('flip_bright',  [aug_flip, aug_brightness]),
        ('crop_front',   [lambda f: (aug_crop_segment(f, 'front'), fps)]),
        ('crop_mid',     [lambda f: (aug_crop_segment(f, 'mid'), fps)]),
        ('crop_back',    [lambda f: (aug_crop_segment(f, 'back'), fps)]),
    ]

    generated = 0
    for aug_name, transforms in augmentations:
        if generated >= count:
            break

        cur_frames = list(frames)
        cur_fps = fps

        for transform in transforms:
            result = transform(cur_frames)
            if isinstance(result, tuple):
                cur_frames, cur_fps = result
            else:
                cur_frames = result

        if len(cur_frames) < 10:
            continue

        out_name = f'{AUG_SUFFIX}{base_name}_{aug_name}.mp4'
        out_path = os.path.join(label_dir, out_name)

        if os.path.exists(out_path):
            generated += 1
            continue

        write_frames(cur_frames, out_path, cur_fps)
        print(f'    + {out_name}')
        generated += 1

    return generated


def main():
    print('🔄 视频数据增强开始...\n')
    total_added = 0

    for label in GESTURE_LABELS:
        label_dir = os.path.join(RAW_DIR, label)
        if not os.path.exists(label_dir):
            print(f'[SKIP] 无视频目录: {label}')
            continue

        exts = ('.mov', '.mp4', '.avi', '.m4v')
        # 只对原始视频做增强（不对已生成的增强视频再增强）
        originals = [
            f for f in os.listdir(label_dir)
            if f.lower().endswith(exts) and not f.startswith(AUG_SUFFIX)
        ]

        if not originals:
            print(f'[SKIP] {label}: 无原始视频')
            continue

        existing_all = [f for f in os.listdir(label_dir) if f.lower().endswith(('.mp4', '.mov', '.avi'))]
        need = max(0, TARGET_PER_CLASS - len(existing_all))

        print(f'{label}: {len(originals)} 个原始视频，当前共 {len(existing_all)} 个，需增强 {need} 个')

        if need <= 0:
            print(f'  已满足目标数量，跳过\n')
            continue

        # 平均分配增强任务
        per_video = max(1, -(-need // len(originals)))  # 向上取整

        added = 0
        for orig_file in originals:
            if added >= need:
                break
            src_path = os.path.join(label_dir, orig_file)
            base_name = Path(orig_file).stem
            n = augment_video(src_path, label_dir, base_name, per_video)
            added += n

        total_added += added
        print(f'  ✅ 增强完成，新增 {added} 个视频\n')

    print('='*50)
    print(f'🎉 增强完成！共新增 {total_added} 个视频')

    # 统计
    print('\n各类别当前数量：')
    exts = ('.mov', '.mp4', '.avi', '.m4v')
    for label in GESTURE_LABELS:
        label_dir = os.path.join(RAW_DIR, label)
        if not os.path.exists(label_dir):
            count = 0
        else:
            count = len([f for f in os.listdir(label_dir) if f.lower().endswith(exts)])
        bar = '█' * min(count, 10)
        warn = ' ← ⚠️' if count < 3 else ''
        print(f'  {label:<22} {bar} {count}{warn}')

    print('\n下一步：')
    print('  python ml/collect_data.py   # 提取关键点特征')
    print('  python ml/train.py          # 训练模型')


if __name__ == '__main__':
    main()
