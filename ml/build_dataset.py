"""
build_dataset.py — 一键构建完整训练集
按优先级依次运行所有数据源，最后汇报每类数据量。

用法: python ml/build_dataset.py

数据源优先级:
  1. 合成数据 (generate_synthetic.py) — 零依赖，立刻可用
  2. 自录视频 (collect_data.py) — 需要 data/raw_videos/ 有视频
  3. HaGRID 图片 (fetch_hagrid.py) — 需要 datasets 库或手动下载
  4. YouTube 采集 (fetch_youtube_gestures.py) — 需要 yt-dlp
  5. NTU 骨架 (fetch_ntu_skeleton.py) — 需要手动下载骨架包
"""

import subprocess, sys
import numpy as np
from pathlib import Path

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / 'data' / 'keypoints'

LABELS = [
    "raise_both_hands", "point_up", "heart", "clap", "spread_arms",
    "fly_kiss", "cover_face", "hands_on_hips", "cross_arms", "chin_rest", "neutral"
]


def run_script(name: str, path: str):
    """运行子脚本，失败不中断"""
    print(f"\n{'─' * 50}")
    print(f"  运行: {name}")
    print(f"{'─' * 50}")
    try:
        result = subprocess.run(
            [sys.executable, path],
            cwd=str(BASE_DIR.parent),
            timeout=600,
        )
        if result.returncode != 0:
            print(f"  ⚠️  {name} 退出码 {result.returncode}，继续下一步")
    except subprocess.TimeoutExpired:
        print(f"  ⚠️  {name} 超时，跳过")
    except Exception as e:
        print(f"  ⚠️  {name} 出错: {e}")


def report():
    """汇报每类数据量"""
    print(f"\n{'=' * 55}")
    print(f"  训练数据汇总")
    print(f"{'=' * 55}")

    total = 0
    insufficient = []

    for label in LABELS:
        npy_path = DATA_DIR / label / 'sequences.npy'
        if npy_path.exists():
            data = np.load(str(npy_path))
            count = data.shape[0]
            status = "✅" if count >= 50 else "⚠️"
            print(f"  {status} {label:25s} {count:5d} 条")
            total += count
            if count < 50:
                insufficient.append(label)
        else:
            print(f"  ❌ {label:25s}     0 条")
            insufficient.append(label)

    print(f"\n  总计: {total} 条序列")

    if insufficient:
        print(f"\n  ⚠️  数据不足的类别 (<50条): {insufficient}")
        print(f"  建议: 周末为这些类别录 5-10 段视频，放入 data/raw_videos/<类名>/")
    else:
        print(f"\n  ✅ 所有类别均达到 50 条以上，可以训练！")
        print(f"  运行: python ml/train.py")


def main():
    print("=" * 55)
    print("  小白快拍 — 一键构建训练数据集")
    print("=" * 55)

    # Step 1: 合成数据（最快，零依赖）
    run_script("合成数据生成", str(BASE_DIR / 'generate_synthetic.py'))

    # Step 2: 自录视频处理
    raw_dir = BASE_DIR / 'data' / 'raw_videos'
    has_raw = raw_dir.exists() and any(raw_dir.iterdir())
    if has_raw:
        run_script("自录视频处理", str(BASE_DIR / 'collect_data.py'))
    else:
        print(f"\n  [跳过] 自录视频: {raw_dir} 无内容")

    # Step 3: HaGRID
    try:
        import datasets
        run_script("HaGRID 数据转换", str(BASE_DIR / 'fetch_hagrid.py'))
    except ImportError:
        hagrid_dir = BASE_DIR / 'data' / 'hagrid'
        if hagrid_dir.exists() and any(hagrid_dir.iterdir()):
            run_script("HaGRID 数据转换", str(BASE_DIR / 'fetch_hagrid.py'))
        else:
            print(f"\n  [跳过] HaGRID: 未安装 datasets 且无本地图片")
            print(f"  安装: pip install datasets")

    # Step 4: YouTube 采集
    try:
        subprocess.run(['yt-dlp', '--version'], capture_output=True, check=True)
        run_script("YouTube 手势采集", str(BASE_DIR / 'fetch_youtube_gestures.py'))
    except (FileNotFoundError, subprocess.CalledProcessError):
        print(f"\n  [跳过] YouTube 采集: 未安装 yt-dlp")
        print(f"  安装: pip install yt-dlp")

    # Step 5: NTU (需手动下载)
    ntu_dir = BASE_DIR / 'data' / 'ntu_skeletons'
    if ntu_dir.exists() and any(ntu_dir.glob("*.skeleton")):
        run_script("NTU 骨架转换", str(BASE_DIR / 'fetch_ntu_skeleton.py'))
    else:
        print(f"\n  [跳过] NTU RGB+D: 无骨架数据")

    # 最终汇报
    report()


if __name__ == '__main__':
    main()
