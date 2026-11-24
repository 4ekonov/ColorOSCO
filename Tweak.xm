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
@interface SBCoverSheetPresentationManager : NSObject
+ (id)sharedInstance; - (BOOL)isPresented; - (void)setCoverSheetPresented:(BOOL)p animated:(BOOL)a withCompletion:(id)c;
@end
@interface SBLockScreenManager : NSObject
+ (id)sharedInstance; - (BOOL)isUILocked;
@end

static NSHashTable *gCoverGRs;
static UIWindow *gStrip;

static void OPCCLog(NSString *line) {
    static int n = 0; if (n++ > 200) return;
    NSString *path = @"/var/mobile/Documents/OPCC_gestures.txt";
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    [[old stringByAppendingFormat:@"%@\n", line] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Собираем ВСЕ живые системные recognizer'ы SpringBoard (по окнам и по менеджеру жестов), а не только пойманные при создании
static void OPCCCollect(UIView *v, NSMutableArray *out) {
    for (UIGestureRecognizer *g in v.gestureRecognizers) [out addObject:g];
    for (UIView *s in v.subviews) OPCCCollect(s, out);
}
static BOOL OPCCIsSystemGR(UIGestureRecognizer *g) {
    NSString *gc = NSStringFromClass([g class]);
    NSString *dc = g.delegate ? NSStringFromClass([g.delegate class]) : @"";
    return [gc hasPrefix:@"SB"] || [gc hasPrefix:@"_SB"] || [gc hasPrefix:@"FB"] || [gc containsString:@"SystemGesture"] || [gc containsString:@"CoverSheet"]
        || [dc hasPrefix:@"SB"] || [dc containsString:@"CoverSheet"] || [dc containsString:@"SystemGesture"];
}
static void OPCCScan(void) {
    if (!gCoverGRs) gCoverGRs = [NSHashTable weakObjectsHashTable];
    NSMutableArray *all = [NSMutableArray array];
    NSArray *wins = nil; SEL ws = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    if ([UIWindow respondsToSelector:ws]) wins = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], ws, YES, NO);
    if (!wins) wins = [UIApplication sharedApplication].windows;
    for (UIWindow *w in wins) { if (w == gStrip) continue; OPCCCollect(w, all); }
    @try {
        id mgr = [objc_getClass("SBSystemGestureManager") performSelector:NSSelectorFromString(@"mainDisplayManager")];
        for (NSString *k in @[@"gestureRecognizers", @"_gestureRecognizers", @"allGestureRecognizers"]) {
            @try { id arr = [mgr valueForKey:k]; if ([arr isKindOfClass:[NSArray class]]) [all addObjectsFromArray:arr]; else if ([arr isKindOfClass:[NSSet class]]) [all addObjectsFromArray:[arr allObjects]]; } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    int found = 0;
    for (UIGestureRecognizer *g in all) {
        if (![g isKindOfClass:[UIGestureRecognizer class]] || !OPCCIsSystemGR(g)) continue;
        if (![gCoverGRs containsObject:g]) {
            [gCoverGRs addObject:g];
            OPCCLog([NSString stringWithFormat:@"GR %@ | delegate=%@ | enabled=%d", NSStringFromClass([g class]), g.delegate ? NSStringFromClass([g.delegate class]) : @"-", g.enabled]);
        }
        found++;
    }
    OPCCLog([NSString stringWithFormat:@"scan: окон=%lu всего recognizer=%lu системных=%d", (unsigned long)wins.count, (unsigned long)all.count, found]);
}
static void OPCCSuppressCover(BOOL on) { for (UIGestureRecognizer *g in gCoverGRs.allObjects) g.enabled = !on; }

static void OPCCOpenCC(void) {
    id cc = [objc_getClass("SBControlCenterController") sharedInstance];
    gAllowCC = YES;
    if ([cc respondsToSelector:@selector(presentAnimated:completion:)]) [cc presentAnimated:YES completion:nil];
    else if ([cc respondsToSelector:@selector(presentAnimated:)]) [cc presentAnimated:YES];
    OPCCLog(@"открываем CC");
    // если шторка уведомлений всё же успела стартовать — убираем её (только когда телефон разблокирован)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id lock = [objc_getClass("SBLockScreenManager") sharedInstance];
        BOOL locked = [lock respondsToSelector:@selector(isUILocked)] ? [lock isUILocked] : YES;
        id cs = [objc_getClass("SBCoverSheetPresentationManager") sharedInstance];
        if (!locked && [cs respondsToSelector:@selector(isPresented)] && [cs isPresented] && [cs respondsToSelector:@selector(setCoverSheetPresented:animated:withCompletion:)]) {
            [cs setCoverSheetPresented:NO animated:NO withCompletion:nil]; OPCCLog(@"закрыли шторку уведомлений");
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gAllowCC = NO; });
}

@interface OPCCStripView : UIView { CGPoint _start; BOOL _fired; }
@end
@implementation OPCCStripView
- (void)flash:(BOOL)on {
    if (![OPCCActions boolPref:@"debugStrip" def:YES]) { self.backgroundColor = [UIColor clearColor]; return; }
    self.backgroundColor = on ? [UIColor colorWithRed:1 green:0 blue:0 alpha:0.45] : [UIColor colorWithRed:1 green:0 blue:0 alpha:0.12];
}
- (void)touchesBegan:(NSSet *)ts withEvent:(UIEvent *)e {
    _start = [[ts anyObject] locationInView:nil]; _fired = NO;
    [self flash:YES]; OPCCLog([NSString stringWithFormat:@"touchesBegan x=%.0f y=%.0f", _start.x, _start.y]);
    OPCCScan(); OPCCSuppressCover(YES);                 // глушим шторку уведомлений, пока палец в нашей зоне
    [super touchesBegan:ts withEvent:e];
}
- (void)touchesMoved:(NSSet *)ts withEvent:(UIEvent *)e {
    [super touchesMoved:ts withEvent:e];
    CGPoint p = [[ts anyObject] locationInView:nil]; CGFloat dy = p.y - _start.y, dx = p.x - _start.x;
    if (!_fired && dy > 6 && dy > fabs(dx)) { _fired = YES; OPCCOpenCC(); }
}
- (void)finish { OPCCSuppressCover(NO); [self flash:NO]; }
- (void)touchesEnded:(NSSet *)ts withEvent:(UIEvent *)e { [super touchesEnded:ts withEvent:e]; [self performSelector:@selector(finish) withObject:nil afterDelay:0.3]; }
- (void)touchesCancelled:(NSSet *)ts withEvent:(UIEvent *)e {
    OPCCLog(@"touchesCancelled (система забрала касание)");
    CGPoint p = [[ts anyObject] locationInView:nil];
    if (!_fired && p.y - _start.y > 3) { _fired = YES; OPCCOpenCC(); }   // система отобрала касание — всё равно открываем свою шторку
    [super touchesCancelled:ts withEvent:e]; [self performSelector:@selector(finish) withObject:nil afterDelay:0.3];
}
@end

static void OPCCInstallStrip(void) {
    if (gStrip || ![OPCCActions boolPref:@"topRightGesture" def:YES]) return;
    CGRect sb = [UIScreen mainScreen].bounds;
    gStrip = [[UIWindow alloc] initWithFrame:CGRectMake(sb.size.width * 0.5, 0, sb.size.width * 0.5, 28)];
    gStrip.windowLevel = 100000; gStrip.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new];
    OPCCStripView *sv = [[OPCCStripView alloc] initWithFrame:gStrip.bounds]; vc.view = sv; [sv flash:NO]; gStrip.rootViewController = vc;
    gStrip.hidden = NO;
    OPCCLog(@"полоса жеста установлена");
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
