"""
fetch_aist.py — Download AIST++ dance dataset annotations + auto-label gesture clips
AIST++: 1408 dance sequences, 10 genres, 3D keypoints available

Step 1: Download 3D keypoint annotations (834MB)
Step 2: Auto-label gesture segments using keypoint heuristics
Step 3: Download corresponding video clips for labeled segments

Usage:
  python ml/fetch_aist.py
"""

import os, json, sys, urllib.request, zipfile
import numpy as np
from pathlib import Path

BASE_DIR = Path(__file__).parent
AIST_DIR = BASE_DIR / 'data' / 'aist_raw'
CLIPS_DIR = BASE_DIR / 'data' / 'aist_clips'
AIST_DIR.mkdir(parents=True, exist_ok=True)

# AIST++ from GitHub releases (Google Storage URLs are dead)
KP3D_URL = "https://github.com/google/aistplusplus_dataset/releases/download/v1.0/keypoints3d.zip"

GESTURE_CLASSES = [
    'raise_both_hands', 'point_up', 'heart', 'clap', 'spread_arms',
    'fly_kiss', 'cover_face', 'hands_on_hips', 'cross_arms',
    'chin_rest', 'neutral'
]

# COCO 17-joint indices used for heuristic labeling
NOSE = 0
L_SHOULDER, R_SHOULDER = 5, 6
L_ELBOW, R_ELBOW = 7, 8
L_WRIST, R_WRIST = 9, 10
L_HIP, R_HIP = 11, 12


def download_file(url, dest):
    """Download with progress."""
    if dest.exists():
        print(f"    Already exists: {dest.name}")
        return True
    print(f"    Downloading {dest.name}...")
    try:
        urllib.request.urlretrieve(url, str(dest))
        print(f"    [OK] {dest.stat().st_size / 1024 / 1024:.1f} MB")
        return True
    except Exception as e:
        print(f"    [FAIL] {e}")
        return False


def label_frame(kp):
    """
    Heuristic gesture labeling from COCO 17-joint 3D keypoints.
    kp: (17, 3) array, y-axis points UP in AIST++ coordinate system.
    Returns gesture label string.
    """
    nose = kp[NOSE]
    lw, rw = kp[L_WRIST], kp[R_WRIST]
    ls, rs = kp[L_SHOULDER], kp[R_SHOULDER]
    lh, rh = kp[L_HIP], kp[R_HIP]

    shoulder_width = np.linalg.norm(ls - rs)
    if shoulder_width < 0.01:
        return 'neutral'

    # raise_both_hands: both wrists above nose
    if lw[1] > nose[1] and rw[1] > nose[1]:
        return 'raise_both_hands'

    # spread_arms: wrists far apart, near shoulder height
    wrist_spread = np.linalg.norm(lw - rw)
    if wrist_spread > shoulder_width * 2.5:
        wrist_avg_y = (lw[1] + rw[1]) / 2
        shoulder_avg_y = (ls[1] + rs[1]) / 2
        if abs(wrist_avg_y - shoulder_avg_y) < shoulder_width * 0.5:
            return 'spread_arms'

    # hands_on_hips: wrists close to hips
    lw_hip_dist = np.linalg.norm(lw - lh)
    rw_hip_dist = np.linalg.norm(rw - rh)
    if lw_hip_dist < shoulder_width * 0.6 and rw_hip_dist < shoulder_width * 0.6:
        return 'hands_on_hips'

    # cross_arms: wrists near chest, crossed (left wrist on right side)
    chest = (ls + rs) / 2
    lw_chest = np.linalg.norm(lw - chest)
    rw_chest = np.linalg.norm(rw - chest)
    if lw_chest < shoulder_width * 0.5 and rw_chest < shoulder_width * 0.5:
        # Check if crossed: left wrist x > right wrist x (in body frame)
        body_right = rs - ls
        lw_proj = np.dot(lw - ls, body_right) / np.dot(body_right, body_right)
        rw_proj = np.dot(rw - ls, body_right) / np.dot(body_right, body_right)
        if lw_proj > 0.6 and rw_proj < 0.4:
            return 'cross_arms'

    # cover_face: both wrists near nose
    if np.linalg.norm(lw - nose) < shoulder_width * 0.5 and \
       np.linalg.norm(rw - nose) < shoulder_width * 0.5:
        return 'cover_face'

    # point_up: one wrist well above head, other near body
    if (lw[1] > nose[1] + shoulder_width * 0.5) != (rw[1] > nose[1] + shoulder_width * 0.5):
        return 'point_up'

    # clap: wrists very close together, in front of body
    if np.linalg.norm(lw - rw) < shoulder_width * 0.3:
        wrist_mid = (lw + rw) / 2
        if wrist_mid[1] > lh[1]:  # above hips
            return 'clap'

    return 'neutral'


def label_sequence(keypoints3d, window_size=13, stride=6):
    """
    Label a full AIST++ sequence using sliding window.
    keypoints3d: (T, 17, 3)
    Returns list of (start_frame, end_frame, label)
    """
    T = keypoints3d.shape[0]
    segments = []

    for start in range(0, T - window_size, stride):
        window = keypoints3d[start:start + window_size]
        # Label based on middle frame
        mid = window[window_size // 2]
        label = label_frame(mid)

        # Require consistency: at least 60% of frames agree
        frame_labels = [label_frame(window[i]) for i in range(window_size)]
        from collections import Counter
        most_common = Counter(frame_labels).most_common(1)[0]
        if most_common[1] >= window_size * 0.6:
            segments.append((start, start + window_size, most_common[0]))

    return segments


def main():
    print("=" * 55)
    print("  AIST++ Dataset -> Gesture Labels")
    print("=" * 55)

    # Step 1: Download 3D keypoints
    kp3d_zip = AIST_DIR / 'keypoints3d.zip'
    if not (AIST_DIR / 'keypoints3d').exists():
        if download_file(KP3D_URL, kp3d_zip):
            print("    Extracting...")
            import zipfile
            with zipfile.ZipFile(str(kp3d_zip), 'r') as zf:
                zf.extractall(str(AIST_DIR))
            print("    [OK] Extracted")

    kp3d_dir = AIST_DIR / 'keypoints3d'
    if not kp3d_dir.exists():
        # Try alternative path
        for d in AIST_DIR.iterdir():
            if d.is_dir() and 'keypoint' in d.name.lower():
                kp3d_dir = d
                break

    if not kp3d_dir.exists():
        print(f"  [ERROR] No keypoints3d directory found in {AIST_DIR}")
        print("  Manual download: https://storage.googleapis.com/aist_plusplus_public/20210308/keypoints3d.zip")
        return

    # Step 2: Process each sequence
    pkl_files = sorted(kp3d_dir.glob('*.pkl'))
    if not pkl_files:
        npy_files = sorted(kp3d_dir.glob('*.npy'))
        json_files = sorted(kp3d_dir.glob('*.json'))
        pkl_files = pkl_files or npy_files or json_files

    print(f"\n  Found {len(pkl_files)} keypoint files")

    # Create output dirs
    for label in GESTURE_CLASSES:
        (CLIPS_DIR / label).mkdir(parents=True, exist_ok=True)

    label_counts = {l: 0 for l in GESTURE_CLASSES}
    total_segments = 0

    for kp_file in pkl_files[:200]:  # process first 200 sequences
        try:
            if kp_file.suffix == '.pkl':
                import pickle
                with open(kp_file, 'rb') as f:
                    data = pickle.load(f)
                if isinstance(data, dict):
                    kp3d = data.get('keypoints3d', data.get('keypoints', None))
                    if kp3d is None:
                        kp3d = list(data.values())[0]
                    kp3d = np.array(kp3d)
                else:
                    kp3d = np.array(data)
            elif kp_file.suffix == '.npy':
                kp3d = np.load(str(kp_file))
            else:
                continue

            if kp3d.ndim != 3 or kp3d.shape[1] != 17:
                continue

            segments = label_sequence(kp3d)
            for start, end, label in segments:
                if label == 'neutral' and label_counts['neutral'] > 500:
                    continue  # cap neutral
                # Save keypoint segment as numpy (for now, video download is separate)
                seg_data = kp3d[start:end]
                seg_name = f"{kp_file.stem}_f{start:05d}.npy"
                np.save(str(CLIPS_DIR / label / seg_name), seg_data)
                label_counts[label] += 1
                total_segments += 1

        except Exception as e:
            continue

    print(f"\n  Labeled {total_segments} segments:")
    for label, count in label_counts.items():
        status = "[OK]" if count >= 20 else "[LOW]"
        print(f"    {status} {label:25s} {count:5d}")

    print(f"\n  Output: {CLIPS_DIR}")
    print("  Next: python ml/train_x3d.py")


if __name__ == '__main__':
    main()
