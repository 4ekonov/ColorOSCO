#import "OPCCView.h"
#import "OPCCActions.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

#define RGB(r,g,b) [UIColor colorWithRed:(r)/255. green:(g)/255. blue:(b)/255. alpha:1]
static UIColor *BG(void)    { return RGB(43,43,43); }
static UIColor *Tile(void)  { return RGB(74,74,74); }
static UIColor *Knob(void)  { return RGB(96,96,96); }
static UIColor *Blue(void)  { return RGB(47,107,255); }
static UIColor *Light(void) { return RGB(236,236,236); }

static UIImage *Sym(NSString *n, CGFloat pt) {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:n withConfiguration:c];
}
static UIImage *BTImage(CGFloat s) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    return [[r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        CGFloat pts[6][2] = {{.27,.32},{.73,.68},{.5,.88},{.5,.12},{.73,.32},{.27,.68}};
        for (int i = 0; i < 6; i++) { CGPoint q = CGPointMake(pts[i][0]*s, pts[i][1]*s); i ? [p addLineToPoint:q] : [p moveToPoint:q]; }
        p.lineWidth = s * .09; p.lineJoinStyle = kCGLineJoinRound; p.lineCapStyle = kCGLineCapRound;
        [UIColor.whiteColor setStroke]; [p stroke];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
static void Haptic(void) { [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred]; }
static void After(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s*NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

#pragma mark - MediaRemote
typedef void (^MRInfo)(CFDictionaryRef);
static void (*MRGetInfo)(dispatch_queue_t, MRInfo);
static void (*MRGetPlaying)(dispatch_queue_t, void (^)(Boolean));
static Boolean (*MRSend)(int, id);
static void (*MRReg)(dispatch_queue_t);
static void MRInit(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        MRGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRGetPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRSend = dlsym(h, "MRMediaRemoteSendCommand");
        MRReg = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (MRReg) MRReg(dispatch_get_main_queue());
    });
}

#pragma mark - нажимаемый контрол
@interface OPCCPress : UIControl
@property (nonatomic, weak) UIView *pressView;
@property (nonatomic) CGFloat pressScale;
@end
@implementation OPCCPress
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) _pressScale = 0.93; return self; }
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    UIView *v = _pressView ?: self;
    [UIView animateWithDuration:h ? 0.14 : 0.5 delay:0 usingSpringWithDamping:h ? 1 : 0.5 initialSpringVelocity:0
        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ v.transform = h ? CGAffineTransformMakeScale(self.pressScale, self.pressScale) : CGAffineTransformIdentity; } completion:nil];
}
@end

#pragma mark - круглая кнопка (обычная / режим правки / лоток)
@interface OPCCRound : OPCCPress
@property (nonatomic, copy) NSString *ident;
@property (nonatomic) NSInteger mode;          // 0 обычный, 1 правка, 2 лоток «добавить»
@property (nonatomic) CGFloat dScale;
@property (nonatomic) BOOL showLabels;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) OPCCPress *badge;
@property (nonatomic, strong) UIImageView *badgeIcon;
@property (nonatomic, strong) UILongPressGestureRecognizer *dragGR;
@property (nonatomic, copy) void (^actionBlock)(OPCCRound *);
@property (nonatomic, copy) NSString *sym; @property (nonatomic, strong) UIColor *iconColor;
- (void)refresh;
- (void)setMode:(NSInteger)m animated:(BOOL)a;
@end
@implementation OPCCRound
- (instancetype)initWithID:(NSString *)i {
    if ((self = [super initWithFrame:CGRectZero])) {
        _ident = i; _dScale = 1; _showLabels = YES;
        _circle = [UIView new]; _circle.userInteractionEnabled = NO; [self addSubview:_circle];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; [_circle addSubview:_icon];
        _label = [UILabel new]; _label.textAlignment = NSTextAlignmentCenter; _label.numberOfLines = 2;
        _label.textColor = RGB(214,214,214); _label.text = [OPCCActions titleFor:i]; [self addSubview:_label];
        self.pressView = _circle;
        _badge = [OPCCPress new]; _badge.alpha = 0; _badge.layer.masksToBounds = YES; _badge.pressScale = 0.8;
        _badgeIcon = [UIImageView new]; _badgeIcon.contentMode = UIViewContentModeCenter; _badgeIcon.tintColor = UIColor.whiteColor; _badgeIcon.userInteractionEnabled = NO;
        [_badge addSubview:_badgeIcon]; [self addSubview:_badge];
        [_badge addTarget:self action:@selector(badgeTap) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(long_:)]; [self addGestureRecognizer:lp];
        _dragGR = [[UILongPressGestureRecognizer alloc] init]; _dragGR.minimumPressDuration = 0.12; _dragGR.enabled = NO; [self addGestureRecognizer:_dragGR];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    if (_badge.alpha > 0.01 && CGRectContainsPoint(CGRectInset(_badge.frame, -8, -8), p)) return YES;
    return [super pointInside:p withEvent:e];
}
- (void)tap {
    if (_mode == 0) { Haptic(); [OPCCActions tap:_ident]; After(0.25, ^{ [self refresh]; }); }
    else if (_mode == 2 && _actionBlock) { Haptic(); _actionBlock(self); }
}
- (void)badgeTap { if (_actionBlock) { Haptic(); _actionBlock(self); } }
- (void)long_:(UILongPressGestureRecognizer *)g { if (_mode == 0 && g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions longPress:_ident]; } }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, d = w * 0.6 * _dScale, top = w * 0.1;
    _circle.bounds = CGRectMake(0, 0, d, d); _circle.center = CGPointMake(w/2, top + d/2); _circle.layer.cornerRadius = d/2; _icon.frame = _circle.bounds;
    _label.hidden = !_showLabels; _label.font = [UIFont systemFontOfSize:w * 0.145];
    _label.frame = CGRectMake(0, top + d + w*0.06, w, w*0.4); [_label sizeToFit];
    CGRect f = _label.frame; f.size.width = w; f.origin.x = 0; _label.frame = f;
    CGFloat bs = w * 0.3; _badge.frame = CGRectMake((w-d)/2 - bs*0.2, top - bs*0.25, bs, bs); _badge.layer.cornerRadius = bs/2;
    _badgeIcon.frame = _badge.bounds;
    [self applyIcon];
}
- (void)applyIcon {
    if (!_sym) return;
    _icon.image = [Sym(_sym, MAX(14, _circle.bounds.size.width * 0.42)) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _icon.tintColor = _iconColor ?: UIColor.whiteColor;
}
- (void)startWiggle {
    if ([self.layer animationForKey:@"w"]) return;
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.values = @[@(-0.04), @(0.04), @(-0.04)]; a.duration = 0.26 + (arc4random_uniform(50) / 1000.0); a.repeatCount = HUGE_VALF;
    a.timeOffset = (arc4random_uniform(100) / 100.0) * a.duration;
    [self.layer addAnimation:a forKey:@"w"];
}
- (void)stopWiggle { [self.layer removeAnimationForKey:@"w"]; }
- (void)setMode:(NSInteger)m animated:(BOOL)a {
    _mode = m; BOOL badgeOn = (m == 1 || m == 2);
    _badge.backgroundColor = m == 2 ? RGB(60,190,90) : RGB(235,64,52);
    _badgeIcon.image = [[UIImage systemImageNamed:m == 2 ? @"plus" : @"minus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightHeavy]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _dragGR.enabled = (m == 1);
    void (^b)(void) = ^{ self->_badge.alpha = badgeOn ? 1 : 0; self->_badge.transform = badgeOn ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.3, 0.3); };
    a ? [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:b completion:nil] : b();
    m == 1 ? [self startWiggle] : [self stopWiggle];
    [self refresh];
}
- (void)refresh {
    BOOL on = (_mode != 2) && [OPCCActions stateFor:_ident], dim = [OPCCActions isDimmed:_ident] && _mode != 2;
    NSString *sym = [OPCCActions symbolFor:_ident];
    if ([_ident isEqualToString:@"torch"]) sym = on ? @"flashlight.on.fill" : @"flashlight.off.fill";
    UIColor *ic = on ? RGB(40,40,40) : UIColor.whiteColor, *bg = on ? Light() : (_mode == 2 ? Knob() : Tile());
    if ([_ident isEqualToString:@"eyecomfort"] && on) { bg = RGB(232,226,208); ic = RGB(244,150,26); }
    [UIView animateWithDuration:0.25 animations:^{ self->_circle.backgroundColor = bg; }];
    _sym = sym; _iconColor = ic; [self applyIcon];
    _circle.alpha = _icon.alpha = dim ? 0.45 : 1; _label.alpha = dim ? 0.45 : 1;
}
@end

#pragma mark - плитка
@interface OPCCTile : OPCCPress
@property (nonatomic, strong) UIView *circle; @property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title, *sub;
@end
@implementation OPCCTile
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile(); self.pressScale = 0.96;
        _circle = [UIView new]; _circle.userInteractionEnabled = NO; _circle.backgroundColor = Knob(); [self addSubview:_circle];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; [_circle addSubview:_icon];
        _title = [UILabel new]; _title.textColor = UIColor.whiteColor; [self addSubview:_title];
        _sub = [UILabel new]; _sub.textColor = RGB(190,190,190); [self addSubview:_sub];
        self.pressView = self;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, d = h * 0.7, in = (h - d)/2;
    self.layer.cornerRadius = h/2 * 0.95; _circle.frame = CGRectMake(in, in, d, d); _circle.layer.cornerRadius = d/2; _icon.frame = _circle.bounds;
    _title.font = [UIFont systemFontOfSize:h*0.235 weight:UIFontWeightMedium]; _sub.font = [UIFont systemFontOfSize:h*0.19];
    CGFloat x = in + d + h*0.12, w = self.bounds.size.width - x - in*0.6;
    if (_sub.text.length) { _title.frame = CGRectMake(x, h*0.19, w, h*0.3); _sub.frame = CGRectMake(x, h*0.5, w, h*0.26); }
    else { _title.frame = CGRectMake(x, h*0.5 - h*0.15, w, h*0.3); _sub.frame = CGRectZero; }
}
- (void)setOn:(BOOL)on image:(UIImage *)img title:(NSString *)t sub:(NSString *)s {
    [UIView animateWithDuration:0.25 animations:^{ self->_circle.backgroundColor = on ? UIColor.whiteColor : Knob(); }];
    _icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _icon.tintColor = on ? Blue() : UIColor.whiteColor;
    _title.text = t; _sub.text = s; [self setNeedsLayout];
}
@end

#pragma mark - вертикальный ползунок
@interface OPCCSlider : UIControl
@property (nonatomic) float value;
@property (nonatomic, strong) UIView *fill; @property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, readonly) BOOL tracking_;
- (void)setValue:(float)v animated:(BOOL)a;
@end
@implementation OPCCSlider { float _startV; CGFloat _startY; BOOL _drag; }
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile(); self.clipsToBounds = YES;
        _fill = [UIView new]; _fill.userInteractionEnabled = NO; [self addSubview:_fill];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; _icon.userInteractionEnabled = NO; [self addSubview:_icon];
    }
    return self;
}
- (BOOL)tracking_ { return _drag; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.width * 0.41; self.layer.cornerCurve = kCACornerCurveContinuous;
    _icon.frame = CGRectMake(0, self.bounds.size.height - self.bounds.size.width*0.9, self.bounds.size.width, self.bounds.size.width*0.6);
    [self apply:NO];
}
- (void)apply:(BOOL)anim {
    CGFloat H = self.bounds.size.height, h = H * _value;
    void (^b)(void) = ^{ self->_fill.frame = CGRectMake(0, H - h, self.bounds.size.width, h); self->_fill.backgroundColor = self.fillColor ?: UIColor.whiteColor; };
    anim ? [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseOut animations:b completion:nil] : b();
}
- (void)setValue:(float)v { [self setValue:v animated:NO]; }
- (void)setValue:(float)v animated:(BOOL)a { _value = MAX(0, MIN(1, v)); [self apply:a]; }
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _drag = YES; _startV = _value; _startY = [t locationInView:self].y;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformMakeScale(1.07, 1.02); } completion:nil];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    CGFloat y = [t locationInView:self].y;
    _value = MAX(0, MIN(1, _startV + (_startY - y) / self.bounds.size.height)); [self apply:NO];
    [self sendActionsForControlEvents:UIControlEventValueChanged]; return YES;
}
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self endDrag]; }
- (void)cancelTrackingWithEvent:(UIEvent *)e { [self endDrag]; }
- (void)endDrag {
    _drag = NO;
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
}
@end

#pragma mark - плеер
@interface OPCCPlayer : UIView
@property (nonatomic, strong) UIImageView *art; @property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) OPCCPress *prev, *play, *next; @property (nonatomic, strong) MPVolumeView *route;
@property (nonatomic) BOOL playing;
- (void)refresh;
@end
@implementation OPCCPlayer
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        MRInit();
        self.backgroundColor = Tile();
        _art = [UIImageView new]; _art.backgroundColor = RGB(92,92,92); _art.clipsToBounds = YES; _art.contentMode = UIViewContentModeCenter;
        _art.image = [Sym(@"music.note", 18) imageWithTintColor:RGB(130,130,130) renderingMode:UIImageRenderingModeAlwaysOriginal]; [self addSubview:_art];
        _title = [UILabel new]; _title.textColor = RGB(185,185,185); _title.text = @"Ничего не играет"; [self addSubview:_title];
        _route = [[MPVolumeView alloc] initWithFrame:CGRectZero]; _route.showsVolumeSlider = NO; _route.tintColor = RGB(200,200,200); [self addSubview:_route];
        _prev = [self ctl:@"backward.end.fill" sel:@selector(doPrev)]; _play = [self ctl:@"play.fill" sel:@selector(doPlay)]; _next = [self ctl:@"forward.end.fill" sel:@selector(doNext)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (OPCCPress *)ctl:(NSString *)s sel:(SEL)sel {
    OPCCPress *b = [OPCCPress new]; b.pressScale = 0.8;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(s, 15) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tag = 9; iv.tintColor = RGB(150,150,150); iv.contentMode = UIViewContentModeCenter; iv.userInteractionEnabled = NO;
    [b addSubview:iv]; b.pressView = iv; [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; return b;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height, k = w / 122.;
    self.layer.cornerRadius = 26*k; self.layer.cornerCurve = kCACornerCurveContinuous; self.clipsToBounds = YES;
    _art.frame = CGRectMake(13*k, 14*k, 38*k, 38*k); _art.layer.cornerRadius = 10*k;
    _route.frame = CGRectMake(w - 40*k, 12*k, 30*k, 30*k);
    _title.font = [UIFont systemFontOfSize:12.5*k]; _title.frame = CGRectMake(13*k, h*0.5 - 4*k, w - 26*k, 18*k);
    CGFloat y = h - 38*k, bw = 36*k;
    _prev.frame = CGRectMake(10*k, y, bw, bw); _play.frame = CGRectMake(w/2 - bw*0.65, y - 2*k, bw*1.3, bw*1.3); _next.frame = CGRectMake(w - 10*k - bw, y, bw, bw);
    for (OPCCPress *b in @[_prev,_play,_next]) [b viewWithTag:9].frame = b.bounds;
}
- (void)doPrev { Haptic(); if (MRSend) MRSend(5, nil); }
- (void)doNext { Haptic(); if (MRSend) MRSend(4, nil); }
- (void)doPlay { Haptic(); if (MRSend) MRSend(2, nil); _playing = !_playing; [self paintPlay]; After(0.4, ^{ [self refresh]; }); }
- (void)paintPlay {
    UIImageView *iv = (UIImageView *)[_play viewWithTag:9];
    iv.image = [Sym(_playing ? @"pause.fill" : @"play.fill", 22) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iv.tintColor = RGB(235,235,235);
}
- (void)refresh {
    MRInit(); if (!MRGetInfo) return;
    MRGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef d) {
        NSDictionary *i = (__bridge NSDictionary *)d;
        NSString *t = i[@"kMRMediaRemoteNowPlayingInfoTitle"], *a = i[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSData *art = i[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        self->_title.text = t.length ? (a.length ? [NSString stringWithFormat:@"%@ – %@", t, a] : t) : @"Ничего не играет";
        self->_title.textColor = t.length ? UIColor.whiteColor : RGB(185,185,185);
        UIImage *img = art ? [UIImage imageWithData:art] : nil;
        self->_art.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        self->_art.image = img ?: [Sym(@"music.note", 18) imageWithTintColor:RGB(130,130,130) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [self paintPlay];
    });
    if (MRGetPlaying) MRGetPlaying(dispatch_get_main_queue(), ^(Boolean p) { self->_playing = p; [self paintPlay]; });
}
@end

#pragma mark - переключатель звука
@interface OPCCSound : UIView
@property (nonatomic, strong) NSArray<OPCCPress *> *btns; @property (nonatomic, strong) UIView *hl;
- (void)refresh;
@end
@implementation OPCCSound
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile();
        _hl = [UIView new]; _hl.backgroundColor = UIColor.whiteColor; _hl.userInteractionEnabled = NO; [self addSubview:_hl];
        NSMutableArray *a = [NSMutableArray array];
        NSArray *syms = @[@"bell.fill", @"iphone.radiowaves.left.and.right", @"bell.slash.fill"];
        for (int i = 0; i < 3; i++) {
            OPCCPress *b = [OPCCPress new]; b.tag = i; b.pressScale = 0.88;
            UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(syms[i], 16) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tag = 9; iv.contentMode = UIViewContentModeCenter; iv.userInteractionEnabled = NO;
            [b addSubview:iv]; b.pressView = iv; [b addTarget:self action:@selector(hit:) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; [a addObject:b];
        }
        _btns = a;
    }
    return self;
}
- (CGRect)slot:(int)i { CGFloat w = self.bounds.size.width, h = self.bounds.size.height, d = h*0.73; CGFloat cx[3] = {.223,.52,.82}; return CGRectMake(cx[i]*w - d/2, (h-d)/2, d, d); }
- (void)layoutSubviews { [super layoutSubviews]; self.layer.cornerRadius = self.bounds.size.height/2*0.95; for (int i = 0; i < 3; i++) { _btns[i].frame = [self slot:i]; [_btns[i] viewWithTag:9].frame = _btns[i].bounds; } [self refreshAnimated:NO]; }
- (void)hit:(OPCCPress *)b { Haptic(); [OPCCActions setRingerMode:b.tag]; [self refreshAnimated:YES]; }
- (void)refresh { [self refreshAnimated:YES]; }
- (void)refreshAnimated:(BOOL)a {
    NSInteger m = [OPCCActions ringerMode];
    void (^blk)(void) = ^{
        CGRect r = [self slot:(int)m]; self->_hl.frame = r; self->_hl.layer.cornerRadius = r.size.width/2;
        for (int i = 0; i < 3; i++) ((UIImageView *)[self->_btns[i] viewWithTag:9]).tintColor = (i == m) ? RGB(236,64,52) : RGB(165,165,165);
    };
    a ? [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState animations:blk completion:nil] : blk();
}
@end

#pragma mark - главный вид
@interface OPCCView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@end

@implementation OPCCView {
    UIView *_bg, *_content;
    UILabel *_date, *_hint;
    OPCCPress *_edit, *_gear, *_more;
    OPCCTile *_wifi, *_bt, *_sim;
    OPCCPlayer *_player; OPCCSlider *_bright, *_vol; OPCCSound *_sound;
    UIScrollView *_scroll; NSMutableArray<OPCCRound *> *_round; UIView *_dots; NSTimer *_timer;
    UIView *_tray; UILabel *_trayTitle; UIScrollView *_trayScroll; NSMutableArray<OPCCRound *> *_trayItems;
    BOOL _editing; OPCCRound *_dragging; CGPoint _grab;
    CGFloat _u, _B;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _u = 1.2; _B = 1.25;
        _bg = [UIView new]; _bg.backgroundColor = BG(); [self addSubview:_bg];
        _content = [UIView new]; [self addSubview:_content];
        UITapGestureRecognizer *tp = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTap)]; tp.delegate = self; tp.cancelsTouchesInView = NO; [_content addGestureRecognizer:tp];

        _date = [UILabel new]; _date.textColor = UIColor.whiteColor; [_content addSubview:_date];
        _hint = [UILabel new]; _hint.textColor = RGB(190,190,190); _hint.text = @"Перетащите кнопки, чтобы изменить порядок"; _hint.alpha = 0; [_content addSubview:_hint];
        _edit = [self top:@"pencil" sel:@selector(doEdit)]; _gear = [self top:@"gearshape" sel:@selector(doGear)]; _more = [self top:@"ellipsis" sel:@selector(doMore)];

        _wifi = [OPCCTile new]; [_wifi addTarget:self action:@selector(tapWifi) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_wifi];
        [_wifi addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(lpWifi:)]];
        _bt = [OPCCTile new]; [_bt addTarget:self action:@selector(tapBT) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_bt];
        [_bt addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(lpBT:)]];
        _sim = [OPCCTile new]; [_sim addTarget:self action:@selector(tapSIM) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_sim];
        [_sim setOn:NO image:Sym(@"arrow.up.arrow.down", 17) title:@"SIM1" sub:nil];

        _player = [OPCCPlayer new]; [_content addSubview:_player];
        _bright = [OPCCSlider new]; _bright.fillColor = RGB(225,225,225); _bright.icon.image = [Sym(@"sun.max.fill", 19) imageWithTintColor:RGB(245,197,66) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_bright addTarget:self action:@selector(brightChanged) forControlEvents:UIControlEventValueChanged]; [_content addSubview:_bright];
        _vol = [OPCCSlider new]; _vol.fillColor = UIColor.whiteColor; _vol.icon.image = [Sym(@"speaker.wave.2.fill", 18) imageWithTintColor:Blue() renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_vol addTarget:self action:@selector(volChanged) forControlEvents:UIControlEventValueChanged]; [_content addSubview:_vol];
        _sound = [OPCCSound new]; [_content addSubview:_sound];

        _scroll = [UIScrollView new]; _scroll.pagingEnabled = YES; _scroll.showsHorizontalScrollIndicator = NO; _scroll.delegate = self; _scroll.clipsToBounds = NO; _scroll.delaysContentTouches = NO; [_content addSubview:_scroll];
        _dots = [UIView new]; _dots.userInteractionEnabled = NO; [_content addSubview:_dots];

        _tray = [UIView new]; _tray.backgroundColor = RGB(56,56,56); _tray.alpha = 0; [_content addSubview:_tray];
        _trayTitle = [UILabel new]; _trayTitle.textColor = RGB(200,200,200); _trayTitle.text = @"Добавить кнопки"; [_tray addSubview:_trayTitle];
        _trayScroll = [UIScrollView new]; _trayScroll.showsHorizontalScrollIndicator = NO; _trayScroll.delaysContentTouches = NO; _trayScroll.clipsToBounds = NO; [_tray addSubview:_trayScroll];
        _trayItems = [NSMutableArray array];

        _round = [NSMutableArray array];
        [self reloadButtons];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bgTap) name:OPCCDismissNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_timer invalidate]; }

- (OPCCPress *)top:(NSString *)sym sel:(SEL)s {
    OPCCPress *b = [OPCCPress new]; b.backgroundColor = RGB(58,58,58); b.pressScale = 0.85;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(sym, 13) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tintColor = UIColor.whiteColor; iv.contentMode = UIViewContentModeCenter; iv.tag = 9; iv.userInteractionEnabled = NO;
    [b addSubview:iv]; [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:b]; return b;
}

// Тап по пустому месту закрывает шторку, тап по кнопкам — нет
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (_editing) return NO;
    UIView *v = t.view;
    return v == _content || v == _scroll || v == _bg || v == self || v == _dots;
}

#pragma mark раскладка
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat S = [OPCCActions shadeScale], B = [OPCCActions buttonScale]; _B = B;
    CGFloat d = 40*B, rowH = d + 37, gridH = 10 + 3*rowH + 6;
    CGFloat topSafe = MAX(self.safeAreaInsets.top, 20);
    CGFloat bottomRef = 350 + gridH + 14;
    CGFloat uW = (W - 12) / 255., uH = (H - topSafe - 30) / (bottomRef - 47 + 18);
    CGFloat u = MIN(MIN(S * W / 316., uW), uH); u = MAX(u, 0.75 * W / 316.); _u = u;
    CGFloat cy = topSafe + 18*u;
    #define X(v) (W/2 + ((v) - 157.5)*u)
    #define Y(v) (cy + ((v) - 47)*u)
    _bg.frame = self.bounds; _content.frame = self.bounds;
    _date.font = [UIFont systemFontOfSize:12*u]; _date.frame = CGRectMake(X(30), cy - 10*u, 130*u, 20*u);
    _hint.font = [UIFont systemFontOfSize:11*u]; _hint.frame = CGRectMake(X(30), Y(66), 255*u, 18*u);
    CGFloat cx[3] = {196,233,271}; OPCCPress *tops[3] = {_edit,_gear,_more};
    for (int i = 0; i < 3; i++) { tops[i].frame = CGRectMake(X(cx[i]) - 14*u, cy - 14*u, 28*u, 28*u); tops[i].layer.cornerRadius = 14*u; [tops[i] viewWithTag:9].frame = tops[i].bounds; }
    _wifi.frame = CGRectMake(X(30), Y(79), 122*u, 52*u); _bt.frame = CGRectMake(X(164), Y(79), 121*u, 52*u);
    _player.frame = CGRectMake(X(30), Y(146), 122*u, 120*u);
    _bright.frame = CGRectMake(X(164), Y(146), 54*u, 120*u); _vol.frame = CGRectMake(X(231), Y(146), 54*u, 120*u);
    _sim.frame = CGRectMake(X(30), Y(279), 122*u, 52*u); _sound.frame = CGRectMake(X(164), Y(279), 121*u, 52*u);
    for (UIView *v in @[_wifi,_bt,_sim,_sound]) v.layer.cornerCurve = kCACornerCurveContinuous;

    CGFloat scrollTop = _editing ? 100 : 350;
    _scroll.frame = CGRectMake(0, Y(scrollTop), W, (gridH + 10)*u);
    [self layoutButtons];
    _dots.frame = CGRectMake(0, Y(scrollTop + gridH + 8), W, 6*u); [self layoutDots];

    CGFloat trayH = (34 + d + 37 + 10)*u, trayY = Y(scrollTop + gridH + 22);
    _tray.frame = CGRectMake(X(30), _editing ? trayY : trayY + 90*u, 255*u, trayH); _tray.layer.cornerRadius = 22*u; _tray.layer.cornerCurve = kCACornerCurveContinuous;
    _trayTitle.font = [UIFont systemFontOfSize:12*u weight:UIFontWeightMedium]; _trayTitle.frame = CGRectMake(16*u, 10*u, 220*u, 18*u);
    _trayScroll.frame = CGRectMake(0, 34*u, 255*u, trayH - 34*u);
    [self layoutTray];

    static NSDateFormatter *df;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"EEE, d MMM"; df.locale = [NSLocale localeWithLocaleIdentifier:@"ru_RU"]; }
    NSString *ds = [df stringFromDate:[NSDate date]];
    if (ds.length) ds = [[[ds substringToIndex:1] uppercaseString] stringByAppendingString:[ds substringFromIndex:1]];
    _date.text = ds;
}

- (void)layoutButtons {
    CGFloat W = self.bounds.size.width, u = _u, B = _B, bw = 66*u, d = 40*B*u, cpad = bw*0.1;
    BOOL labels = [OPCCActions showLabels];
    for (NSUInteger i = 0; i < _round.count; i++) {
        OPCCRound *r = _round[i]; r.dScale = B; r.showLabels = labels;
        if (r == _dragging) continue;
        NSUInteger page = i / 12, k = i % 12, c = k % 4, row = k / 4;
        CGFloat cxp = page*W + W/2 + ((CGFloat)c - 1.5)*66.7*u, cyc = (10 + row*(40*B+37) + 20*B)*u;
        r.bounds = CGRectMake(0, 0, bw, cpad + d + 30*u); r.center = CGPointMake(cxp, cyc - d/2 - cpad + (cpad + d + 30*u)/2);
        [r setNeedsLayout];
    }
    NSUInteger pages = MAX(2, (_round.count + 11) / 12);
    _scroll.contentSize = CGSizeMake(W*pages, (10 + 3*(40*B+37) + 16)*u);
}
- (void)layoutTray {
    CGFloat u = _u, B = _B, bw = 66*u, d = 40*B*u, cpad = bw*0.1; BOOL labels = [OPCCActions showLabels];
    CGFloat x = 8*u;
    for (OPCCRound *r in _trayItems) {
        r.dScale = B; r.showLabels = labels; r.bounds = CGRectMake(0, 0, bw, cpad + d + 30*u);
        r.center = CGPointMake(x + bw/2, (cpad + d + 30*u)/2 + 2*u); x += bw + 2*u; [r setNeedsLayout];
    }
    _trayScroll.contentSize = CGSizeMake(MAX(x + 8*u, 255*u), 1);
}
- (void)layoutDots {
    CGFloat u = _u;
    NSUInteger n = MAX(2, (_round.count + 11) / 12), cur = (NSUInteger)lround(_scroll.contentOffset.x / MAX(1, self.bounds.size.width));
    for (UIView *v in _dots.subviews) [v removeFromSuperview];
    CGFloat d = 5*u, gap = 8*u, total = n*d + (n-1)*gap, x0 = (self.bounds.size.width - total)/2;
    for (NSUInteger i = 0; i < n; i++) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(x0 + i*(d+gap), 0.5*u, d, d)]; v.layer.cornerRadius = d/2;
        v.backgroundColor = i == cur ? UIColor.whiteColor : RGB(120,120,120); [_dots addSubview:v];
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)s { if (s == _scroll) [self layoutDots]; }

#pragma mark кнопки
- (OPCCRound *)makeRound:(NSString *)ident {
    OPCCRound *r = [[OPCCRound alloc] initWithID:ident];
    [r.dragGR addTarget:self action:@selector(dragGesture:)];
    return r;
}
- (void)reloadButtons {
    for (UIView *v in _round) [v removeFromSuperview]; [_round removeAllObjects];
    __weak OPCCView *ws = self;
    for (NSString *i in [OPCCActions activeIDs]) {
        OPCCRound *b = [self makeRound:i]; b.actionBlock = ^(OPCCRound *r) { [ws removeRound:r]; };
        [_scroll addSubview:b]; [_round addObject:b];
    }
    [self setNeedsLayout]; [self layoutIfNeeded];
    for (OPCCRound *b in _round) { [b setMode:_editing ? 1 : 0 animated:NO]; }
    [self rebuildTray];
}
- (void)rebuildTray {
    for (UIView *v in _trayItems) [v removeFromSuperview]; [_trayItems removeAllObjects];
    NSMutableArray *active = [NSMutableArray array]; for (OPCCRound *r in _round) [active addObject:r.ident];
    __weak OPCCView *ws = self;
    for (NSString *i in [OPCCActions allIDs]) {
        if ([active containsObject:i]) continue;
        OPCCRound *b = [self makeRound:i]; b.actionBlock = ^(OPCCRound *r) { [ws addFromTray:r]; };
        [_trayScroll addSubview:b]; [_trayItems addObject:b];
    }
    _trayTitle.text = _trayItems.count ? @"Добавить кнопки" : @"Все кнопки уже добавлены";
    [self layoutTray];
    for (OPCCRound *b in _trayItems) { [b setMode:2 animated:NO]; }
}
- (void)saveOrder { NSMutableArray *ids = [NSMutableArray array]; for (OPCCRound *r in _round) [ids addObject:r.ident]; [OPCCActions saveActiveIDs:ids]; }

- (void)removeRound:(OPCCRound *)r {
    [_round removeObject:r]; [self saveOrder];
    [UIView animateWithDuration:0.25 animations:^{ r.transform = CGAffineTransformMakeScale(0.1, 0.1); r.alpha = 0; } completion:^(BOOL f) { [r removeFromSuperview]; }];
    [UIView animateWithDuration:0.45 delay:0.05 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{ [self layoutButtons]; [self layoutDots]; } completion:nil];
    [self rebuildTray];
}
- (void)addFromTray:(OPCCRound *)t {
    NSString *ident = t.ident;
    OPCCRound *n = [self makeRound:ident]; __weak OPCCView *ws = self; n.actionBlock = ^(OPCCRound *r) { [ws removeRound:r]; };
    [_scroll addSubview:n]; [_round addObject:n];
    n.alpha = 0; n.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [self layoutButtons]; [n layoutIfNeeded]; [n setMode:1 animated:YES];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.4 options:0 animations:^{ n.alpha = 1; n.transform = CGAffineTransformIdentity; } completion:nil];
    NSUInteger pg = (_round.count - 1) / 12;
    [_scroll setContentOffset:CGPointMake(pg * self.bounds.size.width, 0) animated:YES];
    [self saveOrder]; [self rebuildTray]; [self layoutDots];
}

// Перетаскивание (режим правки)
- (NSUInteger)slotAt:(CGPoint)loc {
    CGFloat W = self.bounds.size.width, u = _u;
    NSInteger pages = MAX(2, (NSInteger)(_round.count + 11) / 12);
    NSInteger page = MAX(0, MIN(pages - 1, (NSInteger)floor(loc.x / W)));
    CGFloat lx = loc.x - page*W;
    NSInteger col = MAX(0, MIN(3, lround((lx - W/2) / (66.7*u) + 1.5)));
    CGFloat rowH = (40*_B + 37)*u;
    NSInteger row = MAX(0, MIN(2, (NSInteger)floor((loc.y - 10*u) / rowH)));
    NSInteger idx = page*12 + row*4 + col;
    return (NSUInteger)MAX(0, MIN((NSInteger)_round.count - 1, idx));
}
- (void)dragGesture:(UILongPressGestureRecognizer *)g {
    OPCCRound *r = (OPCCRound *)g.view; CGPoint loc = [g locationInView:_scroll];
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _dragging = r; _scroll.scrollEnabled = NO; [_scroll bringSubviewToFront:r];
            _grab = CGPointMake(loc.x - r.center.x, loc.y - r.center.y); [r stopWiggle]; Haptic();
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ r.transform = CGAffineTransformMakeScale(1.15, 1.15); r.alpha = 0.92; } completion:nil];
            break;
        case UIGestureRecognizerStateChanged: {
            r.center = CGPointMake(loc.x - _grab.x, loc.y - _grab.y);
            NSUInteger idx = [self slotAt:loc], cur = [_round indexOfObject:r];
            if (idx != cur && cur != NSNotFound) {
                [_round removeObject:r]; [_round insertObject:r atIndex:MIN(idx, _round.count)];
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ [self layoutButtons]; } completion:nil];
                Haptic();
            }
            break;
        }
        default:
            _dragging = nil;
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{ r.transform = CGAffineTransformIdentity; r.alpha = 1; [self layoutButtons]; } completion:^(BOOL f) { if (self->_editing) [r startWiggle]; }];
            _scroll.scrollEnabled = YES; [self saveOrder];
            break;
    }
}

#pragma mark режим правки
- (void)setEditing:(BOOL)e animated:(BOOL)a {
    if (_editing == e) return; _editing = e;
    for (OPCCRound *r in _round) [r setMode:e ? 1 : 0 animated:a];
    [self rebuildTray];
    UIImageView *iv = (UIImageView *)[_edit viewWithTag:9];
    UIImage *img = [Sym(e ? @"checkmark" : @"pencil", 13) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (a) [UIView transitionWithView:iv duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ iv.image = img; } completion:nil]; else iv.image = img;
    NSArray *hide = @[_wifi,_bt,_player,_bright,_vol,_sim,_sound,_gear,_more];
    for (UIView *v in hide) v.userInteractionEnabled = !e;
    if (!e) [_scroll setContentOffset:CGPointMake(_scroll.contentOffset.x, 0) animated:NO];
    void (^blk)(void) = ^{
        for (UIView *v in hide) { v.alpha = e ? 0 : 1; v.transform = CGAffineTransformIdentity; }
        self->_hint.alpha = e ? 1 : 0; self->_tray.alpha = e ? 1 : 0; self->_dots.alpha = e ? 0 : 1;
        [self setNeedsLayout]; [self layoutIfNeeded];
    };
    a ? [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.3 options:UIViewAnimationOptionAllowUserInteraction animations:blk completion:nil] : blk();
}
- (void)doEdit { Haptic(); [self setEditing:!_editing animated:YES]; }

#pragma mark действия
- (void)tapWifi { Haptic(); [OPCCActions setWifi:![OPCCActions wifiOn]]; After(0.4, ^{ [self refreshAll]; }); }
- (void)lpWifi:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=WIFI"]; [self bgTap]; } }
- (void)tapBT { Haptic(); [OPCCActions setBT:![OPCCActions btOn]]; After(0.4, ^{ [self refreshAll]; }); }
- (void)lpBT:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=Bluetooth"]; [self bgTap]; } }
- (void)tapSIM { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=MOBILE_DATA_SETTINGS_ID"]; [self bgTap]; }
- (void)brightChanged { [OPCCActions setBrightness:_bright.value]; }
- (void)volChanged { [OPCCActions setVolume:_vol.value]; }
- (void)bgTap { if (self.dismissBlock) self.dismissBlock(); }
- (void)doGear { Haptic(); [OPCCActions openApp:@"com.apple.Preferences"]; [self bgTap]; }
- (void)doMore {
    Haptic(); if (!self.presentBlock) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Редактировать кнопки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self setEditing:YES animated:YES]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Сбросить раскладку" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [OPCCActions saveActiveIDs:[OPCCActions defaultIDs]]; [self reloadButtons]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _more; a.popoverPresentationController.sourceRect = _more.bounds;
    self.presentBlock(a);
}

#pragma mark состояние
- (void)refreshAll {
    BOOL w = [OPCCActions wifiOn]; NSString *n = [OPCCActions wifiName];
    [_wifi setOn:w image:Sym(@"wifi", 17) title:(w && n) ? n : @"Wi-Fi" sub:w ? (n ? @"Подключено" : @"Не подключено") : @"Выключено"];
    [_bt setOn:[OPCCActions btOn] image:BTImage(18) title:@"Bluetooth" sub:nil];
    if (!_bright.tracking_) [_bright setValue:[OPCCActions brightness] animated:YES];
    if (!_vol.tracking_)    [_vol setValue:[OPCCActions volume] animated:YES];
    [_sound refresh]; [_player refresh];
    for (OPCCRound *r in _round) if (r != _dragging) [r refresh];
}

#pragma mark анимация шторки
- (void)present {
    if (_editing) [self setEditing:NO animated:NO];
    [self setNeedsLayout]; [self layoutIfNeeded]; [self refreshAll];
    [_timer invalidate]; _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshAll) userInfo:nil repeats:YES];
    CGFloat H = self.bounds.size.height;
    _bg.alpha = 0; _content.transform = CGAffineTransformMakeTranslation(0, -H*0.5); _content.alpha = 0;
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_bg.alpha = 1; self->_content.transform = CGAffineTransformIdentity; self->_content.alpha = 1; } completion:nil];
    NSMutableArray *items = [NSMutableArray arrayWithObjects:_wifi,_bt,_player,_bright,_vol,_sim,_sound,nil]; [items addObjectsFromArray:_round];
    [items enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *s) {
        v.alpha = 0; v.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9), CGAffineTransformMakeTranslation(0, -18));
        [UIView animateWithDuration:0.55 delay:0.04 + 0.018*i usingSpringWithDamping:0.78 initialSpringVelocity:0.2 options:UIViewAnimationOptionAllowUserInteraction animations:^{ v.alpha = 1; v.transform = CGAffineTransformIdentity; } completion:nil];
    }];
}
- (void)stop { [_timer invalidate]; _timer = nil; if (_editing) [self setEditing:NO animated:NO]; }
@end
