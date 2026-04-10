# ShootAssist ML 知识库

> 2026-04-10 整理，供后续 session 直接参考

---

## 一、当前架构 & 瓶颈

```
摄像头 → MediaPipe BlazePose (33点) → 9关节×(x,y) → LSTM → 11类手势
```

- 训练数据：11类中仅6类各1条序列，远远不够
- 目标：每类 50-100+ 条序列

---

## 二、开源数据集（可用于补数据/预训练）

| 数据集 | 关节数 | 规模 | 适用性 | 链接 |
|--------|--------|------|--------|------|
| **NTU RGB+D 120** | 25 (Kinect) | 114K序列/120类 | **最佳**，含clap/wave/point，需重映射到MediaPipe | rose1.ntu.edu.sg |
| **Halpe Full-Body** | 136 (26体+42手+68脸) | 50K标注(基于COCO) | **手部关键点完整**，可降采样到33点 | github.com/Fang-Haoshu/Halpe-FullBody |
| **HaGRID** | 手部bbox+关键点 | 552K图/18类 | heart/fly_kiss/point_up 直接可用 | github.com/hukenovs/hagrid |
| COCO-Pose | 17 | 250K人 | 通用基线，缺手部细节 | cocodataset.org |
| Human3.6M | 32 (3D) | 3.6M帧 | 3D预训练，动作偏日常 | vision.imar.ro/human3.6m |
| Yoga-82 | 图像级标签 | 28K图/82类 | 个别姿势重叠(T-pose等) | sites.google.com/view/yoga-82 |

### 关键点格式转换 (COCO 17 → MediaPipe 33)

直接映射17个点，缺失的16个点：
- 眼/嘴细节(1,3,4,6,9,10) → 从已有点插值
- **手部(17-22)** → 用Halpe数据补，或退化到wrist位置
- 脚部(29-32) → 从ankle偏移

---

## 三、模型选型（底层 Pose Estimation）

| 模型 | 关键点 | 移动端延迟 | CoreML | 推荐度 |
|------|--------|-----------|--------|--------|
| **MediaPipe BlazePose** | 33 | ~15ms | iOS SDK原生 | **当前最优，保持** |
| RTMPose-s | 17 | ~14ms | 支持导出 | 备选，少16个点 |
| YOLOv8n-pose | 17 | ~5ms | `model.export(format='coreml')` | 快但丢手部信息 |
| MoveNet Lightning | 17 | ~6ms | 需转换 | 不如MediaPipe |

**结论：保持 MediaPipe。** heart/chin_rest/cover_face/fly_kiss 依赖手部关键点，17点模型会降级5+类的识别。

---

## 四、数据增强技术（在关键点序列上操作）

已有：水平翻转 + 高斯噪声 + 时间拉伸

可加的：
1. **关节旋转** — 以hip中心为原点旋转±15°
2. **尺度扰动** — 全坐标乘0.85-1.15
3. **关节dropout** — 随机零化1-3个关键点(模拟遮挡)
4. **时间遮蔽** — 随机置零5-15%帧
5. **Mixup** — 同类两条序列线性插值
6. **程序化生成** — 定义每类的关节角度分布，在约束内采样

---

## 五、配套能力（识别之外的增强功能）

### 5.1 姿势匹配评分

推荐三层指标：
- **实时UI**：加权余弦相似度（快，0-100%直觉分数）
- **具体指导**：关节角度对比（"手臂再抬高15°"）
- **数据分析**：OKS (Object Keypoint Similarity，COCO标准)

iOS实现：`VNDetectHumanBodyPoseRequest` (19关节，iOS 14+)

### 5.2 光线检测

```
脸部区域左右亮度比 > 1.5:1 → 侧光警告
背景亮度 > 人脸亮度 × 1.8 → 逆光警告
```

用 `CIAreaAverage` + `VNDetectFaceLandmarksRequest` 实现。

### 5.3 构图检测（三分法）

```
VNGenerateAttentionBasedSaliencyImageRequest → 显著区域质心
→ 计算到4个三分交叉点的最短距离 → 评分
```

### 5.4 背景杂乱度

```
VNDetectHumanRectanglesRequest → mask人物
→ VNGenerateObjectnessBasedSaliencyImageRequest → 背景blob数
→ >3个显著物体 = 杂乱
```

### 5.5 相机角度建议

每个pose附带推荐角度元数据，用 `CMMotionManager` 检测手机倾斜，实时提示"再往下倾斜10°"。

---

## 六、竞品差异化

| 竞品 | 做了什么 | 没做什么（我们的机会） |
|------|----------|----------------------|
| **Posica** | 1500+姿势图库/AR太阳路径 | 无实时匹配/无评分 |
| **UPose** | 半透明姿势叠加层 | 无评分/无构图/无光线 |
| **美图秀秀** | 拍后美化 | 不做拍前指导 |
| **Lensa** | AI头像/后期编辑 | 不做姿势引导 |

**小白快门独特组合：实时姿势匹配 + 构图评分 + 光线检测 + 难度进阶，一站式拍前指导。**

---

## 七、关键论文

| 论文 | 核心价值 | 可用性 |
|------|----------|--------|
| **InstaPose** (ICCV 2025W) | 场景感知姿势推荐(ViT分析背景→推荐匹配姿势) | 高，可移植 |
| **PAGD** (ACM 2025) | 姿势推荐+美化双阶段 | Stage1可用 |
| RTMPose (2303.07399) | 移动端SOTA姿势估计 | 备选底层 |
| Lightweight GCN (2104.04255) | 轻量骨架手势分类 | 可替代LSTM |
| BlazePose (2006.10204) | 当前底层，33点 | 已在用 |

---

## 八、周末录制数据行动清单

1. 每类录 **8-10段视频**，每段3-5秒
2. 变量覆盖：2个角度(正面/45°) × 2种光线(室内/窗边) × 2-3人
3. 优先补空类：cross_arms / fly_kiss / hands_on_hips / neutral
4. neutral 多录：站/走/看手机/背对都算
5. 录完跑 `python ml/collect_data.py`，目标每类 50+ 序列
6. 再跑 `python ml/train.py`，观察 val accuracy
