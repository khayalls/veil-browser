#import <Cocoa/Cocoa.h>
#import <sqlite3.h>
NS_ASSUME_NONNULL_BEGIN
@class VEEngineView;
@protocol VEEngineDelegate <NSObject>
- (void)engineView:(VEEngineView *)view didUpdate:(NSDictionary<NSString *,id> *)state;
- (void)engineView:(VEEngineView *)view openURL:(NSString *)url;
- (void)engineViewDidClose:(VEEngineView *)view;
@end
@interface VEEngineView : NSView
@property(nonatomic,weak,nullable) id<VEEngineDelegate> delegate;
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) BOOL canGoBack;
@property(nonatomic,readonly) BOOL canGoForward;
@property(nonatomic,readonly) double pageZoom;
@property(nonatomic,readonly,copy,nullable) NSString *currentURL;
- (void)undoEditing;
- (void)redoEditing;
- (instancetype)initWithFrame:(NSRect)frame privateMode:(BOOL)privateMode;
- (void)startWithURL:(NSString *)url;
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reloadIgnoringCache:(BOOL)ignore;
- (void)focusPage;
- (void)closeBrowser:(BOOL)force;
- (void)executeScript:(NSString *)script;
- (void)setPageZoom:(double)level;
- (void)setAudioMuted:(BOOL)muted;
- (void)showDevTools;
- (void)findText:(NSString *)text forward:(BOOL)forward;
- (void)saveHTMLToPath:(NSString *)path NS_SWIFT_NAME(saveHTML(to:));
- (void)performMediaAction:(NSString *)action;
- (void)cancelDownload:(NSInteger)identifier;
- (void)startDownloadURL:(NSString *)url;
@end
FOUNDATION_EXPORT NSString *VEProfileRoot(void);
FOUNDATION_EXPORT void VEQuitEngine(void);
FOUNDATION_EXPORT BOOL VEAccessibilityEnabled(void);
FOUNDATION_EXPORT NSDictionary<NSString *,id> *VEProcessResources(void);
NS_ASSUME_NONNULL_END
