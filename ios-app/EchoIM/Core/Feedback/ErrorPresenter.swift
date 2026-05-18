import Foundation

enum ErrorPresenter {
    static func displayMessage(for error: Error) -> String? {
        guard !isCancellation(error) else {
            return nil
        }

        return message(for: error)
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return message(for: apiError)
        }

        return String(localized: "操作失败，请稍后重试")
    }

    static func message(for error: APIError) -> String {
        if let serverError = error.serverError {
            return message(forServerCode: serverError.code) ?? serverError.message
        }

        switch error {
        case .network(let urlError):
            switch urlError.code {
            case .notConnectedToInternet:
                return String(localized: "网络不可用，请检查连接")
            case .timedOut:
                return String(localized: "请求超时，请稍后重试")
            default:
                return String(localized: "网络错误，请稍后重试")
            }
        case .unauthorized:
            return String(localized: "登录状态已失效，请重新登录")
        case .http:
            return String(localized: "请求失败，请稍后重试")
        case .decoding, .invalidResponse:
            return String(localized: "数据异常，请稍后重试")
        }
    }

    static func message(forServerCode code: String) -> String? {
        switch code {
        case "invalid_invite_code":
            return String(localized: "邀请码无效")
        case "username_too_short":
            return String(localized: "用户名至少需要 3 个字符")
        case "invalid_email":
            return String(localized: "邮箱格式不正确")
        case "email_already_in_use":
            return String(localized: "邮箱已被使用")
        case "username_already_taken":
            return String(localized: "用户名已被占用")
        case "account_already_exists":
            return String(localized: "账号已存在")
        case "invalid_credentials":
            return String(localized: "邮箱或密码错误")
        case "user_not_found", "auth_missing", "auth_invalid", "auth_invalid_payload":
            return String(localized: "登录状态已失效，请重新登录")
        case "no_fields_to_update":
            return String(localized: "没有可保存的修改")
        case "friend_request_self":
            return String(localized: "不能添加自己为好友")
        case "recipient_not_found":
            return String(localized: "用户不存在")
        case "friend_request_already_exists":
            return String(localized: "好友申请已存在")
        case "friend_request_not_found":
            return String(localized: "好友申请不存在或已处理")
        case "message_body_required":
            return String(localized: "消息内容不能为空")
        case "message_media_required", "message_media_invalid":
            return String(localized: "图片消息无效，请重新选择")
        case "message_dimensions_invalid":
            return String(localized: "图片尺寸信息无效，请重新选择")
        case "not_friends":
            return String(localized: "只能给好友发送消息")
        case "invalid_conversation_id", "conversation_not_found":
            return String(localized: "会话不存在")
        case "pagination_cursor_conflict", "invalid_last_read_message_id", "invalid_request":
            return String(localized: "请求参数无效，请重试")
        case "file_required":
            return String(localized: "请选择要上传的文件")
        case "invalid_image_file":
            return String(localized: "图片文件无效，请重新选择")
        case "internal_error":
            return String(localized: "服务器开小差了，请稍后重试")
        default:
            return nil
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let apiError = error as? APIError,
           case .network(let urlError) = apiError {
            return urlError.code == .cancelled
        }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        return false
    }
}
