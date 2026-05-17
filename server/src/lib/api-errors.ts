import type { FastifyReply } from 'fastify'

export type ApiErrorDefinition = {
  statusCode: number
  code: string
  message: string
}

export type ApiErrorResponse = {
  error: {
    code: string
    message: string
  }
}

export const ApiErrors = {
  invalidRequest: {
    statusCode: 400,
    code: 'invalid_request',
    message: 'Invalid request',
  },
  internalError: {
    statusCode: 500,
    code: 'internal_error',
    message: 'Internal server error',
  },
  authMissing: {
    statusCode: 401,
    code: 'auth_missing',
    message: 'Missing or invalid Authorization header',
  },
  authInvalid: {
    statusCode: 401,
    code: 'auth_invalid',
    message: 'Invalid or expired token',
  },
  authInvalidPayload: {
    statusCode: 401,
    code: 'auth_invalid_payload',
    message: 'Invalid token payload',
  },
  invalidInviteCode: {
    statusCode: 403,
    code: 'invalid_invite_code',
    message: 'Invalid invite code',
  },
  usernameTooShort: {
    statusCode: 400,
    code: 'username_too_short',
    message: 'Username must be at least 3 characters',
  },
  invalidEmail: {
    statusCode: 400,
    code: 'invalid_email',
    message: 'Invalid email address',
  },
  emailAlreadyInUse: {
    statusCode: 409,
    code: 'email_already_in_use',
    message: 'Email already in use',
  },
  usernameAlreadyTaken: {
    statusCode: 409,
    code: 'username_already_taken',
    message: 'Username already taken',
  },
  accountAlreadyExists: {
    statusCode: 409,
    code: 'account_already_exists',
    message: 'Account already exists',
  },
  invalidCredentials: {
    statusCode: 401,
    code: 'invalid_credentials',
    message: 'Invalid email or password',
  },
  userNotFound: {
    statusCode: 401,
    code: 'user_not_found',
    message: 'User no longer exists',
  },
  noFieldsToUpdate: {
    statusCode: 400,
    code: 'no_fields_to_update',
    message: 'No fields to update',
  },
  friendRequestSelf: {
    statusCode: 400,
    code: 'friend_request_self',
    message: 'Cannot send friend request to yourself',
  },
  recipientNotFound: {
    statusCode: 404,
    code: 'recipient_not_found',
    message: 'Recipient not found',
  },
  friendRequestAlreadyExists: {
    statusCode: 409,
    code: 'friend_request_already_exists',
    message: 'Friend request already exists',
  },
  friendRequestNotFound: {
    statusCode: 404,
    code: 'friend_request_not_found',
    message: 'Friend request not found',
  },
  messageBodyRequired: {
    statusCode: 400,
    code: 'message_body_required',
    message: 'Body is required for text messages',
  },
  messageMediaRequired: {
    statusCode: 400,
    code: 'message_media_required',
    message: 'Media URL is required for image messages',
  },
  messageMediaInvalid: {
    statusCode: 400,
    code: 'message_media_invalid',
    message: 'Invalid media URL',
  },
  messageDimensionsInvalid: {
    statusCode: 400,
    code: 'message_dimensions_invalid',
    message: 'Media width and height must be provided together',
  },
  notFriends: {
    statusCode: 403,
    code: 'not_friends',
    message: 'You can only send messages to friends',
  },
  invalidConversationId: {
    statusCode: 400,
    code: 'invalid_conversation_id',
    message: 'Invalid conversation id',
  },
  paginationCursorConflict: {
    statusCode: 400,
    code: 'pagination_cursor_conflict',
    message: 'Cannot use both before and after',
  },
  conversationNotFound: {
    statusCode: 404,
    code: 'conversation_not_found',
    message: 'Conversation not found',
  },
  invalidLastReadMessageId: {
    statusCode: 400,
    code: 'invalid_last_read_message_id',
    message: 'Invalid last_read_message_id',
  },
  fileRequired: {
    statusCode: 400,
    code: 'file_required',
    message: 'No file provided',
  },
  invalidImageFile: {
    statusCode: 400,
    code: 'invalid_image_file',
    message: 'Invalid image file',
  },
} as const satisfies Record<string, ApiErrorDefinition>

export function sendApiError(reply: FastifyReply, error: ApiErrorDefinition) {
  return reply.status(error.statusCode).send({
    error: {
      code: error.code,
      message: error.message,
    },
  } satisfies ApiErrorResponse)
}
