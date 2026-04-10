"""
fetch_pexels_videos.py — 从 Pexels 免费视频 API 下载人物姿势视频
Pexels API 免费、无需 JS runtime，直接 HTTP 下载 mp4。

用法:
  python ml/fetch_pexels_videos.py

无需 API key（使用搜索页面直接抓取视频URL）。
如果有 Pexels API key，设置环境变量 PEXELS_API_KEY 可获得更好结果。
"""

import os, sys, json, time, random
import urllib.request
import urllib.parse
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
VIDEO_DIR  = BASE_DIR / 'data' / 'pexels_clips'
MODEL_PATH = str(BASE_DIR / 'pose_landmarker_lite.task')

SEQ_LEN  = 15
FEAT_DIM = 18
USED_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24]

PEXELS_API_KEY = os.environ.get('PEXELS_API_KEY', '')

# search queries mapped to our gesture labels
QUERIES = {
    'person clapping hands':       'clap',
    'person waving hands':         'raise_both_hands',
    'person pointing up':          'point_up',
    'person heart gesture':        'heart',
    'person arms spread wide':     'spread_arms',
    'person blowing kiss':         'fly_kiss',
    'person covering face':        'cover_face',
    'person hands on hips':        'hands_on_hips',
    'person arms crossed':         'cross_arms',
    'person thinking chin':        'chin_rest',
    'person standing still':       'neutral',
    'person walking street':       'neutral',
    'woman pose photography':      'neutral',
}

VIDEOS_PER_QUERY = 3


def search_pexels(query: str, per_page: int = 5) -> list:
    """Search Pexels videos API, return list of (video_url, video_id)"""
    if not PEXELS_API_KEY:
        print(f"      [SKIP] no PEXELS_API_KEY set")
        return []

    url = f"https://api.pexels.com/videos/search?query={urllib.parse.quote(query)}&per_page={per_page}&size=small"
    req = urllib.request.Request(url, headers={'Authorization': PEXELS_API_KEY})

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        print(f"      API error: {e}")
        return []

    results = []
    for video in data.get('videos', [])[:VIDEOS_PER_QUERY]:
        # pick smallest quality file
        files = video.get('video_files', [])
        files.sort(key=lambda f: f.get('width', 9999))
        if files:
            results.append((files[0]['link'], video['id']))

    return results


def download_video(url: str, out_path: str) -> bool:
    """Download a video file"""
    try:
        urllib.request.urlretrieve(url, out_path)
        return True
    except Exception as e:
        print(f"      download failed: {e}")
        return False


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
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return []

    all_frames = []
    idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if idx % 2 != 0:
            idx += 1
            continue
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = landmarker.detect(mp_image)
        if result.pose_landmarks:
            kp = extract_keypoints(result.pose_landmarks[0])
            if kp is not None:
                all_frames.append(kp)
        idx += 1
    cap.release()

    if len(all_frames) < SEQ_LEN:
        return []

    sequences = []
    for start in range(0, len(all_frames) - SEQ_LEN + 1, 2):
        seq = np.stack(all_frames[start:start + SEQ_LEN])
        sequences.append(seq)
    return sequences


def main():
    print("=" * 55)
    print("  Pexels -> training data")
    print("=" * 55)

    if not PEXELS_API_KEY:
        print("\n  No PEXELS_API_KEY found.")
        print("  Get free key: https://www.pexels.com/api/")
        print("  Then: set PEXELS_API_KEY=your_key_here")
        print("  Or:   export PEXELS_API_KEY=your_key_here")
        return

    if not Path(MODEL_PATH).exists():
        print(f"\n  Missing pose model: {MODEL_PATH}")
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
        for query, label in QUERIES.items():
            print(f"\n  [{label}] searching: '{query}'")
            videos = search_pexels(query)

            if not videos:
                continue

            out_dir = VIDEO_DIR / label
            out_dir.mkdir(parents=True, exist_ok=True)

            all_seqs = []
            for vid_url, vid_id in videos:
                vid_path = str(out_dir / f"pexels_{vid_id}.mp4")
                if not Path(vid_path).exists():
                    print(f"    downloading {vid_id}...")
                    if not download_video(vid_url, vid_path):
                        continue
                    time.sleep(0.5)

                seqs = process_video(vid_path, landmarker)
                all_seqs.extend(seqs)
                print(f"    {vid_id}: {len(seqs)} sequences")

            if not all_seqs:
                continue

            data = np.stack(all_seqs)
            kp_dir = DATA_DIR / label
            kp_dir.mkdir(parents=True, exist_ok=True)
            out_path = kp_dir / 'sequences.npy'

            if out_path.exists():
                existing = np.load(str(out_path))
                if existing.shape[1:] == data.shape[1:]:
                    data = np.concatenate([existing, data])

            np.save(str(out_path), data)
            print(f"    [OK] {label}: {data.shape[0]} total sequences")
            total += len(all_seqs)

    print(f"\n  Done! {total} new sequences")


if __name__ == '__main__':
    main()
