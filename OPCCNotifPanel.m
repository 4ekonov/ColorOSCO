#import "OPCCNotifications.h"
#import "OPCCActions.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

#define W_(w,a) [UIColor colorWithWhite:(w) alpha:(a)]

static UIImage *NSym(NSString *n, CGFloat pt, UIImageSymbolWeight w) {
    return [UIImage systemImageNamed:n withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:w]];
}
static void Hap(void) { [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred]; }
static NSString *RelTime(NSDate *d) {
    NSInteger s = (NSInteger)(-[d timeIntervalSinceNow]); if (s < 0) s = 0;
    if (s < 60) return @"сейчас";
    if (s < 3600) return [NSString stringWithFormat:@"%ld мин. назад", (long)(s / 60)];
    if (s < 86400) return [NSString stringWithFormat:@"%ld ч. назад", (long)(s / 3600)];
    return [NSString stringWithFormat:@"%ld дн. назад", (long)(s / 86400)];
}
static NSString *Plural(NSUInteger n, NSString *one, NSString *few, NSString *many) {
    NSUInteger a = n % 100, b = n % 10;
    if (a >= 11 && a <= 14) return many;
    if (b == 1) return one;
    if (b >= 2 && b <= 4) return few;
    return many;
}
static BOOL IsLocked(void) {
    id cls = (id)objc_getClass("SBLockScreenManager"); SEL si = NSSelectorFromString(@"sharedInstance");
    id l = [cls respondsToSelector:si] ? ((id (*)(id, SEL))objc_msgSend)(cls, si) : nil;
    SEL s = NSSelectorFromString(@"isUILocked");
    return [l respondsToSelector:s] ? ((BOOL (*)(id, SEL))objc_msgSend)(l, s) : NO;
}
static CFTimeInterval gStart;
__attribute__((constructor)) static void OPCCNotifInit(void) { gStart = CACurrentMediaTime(); }

static UIImage *AppIcon(NSString *b) {
    SEL s = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (!b.length || ![UIImage respondsToSelector:s]) return nil;
    @try { return ((UIImage *(*)(id, SEL, id, int, double))objc_msgSend)([UIImage class], s, b, 0, [UIScreen mainScreen].scale); } @catch (__unused NSException *e) { return nil; }
}

#pragma mark - кнопка с эффектом нажатия
@interface OPCCNBtn : UIControl @end
@implementation OPCCNBtn
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.12 : 0.45 delay:0 usingSpringWithDamping:h ? 1 : 0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ self.transform = h ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformIdentity; } completion:nil];
}
@end

@interface OPCCNScroll : UIScrollView @end
@implementation OPCCNScroll
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return YES; }
@end

#pragma mark - карточка уведомления
@interface OPCCNotifCard : UIControl <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<OPCCNotif *> *items;
@property (nonatomic) BOOL collapsedGroup, msgExpanded, headerOnly, lockMode;
@property (nonatomic) NSInteger chevMode;
@property (nonatomic, copy) void (^onTap)(OPCCNotifCard *);
@property (nonatomic, copy) void (^onBadge)(OPCCNotifCard *);
@property (nonatomic, copy) void (^onChevron)(OPCCNotifCard *);
@property (nonatomic, copy) void (^onAction)(OPCCNotifCard *, NSInteger);
- (instancetype)initWithItems:(NSArray *)items collapsed:(BOOL)g mode:(NSInteger)m;
- (CGFloat)layoutForWidth:(CGFloat)w u:(CGFloat)u;
@end

@implementation OPCCNotifCard {
    UIView *_body, *_peek1, *_peek2; UIImageView *_icon, *_chevIv; UILabel *_app, *_title, *_msg, *_badgeL; OPCCNBtn *_badge, *_chev;
    NSMutableArray *_pills;
}
- (instancetype)initWithItems:(NSArray *)items collapsed:(BOOL)g mode:(NSInteger)m {
    if ((self = [super initWithFrame:CGRectZero])) {
        _items = items; _collapsedGroup = g; _chevMode = m; _pills = [NSMutableArray array];
        _peek2 = [UIView new]; _peek2.backgroundColor = W_(0, 0.22); _peek2.userInteractionEnabled = NO; _peek2.hidden = !g; [self addSubview:_peek2];
        _peek1 = [UIView new]; _peek1.backgroundColor = W_(0, 0.30); _peek1.userInteractionEnabled = NO; _peek1.hidden = !g; [self addSubview:_peek1];
        _body = [UIView new]; _body.backgroundColor = W_(0, 0.40); _body.userInteractionEnabled = NO; _body.layer.cornerCurve = kCACornerCurveContinuous; [self addSubview:_body];
        _icon = [UIImageView new]; _icon.clipsToBounds = YES; _icon.contentMode = UIViewContentModeScaleAspectFill; _icon.backgroundColor = W_(1, 0.2); [_body addSubview:_icon];
        _app = [UILabel new]; _app.textColor = W_(1, 0.72); [_body addSubview:_app];
        _title = [UILabel new]; _title.textColor = UIColor.whiteColor; _title.numberOfLines = 1; [_body addSubview:_title];
        _msg = [UILabel new]; _msg.textColor = W_(1, 0.82); [_body addSubview:_msg];
        _badge = [OPCCNBtn new]; _badge.backgroundColor = W_(1, 0.20); _badge.hidden = YES; [self addSubview:_badge];
        _badgeL = [UILabel new]; _badgeL.textColor = UIColor.whiteColor; _badgeL.textAlignment = NSTextAlignmentCenter; _badgeL.userInteractionEnabled = NO; [_badge addSubview:_badgeL];
        _chev = [OPCCNBtn new]; _chev.backgroundColor = W_(1, 0.16); _chev.hidden = YES; [self addSubview:_chev];
        _chevIv = [UIImageView new]; _chevIv.contentMode = UIViewContentModeCenter; _chevIv.tintColor = UIColor.whiteColor; _chevIv.userInteractionEnabled = NO; [_chev addSubview:_chevIv];
        [_badge addTarget:self action:@selector(badgeTap) forControlEvents:UIControlEventTouchUpInside];
        [_chev addTarget:self action:@selector(chevTap) forControlEvents:UIControlEventTouchUpInside];
        UITapGestureRecognizer *tg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]; tg.delegate = self; [self addGestureRecognizer:tg];
    }
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return ![t.view isKindOfClass:[OPCCNBtn class]]; }   // кнопки внутри карточки обрабатывают нажатия сами
- (void)tap { if (_onTap) _onTap(self); }
- (void)badgeTap { if (_onBadge) _onBadge(self); }
- (void)chevTap { if (_onChevron) _onChevron(self); }
- (void)pillTap:(OPCCNBtn *)b { if (_onAction) _onAction(self, b.tag); }
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.12 : 0.4 delay:0 usingSpringWithDamping:h ? 1 : 0.6 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ self->_body.transform = h ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity; } completion:nil];
}
- (CGFloat)heightOf:(NSString *)t font:(UIFont *)f width:(CGFloat)w {
    if (!t.length) return 0;
    return ceil([t boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: f} context:nil].size.height);
}
- (CGFloat)layoutForWidth:(CGFloat)w u:(CGFloat)u {
    OPCCNotif *n = _items.firstObject; CGFloat pad = 12*u, ic = 16*u, tw = w - 2*pad;
    _body.layer.cornerRadius = 20*u;
    _icon.image = AppIcon(n.bundleID); _icon.layer.cornerRadius = 4*u; _icon.frame = CGRectMake(pad, pad, ic, ic);
    for (UIView *p in _pills) [p removeFromSuperview]; [_pills removeAllObjects];
    _app.font = [UIFont systemFontOfSize:11*u];

    // Шапка раскрытой группы: «Приложение · N уведомлений ˄»
    if (_headerOnly) {
        _app.text = [NSString stringWithFormat:@"%@ · %lu %@", n.appName, (unsigned long)_items.count, Plural(_items.count, @"уведомление", @"уведомления", @"уведомлений")];
        _title.hidden = _msg.hidden = YES; _badge.hidden = YES; _peek1.hidden = _peek2.hidden = YES;
        CGFloat d = 20*u; _chev.hidden = NO; _chev.frame = CGRectMake(w - pad - d, pad - 2*u, d, d); _chev.layer.cornerRadius = d/2; _chevIv.frame = _chev.bounds;
        _chevIv.image = [NSym(@"chevron.up", 9*u, UIImageSymbolWeightBold) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _app.frame = CGRectMake(pad + ic + 6*u, pad, w - 2*pad - ic - 12*u - d, ic);
        CGFloat hh = pad * 2 + ic; _body.transform = CGAffineTransformIdentity; _body.frame = CGRectMake(0, 0, w, hh); return hh;
    }
    _title.hidden = _msg.hidden = NO; _peek1.hidden = _peek2.hidden = !_collapsedGroup;
    _app.text = [NSString stringWithFormat:@"%@ · %@", n.appName, RelTime(n.date)];
    CGFloat right = 0;
    if (_collapsedGroup) {
        _badgeL.font = [UIFont systemFontOfSize:11*u weight:UIFontWeightMedium]; _badgeL.text = [NSString stringWithFormat:@"%lu", (unsigned long)_items.count];
        CGFloat bw = MAX(24*u, [_badgeL.text sizeWithAttributes:@{NSFontAttributeName: _badgeL.font}].width + 14*u), bh = 18*u;
        _badge.hidden = NO; _badge.frame = CGRectMake(w - pad - bw, pad - 1*u, bw, bh); _badge.layer.cornerRadius = bh/2; _badgeL.frame = _badge.bounds; right = bw + 6*u;
        _chev.hidden = YES;
    } else {
        _badge.hidden = YES;
        UIFont *mf0 = [UIFont systemFontOfSize:12*u];
        BOOL needs = _chevMode == 2 || (!_lockMode && n.actions.count > 0) || [self heightOf:n.message font:mf0 width:tw] > mf0.lineHeight * 2 + 1;
        _chev.hidden = !needs;
        if (needs) {
            CGFloat d = 20*u; _chev.frame = CGRectMake(w - pad - d, pad - 2*u, d, d); _chev.layer.cornerRadius = d/2; _chevIv.frame = _chev.bounds;
            BOOL up = (_chevMode == 2) || _msgExpanded;
            _chevIv.image = [NSym(up ? @"chevron.up" : @"chevron.down", 9*u, UIImageSymbolWeightBold) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; right = d + 6*u;
        }
    }
    _app.frame = CGRectMake(pad + ic + 6*u, pad, w - 2*pad - ic - 6*u - right, ic);
    UIFont *tf = [UIFont boldSystemFontOfSize:13*u], *mf = [UIFont systemFontOfSize:12*u];
    _title.font = tf; _title.text = n.title; _msg.font = mf; _msg.text = n.message;
    CGFloat y = pad + ic + 6*u, th = n.title.length ? ceil(tf.lineHeight) : 0;
    _title.frame = CGRectMake(pad, y, tw, th); y += th + (th ? 2*u : 0);
    CGFloat full = [self heightOf:n.message font:mf width:tw], two = ceil(mf.lineHeight * 2);
    BOOL expanded = _msgExpanded && !_collapsedGroup;
    _msg.numberOfLines = expanded ? 0 : 2;
    CGFloat mh = expanded ? full : MIN(full, two);
    _msg.frame = CGRectMake(pad, y, tw, mh); y += mh;

    // Кнопки действий (как в Android): «Открыть» + действия уведомления
    if (expanded && !_lockMode) {
        NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Открыть"];
        for (id a in n.actions) { NSString *tt = nil; @try { tt = [a valueForKey:@"title"]; } @catch (__unused NSException *e) {} if ([tt isKindOfClass:[NSString class]] && tt.length) [titles addObject:tt]; }
        y += 10*u; CGFloat x = pad, ph = 28*u; UIFont *pf = [UIFont systemFontOfSize:11.5*u weight:UIFontWeightMedium];
        for (NSUInteger i = 0; i < titles.count; i++) {
            CGFloat pw = ceil([titles[i] sizeWithAttributes:@{NSFontAttributeName: pf}].width) + 24*u;
            if (x + pw > w - pad) break;
            OPCCNBtn *b = [OPCCNBtn new]; b.frame = CGRectMake(x, y, pw, ph); b.layer.cornerRadius = ph/2; b.tag = (NSInteger)i;
            if (i == 0) { b.backgroundColor = W_(0, 0.12); b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.78 alpha:0.9].CGColor; }
            else b.backgroundColor = W_(1, 0.16);
            UILabel *l = [[UILabel alloc] initWithFrame:b.bounds]; l.text = titles[i]; l.font = pf; l.textColor = UIColor.whiteColor; l.textAlignment = NSTextAlignmentCenter; l.userInteractionEnabled = NO; [b addSubview:l];
            [b addTarget:self action:@selector(pillTap:) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; [_pills addObject:b];
            x += pw + 8*u;
        }
        y += ph;
    }
    y += pad;
    _body.transform = CGAffineTransformIdentity; _body.frame = CGRectMake(0, 0, w, y);
    if (_collapsedGroup) {
        _peek1.frame = CGRectMake(7*u, y - 10*u, w - 14*u, 16*u); _peek1.layer.cornerRadius = 16*u;
        _peek2.frame = CGRectMake(14*u, y - 6*u, w - 28*u, 16*u); _peek2.layer.cornerRadius = 16*u;
        return y + 10*u;
    }
    return y;
}
@end

#pragma mark - главный вид панели (и список на экране блокировки)
@interface OPCCNotifView : UIView <UIGestureRecognizerDelegate>
- (instancetype)initWithFrame:(CGRect)f lock:(BOOL)lock;
@property (nonatomic) BOOL startMasked;
- (void)setMasked:(BOOL)m animated:(BOOL)a;
- (void)reload;
- (void)present;
- (void)closeAnimated:(void (^)(void))done;
@end

@implementation OPCCNotifView {
    UIView *_shade, *_bg, *_mask; UIScrollView *_scroll; UILabel *_dateL, *_emptyL; OPCCNBtn *_bell, *_x;
    NSMutableArray<OPCCNotifCard *> *_cards; NSMutableSet *_expGroups, *_expMsgs;
    UIPanGestureRecognizer *_panGR; UITapGestureRecognizer *_tapGR;
    BOOL _closing, _panActive, _suppress, _lock; NSInteger _gen; CGFloat _u;
}
- (instancetype)initWithFrame:(CGRect)f { return [self initWithFrame:f lock:NO]; }
- (instancetype)initWithFrame:(CGRect)f lock:(BOOL)lock {
    if ((self = [super initWithFrame:f])) {
        _lock = lock;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _cards = [NSMutableArray array]; _expGroups = [NSMutableSet set]; _expMsgs = [NSMutableSet set]; _u = 1.2;
        _shade = [[UIView alloc] initWithFrame:self.bounds]; _shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self addSubview:_shade];
        UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
        UIView *dim = [UIView new]; dim.backgroundColor = W_(0, 0.38); [fx.contentView addSubview:dim]; _bg = fx; [_shade addSubview:_bg];
        _mask = [UIView new]; _mask.backgroundColor = UIColor.blackColor; _mask.alpha = 0; _mask.userInteractionEnabled = NO; [_shade addSubview:_mask];
        _scroll = [OPCCNScroll new]; _scroll.canCancelContentTouches = YES; _scroll.showsVerticalScrollIndicator = NO; _scroll.bounces = NO; _scroll.delaysContentTouches = NO; _scroll.clipsToBounds = lock; [_shade addSubview:_scroll];
        _dateL = [UILabel new]; _dateL.textColor = UIColor.whiteColor; [_shade addSubview:_dateL];
        _emptyL = [UILabel new]; _emptyL.textColor = W_(1, 0.6); _emptyL.numberOfLines = 0; _emptyL.textAlignment = NSTextAlignmentCenter; _emptyL.font = [UIFont systemFontOfSize:12]; _emptyL.hidden = YES; [_shade addSubview:_emptyL];
        _bell = [OPCCNBtn new]; UIImageView *bi = [[UIImageView alloc] initWithImage:[NSym(@"bell", 17, UIImageSymbolWeightRegular) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        bi.tintColor = UIColor.whiteColor; bi.contentMode = UIViewContentModeCenter; bi.tag = 9; bi.userInteractionEnabled = NO; [_bell addSubview:bi]; [_shade addSubview:_bell];
        [_bell addTarget:self action:@selector(bellTap) forControlEvents:UIControlEventTouchUpInside];
        [_bell addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(bellLong:)]];
        _x = [OPCCNBtn new]; _x.backgroundColor = W_(0, 0.42);
        UIImageView *xi = [[UIImageView alloc] initWithImage:[NSym(@"xmark", 15, UIImageSymbolWeightMedium) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        xi.tintColor = UIColor.whiteColor; xi.contentMode = UIViewContentModeCenter; xi.tag = 9; xi.userInteractionEnabled = NO; [_x addSubview:xi]; [_shade addSubview:_x];
        [_x addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
        if (lock) { _bg.hidden = _dateL.hidden = _bell.hidden = _x.hidden = YES; }
        else {
            UITapGestureRecognizer *tp = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(emptyTap)]; tp.delegate = self; tp.cancelsTouchesInView = NO; [self addGestureRecognizer:tp]; _tapGR = tp;
            UIPanGestureRecognizer *pp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panClose:)]; pp.delegate = self; pp.cancelsTouchesInView = NO; [self addGestureRecognizer:pp]; _panGR = pp;
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeChanged) name:OPCCNotifsChanged object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)storeChanged { if (!_suppress && !_closing && !_panActive) [self reload]; }

#pragma mark карточки
- (OPCCNotifCard *)makeCard:(NSArray *)items collapsed:(BOOL)g mode:(NSInteger)m header:(BOOL)hd {
    OPCCNotifCard *c = [[OPCCNotifCard alloc] initWithItems:items collapsed:g mode:m];
    c.headerOnly = hd; c.lockMode = _lock;
    c.msgExpanded = [_expMsgs containsObject:((OPCCNotif *)items.firstObject).ident];
    __weak OPCCNotifView *ws = self;
    c.onTap = ^(OPCCNotifCard *k) { [ws cardTap:k]; };
    c.onBadge = ^(OPCCNotifCard *k) { [ws expandGroup:k]; };
    c.onChevron = ^(OPCCNotifCard *k) { [ws chevron:k]; };
    c.onAction = ^(OPCCNotifCard *k, NSInteger i) { [ws cardAction:k idx:i]; };
    if (!hd) { UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(cardPan:)]; p.delegate = self; [c addGestureRecognizer:p]; }
    return c;
}
- (void)reload {
    for (UIView *c in _cards) [c removeFromSuperview]; [_cards removeAllObjects];
    NSMutableArray *order = [NSMutableArray array]; NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (OPCCNotif *n in [OPCCNotifStore all]) { NSString *b = n.bundleID ?: @""; if (!map[b]) { map[b] = [NSMutableArray array]; [order addObject:b]; } [map[b] addObject:n]; }
    for (NSString *b in order) {
        NSArray *items = map[b];
        if (items.count > 1 && ![_expGroups containsObject:b]) [_cards addObject:[self makeCard:items collapsed:YES mode:0 header:NO]];
        else {
            if (items.count > 1) [_cards addObject:[self makeCard:items collapsed:NO mode:0 header:YES]];   // шапка группы со «сворачивателем»
            for (NSUInteger i = 0; i < items.count; i++) [_cards addObject:[self makeCard:@[items[i]] collapsed:NO mode:0 header:NO]];
        }
    }
    for (UIView *c in _cards) [_scroll addSubview:c];
    _emptyL.hidden = _lock || _cards.count > 0 || ![OPCCActions boolPref:@"debugStrip" def:YES];
    _emptyL.text = [NSString stringWithFormat:@"Уведомлений нет (захвачено: %lu)\nЕсли они есть — пришлите OPCC_notifs.txt\nДолгое нажатие на колокольчик — тестовые уведомления", (unsigned long)[OPCCNotifStore all].count];
    [self setNeedsLayout];
}
- (void)relayoutAnimated {
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ [self setNeedsLayout]; [self layoutIfNeeded]; } completion:nil];
}
- (void)openNotif:(OPCCNotif *)n {
    Hap(); [OPCCNotifPanel hide];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [OPCCNotifStore openNotif:n]; [OPCCNotifStore clear:n]; });
}
- (void)cardTap:(OPCCNotifCard *)c {
    Hap();
    if (c.collapsedGroup) { [self expandGroup:c]; return; }
    if (c.headerOnly) { [self chevron:c]; return; }
    OPCCNotif *n = c.items.firstObject;
    if (_lock) { [self chevron:c]; return; }       // на экране блокировки тап раскрывает, открытие требует разблокировки
    [self openNotif:n];
}
- (void)cardAction:(OPCCNotifCard *)c idx:(NSInteger)i {
    OPCCNotif *n = c.items.firstObject;
    if (i == 0) { [self openNotif:n]; return; }
    Hap(); NSInteger k = i - 1; if (k >= 0 && k < (NSInteger)n.actions.count) [OPCCNotifStore runAction:n.actions[k]];
}
// Пересборка списка со снимком старого состояния: старое плавно растворяется, новое проявляется — шторка больше не «прыгает»
- (void)animatedReload:(void (^)(void))change {
    UIView *snap = [_scroll snapshotViewAfterScreenUpdates:NO];
    if (snap) { snap.frame = _scroll.frame; snap.userInteractionEnabled = NO; [_shade insertSubview:snap aboveSubview:_scroll]; }
    change(); [self layoutIfNeeded];
    for (UIView *c in _cards) c.alpha = 0;
    [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ snap.alpha = 0; for (UIView *c in self->_cards) c.alpha = 1; } completion:^(BOOL f) { [snap removeFromSuperview]; }];
}
- (void)expandGroup:(OPCCNotifCard *)c {
    Hap(); NSString *b = ((OPCCNotif *)c.items.firstObject).bundleID ?: @"";
    [self animatedReload:^{ [self->_expGroups addObject:b]; [self reload]; }];
}
- (void)chevron:(OPCCNotifCard *)c {
    Hap(); OPCCNotif *n = c.items.firstObject;
    if (c.headerOnly || c.chevMode == 2) { NSString *b = n.bundleID ?: @""; [self animatedReload:^{ [self->_expGroups removeObject:b]; [self reload]; }]; return; }
    if ([_expMsgs containsObject:n.ident]) [_expMsgs removeObject:n.ident]; else [_expMsgs addObject:n.ident];
    c.msgExpanded = [_expMsgs containsObject:n.ident]; [self relayoutAnimated];
}
// Смахивание карточки в сторону
- (void)cardPan:(UIPanGestureRecognizer *)g {
    OPCCNotifCard *c = (OPCCNotifCard *)g.view; CGFloat tx = [g translationInView:self].x, w = MAX(1, c.bounds.size.width);
    if (g.state == UIGestureRecognizerStateChanged) { c.transform = CGAffineTransformMakeTranslation(tx, 0); c.alpha = 1 - MIN(1, fabs(tx) / w) * 0.8; }
    else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        CGFloat vx = [g velocityInView:self].x;
        if (g.state == UIGestureRecognizerStateEnded && (fabs(tx) > w * 0.35 || fabs(vx) > 900)) {
            CGFloat dir = (tx != 0 ? tx : vx) > 0 ? 1 : -1; _suppress = YES;
            [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ c.transform = CGAffineTransformMakeTranslation(dir * (w + 40), 0); c.alpha = 0; } completion:^(BOOL f) {
                [c removeFromSuperview]; [self->_cards removeObject:c];
                for (OPCCNotif *n in c.items) [OPCCNotifStore clear:n];
                [self relayoutAnimated];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self->_suppress = NO; });
            }];
        } else [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{ c.transform = CGAffineTransformIdentity; c.alpha = 1; } completion:nil];
    }
}
- (void)bellLong:(UILongPressGestureRecognizer *)g {      // долгое нажатие на колокольчик — тестовые уведомления вкл/выкл
    if (g.state != UIGestureRecognizerStateBegan) return;
    BOOL now = ![OPCCNotifStore testMode]; Hap(); [OPCCActions setBoolPref:@"testNotifs" value:now]; [OPCCNotifStore setTestMode:now];
}
- (void)bellTap { Hap(); [OPCCNotifPanel hide]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NSURL *u = [NSURL URLWithString:@"App-prefs:NOTIFICATIONS_ID"]; if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil]; }); }
- (void)clearAll {
    Hap(); if (!_cards.count) { [OPCCNotifPanel hide]; return; }
    _suppress = YES; CGFloat u = _u; NSUInteger i = 0;
    for (OPCCNotifCard *c in _cards) {
        [UIView animateWithDuration:0.28 delay:0.035 * MIN(i, 8) options:UIViewAnimationOptionCurveEaseIn animations:^{ c.transform = CGAffineTransformMakeTranslation(0, -30 * u); c.alpha = 0; } completion:nil]; i++;
    }
    [UIView animateWithDuration:0.25 animations:^{ self->_x.alpha = 0; self->_x.transform = CGAffineTransformMakeScale(0.5, 0.5); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [OPCCNotifStore clearAll]; [OPCCNotifPanel hide]; });
}

#pragma mark жесты закрытия
- (void)emptyTap { [OPCCNotifPanel hide]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (_closing) return NO;
    UIView *v = t.view;
    if (g == _tapGR) return v == self || v == _shade || v == _bg || v == _scroll || v == ((UIVisualEffectView *)_bg).contentView;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return [super gestureRecognizerShouldBegin:g];
    CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
    if (_panGR && g == _panGR) {
        if (_closing || !(v.y < 0 && fabs(v.y) > fabs(v.x) * 1.3)) return NO;
        CGFloat maxOff = _scroll.contentSize.height - _scroll.bounds.size.height;
        if (_scroll.scrollEnabled && maxOff > 1 && _scroll.contentOffset.y < maxOff - 2) return NO;
        return YES;
    }
    return fabs(v.x) > fabs(v.y) * 1.2;      // смахивание карточек — только горизонтальное
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)panClose:(UIPanGestureRecognizer *)g {
    CGFloat H = MAX(1, self.bounds.size.height); CGPoint t = [g translationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) { _panActive = YES; [_shade.layer removeAllAnimations]; }
    else if (g.state == UIGestureRecognizerStateChanged) {
        if (!_panActive || _closing) return;
        CGFloat ty = MIN(0, t.y); _shade.transform = CGAffineTransformMakeTranslation(0, ty); _shade.alpha = 1 - MIN(1, -ty / H) * 0.7;
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        if (!_panActive) return; _panActive = NO;
        CGFloat vy = [g velocityInView:self].y, ty = MIN(0, t.y);
        if (g.state == UIGestureRecognizerStateEnded && (ty < -H * 0.12 || vy < -700)) [OPCCNotifPanel hide];
        else [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self->_shade.transform = CGAffineTransformIdentity; self->_shade.alpha = 1; } completion:nil];
    }
}

#pragma mark раскладка
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, u = W / 316.; _u = u;
    CGFloat m = 12*u, cw = W - 2*m;
    if (_lock) {      // список на экране блокировки: только карточки
        _scroll.frame = self.bounds; CGFloat y = 0;
        for (OPCCNotifCard *c in _cards) {
            CGFloat h = [c layoutForWidth:cw u:u];
            if (CGAffineTransformIsIdentity(c.transform)) c.frame = CGRectMake(m, y, cw, h); else { c.bounds = CGRectMake(0, 0, cw, h); c.center = CGPointMake(m + cw/2, y + h/2); }
            y += h + 6*u;
        }
        _scroll.contentSize = CGSizeMake(W, MAX(H, y)); _scroll.scrollEnabled = y > H + 6;
        if (!_scroll.scrollEnabled && _scroll.contentOffset.y != 0) _scroll.contentOffset = CGPointZero;
        return;
    }
    CGFloat top = MAX(self.safeAreaInsets.top, 20), cy = top + 26*u + [OPCCActions topOffset];
    CGRect full = CGRectMake(0, 0, W, H); _bg.frame = full; _mask.frame = full; ((UIVisualEffectView *)_bg).contentView.subviews.firstObject.frame = full;
    _dateL.frame = CGRectMake(m + 4*u, cy - 10*u, 220*u, 20*u);
    _bell.frame = CGRectMake(W - m - 4*u - 30*u, cy - 15*u, 30*u, 30*u); [_bell viewWithTag:9].frame = _bell.bounds;
    CGFloat sTop = cy + 22*u, sH = H - sTop;
    _scroll.frame = CGRectMake(0, sTop, W, sH);
    CGFloat y = 0;
    for (OPCCNotifCard *c in _cards) {
        CGFloat h = [c layoutForWidth:cw u:u];
        if (CGAffineTransformIsIdentity(c.transform)) c.frame = CGRectMake(m, y, cw, h); else { c.bounds = CGRectMake(0, 0, cw, h); c.center = CGPointMake(m + cw/2, y + h/2); }
        y += h + 6*u;
    }
    CGFloat xD = 38*u, xBottom = MAX(self.safeAreaInsets.bottom, 0) + 22*u;
    CGFloat contentH = y + (_cards.count ? xD + xBottom + 8*u : 0);
    _scroll.contentSize = CGSizeMake(W, MAX(sH, contentH));
    _scroll.scrollEnabled = contentH > sH + 6;          // прокрутки нет, пока всё помещается
    if (!_scroll.scrollEnabled && _scroll.contentOffset.y != 0) _scroll.contentOffset = CGPointZero;
    _x.bounds = CGRectMake(0, 0, xD, xD); _x.layer.cornerRadius = xD/2; _x.center = CGPointMake(W/2, H - xBottom - xD/2); [_x viewWithTag:9].frame = _x.bounds;
    _x.hidden = (_cards.count == 0);
    _emptyL.frame = CGRectMake(20*u, H/2 - 30*u, W - 40*u, 60*u);
    NSDateFormatter *tf = [NSDateFormatter new]; tf.dateFormat = @"HH:mm";
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"d MMM, EE"; df.locale = [NSLocale localeWithLocaleIdentifier:@"ru_RU"];
    NSString *ts = [tf stringFromDate:[NSDate date]], *ds = [df stringFromDate:[NSDate date]];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@   %@", ts, ds] attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13*u weight:UIFontWeightRegular]}];
    [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:13*u weight:UIFontWeightSemibold] range:NSMakeRange(0, ts.length)];
    _dateL.attributedText = as;
}

#pragma mark анимации
- (void)setMasked:(BOOL)m animated:(BOOL)a {
    void (^b)(void) = ^{ self->_mask.alpha = m ? 0.94 : 0; };
    a ? [UIView animateWithDuration:0.3 animations:b] : b();
}
- (void)present {
    _mask.alpha = _startMasked ? 0.94 : 0; _startMasked = NO;
    _closing = NO; _panActive = NO; _suppress = NO; _gen++; [_expGroups removeAllObjects]; [_expMsgs removeAllObjects];
    [self reload]; [self setNeedsLayout]; [self layoutIfNeeded];
    CGFloat H = self.bounds.size.height, u = _u;
    [_shade.layer removeAllAnimations]; _shade.alpha = 0; _shade.transform = CGAffineTransformMakeTranslation(0, -H * 0.6);
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self->_shade.alpha = 1; self->_shade.transform = CGAffineTransformIdentity; } completion:nil];
    [_cards enumerateObjectsUsingBlock:^(OPCCNotifCard *c, NSUInteger i, BOOL *s) {
        if (i > 7) return; c.alpha = 0; c.transform = CGAffineTransformMakeTranslation(0, -16 * u);
        [UIView animateWithDuration:0.55 delay:0.05 + 0.035 * i usingSpringWithDamping:0.8 initialSpringVelocity:0.2 options:UIViewAnimationOptionAllowUserInteraction animations:^{ c.alpha = 1; c.transform = CGAffineTransformIdentity; } completion:nil];
    }];
    _x.alpha = 0; _x.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [UIView animateWithDuration:0.5 delay:0.2 usingSpringWithDamping:0.7 initialSpringVelocity:0.3 options:0 animations:^{ self->_x.alpha = 1; self->_x.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)closeAnimated:(void (^)(void))done {
    if (_closing) return; _closing = YES; NSInteger gen = _gen; CGFloat H = self.bounds.size.height;
    [UIView animateWithDuration:0.34 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_shade.transform = CGAffineTransformMakeTranslation(0, -H * 0.6); self->_shade.alpha = 0; } completion:^(BOOL f) { if (f && gen == self->_gen && done) done(); }];
}
@end

#pragma mark - панель и список на экране блокировки
@implementation OPCCNotifPanel
static UIWindow *gWin; static OPCCNotifView *gView; static BOOL gShown, gMaskedStart; static void (^gOnHide)(void);
static OPCCNotifView *gLockView;
+ (BOOL)isShown { return gShown; }
+ (void)setOnHide:(void (^)(void))b { gOnHide = [b copy]; }
+ (void)show {
    if (gShown) return; gShown = YES;
    if (!gWin) {
        CGRect b = [UIScreen mainScreen].bounds;
        gWin = [[UIWindow alloc] initWithFrame:b]; gWin.windowLevel = 3000;   // гарантированно выше приложений и рабочего стола
        gWin.backgroundColor = [UIColor clearColor];
        UIViewController *vc = [UIViewController new]; gView = [[OPCCNotifView alloc] initWithFrame:b]; vc.view = gView; gWin.rootViewController = vc;
    }
    gView.startMasked = gMaskedStart; gMaskedStart = NO;
    gWin.hidden = NO; [gView present];
}
+ (void)showMasked { if (gShown) return; gMaskedStart = YES; [self show]; }     // показать с непрозрачной подложкой, пока уходит стандартная шторка
+ (void)unmask { [gView setMasked:NO animated:YES]; }
+ (void)hide {
    if (!gShown) return; gShown = NO;
    [gView closeAnimated:^{ gWin.hidden = YES; if (gOnHide) gOnHide(); }];
}
+ (BOOL)lockOverlayVisible { return gLockView.superview != nil; }
+ (void)attachLockListTo:(UIView *)host above:(UIView *)ref {
    if (!host.window) return;
    if (!gLockView) gLockView = [[OPCCNotifView alloc] initWithFrame:CGRectZero lock:YES];
    CGRect b = [UIScreen mainScreen].bounds, wf = CGRectMake(0, b.size.height * 0.30, b.size.width, b.size.height * 0.50);
    CGRect f = [host convertRect:wf fromView:nil];
    BOOL fresh = gLockView.superview != host;
    if (fresh) { [gLockView removeFromSuperview]; [host insertSubview:gLockView aboveSubview:ref]; }
    if (!CGRectEqualToRect(gLockView.frame, f)) gLockView.frame = f;
    gLockView.hidden = NO; gLockView.alpha = 1;
    if (fresh) [gLockView reload];
}
+ (void)detachLockList { if (gLockView.superview) [gLockView removeFromSuperview]; }
@end

#pragma mark - всплывающий баннер-капсула
@interface OPCCBannerRoot : UIView @end
@implementation OPCCBannerRoot
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { UIView *v = [super hitTest:p withEvent:e]; return v == self ? nil : v; }   // всё, кроме самой капсулы, пропускаем вниз
@end
@interface OPCCBannerWindow : UIWindow @end
@implementation OPCCBannerWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { UIView *v = [super hitTest:p withEvent:e]; return (v == self || v == self.rootViewController.view) ? nil : v; }
@end

@implementation OPCCBanner
static OPCCBannerWindow *gBWin; static OPCCNotifCard *gBCard; static NSInteger gBGen;
+ (BOOL)isVisible { return gBWin && !gBWin.hidden && gBCard; }
+ (void)show:(OPCCNotif *)n { [self show:n force:NO]; }
+ (void)dismissAnimated:(BOOL)a {
    OPCCNotifCard *c = gBCard; if (!c) return; gBCard = nil; NSInteger g = ++gBGen;
    CGFloat h = c.frame.size.height + 60;
    [UIView animateWithDuration:a ? 0.3 : 0 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ c.transform = CGAffineTransformMakeTranslation(0, -h); c.alpha = 0; } completion:^(BOOL f) {
        [c removeFromSuperview]; if (g == gBGen && !gBCard) gBWin.hidden = YES; }];
}
+ (void)show:(OPCCNotif *)n force:(BOOL)force {
    if (!n || [OPCCNotifPanel isShown] || IsLocked()) return;
    if (![OPCCActions boolPref:@"customNotifications" def:YES] || ![OPCCActions boolPref:@"customBanners" def:YES]) return;
    if (!force && (CACurrentMediaTime() - gStart < 15 || -[n.date timeIntervalSinceNow] > 20)) return;     // не показываем «историю», которая загружается при старте
    if (!gBWin) {
        CGRect b = [UIScreen mainScreen].bounds;
        gBWin = [[OPCCBannerWindow alloc] initWithFrame:b]; gBWin.windowLevel = 99500; gBWin.backgroundColor = [UIColor clearColor];
        UIViewController *vc = [UIViewController new]; vc.view = [[OPCCBannerRoot alloc] initWithFrame:b]; vc.view.backgroundColor = [UIColor clearColor]; gBWin.rootViewController = vc;
    }
    if (gBCard) [self dismissAnimated:NO];
    NSInteger gen = ++gBGen;
    UIView *root = gBWin.rootViewController.view; CGFloat W = root.bounds.size.width, u = W / 316.;
    OPCCNotifCard *c = [[OPCCNotifCard alloc] initWithItems:@[n] collapsed:NO mode:0]; c.lockMode = YES;
    CGFloat w = W - 24*u, h = [c layoutForWidth:w u:u], top = MAX(gBWin.safeAreaInsets.top, 20) + 4*u;
    c.frame = CGRectMake(12*u, top, w, h); c.layer.shadowColor = UIColor.blackColor.CGColor; c.layer.shadowOpacity = 0.35; c.layer.shadowRadius = 14; c.layer.shadowOffset = CGSizeMake(0, 6);
    [root addSubview:c]; gBCard = c; gBWin.hidden = NO;
    __weak OPCCNotifCard *wc = c;
    c.onTap = ^(OPCCNotifCard *k) { Hap(); [OPCCBanner dismissAnimated:YES]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [OPCCNotifStore openNotif:n]; [OPCCNotifStore clear:n]; }); };
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[OPCCBanner class] action:@selector(bannerPan:)]; [c addGestureRecognizer:pan];
    c.transform = CGAffineTransformMakeTranslation(0, -(h + top + 20)); c.alpha = 1;
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{ wc.transform = CGAffineTransformIdentity; } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gen == gBGen && gBCard == wc) [OPCCBanner dismissAnimated:YES]; });
}
+ (void)bannerPan:(UIPanGestureRecognizer *)g {
    OPCCNotifCard *c = (OPCCNotifCard *)g.view; CGFloat ty = MIN(0, [g translationInView:c.superview].y);
    if (g.state == UIGestureRecognizerStateChanged) c.transform = CGAffineTransformMakeTranslation(0, ty);
    else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        if (ty < -20 || [g velocityInView:c.superview].y < -300) [self dismissAnimated:YES];
        else [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{ c.transform = CGAffineTransformIdentity; } completion:nil];
    }
}
@end
