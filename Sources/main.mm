#import <Cocoa/Cocoa.h>
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#import "VEEngine.h"
#include "BuildIdentity.h"
extern "C" void VEILSetupApplication(void);
extern "C" void VEILRequestQuit(void);
static NSString *profileRoot;
static BOOL enhancedAccessibility;
NSString *VEProfileRoot(void) { return profileRoot; }
void VEQuitEngine(void) { CefQuitMessageLoop(); }
BOOL VEAccessibilityEnabled(void) { return enhancedAccessibility || NSWorkspace.sharedWorkspace.voiceOverEnabled || [NSProcessInfo.processInfo.arguments containsObject:@"--veil-qa"]; }
@interface VEApplication : NSApplication<CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation VEApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
- (void)terminate:(id)sender { VEILRequestQuit(); }
- (void)accessibilitySetValue:(id)value forAttribute:(NSString *)attribute {
 if([attribute isEqualToString:@"AXEnhancedUserInterface"]){BOOL requested=[value boolValue];dispatch_async(dispatch_get_main_queue(),^{enhancedAccessibility=requested;[NSNotificationCenter.defaultCenter postNotificationName:@"VEILAccessibilityChanged" object:nil];});}
 [super accessibilitySetValue:value forAttribute:attribute];
}
@end
class VEApp : public CefApp, public CefBrowserProcessHandler {
public:
 CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
 void OnContextInitialized() override { VEILSetupApplication(); }
private:
 IMPLEMENT_REFCOUNTING(VEApp);
};
int main(int argc,char *argv[]) {
 CefScopedLibraryLoader loader;
 if(!loader.LoadInMain()) return 1;
 @autoreleasepool {
  [VEApplication sharedApplication];
  auto cmd=CefCommandLine::CreateCommandLine();cmd->InitFromArgv(argc,argv);
  NSString *overrideRoot=[NSString stringWithUTF8String:cmd->GetSwitchValue("veil-profile-root").ToString().c_str()];
  profileRoot=overrideRoot.length?overrideRoot:[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"VEIL"];
  if(cmd->HasSwitch("veil-qa"))profileRoot=[profileRoot stringByAppendingPathComponent:[@"Build-" stringByAppendingString:@VEIL_BUILD_ID]];
  [[NSFileManager defaultManager] createDirectoryAtPath:profileRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
  [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:profileRoot error:nil];
  NSString *engineRoot=[profileRoot stringByAppendingPathComponent:@"Engine"];
  CefSettings settings;
  CefString(&settings.root_cache_path)=engineRoot.UTF8String;
  CefString(&settings.cache_path)=[engineRoot stringByAppendingPathComponent:@"Default"].UTF8String;
  settings.persist_session_cookies=true;
  // CEF 156's product-specific names isolate VEIL's cookie encryption key.
  // Never request the shared Chromium/Chrome Safe Storage item.
  CefString(&settings.keychain_service_name)="VEIL Safe Storage";
  CefString(&settings.keychain_account_name)="dev.khayal.veil";
  if(cmd->HasSwitch("veil-qa")) {
   // Ad-hoc signatures change during development. Synthetic QA gets its own
   // build-specific key and profile, without changing any user's Keychain ACL.
   CefString(&settings.keychain_service_name)=std::string("VEIL QA Safe Storage ")+VEIL_BUILD_ID;
   CefString(&settings.keychain_account_name)="dev.khayal.veil.qa";
  }
  settings.log_severity=LOGSEVERITY_DISABLE;
  settings.no_sandbox=false;
  if(cmd->HasSwitch("veil-qa")) {
   settings.remote_debugging_port=9223;
   if(cmd->HasSwitch("veil-qa-port")){int port=atoi(cmd->GetSwitchValue("veil-qa-port").ToString().c_str());if(port>=1024 && port<=65535)settings.remote_debugging_port=port;}
   settings.log_severity=LOGSEVERITY_WARNING;
   CefString(&settings.log_file)=[profileRoot stringByAppendingPathComponent:@"cef-qa.log"].UTF8String;
  }
  CefMainArgs args(argc,argv);
  CefRefPtr<VEApp> app=new VEApp();
  if(!CefInitialize(args,settings,app,nullptr)) return CefGetExitCode();
  CefRunMessageLoop();
  CefShutdown();
 }
 return 0;
}
