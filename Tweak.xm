#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "OPCCView.h"
#import "OPCCActions.h"

@interface SBControlCenterController : NSObject
+ (id)sharedInstance;
- (void)dismissAnimated:(BOOL)a;
- (void)presentAnimated:(BOOL)a;
- (void)presentAnimated:(BOOL)a completion:(id)c;
@end
@interface CCUIModularControlCenterOverlayViewController : UIViewController
- (void)opcc_sync;
@end
@interface SpringBoard : UIApplication @end

static const void *kOPCC = &kOPCC;
static BOOL gAllowCC = NO;   // YES только в момент, когда шторку открываем мы сами

#pragma mark - диагностика: список методов классов (поможет, если жест не сработает)
static void OPCCDump(void) {
    NSString *path = @"/var/mobile/Documents/OPCC_methods.txt";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSMutableString *o = [NSMutableString string];
    for (NSString *cn in @[@"SBControlCenterController", @"SBSystemGestureManager", @"CCUIModularControlCenterOverlayViewController"]) {
        Class c = NSClassFromString(cn);
        if (!c) { [o appendFormat:@"\n== %@: класса нет\n", cn]; continue; }
        for (int meta = 0; meta < 2; meta++) {
            unsigned n = 0; Method *ms = class_copyMethodList(meta ? object_getClass(c) : c, &n);
            [o appendFormat:@"\n== %@ (%@)\n", cn, meta ? @"class" : @"instance"];
            for (unsigned i = 0; i < n; i++) [o appendFormat:@"%s\n", sel_getName(method_getName(ms[i]))];
            free(ms);
        }
    }
    [o writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - жест: свайп вниз от правой половины верхнего края
@interface OPCCStripHandler : NSObject
@property (nonatomic) BOOL fired;
- (void)pan:(UIPanGestureRecognizer *)g;
@end
@implementation OPCCStripHandler
- (void)pan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) { self.fired = NO; return; }
    if (g.state != UIGestureRecognizerStateChanged || self.fired) return;
    CGPoint t = [g translationInView:g.view];
    if (t.y > 22 && t.y > fabs(t.x)) {
        self.fired = YES;
        id cc = [objc_getClass("SBControlCenterController") sharedInstance];
        gAllowCC = YES;
        if ([cc respondsToSelector:@selector(presentAnimated:completion:)]) [cc presentAnimated:YES completion:nil];
        else if ([cc respondsToSelector:@selector(presentAnimated:)]) [cc presentAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gAllowCC = NO; });
    }
}
@end

static UIWindow *gStrip; static OPCCStripHandler *gHandler;
static void OPCCInstallStrip(void) {
    if (gStrip || ![OPCCActions boolPref:@"topRightGesture" def:YES]) return;
    CGRect sb = [UIScreen mainScreen].bounds;
    gStrip = [[UIWindow alloc] initWithFrame:CGRectMake(sb.size.width * 0.5, 0, sb.size.width * 0.5, 28)];
    gStrip.windowLevel = 2000; gStrip.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new]; vc.view.backgroundColor = [UIColor clearColor]; gStrip.rootViewController = vc;
    gHandler = [OPCCStripHandler new];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gHandler action:@selector(pan:)];
    pan.cancelsTouchesInView = NO; [vc.view addGestureRecognizer:pan];
    gStrip.hidden = NO;
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ OPCCInstallStrip(); OPCCDump(); });
}
%end

#pragma mark - отключение стандартного жеста Центра управления (снизу)
%hook SBControlCenterController
- (BOOL)_shouldAllowControlCenterGesture {
    if (!gAllowCC && [OPCCActions boolPref:@"disableBottomGesture" def:YES]) return NO;
    return %orig;
}
%end

#pragma mark - переключатель звука
%hook SBRingerControl
- (id)init { id r = %orig; OPCCRingerControl = r; return r; }
- (BOOL)isRingerMuted { OPCCRingerControl = self; return %orig; }
- (void)setRingerMuted:(BOOL)m { OPCCRingerControl = self; %orig; }
%end

#pragma mark - подмена Центра управления
%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLoad {
    %orig;
    __weak UIViewController *weakSelf = self;
    OPCCView *v = [[OPCCView alloc] initWithFrame:self.view.bounds];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.dismissBlock = ^{
        id cc = [objc_getClass("SBControlCenterController") sharedInstance];
        if ([cc respondsToSelector:@selector(dismissAnimated:)]) [cc dismissAnimated:YES];
        else [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    v.presentBlock = ^(UIViewController *vc) { [weakSelf presentViewController:vc animated:YES completion:nil]; };
    objc_setAssociatedObject(self, kOPCC, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.view addSubview:v];
}

- (void)viewDidLayoutSubviews { %orig; [self opcc_sync]; }

%new
- (void)opcc_sync {
    OPCCView *v = objc_getAssociatedObject(self, kOPCC);
    if (!v) return;
    for (UIView *s in self.view.subviews) if (s != v) s.hidden = YES;   // прячем оригинальный iOS CC
    self.view.backgroundColor = [UIColor clearColor];
    UIView *host = v.superview ?: self.view;
    v.frame = host.bounds;
    [host bringSubviewToFront:v];
    // Системные тап-жесты «закрыть по касанию» срабатывали на наших кнопках — отключаем их
    for (UIView *h in @[self.view, self.view.superview ?: self.view]) {
        for (UIGestureRecognizer *g in h.gestureRecognizers)
            if ([g isKindOfClass:[UITapGestureRecognizer class]]) g.enabled = NO;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    OPCCView *v = objc_getAssociatedObject(self, kOPCC);
    UIWindow *w = self.view.window;
    if (w && v.superview != w) {            // кладём нашу шторку прямо в окно, чтобы она не ехала снизу вместе со стоковой
        [w addSubview:v]; v.frame = w.bounds;
    }
    [self opcc_sync];
    [v present];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [(OPCCView *)objc_getAssociatedObject(self, kOPCC) closeForSystemDismiss];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    OPCCView *v = objc_getAssociatedObject(self, kOPCC);
    [v stop];
    if (v.superview != self.view) { [self.view addSubview:v]; v.frame = self.view.bounds; }
}

%end
