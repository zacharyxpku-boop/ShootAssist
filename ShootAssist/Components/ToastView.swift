import SwiftUI

// MARK: - Toast 视图（支持成功/错误两种风格）
struct ToastView: View {
    let message: String
    var isError: Bool = false
    @Binding var isShowing: Bool

    @State private var offset: CGFloat = -60

    var body: some View {
        if isShowing {
            HStack(spacing: 6) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isError ? .red : .rosePink)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.berryBrown)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.white)
                    .overlay(
                        Capsule()
                            .stroke(isError ? Color.red.opacity(0.6) : Color.rosePink, lineWidth: 1.5)
                    )
                    .shadow(color: (isError ? Color.red : Color.rosePink).opacity(0.15), radius: 8, y: 2)
            )
            .offset(y: offset)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    offset = 60
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeIn(duration: 0.3)) { offset = -60 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShowing = false
                        offset = -60
                    }
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Toast 修饰器

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let isError: Bool

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            ToastView(message: message, isError: isError, isShowing: $isShowing)
        }
    }
}

extension View {
    /// 成功 toast（粉色）
    func toast(isShowing: Binding<Bool>, message: String = "✦ 已保存到相册") -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, isError: false))
    }

    /// 错误 toast（红色）
    func errorToast(isShowing: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, isError: true))
    }
}
