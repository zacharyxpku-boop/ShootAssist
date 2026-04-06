# ShootAssist 手势识别模型训练流程

## 目录结构
```
ml/
├── README.md              (本文件)
├── collect_data.py        (数据采集脚本：从视频提取关键点序列)
├── train.py               (LSTM 模型训练)
├── convert_coreml.py      (转换为 CoreML .mlmodel)
├── data/                  (训练数据，不提交到 git)
│   ├── raw_videos/        (原始手势视频)
│   └── keypoints/         (提取的关键点序列 .npy)
└── models/                (训练产物)
    ├── gesture_lstm.h5    (Keras 模型)
    └── GestureClassifier.mlmodel  (CoreML 模型，拷贝到 Xcode)
```

## 环境安装
```bash
pip install mediapipe opencv-python tensorflow coremltools numpy
```

## 流程（3步）

### Step 1: 采集数据
```bash
python collect_data.py
```
- 用手机录制各手势短视频（每个手势 5-10 段，每段 2-4 秒）
- 放入 `data/raw_videos/<gesture_name>/` 文件夹
- 运行脚本自动提取 MediaPipe 关键点，保存为 .npy

### Step 2: 训练模型
```bash
python train.py
```
- 读取 keypoints/ 目录数据
- 训练 LSTM 模型（约 5-10 分钟）
- 保存 gesture_lstm.h5

### Step 3: 转换 CoreML
```bash
python convert_coreml.py
```
- 输出 GestureClassifier.mlmodel
- 拖入 Xcode 项目即可使用

## 手势标签与 Emoji 对应
| 标签               | Emoji | 描述         |
|--------------------|-------|--------------|
| raise_both_hands   | 🙌    | 双手举高     |
| point_up           | ☝️    | 指天         |
| heart              | 🫶    | 比心         |
| clap               | 👏    | 拍手         |
| spread_arms        | 🤸    | 展开双臂     |
| fly_kiss           | 😘    | 飞吻         |
| cover_face         | 🤭    | 捂脸卖萌     |
| hands_on_hips      | 🤗    | 叉腰         |
| cross_arms         | 🙅    | 双手交叉     |
| chin_rest          | 🤔    | 托腮         |
| neutral            | (无)  | 普通站立     |
