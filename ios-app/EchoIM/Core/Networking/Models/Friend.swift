import Foundation

/// 服务端 `/api/friends` 的字段集与 `UserProfile` 完全一致。
/// 用领域别名保留语义，不重复声明一份结构体。
typealias Friend = UserProfile
