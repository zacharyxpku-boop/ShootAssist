#!/usr/bin/env python3
# brightness_label.py
# 亮度变化检测自动标注 — 检测视频中"亮起的手势标签"区域

import cv2
import json
import numpy as np
from pathlib import Path
from collections import defaultdict

# ── 配置 ──────────────────────────────────────────────
BASELINE_FRAMES   = 5       # 头N帧作为 baseline
MIN_SEGMENT_FRAMES= 12      # 至少连续N帧才算有效片段
BUFFER_FRAMES     = 8       # 片段前后各加N帧
GAUSSIAN_KERNEL   = (7, 7)
THRESHOLD_VALUE   = 25      # 亮度差阈值
MIN_CONTOUR_AREA  = 300     # 最小亮区面积(px^2)
CLUSTER_TOLERANCE = 40      # 同一区域的像素容差

BASE_DIR    = Path(__file__).parent
RAW_DIR     = BASE_DIR / 'data' / 'raw_unlabeled'
OUTPUT_DIR  = BASE_DIR / 'data' / 'raw_videos'
RESULT_FILE = BASE_DIR / 'data' / 'brightness_result.json'

GESTURE_LABELS = [
    "raise_both_hands", "point_up", "heart", "clap", "spread_arms",
    "fly_kiss", "cover_face", "hands_on_hips", "cross_arms", "chin_rest", "neutral"
]

# ── 1. 计算 baseline ─────────────────────────────────
def compute_baseline(video_path):
    cap = cv2.VideoCapture(str(video_path))
    frames = []
    for _ in range(BASELINE_FRAMES):
        ret, frame = cap.read()
        if not ret: break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32))
    cap.release()
    if not frames:
        raise RuntimeError(f'无法读取: {video_path}')
    return np.median(frames, axis=0).astype(np.uint8)

# ── 2. 找亮起区域中心 ─────────────────────────────────
def find_lit_region(diff_gray):
    blurred = cv2.GaussianBlur(diff_gray, GAUSSIAN_KERNEL, 0)
    _, thresh = cv2.threshold(blurred, THRESHOLD_VALUE, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    largest = max(contours, key=cv2.contourArea)
    if cv2.contourArea(largest) < MIN_CONTOUR_AREA:
        return None
    M = cv2.moments(largest)
    if M['m00'] == 0:
        return None
    cx = int(M['m10'] / M['m00'])
    cy = int(M['m01'] / M['m00'])
    return (cx, cy)

# ── 3. 聚类连续帧 → 片段 ────────────────────────────
def cluster_segments(detections):
    segments = []
    i = 0
    while i < len(detections):
        if detections[i] is None:
            i += 1
            continue
        start = i
        ref_x, ref_y = detections[i]
        while i < len(detections) and detections[i] is not None:
            x, y = detections[i]
            if abs(x - ref_x) <= CLUSTER_TOLERANCE and abs(y - ref_y) <= CLUSTER_TOLERANCE:
                i += 1
            else:
                break
        length = i - start
        if length >= MIN_SEGMENT_FRAMES:
            seg_pts = [detections[j] for j in range(start, i) if detections[j]]
            med_x = int(np.median([p[0] for p in seg_pts]))
            med_y = int(np.median([p[1] for p in seg_pts]))
            segments.append({
                'start': start, 'end': i - 1,
                'cx': med_x, 'cy': med_y, 'length': length
            })
        else:
            i += 1
    return segments

# ── 4. 保存片段为 mp4 ────────────────────────────────
def save_segment(video_path, seg, output_path, fps, total_frames):
    sf = max(0, seg['start'] - BUFFER_FRAMES)
    ef = min(total_frames, seg['end'] + BUFFER_FRAMES + 1)
    cap = cv2.VideoCapture(str(video_path))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(str(output_path), fourcc, fps, (w, h))
    cap.set(cv2.CAP_PROP_POS_FRAMES, sf)
    for _ in range(ef - sf):
        ret, frame = cap.read()
        if not ret: break
        out.write(frame)
    cap.release()
    out.release()

# ── 5. 从亮起区域截图尝试 OCR ────────────────────────
def try_read_region_text(video_path, seg, frame_idx):
    """从片段中间帧截取亮起区域，尝试识别文字"""
    cap = cv2.VideoCapture(str(video_path))
    mid = (seg['start'] + seg['end']) // 2
    cap.set(cv2.CAP_PROP_POS_FRAMES, mid)
    ret, frame = cap.read()
    cap.release()
    if not ret:
        return None
    # 在亮起区域周围裁剪
    cx, cy = seg['cx'], seg['cy']
    pad = 80
    h, w = frame.shape[:2]
    x1, y1 = max(0, cx-pad), max(0, cy-pad)
    x2, y2 = min(w, cx+pad), min(h, cy+pad)
    roi = frame[y1:y2, x1:x2]
    # 保存 ROI 供调试
    roi_path = BASE_DIR / 'data' / f'roi_{Path(video_path).stem}_seg{frame_idx}.png'
    cv2.imwrite(str(roi_path), roi)
    return roi_path

# ── 主流程 ───────────────────────────────────────────
def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (BASE_DIR / 'data').mkdir(exist_ok=True)

    video_files = sorted(list(RAW_DIR.glob('*.mov')) + list(RAW_DIR.glob('*.mp4')))
    if not video_files:
        print(f'没有找到视频！请把 .mov 放入: {RAW_DIR}')
        return

    print(f'\n{"="*60}')
    print(f'  亮度检测自动标注 — {len(video_files)} 个视频')
    print(f'{"="*60}\n')

    all_results = {}
    segment_registry = {}  # (rounded_cx, rounded_cy) -> label placeholder

    for vp in video_files:
        print(f'  分析: {vp.name}')
        try:
            baseline = compute_baseline(vp)
            cap = cv2.VideoCapture(str(vp))
            fps = cap.get(cv2.CAP_PROP_FPS) or 30
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

            detections = []
            frame_idx = 0
            while True:
                ret, frame = cap.read()
                if not ret: break
                if frame_idx % 2 == 0:  # 每2帧采样一次，加速
                    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                    diff = cv2.absdiff(gray, baseline)
                    center = find_lit_region(diff)
                    detections.append(center)
                else:
                    detections.append(detections[-1] if detections else None)
                frame_idx += 1
            cap.release()

            segments = cluster_segments(detections)
            print(f'    → 检测到 {len(segments)} 个亮起片段')

            video_segs = []
            for si, seg in enumerate(segments):
                # 四舍五入到40px网格，用于跨视频聚类同一位置
                grid_cx = round(seg['cx'] / 40) * 40
                grid_cy = round(seg['cy'] / 40) * 40
                key = (grid_cx, grid_cy)

                # 保存 ROI 截图（用于后续识别）
                roi_path = try_read_region_text(str(vp), seg, si)

                # 保存片段视频到临时目录
                tmp_dir = OUTPUT_DIR / f'pos_{grid_cx}_{grid_cy}'
                tmp_dir.mkdir(parents=True, exist_ok=True)
                out_path = tmp_dir / f'{vp.stem}_seg{si:02d}.mp4'
                save_segment(str(vp), seg, out_path, fps, total)

                print(f'       seg{si}: center=({seg["cx"]},{seg["cy"]}) grid=({grid_cx},{grid_cy}) frames={seg["length"]}')

                video_segs.append({
                    'seg_id': si,
                    'cx': seg['cx'], 'cy': seg['cy'],
                    'grid_cx': grid_cx, 'grid_cy': grid_cy,
                    'start': seg['start'], 'end': seg['end'],
                    'frames': seg['length'],
                    'saved_to': str(out_path),
                    'roi_png': str(roi_path) if roi_path else None,
                })
                segment_registry[key] = segment_registry.get(key, 0) + 1

            all_results[vp.name] = video_segs

        except Exception as e:
            print(f'    ERROR: {e}')
            import traceback; traceback.print_exc()

    # 保存结果
    with open(RESULT_FILE, 'w', encoding='utf-8') as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)

    # 汇总：哪些位置出现了多少次
    print(f'\n{"="*60}')
    print('  检测到的亮起区域位置（跨所有视频）：')
    print(f'{"="*60}')
    for (gcx, gcy), count in sorted(segment_registry.items(), key=lambda x: -x[1]):
        print(f'  位置 ({gcx:4d},{gcy:4d}) — 出现 {count} 次')

    print(f'\n  共 {sum(len(v) for v in all_results.values())} 个片段')
    print(f'  ROI 截图保存在: data/roi_*.png')
    print(f'  片段视频保存在: data/raw_videos/pos_X_Y/')
    print(f'  完整结果: {RESULT_FILE}')
    print('\n  下一步: 查看 data/roi_*.png 确认每个位置对应哪个手势')
    print('  然后运行: python ml/remap_labels.py')


if __name__ == '__main__':
    main()
