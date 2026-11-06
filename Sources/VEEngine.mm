#import "VEEngine.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_browser.h"
#include "include/cef_frame.h"
#include "include/cef_request_context.h"
#include "include/cef_string_visitor.h"
#include "include/cef_image.h"
#include "include/cef_process_message.h"
#include "include/cef_frame_handler.h"
#include <map>
#include "include/wrapper/cef_helpers.h"
class VEClient;
@interface VEEngineView () {
 @public CefRefPtr<CefBrowser> _browser;
 CefRefPtr<VEClient> _client;
 CefRefPtr<CefRequestContext> _context;
 BOOL _privateMode;
 NSString *_pendingURL;
 BOOL _closingRequested;
 BOOL _closeForce;
 BOOL _privateRegistered;
 id _swipeMonitor;
 BOOL _swipeTracking;
}
- (void)refreshAccessibility;
@end
static NSString *NS(const CefString &s) {return [NSString stringWithUTF8String:s.ToString().c_str()]?:@"";}
static CefRefPtr<CefRequestContext> privateContext;
static int privateBrowserCount=0;
static void QAFaviconDiagnostic(NSDictionary *entry){
 if(![NSProcessInfo.processInfo.arguments containsObject:@"--veil-qa"])return;
 NSString *path=[VEProfileRoot() stringByAppendingPathComponent:@"qa-favicons.json"];
 NSData *previous=[NSData dataWithContentsOfFile:path];id decoded=previous?[NSJSONSerialization JSONObjectWithData:previous options:NSJSONReadingMutableContainers error:nil]:nil;
 NSMutableArray *events=[decoded isKindOfClass:NSMutableArray.class]?decoded:[NSMutableArray array];[events addObject:entry];while(events.count>24)[events removeObjectAtIndex:0];
 [[NSJSONSerialization dataWithJSONObject:events options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
}
class VEFavicon:public CefDownloadImageCallback {
 __weak VEEngineView *view;
 NSString *pageURL;
public:
 VEFavicon(VEEngineView *v,NSString *url):view(v),pageURL([url copy]){}
 void OnDownloadImageFinished(const CefString&,int status,CefRefPtr<CefImage> image) override {
  int width=0,height=0;CefRefPtr<CefBinaryValue> bytes=image?image->GetAsPNG(2,true,width,height):nullptr;
  QAFaviconDiagnostic(@{@"event":@"download",@"http_status":@(status),@"has_image":@(image!=nullptr),@"png_bytes":@(bytes?bytes->GetSize():0),@"width":@(width),@"height":@(height)});
  if(!bytes||bytes->GetSize()>131072)return;
  NSMutableData *data=[NSMutableData dataWithLength:bytes->GetSize()];bytes->GetData(data.mutableBytes,data.length,0);
  VEEngineView *v=view;if(v)[v.delegate engineView:v didUpdate:@{@"faviconPNG":data,@"faviconPageURL":pageURL}];
 }
private:IMPLEMENT_REFCOUNTING(VEFavicon);
};
class VEHTMLSave:public CefStringVisitor {
 __weak VEEngineView *view;
 NSString *path;
public:
 VEHTMLSave(VEEngineView *v,NSString *p):view(v),path([p copy]){}
 void Visit(const CefString &text) override {
  NSData *data=[NS(text) dataUsingEncoding:NSUTF8StringEncoding];NSString *destination=path;__weak VEEngineView *target=view;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;BOOL success=[data writeToFile:destination options:NSDataWritingAtomic error:&error];dispatch_async(dispatch_get_main_queue(),^{VEEngineView *v=target;if(v)[v.delegate engineView:v didUpdate:@{@"savedHTML":@(success)}];});});
 }
private:IMPLEMENT_REFCOUNTING(VEHTMLSave);
};
class VEClient : public CefClient, public CefLifeSpanHandler, public CefDisplayHandler, public CefLoadHandler, public CefRequestHandler, public CefFrameHandler, public CefJSDialogHandler, public CefDownloadHandler, public CefPermissionHandler,public CefFocusHandler {
public:
 __weak VEEngineView *view;
 NSMutableDictionary<NSString*,NSDictionary*> *frames=[NSMutableDictionary dictionary];
 std::map<int,CefRefPtr<CefDownloadItemCallback>> downloads;
 std::string mediaFrame;
 bool gestureBlocked=false;
 bool closing=false;
 CefRefPtr<CefJSDialogCallback> unloadDialog;
 __weak NSAlert *activeUnloadAlert;
 VEClient(VEEngineView *v):view(v){}
 CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override{return this;}
 CefRefPtr<CefDisplayHandler> GetDisplayHandler() override{return this;}
 CefRefPtr<CefLoadHandler> GetLoadHandler() override{return this;}
 CefRefPtr<CefRequestHandler> GetRequestHandler() override{return this;}
 CefRefPtr<CefFrameHandler> GetFrameHandler() override{return this;}
 CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override{return this;}
 CefRefPtr<CefDownloadHandler> GetDownloadHandler() override{return this;}
 CefRefPtr<CefPermissionHandler> GetPermissionHandler() override{return this;}
 CefRefPtr<CefFocusHandler> GetFocusHandler() override{return this;}
 bool OnSetFocus(CefRefPtr<CefBrowser>,FocusSource) override{VEEngineView *v=view;return v.window && !v.window.isKeyWindow;}
 void emit(NSDictionary *state) {VEEngineView *v=view;if(v) [v.delegate engineView:v didUpdate:state];}
 void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
  if(!view) {browser->GetHost()->CloseBrowser(true);return;}
  view->_browser=browser;
  NSView *child=(__bridge NSView*)browser->GetHost()->GetWindowHandle();
  child.frame=view.bounds;child.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  if([NSProcessInfo.processInfo.arguments containsObject:@"--veil-qa"])NSLog(@"VEIL child=%@ parent=%@ window=%@",child,child.superview,child.window);
  [view refreshAccessibility];
  emit(@{@"ready":@YES});
  if(view->_closingRequested)browser->GetHost()->CloseBrowser(view->_closeForce);
 }
 bool DoClose(CefRefPtr<CefBrowser> browser) override {
  closing=true;
  // Each browser is an embedded tab, so closing it must tear down its native
  // child view rather than sending performClose: to the entire browser window.
  NSView *child=(__bridge NSView*)browser->GetHost()->GetWindowHandle();
  dispatch_async(dispatch_get_main_queue(),^{[child removeFromSuperview];});
  return true;
 }
 void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {VEEngineView *v=view;if(v){v->_browser=nullptr;v->_context=nullptr;if(v->_privateRegistered){v->_privateRegistered=NO;if(--privateBrowserCount==0)privateContext=nullptr;}[v.delegate engineViewDidClose:v];}}
 void OnTitleChange(CefRefPtr<CefBrowser> browser,const CefString &title) override{emit(@{@"title":NS(title)});}
 void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,const std::vector<CefString> &urls) override {
  QAFaviconDiagnostic(@{@"event":@"candidates",@"count":@(urls.size())});
  if(urls.empty())return;const auto &url=urls[0];const auto raw=url.ToString();if(raw.rfind("https://",0)!=0&&raw.rfind("http://",0)!=0)return;
  browser->GetHost()->DownloadImage(url,true,32,false,new VEFavicon(view,NS(browser->GetMainFrame()->GetURL())));
 }
 void OnAddressChange(CefRefPtr<CefBrowser> browser,CefRefPtr<CefFrame> frame,const CefString &url) override{if(frame->IsMain())emit(@{@"url":NS(url)});}
 void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,bool loading,bool back,bool forward) override{emit(@{@"loading":@(loading),@"canBack":@(back),@"canForward":@(forward)});}
 void OnFullscreenModeChange(CefRefPtr<CefBrowser>,bool fullscreen) override{emit(@{@"webFullscreen":@(fullscreen)});}
 void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,TerminationStatus status,int code,const CefString &error) override{emit(@{@"crashed":@YES,@"error":NS(error)});}
 void OnLoadError(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame,ErrorCode code,const CefString &text,const CefString&) override{if(frame->IsMain()&&code!=ERR_ABORTED)emit(@{@"loadError":NS(text),@"errorCode":@(code)});}
 void aggregate() {
  if(closing)return;
  BOOL dirty=NO,playing=NO,capture=NO,upload=NO,hasMedia=NO,horizontal=NO,previous=NO,next=NO;
  NSDictionary *chosen=nil;
  for(NSString *key in frames){NSDictionary *state=frames[key];dirty|=[state[@"dirty"] boolValue];capture|=[state[@"capture"] boolValue];upload|=[state[@"upload"] boolValue];horizontal|=[state[@"horizontal"] boolValue];hasMedia|=[state[@"hasMedia"] boolValue];if([state[@"playing"] boolValue]){playing=YES;chosen=state;mediaFrame=key.UTF8String;}else if(!chosen&&[state[@"hasMedia"] boolValue]){chosen=state;mediaFrame=key.UTF8String;}}
  if(chosen){previous=[chosen[@"previous"] boolValue];next=[chosen[@"next"] boolValue];}
  gestureBlocked=horizontal;
  emit(@{@"dirty":@(frames.count==0 || dirty),@"playing":@(playing),@"capture":@(capture),@"upload":@(upload),@"hasMedia":@(hasMedia),@"mediaTitle":chosen[@"mediaTitle"]?:@"Media",@"mediaArtist":chosen[@"mediaArtist"]?:@"",@"mediaPrevious":@(previous),@"mediaNext":@(next),@"downloadActive":@(!downloads.empty())});
 }
 void OnFrameCreated(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame) override{frames[NS(frame->GetIdentifier())]=@{@"dirty":@YES};}
 void OnFrameDetached(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame) override{[frames removeObjectForKey:NS(frame->GetIdentifier())];aggregate();}
 bool OnProcessMessageReceived(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame,CefProcessId source,CefRefPtr<CefProcessMessage> message) override {
  if(source!=PID_RENDERER || message->GetName()!="veil.telemetry")return false;
  auto list=message->GetArgumentList();if(list->GetSize()!=1 || list->GetType(0)!=VTYPE_STRING)return true;
  NSString *text=NS(list->GetString(0));if(text.length>4096)return true;
  id parsed=[NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(![parsed isKindOfClass:NSDictionary.class])return true;
  NSMutableDictionary *safe=[NSMutableDictionary dictionary];
  for(NSString *key in @[@"dirty",@"playing",@"capture",@"upload",@"hasMedia",@"previous",@"next",@"horizontal"]){id value=parsed[key];safe[key]=@([value isKindOfClass:NSNumber.class]&&[value boolValue]);}
  for(NSString *key in @[@"mediaTitle",@"mediaArtist"]){id value=parsed[key];safe[key]=[value isKindOfClass:NSString.class]?[value substringToIndex:MIN((NSUInteger)256,[value length])]:@"";}
  frames[NS(frame->GetIdentifier())]=safe;aggregate();return true;
 }
 bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>,const CefString&,bool,CefRefPtr<CefJSDialogCallback> callback) override {
  VEEngineView *v=view;if(!v.window){callback->Continue(false,"");emit(@{@"closeCancelled":@YES});return true;}
  NSAlert *alert=[NSAlert new];alert.messageText=@"Leave this page?";alert.informativeText=@"Changes you made may not be saved.";[alert addButtonWithTitle:@"Leave Page"];[alert addButtonWithTitle:@"Stay"];
  unloadDialog=callback;activeUnloadAlert=alert;CefRefPtr<VEClient> self=this;
  [alert beginSheetModalForWindow:v.window completionHandler:^(NSModalResponse response){if(self->unloadDialog!=callback)return;self->unloadDialog=nullptr;BOOL leave=response==NSAlertFirstButtonReturn;callback->Continue(leave,"");if(!leave)self->emit(@{@"closeCancelled":@YES});}];return true;
 }
 void OnResetDialogState(CefRefPtr<CefBrowser>) override {if(unloadDialog){auto pending=unloadDialog;unloadDialog=nullptr;if(activeUnloadAlert.window.sheetParent)[NSApp endSheet:activeUnloadAlert.window returnCode:NSAlertSecondButtonReturn];pending->Continue(false,"");emit(@{@"closeCancelled":@YES});}}
 bool OnBeforeDownload(CefRefPtr<CefBrowser>,CefRefPtr<CefDownloadItem>,const CefString &name,CefRefPtr<CefBeforeDownloadCallback> callback) override {callback->Continue("",true);return true;}
 void OnDownloadUpdated(CefRefPtr<CefBrowser>,CefRefPtr<CefDownloadItem> item,CefRefPtr<CefDownloadItemCallback> callback) override {
  const int id=item->GetId();if(item->IsInProgress())downloads[id]=callback;else downloads.erase(id);
  emit(@{@"download":@{@"id":@(id),@"name":NS(item->GetSuggestedFileName()),@"path":NS(item->GetFullPath()),@"url":NS(item->GetURL()),@"complete":@(item->IsComplete()),@"cancelled":@(item->IsCanceled()),@"percent":@(item->GetPercentComplete()),@"active":@(item->IsInProgress())}});aggregate();
 }
 bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame>,const CefString &origin,uint32_t requested,CefRefPtr<CefMediaAccessCallback> callback) override {
  VEEngineView *v=view;if(!v.window){callback->Continue(0);return true;}
  NSMutableArray *names=[NSMutableArray array];if(requested&CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE)[names addObject:@"microphone"];if(requested&CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE)[names addObject:@"camera"];if(requested&CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE)[names addObject:@"system audio"];if(requested&CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE)[names addObject:@"screen"];
  if(names.count==0){callback->Continue(0);return true;}
  NSAlert *alert=[NSAlert new];alert.messageText=@"Allow media access?";alert.informativeText=[NSString stringWithFormat:@"%@ wants to use your %@. Only allow sites you trust.",NS(origin),[names componentsJoinedByString:@", "]];[alert addButtonWithTitle:@"Don't Allow"];[alert addButtonWithTitle:@"Allow"];
  [alert beginSheetModalForWindow:v.window completionHandler:^(NSModalResponse response){callback->Continue(response==NSAlertSecondButtonReturn?requested:0);}];return true;
 }
 bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>,uint64_t,const CefString &origin,uint32_t requested,CefRefPtr<CefPermissionPromptCallback> callback) override {
  VEEngineView *v=view;if(!v.window){callback->Continue(CEF_PERMISSION_RESULT_DENY);return true;}
  NSDictionary<NSNumber*,NSString*> *types=@{@(CEF_PERMISSION_TYPE_AR_SESSION):@"augmented reality",@(CEF_PERMISSION_TYPE_CAMERA_PAN_TILT_ZOOM):@"camera movement",@(CEF_PERMISSION_TYPE_CAMERA_STREAM):@"camera",@(CEF_PERMISSION_TYPE_CAPTURED_SURFACE_CONTROL):@"shared-screen controls",@(CEF_PERMISSION_TYPE_CLIPBOARD):@"clipboard",@(CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS):@"cross-site storage",@(CEF_PERMISSION_TYPE_DISK_QUOTA):@"additional storage",@(CEF_PERMISSION_TYPE_LOCAL_FONTS):@"local fonts",@(CEF_PERMISSION_TYPE_GEOLOCATION):@"location",@(CEF_PERMISSION_TYPE_HAND_TRACKING):@"hand tracking",@(CEF_PERMISSION_TYPE_IDENTITY_PROVIDER):@"identity provider",@(CEF_PERMISSION_TYPE_IDLE_DETECTION):@"idle detection",@(CEF_PERMISSION_TYPE_MIC_STREAM):@"microphone",@(CEF_PERMISSION_TYPE_MIDI_SYSEX):@"MIDI devices",@(CEF_PERMISSION_TYPE_MULTIPLE_DOWNLOADS):@"multiple downloads",@(CEF_PERMISSION_TYPE_NOTIFICATIONS):@"notifications",@(CEF_PERMISSION_TYPE_KEYBOARD_LOCK):@"keyboard capture",@(CEF_PERMISSION_TYPE_POINTER_LOCK):@"pointer capture",@(CEF_PERMISSION_TYPE_PROTECTED_MEDIA_IDENTIFIER):@"protected-media identifier",@(CEF_PERMISSION_TYPE_REGISTER_PROTOCOL_HANDLER):@"link handling",@(CEF_PERMISSION_TYPE_STORAGE_ACCESS):@"cross-site cookies",@(CEF_PERMISSION_TYPE_VR_SESSION):@"virtual reality",@(CEF_PERMISSION_TYPE_WEB_APP_INSTALLATION):@"web app installation",@(CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT):@"window management",@(CEF_PERMISSION_TYPE_FILE_SYSTEM_ACCESS):@"selected filesystem access"};
  NSMutableArray *names=[NSMutableArray array];uint32_t known=0;for(NSNumber *mask in types){known|=mask.unsignedIntValue;if(requested&mask.unsignedIntValue)[names addObject:types[mask]];}
  if(names.count==0 || (requested&~known)!=0){callback->Continue(CEF_PERMISSION_RESULT_DENY);return true;}
  NSAlert *alert=[NSAlert new];alert.messageText=@"Website permission";alert.informativeText=[NSString stringWithFormat:@"%@ requests: %@. Allow for this request?",NS(origin),[names componentsJoinedByString:@", "]];[alert addButtonWithTitle:@"Don't Allow"];[alert addButtonWithTitle:@"Allow"];
  [alert beginSheetModalForWindow:v.window completionHandler:^(NSModalResponse response){callback->Continue(response==NSAlertSecondButtonReturn?CEF_PERMISSION_RESULT_ACCEPT:CEF_PERMISSION_RESULT_DENY);}];return true;
 }
 bool OnBeforePopup(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame>,int,const CefString &url,const CefString&,WindowOpenDisposition,bool gesture,const CefPopupFeatures&,CefWindowInfo&,CefRefPtr<CefClient>&,CefBrowserSettings&,CefRefPtr<CefDictionaryValue>&,bool*) override {
  VEEngineView *v=view;if(v&&gesture)[v.delegate engineView:v openURL:NS(url)];return true;
 }
private: IMPLEMENT_REFCOUNTING(VEClient);
};
@implementation VEEngineView
- (instancetype)initWithFrame:(NSRect)frame privateMode:(BOOL)mode {
 if((self=[super initWithFrame:frame])){
  _privateMode=mode;__weak VEEngineView *weakSelf=self;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accessibilityRequestChanged:) name:@"VEILAccessibilityChanged" object:nil];
  _swipeMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent*(NSEvent *event){
   VEEngineView *v=weakSelf;
   if(!v || !v.window || event.window!=v.window || v.hiddenOrHasHiddenAncestor || !NSPointInRect([v convertPoint:event.locationInWindow fromView:nil],v.bounds))return event;
   if(v->_swipeTracking)return nil;
   if(!NSEvent.swipeTrackingFromScrollEventsEnabled || !event.hasPreciseScrollingDeltas || event.momentumPhase!=NSEventPhaseNone || !(event.phase&(NSEventPhaseBegan|NSEventPhaseChanged)))return event;
   if(!v->_browser || !v->_client || v->_client->gestureBlocked || fabs(event.scrollingDeltaX)<2 || fabs(event.scrollingDeltaX)<fabs(event.scrollingDeltaY)*1.6)return event;
   const BOOL back=v.canGoBack,forward=v.canGoForward;
   if((event.scrollingDeltaX>0&&!back)||(event.scrollingDeltaX<0&&!forward))return event;
   v->_swipeTracking=YES;
   [event trackSwipeEventWithOptions:NSEventSwipeTrackingLockDirection dampenAmountThresholdMin:forward?-1:0 max:back?1:0 usingHandler:^(CGFloat amount,NSEventPhase phase,BOOL complete,BOOL *stop){
    VEEngineView *target=weakSelf;
    if(!target || !target.window || target.hiddenOrHasHiddenAncestor || target->_closingRequested){if(target)target->_swipeTracking=NO;*stop=YES;return;}
    [target.delegate engineView:target didUpdate:@{@"swipeAmount":@(amount),@"swipeComplete":@(complete)}];
    if(complete){target->_swipeTracking=NO;if(phase!=NSEventPhaseCancelled){if(amount>=0.99&&back)[target goBack];else if(amount<=-0.99&&forward)[target goForward];}}
   }];
   return nil;
  }];
 }return self;
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];if(_swipeMonitor)[NSEvent removeMonitor:_swipeMonitor];}
- (void)accessibilityRequestChanged:(NSNotification *)notification{[self refreshAccessibility];}
- (void)refreshAccessibility {
 if(!_browser)return;
 // Hidden Chromium platform trees can retain a detached Cocoa accessibility
 // root. Keep only visible trees enabled and rebuild when their tab is shown.
 _browser->GetHost()->SetAccessibilityState(self.hiddenOrHasHiddenAncestor ? STATE_DISABLED:(VEAccessibilityEnabled() ? STATE_ENABLED:STATE_DEFAULT));
}
- (void)setHidden:(BOOL)hidden {
 if(self.hidden==hidden)return;
 if(hidden && _browser)_browser->GetHost()->SetFocus(false);
 [super setHidden:hidden];
 [self refreshAccessibility];
 if(!hidden && self.window)NSAccessibilityPostNotification(self.window,NSAccessibilityLayoutChangedNotification);
}
- (BOOL)ready{return _browser!=nullptr;}
- (BOOL)canGoBack{return _browser&&_browser->CanGoBack();}
- (BOOL)canGoForward{return _browser&&_browser->CanGoForward();}
- (double)pageZoom{return _browser?_browser->GetHost()->GetZoomLevel():0;}
- (NSString*)currentURL{return _browser?NS(_browser->GetMainFrame()->GetURL()):nil;}
- (void)undoEditing{if(_browser)_browser->GetFocusedFrame()->Undo();}
- (void)redoEditing{if(_browser)_browser->GetFocusedFrame()->Redo();}
- (void)startWithURL:(NSString*)url {
 if(_client)return;
 _pendingURL=[url copy];_client=new VEClient(self);
 CefWindowInfo info;info.SetAsChild((__bridge CefWindowHandle)self,CefRect(0,0,self.bounds.size.width,self.bounds.size.height));info.runtime_style=CEF_RUNTIME_STYLE_ALLOY;
 CefBrowserSettings settings;settings.background_color=CefColorSetARGB(255,248,248,248);
 if(_privateMode){if(!privateContext){CefRequestContextSettings cs;privateContext=CefRequestContext::CreateContext(cs,nullptr);}_context=privateContext;privateBrowserCount++;_privateRegistered=YES;}else _context=CefRequestContext::GetGlobalContext();
 if(!CefBrowserHost::CreateBrowser(info,_client,url.UTF8String,settings,nullptr,_context)){if(_privateRegistered){_privateRegistered=NO;if(--privateBrowserCount==0)privateContext=nullptr;}[self.delegate engineView:self didUpdate:@{@"loadError":@"Could not create browser"}];[self.delegate engineViewDidClose:self];}
}
- (void)loadURL:(NSString*)url {if(_browser)_browser->GetMainFrame()->LoadURL(url.UTF8String);else _pendingURL=[url copy];}
- (void)goBack{if(_browser)_browser->GoBack();}
- (void)goForward{if(_browser)_browser->GoForward();}
- (void)reloadIgnoringCache:(BOOL)ignore {if(_browser){if(ignore)_browser->ReloadIgnoreCache();else _browser->Reload();}}
- (void)focusPage{if(_browser)_browser->GetHost()->SetFocus(true);}
- (void)closeBrowser:(BOOL)force{_closingRequested=YES;_closeForce=force;if(_browser)_browser->GetHost()->CloseBrowser(force);}
- (void)executeScript:(NSString*)script{if(_browser)_browser->GetMainFrame()->ExecuteJavaScript(script.UTF8String,_browser->GetMainFrame()->GetURL(),0);}
- (void)setPageZoom:(double)level{if(_browser)_browser->GetHost()->SetZoomLevel(level);}
- (void)setAudioMuted:(BOOL)muted{if(_browser)_browser->GetHost()->SetAudioMuted(muted);}
- (void)showDevTools{if(_browser){CefWindowInfo info;CefBrowserSettings s;_browser->GetHost()->ShowDevTools(info,nullptr,s,CefPoint());}}
- (void)findText:(NSString*)text forward:(BOOL)forward{if(_browser)_browser->GetHost()->Find(text.UTF8String,forward,false,false);}
- (void)saveHTMLToPath:(NSString*)path{if(_browser)_browser->GetMainFrame()->GetSource(new VEHTMLSave(self,path));}
- (void)performMediaAction:(NSString*)action {
 if(!_browser || ![@[@"toggle",@"play",@"pause",@"previoustrack",@"nexttrack"] containsObject:action])return;
 auto frame=_client->mediaFrame.empty()?nullptr:_browser->GetFrameByIdentifier(_client->mediaFrame);if(!frame)frame=_browser->GetMainFrame();
 NSString *script=[NSString stringWithFormat:@"window.__veilControl && window.__veilControl('%@')",action];frame->ExecuteJavaScript(script.UTF8String,frame->GetURL(),0);
}
- (void)cancelDownload:(NSInteger)identifier{if(_client){auto found=_client->downloads.find((int)identifier);if(found!=_client->downloads.end())found->second->Cancel();}}
- (void)startDownloadURL:(NSString*)url{if(_browser)_browser->GetHost()->StartDownload(url.UTF8String);}
@end
