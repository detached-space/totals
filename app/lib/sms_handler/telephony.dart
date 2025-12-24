import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:platform/platform.dart';

part 'constants.dart';

part 'filter.dart';

typedef MessageHandler(SmsMessage message);
typedef SmsSendStatusListener(SendStatus status);

void _flutterSmsSetupBackgroundChannel(
    {MethodChannel backgroundChannel =
        const MethodChannel(_BACKGROUND_CHANNEL)}) async {
  WidgetsFlutterBinding.ensureInitialized();

  backgroundChannel.setMethodCallHandler((call) async {
    if (call.method == HANDLE_BACKGROUND_MESSAGE) {
      final CallbackHandle handle =
          CallbackHandle.fromRawHandle(call.arguments['handle']);
      final Function handlerFunction =
          PluginUtilities.getCallbackFromHandle(handle)!;
      try {
        await handlerFunction(SmsMessage.fromMap(
            call.arguments['message'], INCOMING_SMS_COLUMNS));
      } catch (e) {
        print('Unable to handle incoming background message.');
        print(e);
      }
      return Future<void>.value();
    }
  });

  backgroundChannel.invokeMethod<void>(BACKGROUND_SERVICE_INITIALIZED);
}

///
/// A Flutter plugin to use telephony features such as
/// - Send SMS Messages
/// - Query SMS Messages
/// - Listen for incoming SMS
/// - Retrieve various network parameters
///
///
/// This plugin tries to replicate some of the functionality provided by Android's Telephony class.
///
///
class Telephony {
  final MethodChannel _foregroundChannel;
  final Platform _platform;

  late MessageHandler _onNewMessage;
  late MessageHandler _onBackgroundMessages;
  late SmsSendStatusListener _statusListener;

  ///
  /// Gets a singleton instance of the [Telephony] class.
  ///
  static Telephony get instance => _instance;

  ///
  /// Gets a singleton instance of the [Telephony] class to be used in background execution context.
  ///
  static Telephony get backgroundInstance => _backgroundInstance;

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  Telephony.private(MethodChannel methodChannel, Platform platform)
      : _foregroundChannel = methodChannel,
        _platform = platform;

  Telephony._newInstance(MethodChannel methodChannel, LocalPlatform platform)
      : _foregroundChannel = methodChannel,
        _platform = platform {
    _foregroundChannel.setMethodCallHandler(handler);
  }

  static final Telephony _instance = Telephony._newInstance(
      const MethodChannel(_FOREGROUND_CHANNEL), const LocalPlatform());
  static final Telephony _backgroundInstance = Telephony._newInstance(
      const MethodChannel(_FOREGROUND_CHANNEL), const LocalPlatform());

  ///
  /// Listens to incoming SMS.
  ///
  /// ### Requires RECEIVE_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [onNewMessage] : Called on every new message received when app is in foreground.
  /// - [onBackgroundMessage] (optional) : Called on every new message received when app is in background.
  /// - [listenInBackground] (optional) : Defaults to true. Set to false to only listen to messages in foreground. [listenInBackground] is
  /// ignored if [onBackgroundMessage] is not set.
  ///
  ///
  void listenIncomingSms(
      {required MessageHandler onNewMessage,
      MessageHandler? onBackgroundMessage,
      bool listenInBackground = true}) {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    assert(
        listenInBackground
            ? onBackgroundMessage != null
            : onBackgroundMessage == null,
        listenInBackground
            ? "`onBackgroundMessage` cannot be null when `listenInBackground` is true. Set `listenInBackground` to false if you don't need background processing."
            : "You have set `listenInBackground` to false. `onBackgroundMessage` can only be set when `listenInBackground` is true");

    _onNewMessage = onNewMessage;

    if (listenInBackground && onBackgroundMessage != null) {
      _onBackgroundMessages = onBackgroundMessage;
      final CallbackHandle backgroundSetupHandle =
          PluginUtilities.getCallbackHandle(_flutterSmsSetupBackgroundChannel)!;
      final CallbackHandle? backgroundMessageHandle =
          PluginUtilities.getCallbackHandle(_onBackgroundMessages);

      if (backgroundMessageHandle == null) {
        throw ArgumentError(
          '''Failed to setup background message handler! `onBackgroundMessage`
          should be a TOP-LEVEL OR STATIC FUNCTION and should NOT be tied to a
          class or an anonymous function.''',
        );
      }

      _foregroundChannel.invokeMethod<bool>(
        'startBackgroundService',
        <String, dynamic>{
          'setupHandle': backgroundSetupHandle.toRawHandle(),
          'backgroundHandle': backgroundMessageHandle.toRawHandle()
        },
      );
    } else {
      _foregroundChannel.invokeMethod('disableBackgroundService');
    }
  }

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case ON_MESSAGE:
        final message = call.arguments["message"];
        return _onNewMessage(SmsMessage.fromMap(message, INCOMING_SMS_COLUMNS));
      case SMS_SENT:
        return _statusListener(SendStatus.SENT);
      case SMS_DELIVERED:
        return _statusListener(SendStatus.DELIVERED);
    }
  }

  ///
  /// Query SMS Inbox.
  ///
  /// ### Requires READ_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [columns] (optional) : List of [SmsColumn] to be returned by this query. Defaults to [ SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE ]
  /// - [filter] (optional) : [SmsFilter] to filter the results of this query. Works like SQL WHERE clause.
  /// - [sortOrder] (optional): List of [OrderBy]. Orders the results of this query by the provided columns and order.
  ///
  /// Returns:
  ///
  /// [Future<List<SmsMessage>>]
  Future<List<SmsMessage>> getInboxSms(
      {List<SmsColumn> columns = DEFAULT_SMS_COLUMNS,
      SmsFilter? filter,
      List<OrderBy>? sortOrder}) async {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    final args = _getArguments(columns, filter, sortOrder);

    final messages =
        await _foregroundChannel.invokeMethod<List?>(GET_ALL_INBOX_SMS, args);

    return messages
            ?.map((message) => SmsMessage.fromMap(message, columns))
            .toList(growable: false) ??
        List.empty();
  }

  ///
  /// Query SMS Outbox / Sent messages.
  ///
  /// ### Requires READ_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [columns] (optional) : List of [SmsColumn] to be returned by this query. Defaults to [ SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE ]
  /// - [filter] (optional) : [SmsFilter] to filter the results of this query. Works like SQL WHERE clause.
  /// - [sortOrder] (optional): List of [OrderBy]. Orders the results of this query by the provided columns and order.
  ///
  /// Returns:
  ///
  /// [Future<List<SmsMessage>>]
  Future<List<SmsMessage>> getSentSms(
      {List<SmsColumn> columns = DEFAULT_SMS_COLUMNS,
      SmsFilter? filter,
      List<OrderBy>? sortOrder}) async {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    final args = _getArguments(columns, filter, sortOrder);

    final messages =
        await _foregroundChannel.invokeMethod<List?>(GET_ALL_SENT_SMS, args);

    return messages
            ?.map((message) => SmsMessage.fromMap(message, columns))
            .toList(growable: false) ??
        List.empty();
  }

  ///
  /// Query SMS Drafts.
  ///
  /// ### Requires READ_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [columns] (optional) : List of [SmsColumn] to be returned by this query. Defaults to [ SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE ]
  /// - [filter] (optional) : [SmsFilter] to filter the results of this query. Works like SQL WHERE clause.
  /// - [sortOrder] (optional): List of [OrderBy]. Orders the results of this query by the provided columns and order.
  ///
  /// Returns:
  ///
  /// [Future<List<SmsMessage>>]
  Future<List<SmsMessage>> getDraftSms(
      {List<SmsColumn> columns = DEFAULT_SMS_COLUMNS,
      SmsFilter? filter,
      List<OrderBy>? sortOrder}) async {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    final args = _getArguments(columns, filter, sortOrder);

    final messages =
        await _foregroundChannel.invokeMethod<List?>(GET_ALL_DRAFT_SMS, args);

    return messages
            ?.map((message) => SmsMessage.fromMap(message, columns))
            .toList(growable: false) ??
        List.empty();
  }

  ///
  /// Query SMS Inbox.
  ///
  /// ### Requires READ_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [filter] (optional) : [ConversationFilter] to filter the results of this query. Works like SQL WHERE clause.
  /// - [sortOrder] (optional): List of [OrderBy]. Orders the results of this query by the provided columns and order.
  ///
  /// Returns:
  ///
  /// [Future<List<SmsConversation>>]
  Future<List<SmsConversation>> getConversations(
      {ConversationFilter? filter, List<OrderBy>? sortOrder}) async {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    final args = _getArguments(DEFAULT_CONVERSATION_COLUMNS, filter, sortOrder);

    final conversations = await _foregroundChannel.invokeMethod<List?>(
        GET_ALL_CONVERSATIONS, args);

    return conversations
            ?.map((conversation) => SmsConversation.fromMap(conversation))
            .toList(growable: false) ??
        List.empty();
  }

  Map<String, dynamic> _getArguments(List<_TelephonyColumn> columns,
      Filter? filter, List<OrderBy>? sortOrder) {
    final Map<String, dynamic> args = {};

    args["projection"] = columns.map((c) => c._name).toList();

    if (filter != null) {
      args["selection"] = filter.selection;
      args["selection_args"] = filter.selectionArgs;
    }

    if (sortOrder != null && sortOrder.isNotEmpty) {
      args["sort_order"] = sortOrder.map((o) => o._value).join(",");
    }

    return args;
  }

  ///
  /// Send an SMS directly from your application. Uses Android's SmsManager to send SMS.
  ///
  /// ### Requires SEND_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [to] : Address to send the SMS to.
  /// - [message] : Message to be sent. If message body is longer than standard SMS length limits set appropriate
  /// value for [isMultipart]
  /// - [statusListener] (optional) : Listen to the status of the sent SMS. Values can be one of [SmsStatus]
  /// - [isMultipart] (optional) : If message body is longer than standard SMS limit of 160 characters, set this flag to
  /// send the SMS in multiple parts.
  Future<void> sendSms({
    required String to,
    required String message,
    SmsSendStatusListener? statusListener,
    bool isMultipart = false,
  }) async {
    assert(_platform.isAndroid == true, "Can only be called on Android.");
    bool listenStatus = false;
    if (statusListener != null) {
      _statusListener = statusListener;
      listenStatus = true;
    }
    final Map<String, dynamic> args = {
      "address": to,
      "message_body": message,
      "listen_status": listenStatus
    };
    final String method = isMultipart ? SEND_MULTIPART_SMS : SEND_SMS;
    await _foregroundChannel.invokeMethod(method, args);
  }

  ///
  /// Open Android's default SMS application with the provided message and address.
  ///
  /// ### Requires SEND_SMS permission.
  ///
  /// Parameters:
  ///
  /// - [to] : Address to send the SMS to.
  /// - [message] : Message to be sent.
  ///
  Future<void> sendSmsByDefaultApp({
    required String to,
    required String message,
  }) async {
    final Map<String, dynamic> args = {
      "address": to,
      "message_body": message,
    };
    await _foregroundChannel.invokeMethod(SEND_SMS_INTENT, args);
  }

  ///
  /// Checks if the device has necessary features to send and receive SMS.
  ///
  /// Uses TelephonyManager class on Android.
  ///
  Future<bool?> get isSmsCapable =>
      _foregroundChannel.invokeMethod<bool>(IS_SMS_CAPABLE);

  ///
  /// Returns a constant indicating the current data connection state (cellular).
  ///
  /// Returns:
  ///
  /// [Future<DataState>]
  Future<DataState> get cellularDataState async {
    final int? dataState =
        await _foregroundChannel.invokeMethod<int>(GET_CELLULAR_DATA_STATE);
    if (dataState == null || dataState == -1) {
      return DataState.UNKNOWN;
    } else {
      return DataState.values[dataState];
    }
  }

  ///
  /// Returns a constant that represents the current state of all phone calls.
  ///
  /// Returns:
  ///
  /// [Future<CallState>]
  Future<CallState> get callState async {
    final int? state =
        await _foregroundChannel.invokeMethod<int>(GET_CALL_STATE);
    if (state != null) {
      return CallState.values[state];
    } else {
      return CallState.UNKNOWN;
    }
  }

  ///
  /// Returns a constant that represents the current state of all phone calls.
  ///
  /// Returns:
  ///
  /// [Future<CallState>]
  Future<DataActivity> get dataActivity async {
    final int? activity =
        await _foregroundChannel.invokeMethod<int>(GET_DATA_ACTIVITY);
    if (activity != null) {
      return DataActivity.values[activity];
    } else {
      return DataActivity.UNKNOWN;
    }
  }

  ///
  /// Returns the numeric name (MCC+MNC) of current registered operator.
  ///
  /// Availability: Only when user is registered to a network.
  ///
  /// Result may be unreliable on CDMA networks (use phoneType to determine if on a CDMA network).
  ///
  Future<String?> get networkOperator =>
      _foregroundChannel.invokeMethod<String>(GET_NETWORK_OPERATOR);

  ///
  /// Returns the alphabetic name of current registered operator.
  ///
  /// Availability: Only when user is registered to a network.
  ///
  /// Result may be unreliable on CDMA networks (use phoneType to determine if on a CDMA network).
  ///
  Future<String?> get networkOperatorName =>
      _foregroundChannel.invokeMethod<String>(GET_NETWORK_OPERATOR_NAME);

  ///
  /// Returns a constant indicating the radio technology (network type) currently in use on the device for data transmission.
  ///
  /// ### Requires READ_PHONE_STATE permission.
  ///
  Future<NetworkType> get dataNetworkType async {
    final int? type =
        await _foregroundChannel.invokeMethod<int>(GET_DATA_NETWORK_TYPE);
    if (type != null) {
      return NetworkType.values[type];
    } else {
      return NetworkType.UNKNOWN;
    }
  }

  ///
  /// Returns a constant indicating the device phone type. This indicates the type of radio used to transmit voice calls.
  ///
  Future<PhoneType> get phoneType async {
    final int? type =
        await _foregroundChannel.invokeMethod<int>(GET_PHONE_TYPE);
    if (type != null) {
      return PhoneType.values[type];
    } else {
      return PhoneType.UNKNOWN;
    }
  }

  ///
  /// Returns the MCC+MNC (mobile country code + mobile network code) of the provider of the SIM. 5 or 6 decimal digits.
  ///
  /// Availability: SimState must be SIM\_STATE\_READY
  Future<String?> get simOperator =>
      _foregroundChannel.invokeMethod<String>(GET_SIM_OPERATOR);

  ///
  /// Returns the Service Provider Name (SPN).
  ///
  /// Availability: SimState must be SIM_STATE_READY
  Future<String?> get simOperatorName =>
      _foregroundChannel.invokeMethod<String>(GET_SIM_OPERATOR_NAME);

  ///
  /// Returns a constant indicating the state of the default SIM card.
  ///
  /// Returns:
  ///
  /// [Future<SimState>]
  Future<SimState> get simState async {
    final int? state =
        await _foregroundChannel.invokeMethod<int>(GET_SIM_STATE);
    if (state != null) {
      return SimState.values[state];
    } else {
      return SimState.UNKNOWN;
    }
  }

  ///
  /// Returns true if the device is considered roaming on the current network, for GSM purposes.
  ///
  /// Availability: Only when user registered to a network.
  Future<bool?> get isNetworkRoaming =>
      _foregroundChannel.invokeMethod<bool>(IS_NETWORK_ROAMING);

  ///
  /// Returns a List of SignalStrength or an empty List if there are no valid measurements.
  ///
  /// ### Requires Android build version 29 --> Android Q
  ///
  /// Returns:
  ///
  /// [Future<List<SignalStrength>>]
  Future<List<SignalStrength>> get signalStrengths async {
    final List<dynamic>? strengths =
        await _foregroundChannel.invokeMethod(GET_SIGNAL_STRENGTH);
    return (strengths ?? [])
        .map((s) => SignalStrength.values[s])
        .toList(growable: false);
  }

  ///
  /// Returns current voice service state.
  ///
  /// ### Requires Android build version 26 --> Android O
  /// ### Requires permissions ACCESS_COARSE_LOCATION and READ_PHONE_STATE
  ///
  /// Returns:
  ///
  /// [Future<ServiceState>]
  Future<ServiceState> get serviceState async {
    final int? state =
        await _foregroundChannel.invokeMethod<int>(GET_SERVICE_STATE);
    if (state != null) {
      return ServiceState.values[state];
    } else {
      return ServiceState.UNKNOWN;
    }
  }

  ///
  /// Request the user for all the sms permissions listed in the app's AndroidManifest.xml
  ///
  Future<bool?> get requestSmsPermissions =>
      _foregroundChannel.invokeMethod<bool>(REQUEST_SMS_PERMISSION);

  ///
  /// Request the user for all the phone permissions listed in the app's AndroidManifest.xml
  ///
  Future<bool?> get requestPhonePermissions =>
      _foregroundChannel.invokeMethod<bool>(REQUEST_PHONE_PERMISSION);

  ///
  /// Request the user for all the phone and sms permissions listed in the app's AndroidManifest.xml
  ///
  Future<bool?> get requestPhoneAndSmsPermissions =>
      _foregroundChannel.invokeMethod<bool>(REQUEST_PHONE_AND_SMS_PERMISSION);

  ///
  /// Opens the default dialer with the given phone number.
  ///
  Future<void> openDialer(String phoneNumber) async {
    assert(phoneNumber.isNotEmpty, "phoneNumber cannot be empty");
    final Map<String, dynamic> args = {"phoneNumber": phoneNumber};
    await _foregroundChannel.invokeMethod(OPEN_DIALER, args);
  }

  ///
  /// Starts a phone all with the given phone number.
  ///
  /// ### Requires permission CALL_PHONE
  ///
  Future<void> dialPhoneNumber(String phoneNumber) async {
    assert(phoneNumber.isNotEmpty, "phoneNumber cannot be null or empty");
    final Map<String, dynamic> args = {"phoneNumber": phoneNumber};
    await _foregroundChannel.invokeMethod(DIAL_PHONE_NUMBER, args);
  }
}

///
/// Represents a message returned by one of the query functions such as
/// [getInboxSms], [getSentSms], [getDraftSms]
class SmsMessage {
  int? id;
  String? address;
  String? body;
  int? date;
  int? dateSent;
  bool? read;
  bool? seen;
  String? subject;
  int? subscriptionId;
  int? threadId;
  SmsType? type;
  SmsStatus? status;
  String? serviceCenterAddress;

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  SmsMessage.fromMap(Map rawMessage, List<SmsColumn> columns) {
    final message = Map.castFrom<dynamic, dynamic, String, dynamic>(rawMessage);
    for (var column in columns) {
      // debugPrint('Column is ${column._columnName}');
      final value = message[column._columnName];
      switch (column._columnName) {
        case _SmsProjections.ID:
          this.id = int.tryParse(value);
          break;
        case _SmsProjections.ORIGINATING_ADDRESS:
        case _SmsProjections.ADDRESS:
          this.address = value;
          break;
        case _SmsProjections.MESSAGE_BODY:
        case _SmsProjections.BODY:
          this.body = value;
          break;
        case _SmsProjections.DATE:
        case _SmsProjections.TIMESTAMP:
          this.date = int.tryParse(value);
          break;
        case _SmsProjections.DATE_SENT:
          this.dateSent = int.tryParse(value);
          break;
        case _SmsProjections.READ:
          this.read = int.tryParse(value) == 0 ? false : true;
          break;
        case _SmsProjections.SEEN:
          this.seen = int.tryParse(value) == 0 ? false : true;
          break;
        case _SmsProjections.STATUS:
          switch (int.tryParse(value)) {
            case 0:
              this.status = SmsStatus.STATUS_COMPLETE;
              break;
            case 32:
              this.status = SmsStatus.STATUS_PENDING;
              break;
            case 64:
              this.status = SmsStatus.STATUS_FAILED;
              break;
            case -1:
            default:
              this.status = SmsStatus.STATUS_NONE;
              break;
          }
          break;
        case _SmsProjections.SUBJECT:
          this.subject = value;
          break;
        case _SmsProjections.SUBSCRIPTION_ID:
          this.subscriptionId = int.tryParse(value);
          break;
        case _SmsProjections.THREAD_ID:
          this.threadId = int.tryParse(value);
          break;
        case _SmsProjections.TYPE:
          var smsTypeIndex = int.tryParse(value);
          this.type =
              smsTypeIndex != null ? SmsType.values[smsTypeIndex] : null;
          break;
        case _SmsProjections.SERVICE_CENTER_ADDRESS:
          this.serviceCenterAddress = value;
          break;
      }
    }
  }

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  bool equals(SmsMessage other) {
    return this.id == other.id &&
        this.address == other.address &&
        this.body == other.body &&
        this.date == other.date &&
        this.dateSent == other.dateSent &&
        this.read == other.read &&
        this.seen == other.seen &&
        this.subject == other.subject &&
        this.subscriptionId == other.subscriptionId &&
        this.threadId == other.threadId &&
        this.type == other.type &&
        this.status == other.status;
  }
}

///
/// Represents a conversation returned by the query conversation functions
/// [getConversations]
class SmsConversation {
  String? snippet;
  int? threadId;
  int? messageCount;

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  SmsConversation.fromMap(Map rawConversation) {
    final conversation =
        Map.castFrom<dynamic, dynamic, String, dynamic>(rawConversation);
    for (var column in DEFAULT_CONVERSATION_COLUMNS) {
      final String? value = conversation[column._columnName];
      switch (column._columnName) {
        case _ConversationProjections.SNIPPET:
          this.snippet = value;
          break;
        case _ConversationProjections.THREAD_ID:
          this.threadId = int.tryParse(value!);
          break;
        case _ConversationProjections.MSG_COUNT:
          this.messageCount = int.tryParse(value!);
          break;
      }
    }
  }

  /// ## Do not call this method. This method is visible only for testing.
  @visibleForTesting
  bool equals(SmsConversation other) {
    return this.threadId == other.threadId &&
        this.snippet == other.snippet &&
        this.messageCount == other.messageCount;
  }
}
