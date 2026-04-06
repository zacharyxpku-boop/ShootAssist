"""
label_videos.py — 视频快速标注工具
把下载好的原始视频一个个播放，你按对应数字键分类，自动移入正确文件夹。

使用方法:
  1. 把下载的 .mov 文件全部放入 data/raw_unlabeled/ 文件夹
  2. pip install opencv-python
  3. python ml/label_videos.py
  4. 按数字键给每个视频打标签，'s' 跳过，'q' 退出保存进度

标注完成后直接运行:
  python ml/collect_data.py
"""

import os, sys, shutil, json, cv2

# ── 手势标签菜单 ────────────────────────────────────────
LABELS = {
    '1': 'raise_both_hands',  # 🙌 双手举高
    '2': 'point_up',          # ☝️ 指天
    '3': 'heart',             # 🫶 比心
    '4': 'clap',              # 👏 拍手
    '5': 'spread_arms',       # 🤸 展开双臂
    '6': 'fly_kiss',          # 😘 飞吻
    '7': 'cover_face',        # 🤭 捂脸卖萌
    '8': 'hands_on_hips',     # 🤗 叉腰
    '9': 'cross_arms',        # 🙅 双手交叉
    '0': 'chin_rest',         # 🤔 托腮
    'n': 'neutral',           # 普通站立
}

EMOJI_MAP = {
    'raise_both_hands': '🙌', 'point_up': '☝️', 'heart': '🫶',
    'clap': '👏', 'spread_arms': '🤸', 'fly_kiss': '😘',
    'cover_face': '🤭', 'hands_on_hips': '🤗', 'cross_arms': '🙅',
    'chin_rest': '🤔', 'neutral': '⬜'
}

UNLABELED_DIR = 'data/raw_unlabeled'
RAW_DIR       = 'data/raw_videos'
PROGRESS_FILE = 'data/.label_progress.json'

def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {}

def save_progress(progress):
    os.makedirs('data', exist_ok=True)
    with open(PROGRESS_FILE, 'w') as f:
        json.dump(progress, f, indent=2)

def print_menu():
    print('\n' + '='*50)
    print('  手势标签菜单（按对应键）')
    print('='*50)
    for key, label in LABELS.items():
        emoji = EMOJI_MAP.get(label, '')
        print(f'  [{key}] {emoji}  {label}')
    print('  [s] 跳过这个视频')
    print('  [q] 保存并退出')
    print('='*50)

def play_and_label(video_path: str) -> str | None:
    """播放视频，返回用户选择的标签（或 None=跳过）"""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f'无法打开: {video_path}')
        return None

    filename = os.path.basename(video_path)
    print(f'\n▶ 正在播放: {filename}')
    print('  按 [空格] 暂停/继续，视频播完后选择手势标签')

    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    frame_delay = max(1, int(1000 / fps))
    paused = False

    while True:
        if not paused:
            ret, frame = cap.read()
            if not ret:
                # 视频播完，显示最后一帧等待输入
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ret, frame = cap.read()
                if ret:
                    cv2.putText(frame, 'ENDED - Press label key', (20, 40),
                                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
                    cv2.imshow(f'Label: {filename}', frame)
                paused = True
                continue

            cv2.putText(frame, filename, (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
            cv2.imshow(f'Label: {filename}', frame)

        key = cv2.waitKey(frame_delay if not paused else 0) & 0xFF

        if key == ord(' '):
            paused = not paused
        elif key == ord('q'):
            cap.release()
            cv2.destroyAllWindows()
            return 'QUIT'
        elif key == ord('s'):
            cap.release()
            cv2.destroyAllWindows()
            return None
        elif chr(key) in LABELS:
            label = LABELS[chr(key)]
            print(f'  → 标注为: {EMOJI_MAP.get(label, "")} {label}')
            cap.release()
            cv2.destroyAllWindows()
            return label

    cap.release()
    cv2.destroyAllWindows()
    return None

def main():
    os.makedirs(UNLABELED_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)

    # 获取所有未标注视频
    exts = ('.mov', '.mp4', '.avi', '.m4v')
    videos = sorted([
        os.path.join(UNLABELED_DIR, f)
        for f in os.listdir(UNLABELED_DIR)
        if f.lower().endswith(exts)
    ])

    if not videos:
        print(f'没有找到视频文件！')
        print(f'请把下载的 .mov 文件放入: {os.path.abspath(UNLABELED_DIR)}/')
        sys.exit(0)

    progress = load_progress()
    remaining = [v for v in videos if os.path.basename(v) not in progress]

    print(f'\n共 {len(videos)} 个视频，已标注 {len(progress)} 个，剩余 {len(remaining)} 个')
    print_menu()

    labeled_count = 0
    for video_path in remaining:
        fname = os.path.basename(video_path)
        label = play_and_label(video_path)

        if label == 'QUIT':
            print('\n已保存进度，下次运行继续。')
            break

        if label is None:
            print(f'  [跳过] {fname}')
            continue

        # 移入对应手势文件夹
        dest_dir = os.path.join(RAW_DIR, label)
        os.makedirs(dest_dir, exist_ok=True)
        dest_path = os.path.join(dest_dir, fname)
        shutil.move(video_path, dest_path)
        progress[fname] = label
        save_progress(progress)
        labeled_count += 1
        print(f'  ✅ 已保存到: {dest_dir}/')

    # 统计结果
    print('\n' + '='*50)
    print('标注完成！各类别文件数量：')
    from collections import Counter
    counts = Counter(progress.values())
    for label, count in sorted(counts.items()):
        bar = '█' * count + '░' * max(0, 5 - count)
        warn = ' ⚠️ 建议>=5个' if count < 5 else ''
        print(f'  {EMOJI_MAP.get(label,""):<4} {label:<20} {bar} {count}{warn}')

    print('\n下一步：')
    print('  python ml/collect_data.py   # 提取关键点特征')
    print('  python ml/train.py          # 训练模型')

if __name__ == '__main__':
    main()
