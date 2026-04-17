#import "TelephonyPlugin.h"
#if __has_include(<telephony/telephony-Swift.h>)
#import <telephony/telephony-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "telephony-Swift.h"
#endif

@implementation TelephonyPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftTelephonyPlugin registerWithRegistrar:registrar];
}
@end
