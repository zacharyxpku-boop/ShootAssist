import SwiftUI

// MARK: - Pose 灵感库主页
struct PoseLibraryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.warmCream, .lightPink, .lavenderPink],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 拍照小技巧横滑
                    TipsCarousel()
                        .padding(.top, 8)

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
        .navigationTitle("Pose 灵感 ✦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - 分类卡片
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
                NavigationLink(destination: PhotoModeView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10))
                        Text("用这个Pose拍")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.rosePink))
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
