#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

static NSString * const TrackerBaseURL = @"http://127.0.0.1:4177";
static NSString * const PanelModeDefaultsKey = @"idolOpsPanelMode";

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler>
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTask *trackerTask;
@property(nonatomic, assign) BOOL ownsTrackerTask;
@property(nonatomic, copy) NSString *panelMode;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *savedMode = [[NSUserDefaults standardUserDefaults] stringForKey:PanelModeDefaultsKey];
    self.panelMode = [self isValidPanelMode:savedMode] ? savedMode : @"compact";
    [self installStatusItem];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    [self prepareTrackerAndShow];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"panelMode"];
    if (self.ownsTrackerTask && self.trackerTask.isRunning) {
        [self.trackerTask terminate];
    }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [sender orderOut:nil];
    [self updateToggleTitle];
    return NO;
}

- (void)installStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"rectangle.3.group.fill"
                                            accessibilityDescription:@"IDOL Ops"];
    self.statusItem.button.toolTip = @"IDOL Ops Control";

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"패널 숨기기"
                                                   action:@selector(togglePanel:)
                                            keyEquivalent:@""];
    toggle.tag = 1001;
    toggle.target = self;
    [menu addItem:toggle];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"상태 새로고침"
                                                    action:@selector(refreshPanel:)
                                             keyEquivalent:@"r"];
    refresh.target = self;
    [menu addItem:refresh];

    NSMenuItem *peek = [[NSMenuItem alloc] initWithTitle:@"초소형으로 접기"
                                                  action:@selector(showPeekMode:)
                                           keyEquivalent:@""];
    peek.target = self;
    [menu addItem:peek];

    NSMenuItem *compact = [[NSMenuItem alloc] initWithTitle:@"요약으로 보기"
                                                     action:@selector(showCompactMode:)
                                              keyEquivalent:@""];
    compact.target = self;
    [menu addItem:compact];

    NSMenuItem *expanded = [[NSMenuItem alloc] initWithTitle:@"전체로 펼치기"
                                                      action:@selector(showExpandedMode:)
                                               keyEquivalent:@""];
    expanded.target = self;
    [menu addItem:expanded];

    NSMenuItem *openFull = [[NSMenuItem alloc] initWithTitle:@"전체 대시보드 열기"
                                                     action:@selector(openFullDashboard:)
                                              keyEquivalent:@"o"];
    openFull.target = self;
    [menu addItem:openFull];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *boundary = [[NSMenuItem alloc] initWithTitle:@"하네스 읽기 전용 · Local only"
                                                      action:nil
                                               keyEquivalent:@""];
    boundary.enabled = NO;
    [menu addItem:boundary];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"IDOL Ops 종료"
                                                  action:@selector(quitApp:)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)prepareTrackerAndShow {
    if ([self trackerIsHealthy]) {
        [self showPanel];
        return;
    }

    NSError *error = nil;
    if (![self startTrackerServer:&error]) {
        [self showStartupError:[NSString stringWithFormat:@"로컬 트래커를 시작하지 못했습니다: %@",
                                error.localizedDescription ?: @"알 수 없는 오류"]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ready = NO;
        for (NSInteger attempt = 0; attempt < 40; attempt += 1) {
            if ([weakSelf trackerIsHealthy]) {
                ready = YES;
                break;
            }
            [NSThread sleepForTimeInterval:0.2];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ready) {
                [weakSelf showPanel];
            } else {
                [weakSelf showStartupError:@"로컬 트래커가 8초 안에 준비되지 않았습니다."];
            }
        });
    });
}

- (BOOL)trackerIsHealthy {
    NSURL *url = [NSURL URLWithString:[TrackerBaseURL stringByAppendingString:@"/api/health"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:0.7];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL healthy = NO;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error && [(NSHTTPURLResponse *)response statusCode] == 200) {
            NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            healthy = [object[@"ok"] boolValue] && [object[@"service"] isEqualToString:@"idol-ops-tracker"];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)));
    return healthy;
}

- (NSString *)resourceTextNamed:(NSString *)name {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
    if (!path) return nil;
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length ? trimmed : nil;
}

- (BOOL)startTrackerServer:(NSError **)error {
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    NSString *trackerRoot = environment[@"IDOL_TRACKER_ROOT"] ?: [self resourceTextNamed:@"tracker-root"];
    NSString *python = environment[@"IDOL_TRACKER_PYTHON"] ?: [self resourceTextNamed:@"python-path"] ?: @"/opt/homebrew/bin/python3";
    NSString *startScript = [trackerRoot stringByAppendingPathComponent:@"start.py"];
    BOOL executable = [[NSFileManager defaultManager] isExecutableFileAtPath:python];
    BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath:startScript];
    if (!trackerRoot.length || !executable || !scriptExists) {
        if (error) {
            *error = [NSError errorWithDomain:@"IDOLOpsWidget"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Python 또는 start.py를 찾지 못했습니다."}];
        }
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:python];
    task.arguments = @[startScript, @"--host", @"127.0.0.1", @"--port", @"4177"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:trackerRoot];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:error]) return NO;
    self.trackerTask = task;
    self.ownsTrackerTask = YES;
    return YES;
}

- (NSPanel *)buildPanel {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    [configuration.userContentController addScriptMessageHandler:self name:@"panelMode"];
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.webView.allowsMagnification = NO;
    NSURL *url = [self compactURL];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url
                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                          timeoutInterval:10]];

    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                              NSWindowStyleMaskUtilityWindow;
    NSSize initialSize = [self contentSizeForMode:self.panelMode];
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, initialSize.width, initialSize.height)
                                            styleMask:style
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.panel.title = @"IDOL Ops Control";
    self.panel.titleVisibility = NSWindowTitleHidden;
    self.panel.titlebarAppearsTransparent = YES;
    self.panel.floatingPanel = YES;
    self.panel.level = NSFloatingWindowLevel;
    self.panel.hidesOnDeactivate = NO;
    self.panel.releasedWhenClosed = NO;
    self.panel.movableByWindowBackground = YES;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary;
    self.panel.backgroundColor = [NSColor colorWithCalibratedWhite:0.04 alpha:1];
    self.panel.contentMinSize = NSMakeSize(330, 86);
    self.panel.contentMaxSize = NSMakeSize(560, 880);
    self.panel.contentView = self.webView;
    self.panel.delegate = self;
    NSButton *miniaturizeButton = [self.panel standardWindowButton:NSWindowMiniaturizeButton];
    miniaturizeButton.hidden = NO;
    miniaturizeButton.enabled = YES;
    [[self.panel standardWindowButton:NSWindowZoomButton] setHidden:YES];
    return self.panel;
}

- (BOOL)isValidPanelMode:(NSString *)mode {
    return [mode isEqualToString:@"peek"] || [mode isEqualToString:@"compact"] || [mode isEqualToString:@"expanded"];
}

- (NSSize)contentSizeForMode:(NSString *)mode {
    if ([mode isEqualToString:@"peek"]) return NSMakeSize(360, 92);
    if ([mode isEqualToString:@"expanded"]) return NSMakeSize(520, 840);
    return NSMakeSize(410, 336);
}

- (NSURL *)compactURL {
    NSString *escapedMode = [self.panelMode stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/compact.html?mode=%@", TrackerBaseURL, escapedMode ?: @"compact"]];
}

- (void)setPanelToMode:(NSString *)mode animated:(BOOL)animated updateWeb:(BOOL)updateWeb {
    if (![self isValidPanelMode:mode]) return;
    self.panelMode = mode;
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:PanelModeDefaultsKey];
    if (!self.panel) return;

    NSSize contentSize = [self contentSizeForMode:mode];
    NSRect currentFrame = self.panel.frame;
    NSRect desiredFrame = [self.panel frameRectForContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    desiredFrame.origin.x = NSMaxX(currentFrame) - NSWidth(desiredFrame);
    desiredFrame.origin.y = NSMaxY(currentFrame) - NSHeight(desiredFrame);

    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen) {
        NSRect visible = screen.visibleFrame;
        CGFloat margin = 16;
        if (NSWidth(desiredFrame) > NSWidth(visible) - margin * 2) {
            desiredFrame.size.width = NSWidth(visible) - margin * 2;
        }
        if (NSHeight(desiredFrame) > NSHeight(visible) - margin * 2) {
            desiredFrame.size.height = NSHeight(visible) - margin * 2;
        }
        desiredFrame.origin.x = MIN(MAX(desiredFrame.origin.x, NSMinX(visible) + margin), NSMaxX(visible) - NSWidth(desiredFrame) - margin);
        desiredFrame.origin.y = MIN(MAX(desiredFrame.origin.y, NSMinY(visible) + margin), NSMaxY(visible) - NSHeight(desiredFrame) - margin);
    }
    [self.panel setFrame:desiredFrame display:YES animate:animated];
    if (updateWeb) {
        NSString *script = [NSString stringWithFormat:@"if (typeof setMode === 'function') setMode('%@', false);", mode];
        [self.webView evaluateJavaScript:script completionHandler:nil];
    }
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"panelMode"]) return;
    NSString *mode = nil;
    if ([message.body isKindOfClass:NSDictionary.class]) mode = message.body[@"mode"];
    if ([message.body isKindOfClass:NSString.class]) mode = message.body;
    if (![mode isKindOfClass:NSString.class] || ![self isValidPanelMode:mode]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setPanelToMode:mode animated:YES updateWeb:NO];
    });
}

- (void)showPanel {
    NSPanel *window = self.panel ?: [self buildPanel];
    [self positionPanel];
    [window orderFrontRegardless];
    [self updateToggleTitle];
}

- (void)positionPanel {
    if (!self.panel) return;
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    CGFloat margin = 16;
    [self.panel setFrameOrigin:NSMakePoint(NSMaxX(visible) - NSWidth(self.panel.frame) - margin,
                                           NSMaxY(visible) - NSHeight(self.panel.frame) - margin)];
}

- (void)screenParametersChanged:(NSNotification *)notification {
    [self positionPanel];
}

- (void)updateToggleTitle {
    NSMenuItem *toggle = [self.statusItem.menu itemWithTag:1001];
    toggle.title = self.panel.visible ? @"패널 숨기기" : @"패널 보이기";
}

- (void)showStartupError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"IDOL Ops 시작 오류";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"확인"];
    [alert runModal];
}

- (void)togglePanel:(id)sender {
    if (self.panel.visible) {
        [self.panel orderOut:nil];
        [self updateToggleTitle];
    } else {
        [self showPanel];
    }
}

- (void)refreshPanel:(id)sender {
    NSURL *url = [self compactURL];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url
                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                          timeoutInterval:10]];
    if (!self.panel.visible) [self showPanel];
}

- (void)showPeekMode:(id)sender {
    if (!self.panel.visible) [self showPanel];
    [self setPanelToMode:@"peek" animated:YES updateWeb:YES];
}

- (void)showCompactMode:(id)sender {
    if (!self.panel.visible) [self showPanel];
    [self setPanelToMode:@"compact" animated:YES updateWeb:YES];
}

- (void)showExpandedMode:(id)sender {
    if (!self.panel.visible) [self showPanel];
    [self setPanelToMode:@"expanded" animated:YES updateWeb:YES];
}

- (void)openFullDashboard:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[TrackerBaseURL stringByAppendingString:@"/?view=workers"]]];
}

- (void)quitApp:(id)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
