part of 'telephony.dart';

const _FOREGROUND_CHANNEL = 'plugins.shounakmulay.com/foreground_sms_channel';
const _BACKGROUND_CHANNEL = 'plugins.shounakmulay.com/background_sms_channel';

const HANDLE_BACKGROUND_MESSAGE = "handleBackgroundMessage";
const BACKGROUND_SERVICE_INITIALIZED = "backgroundServiceInitialized";
const GET_ALL_INBOX_SMS = "getAllInboxSms";
const GET_ALL_SENT_SMS = "getAllSentSms";
const GET_ALL_DRAFT_SMS = "getAllDraftSms";
const GET_ALL_CONVERSATIONS = "getAllConversations";
const SEND_SMS = "sendSms";
const SEND_MULTIPART_SMS = "sendMultipartSms";
const SEND_SMS_INTENT = "sendSmsIntent";
const IS_SMS_CAPABLE = "isSmsCapable";
const GET_CELLULAR_DATA_STATE = "getCellularDataState";
const GET_CALL_STATE = "getCallState";
const GET_DATA_ACTIVITY = "getDataActivity";
const GET_NETWORK_OPERATOR = "getNetworkOperator";
const GET_NETWORK_OPERATOR_NAME = "getNetworkOperatorName";
const GET_DATA_NETWORK_TYPE = "getDataNetworkType";
const GET_PHONE_TYPE = "getPhoneType";
const GET_SIM_OPERATOR = "getSimOperator";
const GET_SIM_OPERATOR_NAME = "getSimOperatorName";
const GET_SIM_STATE = "getSimState";
const IS_NETWORK_ROAMING = "isNetworkRoaming";
const GET_SIGNAL_STRENGTH = "getSignalStrength";
const GET_SERVICE_STATE = "getServiceState";
const REQUEST_SMS_PERMISSION = "requestSmsPermissions";
const REQUEST_PHONE_PERMISSION = "requestPhonePermissions";
const REQUEST_PHONE_AND_SMS_PERMISSION = "requestPhoneAndSmsPermissions";
const OPEN_DIALER = "openDialer";
const DIAL_PHONE_NUMBER = "dialPhoneNumber";

const ON_MESSAGE = "onMessage";
const SMS_SENT = "smsSent";
const SMS_DELIVERED = "smsDelivered";

///
/// Possible parameters that can be fetched during a SMS query operation.
class _SmsProjections {
//  static const String COUNT = "_count";
  static const String ID = "_id";
  static const String ORIGINATING_ADDRESS = "originating_address";
  static const String ADDRESS = "address";
  static const String MESSAGE_BODY = "message_body";
  static const String BODY = "body";
  static const String SERVICE_CENTER_ADDRESS = "service_center";

//  static const String CREATOR = "creator";
  static const String TIMESTAMP = "timestamp";
  static const String DATE = "date";
  static const String DATE_SENT = "date_sent";

//  static const String ERROR_CODE = "error_code";
//  static const String LOCKED = "locked";
//  static const int MESSAGE_TYPE_ALL = 0;
//  static const int MESSAGE_TYPE_DRAFT = 3;
//  static const int MESSAGE_TYPE_FAILED = 5;
//  static const int MESSAGE_TYPE_INBOX = 1;
//  static const int MESSAGE_TYPE_OUTBOX = 4;
//  static const int MESSAGE_TYPE_QUEUED = 6;
//  static const int MESSAGE_TYPE_SENT = 2;
//  static const String PERSON = "person";
//  static const String PROTOCOL = "protocol";
  static const String READ = "read";

//  static const String REPLY_PATH_PRESENT = "reply_path_present";
  static const String SEEN = "seen";

//  static const String SERVICE_CENTER = "service_center";
  static const String STATUS = "status";

//  static const int STATUS_COMPLETE = 0;
//  static const int STATUS_FAILED = 64;
//  static const int STATUS_NONE = -1;
//  static const int STATUS_PENDING = 32;
  static const String SUBJECT = "subject";
  static const String SUBSCRIPTION_ID = "sub_id";
  static const String THREAD_ID = "thread_id";
  static const String TYPE = "type";
}

///
/// Possible parameters that can be fetched during a Conversation query operation.
class _ConversationProjections {
  static const String SNIPPET = "snippet";
  static const String THREAD_ID = "thread_id";
  static const String MSG_COUNT = "msg_count";
}

abstract class _TelephonyColumn {
  const _TelephonyColumn();

  String get _name;
}

/// Represents all the possible parameters for a SMS
class SmsColumn extends _TelephonyColumn {
  final String _columnName;

  const SmsColumn._(this._columnName);

  static const ID = SmsColumn._(_SmsProjections.ID);
  static const ADDRESS = SmsColumn._(_SmsProjections.ADDRESS);
  static const SERVICE_CENTER_ADDRESS =
      SmsColumn._(_SmsProjections.SERVICE_CENTER_ADDRESS);
  static const BODY = SmsColumn._(_SmsProjections.BODY);
  static const DATE = SmsColumn._(_SmsProjections.DATE);
  static const DATE_SENT = SmsColumn._(_SmsProjections.DATE_SENT);
  static const READ = SmsColumn._(_SmsProjections.READ);
  static const SEEN = SmsColumn._(_SmsProjections.SEEN);
  static const STATUS = SmsColumn._(_SmsProjections.STATUS);
  static const SUBJECT = SmsColumn._(_SmsProjections.SUBJECT);
  static const SUBSCRIPTION_ID = SmsColumn._(_SmsProjections.SUBSCRIPTION_ID);
  static const THREAD_ID = SmsColumn._(_SmsProjections.THREAD_ID);
  static const TYPE = SmsColumn._(_SmsProjections.TYPE);

  @override
  String get _name => _columnName;
}

/// Represents all the possible parameters for a Conversation
class ConversationColumn extends _TelephonyColumn {
  final String _columnName;

  const ConversationColumn._(this._columnName);

  static const SNIPPET = ConversationColumn._(_ConversationProjections.SNIPPET);
  static const THREAD_ID =
      ConversationColumn._(_ConversationProjections.THREAD_ID);
  static const MSG_COUNT =
      ConversationColumn._(_ConversationProjections.MSG_COUNT);

  @override
  String get _name => _columnName;
}

const DEFAULT_SMS_COLUMNS = [
  SmsColumn.ID,
  SmsColumn.ADDRESS,
  SmsColumn.BODY,
  SmsColumn.DATE
];

const INCOMING_SMS_COLUMNS = [
  SmsColumn._(_SmsProjections.ORIGINATING_ADDRESS),
  SmsColumn._(_SmsProjections.MESSAGE_BODY),
  SmsColumn._(_SmsProjections.TIMESTAMP),
  SmsColumn._(_SmsProjections.SERVICE_CENTER_ADDRESS),
  SmsColumn.STATUS
];

const DEFAULT_CONVERSATION_COLUMNS = [
  ConversationColumn.SNIPPET,
  ConversationColumn.THREAD_ID,
  ConversationColumn.MSG_COUNT
];

/// Represents types of SMS.
enum SmsType {
  MESSAGE_TYPE_ALL,
  MESSAGE_TYPE_INBOX,
  MESSAGE_TYPE_SENT,
  MESSAGE_TYPE_DRAFT,
  MESSAGE_TYPE_OUTBOX,
  MESSAGE_TYPE_FAILED,
  MESSAGE_TYPE_QUEUED
}

/// Represents states of SMS.
enum SmsStatus { STATUS_COMPLETE, STATUS_FAILED, STATUS_NONE, STATUS_PENDING }

/// Represents data connection state.
enum DataState { DISCONNECTED, CONNECTING, CONNECTED, SUSPENDED, UNKNOWN }

/// Represents state of cellular calls.
enum CallState { IDLE, RINGING, OFFHOOK, UNKNOWN }

/// Represents state of cellular network data activity.
enum DataActivity { NONE, IN, OUT, INOUT, DORMANT, UNKNOWN }

/// Represents types of networks for a device.
enum NetworkType {
  UNKNOWN,
  GPRS,
  EDGE,
  UMTS,
  CDMA,
  EVDO_0,
  EVDO_A,
  TYPE_1xRTT,
  HSDPA,
  HSUPA,
  HSPA,
  IDEN,
  EVDO_B,
  LTE,
  EHRPD,
  HSPAP,
  GSM,
  TD_SCDMA,
  IWLAN,
  LTE_CA,
  NR,
}

/// Represents types of cellular technology supported by a device.
enum PhoneType { NONE, GSM, CDMA, SIP, UNKNOWN }

/// Represents state of SIM.
enum SimState {
  UNKNOWN,
  ABSENT,
  PIN_REQUIRED,
  PUK_REQUIRED,
  NETWORK_LOCKED,
  READY,
  NOT_READY,
  PERM_DISABLED,
  CARD_IO_ERROR,
  CARD_RESTRICTED,
  LOADED,
  PRESENT
}

/// Represents state of cellular service.
enum ServiceState {
  IN_SERVICE,
  OUT_OF_SERVICE,
  EMERGENCY_ONLY,
  POWER_OFF,
  UNKNOWN
}

/// Represents the quality of cellular signal.
enum SignalStrength { NONE_OR_UNKNOWN, POOR, MODERATE, GOOD, GREAT }

/// Represents sort order for [OrderBy].
enum Sort { ASC, DESC }

extension Value on Sort {
  String get value {
    switch (this) {
      case Sort.ASC:
        return "ASC";
      case Sort.DESC:
      default:
        return "DESC";
    }
  }
}

/// Represents the status of a sms message sent from the device.
enum SendStatus { SENT, DELIVERED }
