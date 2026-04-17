import 'dart:collection';

final mockMessages = [
  LinkedHashMap.from({
    "_id": "1",
    "address": "123456",
    "body": "message body",
    "date": "1595056125597",
    "thread_id": "3"
  }),
  LinkedHashMap.from({
    "_id": "12",
    "address": "0000000000",
    "body": "text message",
    "date": "1595056125663",
    "thread_id": "6"
  })
];

final mockMessageWithSmsType = LinkedHashMap.from({
  "_id": "1",
  "address": "123456",
  "body": "message body",
  "date": "1595056125597",
  "thread_id": "3",
  "type": "1"
});

final mockMessageWithInvalidSmsType = LinkedHashMap.from({
  "_id": "1",
  "address": "123456",
  "body": "message body",
  "date": "1595056125597",
  "thread_id": "3",
  "type": "type"
});

final mockConversations = [
  LinkedHashMap.from(
      {"snippet": "message snippet", "thread_id": "2", "msg_count": "32"}),
  LinkedHashMap.from(
      {"snippet": "snippet", "thread_id": "5", "msg_count": "20"})
];

const mockIncomingMessage = {
  "originating_address": "123456789",
  "message_body": "incoming sms",
  "timestamp": "123422135",
  "status": "0"
};
