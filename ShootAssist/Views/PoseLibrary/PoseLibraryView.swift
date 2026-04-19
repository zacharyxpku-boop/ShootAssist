import SwiftUI

// MARK: - Tab 枚举
enum LibraryTab: String, CaseIterable {
    case popular = "爆款场景"
    case all     = "全部姿势"
}

// MARK: - Pose 灵感库主页
struct PoseLibraryView: View {
    @Environment(\.dismiss) private var dismiss

    // 新数据更吸引人，默认进页显示爆款
    @State private var selectedTab: LibraryTab = .popular
    @State private var selectedCategory: PopularPoseCategory = .cafe
    @State private var selectedPreset: PosePreset?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.warmCream, .lightPink, .lavenderPink],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部 Segmented Tab
                tabSwitcher
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                // 内容区
                Group {
                    if selectedTab == .popular {
                        popularTab
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        allTab
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .navigationTitle("Pose 灵感 ✦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $selectedPreset) { preset in
            PresetDetailSheet(preset: preset)
        }
    }

    // MARK: - Tab 切换条
    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .berryBrown)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                selectedTab == tab
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.7))
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(Color.white.opacity(0.4))
        )
    }

    // MARK: - Tab 1：爆款场景
    private var popularTab: some View {
        VStack(spacing: 14) {
            // 6 类横滑 chip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PopularPoseCategory.allCases, id: \.self) { cat in
                        CategoryChip(
                            category: cat,
                            isSelected: selectedCategory == cat
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // 该类 5 条 Preset 两列网格
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(PopularPosePresets.by(category: selectedCategory)) { preset in
                        PresetCard(preset: preset) {
                            selectedPreset = preset
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Tab 2：全部姿势（沿用原 PoseDatabase 逻辑）
    private var allTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 拍照小技巧横滑
                TipsCarousel()
                    .padding(.top, 4)

                // Pose 分类网格
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(poseDatabase) { category in
                        NavigationLink(destination: PoseCategoryDetailView(category: category)) {
                            CategoryCard(category: category)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - 场景分类 Chip
private struct CategoryChip: View {
    let category: PopularPoseCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(category.emoji)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .berryBrown)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    : AnyShapeStyle(Color.white.opacity(0.8))
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? Color.clear : Color.sakuraPink,
                        lineWidth: 1
                    )
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 爆款 Preset 卡片（两列 3:4）
private struct PresetCard: View {
    let preset: PosePreset
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // 顶部：左 emoji + 右构图图标
                HStack(alignment: .top) {
                    Text(preset.sceneEmoji)
                        .font(.system(size: 34))
                    Spacer()
                    Image(systemName: preset.orientation == .portrait ? "iphone" : "iphone.landscape")
                        .font(.system(size: 14))
                        .foregroundColor(.rosePink)
                }

                Spacer(minLength: 2)

                // 中：名字
                Text(preset.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.berryBrown)
                    .lineLimit(1)

                // 下：描述 2 行
                Text(preset.description)
                    .font(.system(size: 11))
                    .foregroundColor(.midBerryBrown)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                // 底：相机提示
                HStack(spacing: 3) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 8))
                        .foregroundColor(.rosePink)
                    Text(preset.cameraHint)
                        .font(.system(size: 10))
                        .foregroundColor(.midBerryBrown.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "FFF0F5"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.sakuraPink.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: .rosePink.opacity(0.1), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset 详情 Sheet
private struct PresetDetailSheet: View {
    let preset: PosePreset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.warmCream, .lightPink],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // 顶部大 emoji + name
                        HStack(alignment: .center, spacing: 14) {
                            Text(preset.sceneEmoji)
                                .font(.system(size: 64))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.berryBrown)
                                HStack(spacing: 6) {
                                    Label(preset.category.rawValue, systemImage: "tag.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.rosePink)
                                    Image(systemName: preset.orientation == .portrait ? "iphone" : "iphone.landscape")
                                        .font(.system(size: 12))
                                        .foregroundColor(.midBerryBrown)
                                }
                            }
                            Spacer()
                        }

                        // 动作描述
                        fieldBlock(title: "动作描述", content: preset.description, icon: "figure.walk")

                        // 相机机位
                        fieldBlock(title: "相机机位", content: preset.cameraHint, icon: "camera.aperture")

                        // ID（调试/追踪用）
                        HStack {
                            Text("ID")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.midBerryBrown)
                            Text(preset.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.midBerryBrown.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        // 「用这个姿势拍」按钮
                        // TODO: 把 preset 数据传入 PhotoModeView 作为姿势引导，
                        // 目前 PhotoModeView 仅支持 launchCloneDirectly，后续扩展参数
                        NavigationLink {
                            PhotoModeView(launchCloneDirectly: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                Text("用这个姿势拍")
                                    .font(.system(size: 16, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().fill(LinearGradient(
                                    colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                            )
                            .shadow(color: .rosePink.opacity(0.3), radius: 10, y: 4)
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("姿势详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(.rosePink)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldBlock(title: String, content: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.rosePink)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.berryBrown)
            }
            Text(content)
                .font(.system(size: 14))
                .foregroundColor(.berryBrown.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.85))
                .shadow(color: .rosePink.opacity(0.08), radius: 6, y: 2)
        )
    }
}

// MARK: - 原泛用 Pose 分类卡片
private struct CategoryCard: View {
    let category: PoseCategory

    var body: some View {
        VStack(spacing: 8) {
            Text(category.icon)
                .font(.system(size: 32))
            Text(category.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.berryBrown)
            Text("\(category.poses.count) 个 Pose")
                .font(.system(size: 10))
                .foregroundColor(.midBerryBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.sakuraPink, lineWidth: 1)
                )
                .shadow(color: .rosePink.opacity(0.08), radius: 8, y: 2)
        )
    }
}

// MARK: - 分类详情页
struct PoseCategoryDetailView: View {
    let category: PoseCategory

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(category.poses) { pose in
                    PoseCard(pose: pose)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(
            LinearGradient(colors: [.warmCream, .softWhite], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle("\(category.icon) \(category.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 单个 Pose 卡片
private struct PoseCard: View {
    let pose: PoseData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: pose.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.rosePink)
                    .frame(width: 36, height: 36)
                    .background(Color.sakuraPink.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(pose.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.berryBrown)

                        // 难度星级
                        HStack(spacing: 1) {
                            ForEach(0..<pose.difficulty, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.honeyOrange)
                            }
                        }
                    }
                    Text(pose.description)
                        .font(.system(size: 11))
                        .foregroundColor(.midBerryBrown)
                }

                Spacer()
            }

            // 技巧 Tips
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pose.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text("✦")
                            .font(.system(size: 8))
                            .foregroundColor(.rosePink)
                            .offset(y: 2)
                        Text(tip)
                            .font(.system(size: 11))
                            .foregroundColor(.berryBrown.opacity(0.8))
                    }
                }
            }

            // 场景 + 机位 + 跳转拍照
            HStack(spacing: 12) {
                Label(pose.bestFor, systemImage: "mappin.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.midBerryBrown)
                Label(pose.cameraAngle, systemImage: "camera.metering.center.weighted")
                    .font(.system(size: 10))
                    .foregroundColor(.midBerryBrown)
                Spacer()
                NavigationLink(destination: PhotoModeView(launchCloneDirectly: true)) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill").font(.system(size: 10))
                        Text("拍同款").font(.system(size: 10, weight: .semibold))
                        Image(systemName: "arrow.right").font(.system(size: 8))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient(
                        colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                        startPoint: .leading, endPoint: .trailing
                    )))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .rosePink.opacity(0.08), radius: 8, y: 2)
        )
    }
}

// MARK: - 拍照小技巧横滑
private struct TipsCarousel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 拍照小技巧")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.berryBrown)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(photoTips.enumerated()), id: \.offset) { idx, tip in
                        TipCard(number: idx + 1, text: tip)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct TipCard: View {
    let number: Int
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.rosePink)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.berryBrown)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 180)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sakuraPink.opacity(0.5), lineWidth: 1)
                )
        )
    }
}
