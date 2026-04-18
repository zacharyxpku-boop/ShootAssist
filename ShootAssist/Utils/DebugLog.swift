import Foundation

/// Release 构建下会被编译器完全消除的调试日志
/// 好处：
///  1. 不会污染 Console 也不会被 os_log 采样到
///  2. 字符串拼接/插值在 Release 里根本不会求值，零开销
///  3. 避免把用户设备路径/视频 URL 这类半敏感信息写进发行版日志
///
/// 用法：`saLog("[Camera] session started preset=\(preset)")`
@inlinable
public func saLog(_ message: @autoclosure () -> String,
                  file: StaticString = #fileID,
                  line: UInt = #line) {
    #if DEBUG
    print("[\(file):\(line)] \(message())")
    #endif
}
