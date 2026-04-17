import "package:another_telephony/telephony.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:platform/platform.dart";

import 'mocks/messages.dart';

main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel methodChannel;
  late Telephony telephony;
  final List<MethodCall> log = <MethodCall>[];
  SmsSendStatusListener listener;

  setUp(() {
    methodChannel = MethodChannel("testChannel");
    telephony = Telephony.private(
        methodChannel, FakePlatform(operatingSystem: "android"));
    // methodChannel.setMockMethodCallHandler((call) {
    //   log.add(call);
    //   return telephony.handler(call);
    // });
  });

  tearDown(() {
    // methodChannel.setMockMethodCallHandler(null);
    log.clear();
  });

  group("should listen to", () {
    test("sms sent status", () async {
      listener = (status) {
        expect(status, SendStatus.SENT);
      };

      final args = {
        "address": "0000000000",
        "message_body": "Test message",
        "listen_status": true
      };

      telephony.sendSms(
          to: "0000000000", message: "Test message", statusListener: listener);

      expect(log, [isMethodCall(SEND_SMS, arguments: args)]);

      // called by native side
      methodChannel.invokeMethod(SMS_SENT);

      expect(log.length, 2);
      expect(log.last, isMethodCall(SMS_SENT, arguments: null));
    });

    test("incoming sms", () async {
      telephony.listenIncomingSms(
          onNewMessage: (message) {
            expect(message.body, mockIncomingMessage["message_body"]);
            expect(message.address, mockIncomingMessage["originating_address"]);
            expect(message.status, SmsStatus.STATUS_COMPLETE);
          },
          listenInBackground: false);

      methodChannel.invokeMethod(ON_MESSAGE, {"message": mockIncomingMessage});
    });
  });
}
