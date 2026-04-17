

# Telephony

## We create this fork because the [original package](https://github.com/shounakmulay/Telephony) is not maintained anymore. We will try to keep this package up to date with the latest Flutter version.

|:exclamation: This plugin currently only works on Android Platform|
|------------------------------------------------------------------|


A Flutter plugin to use telephony features such as
- Send SMS Messages
- Query SMS Messages
- Listen for incoming SMS
- Retrieve various network parameters
- Start phone calls

This plugin tries to replicate some of the functionality provided by Android's [Telephony](https://developer.android.com/reference/android/provider/Telephony) class.

Check the [Features section](#Features) to see the list of implemented and missing features.

## Get Started
### :bulb: View the **[entire documentation here](https://telephony.shounakmulay.dev/)**.

## Usage
To use this plugin add `telephony` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages).

##### Versions [0.0.9](https://pub.dev/packages/telephony/versions/0.0.9) and lower are not null safe.
##### Versions [0.1.0](https://pub.dev/packages/telephony/versions/0.1.0) and above opt into null safety.


### Setup
Import the `telephony` package
```dart
import 'package:telephony/telephony.dart';
```


Retrieve the singleton instance of `telephony` by calling
```dart
final Telephony telephony = Telephony.instance;
```

### [Permissions](https://shounakmulay.gitbook.io/telephony/permissions)
**Although this plugin will check and ask for permissions at runtime, it is advisable to _manually ask for permissions_ before calling any other functions.**

The plugin will only request those permission that are listed in the `AndroidManifest.xml`.

Manually request permission using
```dart
bool permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
```
You can also request SMS or Phone permissions separately using `requestSmsPermissions` or `requestPhonePermissions` respectively.

### [Send SMS](https://shounakmulay.gitbook.io/telephony/sending-an-sms)
:exclamation: Requires `SEND_SMS` permission.
Add the following permission in your `AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.SEND_SMS"/>
```

SMS can either be sent directly or via the default SMS app.

#### Send SMS directly from your app:
```dart
telephony.sendSms(
	to: "1234567890",
	message: "May the force be with you!"
	);
```
If you want to listen to the status of the message being sent, provide `SmsSendStatusListener` to the `sendSms` function.
```dart
final SmsSendStatusListener listener = (SendStatus status) {
	// Handle the status
	};
	
telephony.sendSms(
	to: "1234567890",
	message: "May the force be with you!",
	statusListener: listener
	);
```
If the body of the message is longer than the standard SMS length limit of `160 characters`, you can send a multipart SMS by setting the `isMultipart` flag.

#### Send SMS via the default SMS app:
```dart
telephony.sendSmsByDefaultApp(to: "1234567890", message: "May the force be with you!");
```

### [Query SMS](https://shounakmulay.gitbook.io/telephony/query-sms)
:exclamation: Requires `READ_SMS` permission.
Add the following permission in your `AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.READ_SMS"/>
```

Use one of `getInboxSms()`, `getSentSms()` or `getDraftSms()` functions to query the messages on device.

You can provide the list of `SmsColumns` that need to be returned by the query.

If not explicitly specified, defaults to `[
  SmsColumn.ID,
  SmsColumn.ADDRESS,
  SmsColumn.BODY,
  SmsColumn.DATE
]`

Provide a `SmsFilter` to filter the results of the query. Functions like a `SQL WHERE` clause.

Provide a list of `OrderBy` objects to sort the results. The level of importance is determined by the position of `OrderBy` in the list.

All paramaters are optional.
```dart
List<SmsMessage> messages = await telephony.getInboxSms(
		columns: [SmsColumn.ADDRESS, SmsColumn.BODY],
		filter: SmsFilter.where(SmsColumn.ADDRESS)
				 .equals("1234567890")
				 .and(SmsColumn.BODY)
				 .like("starwars"),
		sortOrder: [OrderBy(SmsColumn.ADDRESS, sort: Sort.ASC),
			    OrderBy(SmsColumn.BODY)]
		);
```

### [Query Conversations](https://shounakmulay.gitbook.io/telephony/query-conversations)
:exclamation: Requires `READ_SMS` permission.
Add the following permission in your `AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.READ_SMS"/>
```

Works similar to [SMS queries](#query-sms). 

All columns are returned with every query. They are `[
  ConversationColumn.SNIPPET,
  ConversationColumn.THREAD_ID,
  ConversationColumn.MSG_COUNT
]`

Uses `ConversationFilter` instead of `SmsFilter`.

```dart
List<SmsConversation> messages = await telephony.getConversations(
		filter: ConversationFilter.where(ConversationColumn.MSG_COUNT)
					  .equals("4")
					  .and(ConversationColumn.THREAD_ID)
					  .greaterThan("12"),
		sortOrder: [OrderBy(ConversationColumn.THREAD_ID, sort: Sort.ASC)]
		);
```

### [Listen to incoming SMS](https://shounakmulay.gitbook.io/telephony/listen-incoming-sms)
:exclamation: Requires `RECEIVE_SMS` permission.

1. To listen to incoming SMS add the `RECEIVE_SMS` permission to your `AndroidManifest.xml` file and register the `BroadcastReceiver`.


```xml
<manifest>
	<uses-permission android:name="android.permission.RECEIVE_SMS"/>

	<application>
		...
		...

		<receiver android:name="com.shounakmulay.telephony.sms.IncomingSmsReceiver"
		    android:permission="android.permission.BROADCAST_SMS" android:exported="true">
		    <intent-filter>
			<action android:name="android.provider.Telephony.SMS_RECEIVED"/>
		    </intent-filter>
		</receiver>

	</application>
</manifest>
```

2. Create a **top-level static function** to handle incoming messages when app is not is foreground.

	:warning: Avoid heavy computations in the background handler as Android system may kill long running operations in the background.

```dart
@pragma('vm:entry-point')
backgroundMessageHandler(SmsMessage message) async {
	//Handle background message	
}

void main() {
  runApp(MyApp());
}
```
3. Call `listenIncomingSms` with a foreground `MessageHandler` and pass in the static `backgroundMessageHandler`.
```dart
telephony.listenIncomingSms(
		onNewMessage: (SmsMessage message) {
			// Handle message
		},
		onBackgroundMessage: backgroundMessageHandler
	);
```

Preferably should be called early in app lifecycle.

4. If you do not wish to receive incoming SMS when the app is in background, just do not pass the `onBackgroundMessage` paramater. 

	Alternatively if you prefer to expecility disable background execution, set the `listenInBackground` flag to `false`.
```dart
telephony.listenIncomingSms(
		onNewMessage: (SmsMessage message) {
			// Handle message
		},
		listenInBackground: false
	);
```
5. As of the `1.12` release of Flutter, plugins are automatically registered. This will allow you to use plugins as you normally do even in the background execution context. 
```dart
@pragma('vm:entry-point')
backgroundMessageHandler(SmsMessage message) async {
		// Handle background message
		
		// Use plugins
		Vibration.vibrate(duration: 500);
	}
```
### [Network data and metrics](https://shounakmulay.gitbook.io/telephony/network-data-and-metrics)

Fetch various metrics such as `network type`, `sim state`, etc.

```dart

// Check if a device is capable of sending SMS
bool canSendSms = await telephony.isSmsCapable;

// Get sim state
SimState simState = await telephony.simState;
```

Check out the [detailed documentation](https://shounakmulay.gitbook.io/telephony/network-data-and-metrics) to know all possible metrics and their values.

### Executing in background
If you want to call the `telephony` methods in background, you can do in the following ways.

#### 1. Using only `Telephony.instance`
If you want to continue using `Telephony.instance` in the background, you will need to make sure that once the app comes back to the front, it again calls `Telephony.instance`.
```dart
@pragma('vm:entry-point')
backgroundMessageHandler(SmsMessage message) async {
	// Handle background message
	Telephony.instance.sendSms(to: "123456789", message: "Message from background")
}

void main() {
  runApp(MyApp());
}

class _MyAppState extends State<MyApp> {
  String _message;
  // This will not work as the instance will be replaced by
  // the one in background.
  final telephony = Telephony.instance;
  
   @override
  void initState() {
    super.initState();
    // You should make sure call to instance is made every time 
    // app comes to foreground
    final inbox = Telephony.instance.getInboxSms()
  }

```

#### 2. Use `backgroundInstance`
If you cannot make sure that the call to instance would be made every time app comes to foreground, or if you would prefer to maintain a separate background instance,
you can use `Telephony.backgroundInstance` in the background execution context.
```dart
@pragma('vm:entry-point')
backgroundMessageHandler(SmsMessage message) async {
	// Handle background message
	Telephony.backgroundInstance.sendSms(to: "123456789", message: "Message from background")
}

void main() {
  runApp(MyApp());
}

class _MyAppState extends State<MyApp> {
  String _message;
  final telephony = Telephony.instance;
  
   @override
  void initState() {
    super.initState();
    final inbox = telephony.getInboxSms()
  }

```


## Features

 - [x] [Send SMS](#send-sms)
 - [x] [Query SMS](#query-sms)
	 - [x] Inbox
	 - [x] Sent
	 - [x] Draft
 - [x] [Query Conversations](#query-conversations)
 - [x] [Listen to incoming SMS](#listen-to-incoming-sms)
	 - [x] When app is in foreground
	 - [x] When app is in background
 - [x] [Network data and metrics](#network-data-and-metrics)
	 - [x] Cellular data state
	 - [x] Call state
	 - [x] Data activity
	 - [x] Network operator
	 - [x] Network operator name
	 - [x] Data network type
	 - [x] Phone type
	 - [x] Sim operator
	 - [x] Sim operator name
	 - [x] Sim state
	 - [x] Network roaming
	 - [x] Signal strength
	 - [x] Service state
 - [x] Start Phone Call
 - [ ] Schedule a SMS
 - [ ] SMS Retriever API
