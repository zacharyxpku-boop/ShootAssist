"""
fetch_youtube_gestures.py — 从 YouTube/网络视频批量采集手势训练数据
搜索手势教学视频 → 下载 → MediaPipe 提取关键点 → auto_detect_label 分类 → 存储

用法:
  pip install yt-dlp mediapipe opencv-python
  python ml/fetch_youtube_gestures.py

每个搜索词下载 3 个视频，每个视频提取约 20-50 条序列。
"""

import os, subprocess, sys, json, random
import cv2
import numpy as np
from pathlib import Path

try:
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision as mp_vision
except ImportError:
    print("pip install mediapipe opencv-python")
    sys.exit(1)

BASE_DIR   = Path(__file__).parent
DATA_DIR   = BASE_DIR / 'data' / 'keypoints'
VIDEO_DIR  = BASE_DIR / 'data' / 'youtube_clips'
MODEL_PATH = str(BASE_DIR / 'pose_landmarker_lite.task')

SEQ_LEN  = 15
FEAT_DIM = 18
USED_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24]

# 搜索词 → 目标类别
SEARCH_QUERIES = {
    'raise both hands dance tutorial':       'raise_both_hands',
    'pointing up gesture tutorial':          'point_up',
    'heart hand gesture kpop':               'heart',
    'clapping hands tutorial':               'clap',
    'spread arms wide pose':                 'spread_arms',
    'flying kiss gesture tutorial':          'fly_kiss',
    'cover face shy pose tutorial':          'cover_face',
    'hands on hips pose fashion':            'hands_on_hips',
    'cross arms pose confidence':            'cross_arms',
    'chin rest hand thinking pose':          'chin_rest',
    'neutral standing pose photography':     'neutral',
    'walking pose photography tutorial':     'neutral',
}

VIDEOS_PER_QUERY = 2
MAX_DURATION = 30  # 每个视频最多截取30秒


def check_ytdlp():
    """检查 yt-dlp 是否可用"""
    try:
        subprocess.run(['yt-dlp', '--version'], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def download_videos(query: str, label: str, n_videos: int = VIDEOS_PER_QUERY) -> list:
    """搜索并下载YouTube短视频"""
    out_dir = VIDEO_DIR / label
    out_dir.mkdir(parents=True, exist_ok=True)

    # 用 yt-dlp 搜索+下载
    safe_query = query.replace(' ', '_')[:30]
    cmd = [
        'yt-dlp',
        f'ytsearch{n_videos}:{query}',
        '--format', 'worst[ext=mp4]',  # 低画质即可，省带宽
        '--max-downloads', str(n_videos),
        '--max-filesize', '50M',
        '--download-sections', f'*0:00-0:{MAX_DURATION}',
        '--output', str(out_dir / f'{safe_query}_%(autonumber)03d.%(ext)s'),
        '--no-playlist',
        '--quiet',
    ]

    print(f"    搜索: '{query}'")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            print(f"      yt-dlp 警告: {result.stderr[:100]}")
    except subprocess.TimeoutExpired:
        print(f"      下载超时，跳过")
    except Exception as e:
        print(f"      下载失败: {e}")

    return sorted(out_dir.glob("*.mp4"))


def extract_keypoints(pose_landmarks_list) -> np.ndarray | None:
    if not pose_landmarks_list:
        return None
    lm = pose_landmarks_list
    kp = []
    for i in USED_INDICES:
        pt = lm[i]
        vis = pt.visibility if hasattr(pt, 'visibility') else 1.0
        if vis < 0.3:
            kp.extend([0.0, 0.0])
        else:
            kp.extend([pt.x, pt.y])
    return np.array(kp, dtype=np.float32)


def process_video(video_path: str, landmarker) -> list:
    """从视频提取关键点序列"""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    all_frames = []
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_idx % 2 != 0:  # 每2帧取1帧
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

    if len(all_frames) < SEQ_LEN:
        return []

    # 滑窗切割
    sequences = []
    for start in range(0, len(all_frames) - SEQ_LEN + 1, 2):
        seq = np.stack(all_frames[start:start + SEQ_LEN])
        sequences.append(seq)

    return sequences


def main():
    print("\n" + "=" * 55)
    print("  YouTube 手势视频 → 训练数据采集")
    print("=" * 55)

    if not check_ytdlp():
        print("\n  需要安装 yt-dlp:")
        print("  pip install yt-dlp")
        print("  或: https://github.com/yt-dlp/yt-dlp#installation")
        return

    if not Path(MODEL_PATH).exists():
        print(f"\n  缺少 pose 模型: {MODEL_PATH}")
        return

    base_options = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
    options = mp_vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=mp_vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.4,
    )

    total = 0
    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        for query, label in SEARCH_QUERIES.items():
            print(f"\n  [{label}] 采集中...")

            # 下载视频
            videos = download_videos(query, label)
            if not videos:
                print(f"    没有下载到视频")
                continue

            all_seqs = []
            for vf in videos:
                seqs = process_video(str(vf), landmarker)
                all_seqs.extend(seqs)
                print(f"    {vf.name}: {len(seqs)} 条序列")

            if not all_seqs:
                continue

            data = np.stack(all_seqs)

            # 保存（追加模式）
            out_dir = DATA_DIR / label
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / 'sequences.npy'

            if out_path.exists():
                existing = np.load(str(out_path))
                if existing.shape[1:] == data.shape[1:]:
                    data = np.concatenate([existing, data])

            np.save(str(out_path), data)
            print(f"    ✅ {label}: 总计 {data.shape[0]} 条序列")
            total += len(all_seqs)

    print(f"\n{'=' * 55}")
    print(f"  完成！新增 {total} 条训练序列")
    print(f"  接下来: python ml/train.py")


if __name__ == '__main__':
    main()
