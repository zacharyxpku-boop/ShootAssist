"""copy_labels.py — 根据视觉分析结果把视频复制到标签文件夹"""
import shutil
from pathlib import Path

BASE_DIR    = Path(__file__).parent
RAW_DIR     = BASE_DIR / 'data' / 'raw_unlabeled'
LABELED_DIR = BASE_DIR / 'data' / 'raw_videos'

LABEL_MAP = {
    '2026-04-06 215912.mov': 'point_up',
    '2026-04-06 215940.mov': 'raise_both_hands',
    '2026-04-06 220028.mov': 'heart',
    '2026-04-06 220038.mov': 'point_up',
    '2026-04-06 220042.mov': 'cover_face',
    '2026-04-06 220125.mov': 'spread_arms',
    '2026-04-06 220159.mov': 'spread_arms',
    '2026-04-06 220245.mov': 'heart',
    '2026-04-06 220510.mov': 'clap',
    '2026-04-06 220515.mov': 'raise_both_hands',
    '2026-04-06 220530.mov': 'point_up',
    '2026-04-06 220538.mov': 'chin_rest',
    '2026-04-06 220545.mov': 'spread_arms',
}

from collections import Counter
counts = Counter(LABEL_MAP.values())
print("Label distribution:")
for label, cnt in sorted(counts.items()):
    print(f"  {label}: {cnt}")

for fname, label in LABEL_MAP.items():
    src = RAW_DIR / fname
    if not src.exists():
        print(f"[MISS] {fname}")
        continue
    dst_dir = LABELED_DIR / label
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / fname
    shutil.copy2(str(src), str(dst))
    print(f"  {label}/{fname}")

print(f"\nDone. {len(LABEL_MAP)} videos copied.")
