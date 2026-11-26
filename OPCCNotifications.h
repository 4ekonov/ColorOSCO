#import <UIKit/UIKit.h>
extern NSString *const OPCCNotifsChanged;

@interface OPCCNotif : NSObject
@property (nonatomic, copy) NSString *ident, *bundleID, *appName, *title, *message;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) id request;
@property (nonatomic, strong) NSArray *actions;   // дополнительные действия («Прочитано», «Ответить»…)
@property (nonatomic, strong) id defaultAction;
@end

// Хранилище уведомлений: наполняется хуками в Tweak.xm
@interface OPCCNotifStore : NSObject
+ (NSArray<OPCCNotif *> *)all;
+ (void)post:(id)request;
+ (void)withdraw:(id)request;
+ (void)clear:(OPCCNotif *)n;
+ (void)clearAll;
+ (BOOL)testMode;
+ (void)setTestMode:(BOOL)on;       // тестовые уведомления для проверки всех функций
+ (void)runAction:(id)action;          // выполнить действие уведомления
+ (void)openNotif:(OPCCNotif *)n;      // открыть уведомление (действие по умолчанию или приложение)
@end

// Своя панель уведомлений в стиле ColorOS
@interface OPCCNotifPanel : NSObject
+ (void)show;
+ (void)hide;
+ (BOOL)isShown;
+ (void)setOnHide:(void (^)(void))block;   // вызывается, когда панель полностью скрыта
+ (BOOL)lockOverlayVisible;
+ (void)attachLockListTo:(UIView *)host above:(UIView *)ref;   // встроить наш список в иерархию экрана блокировки
+ (void)detachLockList;
+ (void)showMasked;     // показать панель с непрозрачной подложкой (пока уходит стандартная шторка)
+ (void)unmask;
@end

// Всплывающие уведомления (капсулы поверх всего)
@interface OPCCBanner : NSObject
+ (void)show:(OPCCNotif *)n;
+ (void)show:(OPCCNotif *)n force:(BOOL)force;
+ (BOOL)isVisible;
@end
