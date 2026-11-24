#import <UIKit/UIKit.h>
extern NSString *const OPCCDismissNotification;
extern NSString *const OPCCReloadNotification;

extern __weak id OPCCRingerControl;   // заполняется хуком SBRingerControl в Tweak.xm

@interface OPCCActions : NSObject
+ (NSUserDefaults *)prefs;
+ (CGFloat)shadeScale;    // масштаб шторки
+ (CGFloat)buttonScale;   // размер круглых кнопок
+ (BOOL)showLabels;       // подписи под кнопками
// каталог кнопок
+ (NSArray<NSString *> *)allIDs;
+ (NSArray<NSString *> *)defaultIDs;
+ (NSArray<NSString *> *)activeIDs;
+ (void)saveActiveIDs:(NSArray<NSString *> *)ids;
+ (NSString *)titleFor:(NSString *)ident;
+ (NSString *)symbolFor:(NSString *)ident;
+ (BOOL)isDimmed:(NSString *)ident;
+ (BOOL)stateFor:(NSString *)ident;
+ (void)tap:(NSString *)ident;
+ (void)longPress:(NSString *)ident;
// ползунки
+ (float)brightness;  + (void)setBrightness:(float)v;
+ (float)volume;      + (void)setVolume:(float)v;
// плитки
+ (BOOL)wifiOn;  + (NSString *)wifiName;  + (void)setWifi:(BOOL)on;
+ (BOOL)btOn;    + (void)setBT:(BOOL)on;
+ (NSInteger)ringerMode;                 // 0 звонок, 1 вибро, 2 без звука
+ (void)setRingerMode:(NSInteger)m;
+ (void)openApp:(NSString *)bundleID;
+ (void)openSettingsURL:(NSString *)url;
@end
