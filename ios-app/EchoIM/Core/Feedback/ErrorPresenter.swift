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
            guard let knownCode = serverError.knownCode else {
                return serverError.message
            }

            return message(forServerCode: knownCode)
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

    static func message(forServerCode code: KnownServerErrorCode) -> String {
        switch code {
        case .invalidInviteCode:
            return String(localized: "邀请码无效")
        case .usernameTooShort:
            return String(localized: "用户名至少需要 3 个字符")
        case .invalidEmail:
            return String(localized: "邮箱格式不正确")
        case .emailAlreadyInUse:
            return String(localized: "邮箱已被使用")
        case .usernameAlreadyTaken:
            return String(localized: "用户名已被占用")
        case .accountAlreadyExists:
            return String(localized: "账号已存在")
        case .invalidCredentials:
            return String(localized: "邮箱或密码错误")
        case .userNotFound, .authMissing, .authInvalid, .authInvalidPayload:
            return String(localized: "登录状态已失效，请重新登录")
        case .noFieldsToUpdate:
            return String(localized: "没有可保存的修改")
        case .friendRequestSelf:
            return String(localized: "不能添加自己为好友")
        case .recipientNotFound:
            return String(localized: "用户不存在")
        case .friendRequestAlreadyExists:
            return String(localized: "好友申请已存在")
        case .friendRequestNotFound:
            return String(localized: "好友申请不存在或已处理")
        case .messageBodyRequired:
            return String(localized: "消息内容不能为空")
        case .messageMediaRequired, .messageMediaInvalid:
            return String(localized: "图片消息无效，请重新选择")
        case .messageDimensionsInvalid:
            return String(localized: "图片尺寸信息无效，请重新选择")
        case .notFriends:
            return String(localized: "只能给好友发送消息")
        case .invalidConversationId, .conversationNotFound:
            return String(localized: "会话不存在")
        case .paginationCursorConflict, .invalidLastReadMessageId, .invalidRequest:
            return String(localized: "请求参数无效，请重试")
        case .fileRequired:
            return String(localized: "请选择要上传的文件")
        case .invalidImageFile:
            return String(localized: "图片文件无效，请重新选择")
        case .internalError:
            return String(localized: "服务器开小差了，请稍后重试")
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
