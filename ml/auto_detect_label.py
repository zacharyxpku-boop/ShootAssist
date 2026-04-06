"""
auto_detect_label.py — MediaPipe 几何规则自动打标
不需要人工介入，自动分析每个视频的主要手势并分类到对应文件夹。

使用方法: python ml/auto_detect_label.py
"""

import os, shutil, json
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from pathlib import Path
from collections import Counter

BASE_DIR      = Path(__file__).parent
UNLABELED_DIR = BASE_DIR / 'data' / 'raw_unlabeled'
LABELED_DIR   = BASE_DIR / 'data' / 'raw_videos'
REPORT_FILE   = BASE_DIR / 'data' / 'auto_label_report.json'
MODEL_PATH    = str(BASE_DIR / 'pose_landmarker_lite.task')

# ── 关节索引 (PoseLandmarker 同 33 点) ──────────────────
NOSE       = 0
L_SHOULDER = 11; R_SHOULDER = 12
L_ELBOW    = 13; R_ELBOW    = 14
L_WRIST    = 15; R_WRIST    = 16
L_HIP      = 23; R_HIP      = 24
L_EAR      = 7;  R_EAR      = 8
L_EYE      = 2;  R_EYE      = 5
L_THUMB    = 21; R_THUMB    = 22
L_INDEX    = 19; R_INDEX    = 20

def get_lm(lm_list, idx):
    """获取关节点坐标 (x, y, visibility)"""
    pt = lm_list[idx]
    return pt.x, pt.y, pt.visibility

def dist(p1, p2):
    return ((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2) ** 0.5

# ── 手势分类规则 ──────────────────────────────────────
def classify_frame(pose_landmarks_list) -> tuple[str, float]:
    """
    基于关键点几何关系分类手势。
    pose_landmarks_list: list of NormalizedLandmark (新 API)
    返回 (gesture_name, confidence 0-1)
    坐标系：(0,0)=左上, (1,1)=右下，y 向下为正
    """
    lm = pose_landmarks_list  # list of NormalizedLandmark

    def pt(idx): return lm[idx].x, lm[idx].y
    def vis(idx): return lm[idx].visibility if hasattr(lm[idx], 'visibility') else 1.0

    nose_x,   nose_y   = pt(NOSE)
    ls_x,     ls_y     = pt(L_SHOULDER)
    rs_x,     rs_y     = pt(R_SHOULDER)
    lw_x,     lw_y     = pt(L_WRIST)
    rw_x,     rw_y     = pt(R_WRIST)
    lh_x,     lh_y     = pt(L_HIP)
    rh_x,     rh_y     = pt(R_HIP)
    le_x,     le_y     = pt(L_ELBOW)
    re_x,     re_y     = pt(R_ELBOW)

    # 可见性检查
    if vis(L_SHOULDER) < 0.3 or vis(R_SHOULDER) < 0.3:
        return 'neutral', 0.2

    shoulder_w = abs(ls_x - rs_x) or 0.01
    shoulder_y = (ls_y + rs_y) / 2
    hip_y      = (lh_y + rh_y) / 2
    body_h     = abs(hip_y - shoulder_y) or 0.01

    # 手腕相对肩膀的高度（负=高于肩，正=低于肩）
    lw_rel = (lw_y - shoulder_y) / body_h
    rw_rel = (rw_y - shoulder_y) / body_h

    # 手腕到鼻子距离（归一化）
    lw_to_nose = dist(pt(L_WRIST), pt(NOSE)) / shoulder_w
    rw_to_nose = dist(pt(R_WRIST), pt(NOSE)) / shoulder_w

    # 两腕距离
    wrist_dist = dist(pt(L_WRIST), pt(R_WRIST)) / shoulder_w

    # 手腕到臀部距离
    lw_to_hip = dist(pt(L_WRIST), pt(L_HIP)) / shoulder_w
    rw_to_hip = dist(pt(R_WRIST), pt(R_HIP)) / shoulder_w

    scores = {}

    # 1. raise_both_hands 🙌 — 双手举高过头顶
    if lw_y < nose_y and rw_y < nose_y:
        h = min(lw_rel, rw_rel)   # 越负越高
        scores['raise_both_hands'] = min(1.0, 0.5 + abs(h) * 0.8)
    else:
        scores['raise_both_hands'] = 0.05

    # 2. point_up ☝️ — 单手高举过头，另一手自然
    one_up = (lw_y < nose_y - 0.05) ^ (rw_y < nose_y - 0.05)
    if one_up:
        up_h = min(lw_rel if lw_y < nose_y else 99,
                   rw_rel if rw_y < nose_y else 99)
        scores['point_up'] = min(1.0, 0.5 + abs(up_h) * 0.5)
    else:
        scores['point_up'] = 0.05

    # 3. heart 🫶 — 双手腕靠近且在胸口高度（肩到腰之间）
    chest_y_ok = (shoulder_y < (lw_y + rw_y)/2 < hip_y)
    if wrist_dist < 0.6 and chest_y_ok:
        scores['heart'] = min(1.0, 0.4 + (0.6 - wrist_dist) * 1.5)
    else:
        scores['heart'] = 0.05

    # 4. clap 👏 — 双手腕极近
    if wrist_dist < 0.3:
        scores['clap'] = min(1.0, 0.5 + (0.3 - wrist_dist) * 3.0)
    else:
        scores['clap'] = 0.05

    # 5. spread_arms 🤸 — 双手腕水平展开，超过肩宽1.5倍
    arm_span = abs(lw_x - rw_x) / shoulder_w
    arms_level = abs((lw_y + rw_y)/2 - shoulder_y) / body_h < 0.4
    if arm_span > 1.4 and arms_level:
        scores['spread_arms'] = min(1.0, 0.4 + (arm_span - 1.4) * 0.8)
    else:
        scores['spread_arms'] = 0.05

    # 6. fly_kiss 😘 — 单手靠近嘴唇（鼻子下方）
    kiss_l = lw_to_nose < 0.5 and lw_y > nose_y
    kiss_r = rw_to_nose < 0.5 and rw_y > nose_y
    if kiss_l or kiss_r:
        best = min(lw_to_nose if kiss_l else 99,
                   rw_to_nose if kiss_r else 99)
        scores['fly_kiss'] = min(1.0, 0.5 + (0.5 - best) * 1.5)
    else:
        scores['fly_kiss'] = 0.05

    # 7. cover_face 🤭 — 单手或双手靠近鼻子/眼睛
    cover_l = lw_to_nose < 0.4
    cover_r = rw_to_nose < 0.4
    if cover_l or cover_r:
        best = min(lw_to_nose if cover_l else 99,
                   rw_to_nose if cover_r else 99)
        # 区分 fly_kiss：手更高（接近眼睛）
        hand_above_nose = (lw_y < nose_y if cover_l else False) or \
                          (rw_y < nose_y if cover_r else False)
        if best < 0.35:
            scores['cover_face'] = min(1.0, 0.5 + (0.4 - best) * 2.0)
        else:
            scores['cover_face'] = 0.1
    else:
        scores['cover_face'] = 0.05

    # 8. hands_on_hips 🤗 — 双手腕靠近臀部两侧
    hip_ok = lw_to_hip < 0.5 and rw_to_hip < 0.5
    if hip_ok:
        scores['hands_on_hips'] = min(1.0, 0.5 + (1.0 - lw_to_hip - rw_to_hip) * 0.5)
    else:
        scores['hands_on_hips'] = 0.05

    # 9. cross_arms 🙅 — 双手腕交叉（左腕在右侧，右腕在左侧）
    crossed = (lw_x > rs_x and rw_x < ls_x) or \
              (lw_x > (ls_x+rs_x)/2 and rw_x < (ls_x+rs_x)/2)
    # 高度在胸口
    cross_h_ok = shoulder_y < (lw_y+rw_y)/2 < hip_y
    if crossed and cross_h_ok:
        scores['cross_arms'] = 0.75
    else:
        scores['cross_arms'] = 0.05

    # 10. chin_rest 🤔 — 单手靠近下巴（鼻子略下方，x 居中）
    chin_y = nose_y + 0.05
    chin_ok_l = abs(lw_y - chin_y) < 0.12 and lw_to_nose < 0.4
    chin_ok_r = abs(rw_y - chin_y) < 0.12 and rw_to_nose < 0.4
    if (chin_ok_l or chin_ok_r) and wrist_dist > 0.3:  # 另一手不在脸旁
        scores['chin_rest'] = 0.65
    else:
        scores['chin_rest'] = 0.05

    # 11. neutral ⬜ — 手垂在两侧，靠近臀部
    natural_l = lw_y > hip_y * 0.9 or (lw_y > shoulder_y and abs(lw_x - ls_x) < 0.3)
    natural_r = rw_y > hip_y * 0.9 or (rw_y > shoulder_y and abs(rw_x - rs_x) < 0.3)
    if natural_l and natural_r:
        scores['neutral'] = 0.6
    else:
        scores['neutral'] = 0.1

    # 冲突消解：cover_face vs fly_kiss
    # fly_kiss 通常嘴型在鼻下，cover_face 手挡眼
    if scores.get('cover_face', 0) > 0.4 and scores.get('fly_kiss', 0) > 0.4:
        # 手如果高于鼻子 → cover_face，低于鼻子 → fly_kiss
        wrist_above_nose = (lw_y < nose_y and lw_to_nose < 0.4) or \
                           (rw_y < nose_y and rw_to_nose < 0.4)
        if wrist_above_nose:
            scores['fly_kiss'] = 0.1
        else:
            scores['cover_face'] = 0.1

    best = max(scores, key=scores.get)
    return best, scores[best]


def analyze_video(video_path: Path) -> dict:
    """分析整个视频，返回各手势出现次数和置信度统计"""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return {'error': '无法打开视频'}

    results = []
    frame_idx = 0

    # 新 MediaPipe Tasks API
    base_options = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
    options = mp_vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=mp_vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % 3 != 0:   # 每3帧采样1帧
                frame_idx += 1
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            detection_result = landmarker.detect(mp_image)

            if detection_result.pose_landmarks:
                # 取第一个人的关键点列表
                lm_list = detection_result.pose_landmarks[0]
                gesture, conf = classify_frame(lm_list)
                results.append((gesture, conf))

            frame_idx += 1

    cap.release()

    if not results:
        return {'dominant': 'neutral', 'confidence': 0.0, 'counts': {}}

    # 只取置信度 > 0.45 的帧
    high_conf = [(g, c) for g, c in results if c > 0.45]
    if not high_conf:
        high_conf = results  # fallback 全用

    counts = Counter(g for g, c in high_conf)
    avg_conf = {g: np.mean([c for g2, c in high_conf if g2 == g]) for g in counts}

    # 按加权出现次数排序（次数 × 平均置信度）
    weighted = {g: counts[g] * avg_conf[g] for g in counts}
    dominant = max(weighted, key=weighted.get)
    dom_conf = avg_conf[dominant]

    return {
        'dominant': dominant,
        'confidence': round(dom_conf, 3),
        'counts': {g: counts[g] for g in sorted(counts, key=counts.get, reverse=True)},
        'total_frames': len(results),
    }


def main():
    LABELED_DIR.mkdir(parents=True, exist_ok=True)

    exts = ('.mov', '.mp4', '.avi', '.m4v', '.MOV', '.MP4')
    videos = sorted([p for p in UNLABELED_DIR.iterdir() if p.suffix in exts])

    if not videos:
        print(f'\n没有找到视频！请把 .mov 文件放入:\n  {UNLABELED_DIR.resolve()}')
        return

    print(f'\n{"="*60}')
    print(f'  AutoDetect 自动标注 — {len(videos)} 个视频')
    print(f'{"="*60}\n')

    report = {}
    labeled_count = 0

    for i, vp in enumerate(videos, 1):
        print(f'  [{i:02d}/{len(videos)}] 分析: {vp.name}')
        info = analyze_video(vp)

        if 'error' in info:
            print(f'         ❌ {info["error"]}')
            continue

        dom = info['dominant']
        conf = info['confidence']
        top2 = list(info['counts'].items())[:3]
        print(f'         → {dom} (conf={conf:.2f}) | 帧分布: {top2}')

        # 移动到对应文件夹
        dest_dir = LABELED_DIR / dom
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / vp.name
        shutil.copy2(str(vp), str(dest))   # copy 而非 move，保留原文件

        report[vp.name] = {**info, 'labeled_as': dom}
        labeled_count += 1

    # 保存报告
    with open(REPORT_FILE, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    # 统计
    print(f'\n{"="*60}')
    print('  各类别分配结果：')
    label_counts = Counter(v['labeled_as'] for v in report.values())
    for label, cnt in sorted(label_counts.items()):
        bar = '█' * cnt
        print(f'  {label:<22} {bar} {cnt}')

    missing = [l for l in [
        "raise_both_hands","point_up","heart","clap","spread_arms",
        "fly_kiss","cover_face","hands_on_hips","cross_arms","chin_rest","neutral"
    ] if label_counts.get(l, 0) == 0]

    if missing:
        print(f'\n  ⚠️  以下类别没有视频（训练时会跳过）: {missing}')

    print(f'\n  ✅ 已标注 {labeled_count} 个视频')
    print(f'  📄 报告: {REPORT_FILE}')
    print(f'\n  下一步: python ml/collect_data.py')


if __name__ == '__main__':
    main()
