"""
auto_label.py — 智能多段标注工具
适用于：视频上有 on-screen 手势标签，执行到某个手势时标签会亮起

使用方法:
  python ml/auto_label.py

播放时操作:
  - 看到某个手势标签"亮起"时，立刻按对应数字键
  - 程序自动截取 该时刻前30帧+后30帧 作为该手势样本
  - 一个视频可以多次按键（不同手势都能标注）
  - [空格] 暂停/继续
  - [r]    重新播放当前视频
  - [s]    跳过当前视频
  - [q]    保存进度并退出

手势映射:
  1=raise_both_hands  2=point_up    3=heart       4=clap
  5=spread_arms       6=fly_kiss    7=cover_face  8=hands_on_hips
  9=cross_arms        0=chin_rest   n=neutral
"""

import os, sys, json, cv2
import numpy as np
from pathlib import Path
from datetime import datetime

# ── 配置 ─────────────────────────────────────────────────────
BASE_DIR      = Path(__file__).parent
UNLABELED_DIR = BASE_DIR / 'data' / 'raw_unlabeled'
LABELED_DIR   = BASE_DIR / 'data' / 'raw_videos'   # 与 collect_data.py 一致
PROGRESS_FILE = BASE_DIR / 'data' / '.auto_label_progress.json'

WINDOW_BEFORE = 30   # 按键前取多少帧
WINDOW_AFTER  = 30   # 按键后取多少帧

LABELS = {
    '1': 'raise_both_hands',
    '2': 'point_up',
    '3': 'heart',
    '4': 'clap',
    '5': 'spread_arms',
    '6': 'fly_kiss',
    '7': 'cover_face',
    '8': 'hands_on_hips',
    '9': 'cross_arms',
    '0': 'chin_rest',
    'n': 'neutral',
}

EMOJI = {
    'raise_both_hands': '🙌', 'point_up': '☝️',   'heart': '🫶',
    'clap': '👏',             'spread_arms': '🤸',  'fly_kiss': '😘',
    'cover_face': '🤭',       'hands_on_hips': '🤗','cross_arms': '🙅',
    'chin_rest': '🤔',        'neutral': '⬜',
}

# ── 进度持久化 ────────────────────────────────────────────────
def load_progress():
    if PROGRESS_FILE.exists():
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {}

def save_progress(progress):
    PROGRESS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(PROGRESS_FILE, 'w') as f:
        json.dump(progress, f, indent=2, ensure_ascii=False)

# ── 帧缓冲区（滚动窗口）────────────────────────────────────────
class FrameBuffer:
    """固定大小的帧滚动缓冲区，用于回溯 WINDOW_BEFORE 帧"""
    def __init__(self, maxsize=90):
        self.maxsize = maxsize
        self.buf = []

    def push(self, frame):
        self.buf.append(frame.copy())
        if len(self.buf) > self.maxsize:
            self.buf.pop(0)

    def get_before(self, n):
        """取最近 n 帧（不含当前）"""
        return list(self.buf[-n:]) if len(self.buf) >= n else list(self.buf)

# ── 保存片段为视频 ────────────────────────────────────────────
def save_segment(frames, label, video_name, seg_idx, fps=30):
    out_dir = LABELED_DIR / label
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = Path(video_name).stem.replace(' ', '_')
    out_path = str(out_dir / f'{stem}_seg{seg_idx:03d}.mp4')

    if not frames:
        return out_path

    h, w = frames[0].shape[:2]
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(out_path, fourcc, fps, (w, h))
    for f in frames:
        writer.write(f)
    writer.release()
    return out_path

# ── 主标注函数 ────────────────────────────────────────────────
def label_video(video_path: Path, progress: dict):
    """
    播放视频，用户实时按键打标。
    返回: 'QUIT' | 'SKIP' | 'DONE'
    """
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f'  [ERROR] 无法打开: {video_path.name}')
        return 'SKIP'

    fps      = cap.get(cv2.CAP_PROP_FPS) or 30
    total_f  = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    delay    = max(1, int(1000 / fps))
    fname    = video_path.name

    buf       = FrameBuffer(maxsize=WINDOW_BEFORE + 10)
    segments  = []     # list of (label, start_frame_idx, pending_frames_left)
    pending   = {}     # label -> frames_remaining_to_collect
    pending_frames = {}  # label -> list of frames for current segment

    seg_counter = progress.get(fname, {}).get('seg_count', 0)
    paused      = False
    frame_idx   = 0

    print(f'\n  ▶  {fname}  ({total_f} 帧, {fps:.0f}fps)')
    print('     按手势键打标 | [空格]暂停 | [r]重播 | [s]跳过 | [q]退出')

    win_name = f'AutoLabel | {fname}'

    # 收集待写帧的任务队列：[(label, seg_idx, frames_list)]
    collecting = []   # 每个元素: {'label':str, 'seg':int, 'frames':list, 'need':int}

    while True:
        if not paused:
            ret, frame = cap.read()
            if not ret:
                # 视频结束，flush 所有未满的 collecting
                for task in collecting:
                    if task['frames']:
                        out = save_segment(task['frames'], task['label'], fname, task['seg'], int(fps))
                        print(f'     ✅ 段落保存: {task["label"]} → {Path(out).name}')
                        seg_counter += 1
                        segments.append({'label': task['label'], 'seg': task['seg']})
                collecting = []

                # 显示"已结束"提示
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ret2, last = cap.read()
                if ret2:
                    overlay = last.copy()
                    cv2.rectangle(overlay, (0, 0), (overlay.shape[1], 50), (0, 0, 0), -1)
                    cv2.addWeighted(overlay, 0.6, last, 0.4, 0, last)
                    cv2.putText(last, 'END - Press [n]ext/[r]eplay/[q]uit', (10, 33),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                    cv2.imshow(win_name, last)
                paused = True
                frame_idx = total_f
                continue

            frame_idx += 1

            # 把当前帧加入所有正在收集的任务
            for task in collecting:
                if task['need'] > 0:
                    task['frames'].append(frame.copy())
                    task['need'] -= 1
                    if task['need'] == 0:
                        out = save_segment(task['frames'], task['label'], fname, task['seg'], int(fps))
                        print(f'     ✅ 段落保存: {task["label"]} → {Path(out).name}')
                        seg_counter += 1
                        segments.append({'label': task['label'], 'seg': task['seg']})
            collecting = [t for t in collecting if t['need'] > 0]

            buf.push(frame)

            # HUD 叠加
            display = frame.copy()
            h, w = display.shape[:2]
            progress_pct = frame_idx / max(total_f, 1)
            bar_w = int(w * progress_pct)
            cv2.rectangle(display, (0, h-8), (bar_w, h), (0, 200, 100), -1)
            cv2.rectangle(display, (0, h-8), (w, h), (100, 100, 100), 1)

            # 显示已打标次数
            if segments:
                label_str = '  '.join([f'{EMOJI.get(s["label"],"?")}' for s in segments[-5:]])
                cv2.putText(display, label_str, (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)

            # 显示正在收集中的标签
            if collecting:
                col_str = 'collecting: ' + ', '.join([EMOJI.get(t['label'],'?') for t in collecting])
                cv2.putText(display, col_str, (10, 60),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 128, 0), 2)

            cv2.imshow(win_name, display)

        key = cv2.waitKey(delay if not paused else 30) & 0xFF

        if key == ord('q'):
            cap.release()
            cv2.destroyAllWindows()
            return 'QUIT'

        elif key == ord('s'):
            cap.release()
            cv2.destroyAllWindows()
            return 'SKIP'

        elif key == ord('r'):
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            buf = FrameBuffer(maxsize=WINDOW_BEFORE + 10)
            frame_idx = 0
            collecting = []
            paused = False
            print('  ↩  重新播放')

        elif key == ord(' '):
            paused = not paused
            print(f'  {"⏸ 暂停" if paused else "▶ 继续"}')

        elif chr(key) in LABELS:
            label = LABELS[chr(key)]
            # 取缓冲区里的前 WINDOW_BEFORE 帧
            before_frames = buf.get_before(WINDOW_BEFORE)
            seg_idx = seg_counter + len(collecting) + 1
            task = {
                'label': label,
                'seg': seg_idx,
                'frames': list(before_frames),   # 复制 before 帧
                'need': WINDOW_AFTER,             # 还需要收集的后续帧数
            }
            collecting.append(task)
            emoji = EMOJI.get(label, '')
            print(f'  🎯 [{frame_idx}/{total_f}] 标注: {emoji} {label} (前{len(before_frames)}帧+后{WINDOW_AFTER}帧)')

    cap.release()
    cv2.destroyAllWindows()

    # 保存该视频进度
    progress[fname] = {
        'seg_count': seg_counter,
        'segments': segments,
        'done': True,
    }
    return 'DONE'

# ── 统计 ──────────────────────────────────────────────────────
def print_stats():
    print('\n' + '='*55)
    print('  各类别视频片段数量：')
    print('='*55)
    total = 0
    for label in sorted(LABELS.values()):
        d = LABELED_DIR / label
        if d.exists():
            count = len([f for f in d.iterdir() if f.suffix in ('.mp4','.avi','.mov')])
        else:
            count = 0
        bar = '█' * count + '░' * max(0, 8 - count)
        warn = ' ⚠️' if count < 3 else ''
        print(f'  {EMOJI.get(label,""):<3} {label:<22} {bar} {count}{warn}')
        total += count
    print(f'\n  合计: {total} 个片段')
    print('='*55)

# ── 入口 ──────────────────────────────────────────────────────
def main():
    UNLABELED_DIR.mkdir(parents=True, exist_ok=True)
    LABELED_DIR.mkdir(parents=True, exist_ok=True)

    exts = ('.mov', '.mp4', '.avi', '.m4v', '.MOV', '.MP4')
    videos = sorted([
        p for p in UNLABELED_DIR.iterdir()
        if p.suffix in exts
    ])

    if not videos:
        print(f'\n  没有找到视频！请把 .mov 文件放入:')
        print(f'  {UNLABELED_DIR.resolve()}')
        sys.exit(0)

    progress = load_progress()
    done_files = {k for k, v in progress.items() if v.get('done')}
    remaining  = [v for v in videos if v.name not in done_files]

    print(f'\n{"="*55}')
    print(f'  AutoLabel 智能标注工具')
    print(f'{"="*55}')
    print(f'  共 {len(videos)} 个视频 | 已完成 {len(done_files)} | 剩余 {len(remaining)}')
    print()
    print('  按键说明:')
    for k, label in LABELS.items():
        print(f'    [{k}] {EMOJI.get(label,"")} {label}')
    print('    [空格] 暂停/继续   [r] 重播   [s] 跳过   [q] 退出')
    print(f'{"="*55}\n')

    for video_path in remaining:
        result = label_video(video_path, progress)
        save_progress(progress)

        if result == 'QUIT':
            print('\n  进度已保存，下次运行继续。')
            break
        elif result == 'SKIP':
            print(f'  [跳过] {video_path.name}')

    print_stats()
    print('\n  下一步：')
    print('  python ml/collect_data.py   # 提取 MediaPipe 关键点')
    print('  python ml/train.py          # 训练 LSTM 模型')

if __name__ == '__main__':
    main()
