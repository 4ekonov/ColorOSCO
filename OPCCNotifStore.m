#import "OPCCNotifications.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "OPCCActions.h"

NSString *const OPCCNotifsChanged = @"OPCCNotifsChanged";

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)i;
- (NSString *)localizedName;
@end

static id KV(id o, NSString *k) { if (!o) return nil; @try { return [o valueForKey:k]; } @catch (__unused NSException *e) { return nil; } }
static NSString *KS(id o, NSString *k) {
    id v = KV(o, k);
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)v string];
    return nil;
}
static void NLog(NSString *s) {
    static int n = 0; if (n++ > 80) return;
    NSString *path = @"/var/mobile/Documents/OPCC_notifs.txt";
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    [[old stringByAppendingFormat:@"%@\n", s] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@implementation OPCCNotif
@end

// Поддельное действие для тестовых уведомлений («Прочитано», «Архивировать» и т. п.): просто убирает свою карточку
@interface OPCCFakeAction : NSObject
@property (nonatomic, copy) NSString *title, *ownerIdent;
@end
@implementation OPCCFakeAction
@end

static BOOL gTest = NO;

@implementation OPCCNotifStore
+ (NSMutableArray *)items { static NSMutableArray *a; static dispatch_once_t t; dispatch_once(&t, ^{ a = [NSMutableArray array]; }); return a; }
+ (NSArray *)all { @synchronized (self) { return [[self items] copy]; } }
+ (void)changed { dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:OPCCNotifsChanged object:nil]; }); }

+ (NSString *)nameForBundle:(NSString *)b {
    static NSMutableDictionary *cache; if (!cache) cache = [NSMutableDictionary dictionary];
    if (!b.length) return @"";
    NSString *n = cache[b]; if (n) return n;
    @try { n = [[objc_getClass("LSApplicationProxy") applicationProxyForIdentifier:b] localizedName]; } @catch (__unused NSException *e) {}
    if (!n.length) n = b;
    cache[b] = n; return n;
}

+ (void)post:(id)r {
    if (!r) return;
    id content = KV(r, @"content");
    NSString *ident = KS(r, @"notificationIdentifier"); if (!ident.length) ident = [NSString stringWithFormat:@"%p", r];
    NSString *bundle = KS(r, @"sectionIdentifier") ?: @"";
    NSString *title = KS(content, @"title"), *sub = KS(content, @"subtitle"), *msg = KS(content, @"message"), *header = KS(content, @"header");
    if (!title.length) { title = sub; sub = nil; }
    NSString *message = msg ?: @"";
    if (sub.length) message = message.length ? [NSString stringWithFormat:@"%@\n%@", sub, message] : sub;
    if (!title.length && !message.length) return;
    id d = KV(r, @"timestamp"); if (![d isKindOfClass:[NSDate class]]) d = KV(content, @"date"); if (![d isKindOfClass:[NSDate class]]) d = [NSDate date];

    OPCCNotif *n = [OPCCNotif new];
    n.ident = ident; n.bundleID = bundle; n.title = title ?: @""; n.message = message; n.date = d; n.request = r;
    n.appName = header.length ? header : [self nameForBundle:bundle];
    NSMutableArray *acts = [NSMutableArray array];
    id sup = KV(r, @"supplementaryActions");
    if ([sup isKindOfClass:[NSArray class]]) for (id a in sup) {
        if ([NSStringFromClass([a class]) containsString:@"TextInput"]) continue;      // ответ с вводом текста пока не поддерживается
        NSString *tt = KS(a, @"title"); if (tt.length && acts.count < 3) [acts addObject:a];
    }
    n.actions = acts; n.defaultAction = KV(r, @"defaultAction");
    BOOL isNew = NO;
    @synchronized (self) {
        NSMutableArray *a = [self items]; NSUInteger idx = NSNotFound;
        for (NSUInteger i = 0; i < a.count; i++) if ([((OPCCNotif *)a[i]).ident isEqualToString:ident]) { idx = i; break; }
        isNew = (idx == NSNotFound);
        if (idx != NSNotFound) a[idx] = n; else [a addObject:n];
        [a sortUsingComparator:^NSComparisonResult(OPCCNotif *x, OPCCNotif *y) { return [y.date compare:x.date]; }];
    }
    NLog([NSString stringWithFormat:@"+ %@ | %@ | %@ | %@", bundle, n.appName, n.title, n.message]);
    [self changed];
    if (isNew) dispatch_async(dispatch_get_main_queue(), ^{ [OPCCBanner show:n]; });
}
+ (void)withdraw:(id)r {
    NSString *ident = KS(r, @"notificationIdentifier"); if (!ident.length) return;
    @synchronized (self) { NSMutableArray *a = [self items]; for (NSInteger i = (NSInteger)a.count - 1; i >= 0; i--) if ([((OPCCNotif *)a[i]).ident isEqualToString:ident]) [a removeObjectAtIndex:i]; }
    [self changed];
}

// Убираем уведомление и в самой системе (через её действие «очистить»), иначе оно вернётся после респринга
+ (void)systemClear:(id)req {
    @try {
        id act = KV(req, @"clearAction"), runner = KV(act, @"actionRunner");
        SEL s = NSSelectorFromString(@"executeAction:fromOrigin:endpoint:withParameters:completion:");
        if (act && runner && [runner respondsToSelector:s]) { ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(runner, s, act, nil, nil, nil, nil); NLog(@"clear: через clearAction"); return; }
        NLog(@"clear: clearAction недоступен");
    } @catch (__unused NSException *e) { NLog(@"clear: исключение"); }
}
+ (BOOL)testMode { return gTest; }
+ (OPCCNotif *)fakeIdent:(NSString *)ident bundle:(NSString *)b app:(NSString *)app title:(NSString *)t msg:(NSString *)m ago:(NSTimeInterval)sec actions:(NSArray *)titles {
    OPCCNotif *n = [OPCCNotif new]; n.ident = ident; n.bundleID = b; n.appName = app; n.title = t; n.message = m; n.date = [NSDate dateWithTimeIntervalSinceNow:-sec];
    NSMutableArray *acts = [NSMutableArray array];
    for (NSString *tt in titles) { OPCCFakeAction *a = [OPCCFakeAction new]; a.title = tt; a.ownerIdent = ident; [acts addObject:a]; }
    n.actions = acts; return n;
}
+ (void)setTestMode:(BOOL)on {
    if (on == gTest) return; gTest = on;
    @synchronized (self) {
        NSMutableArray *a = [self items];
        for (NSInteger i = (NSInteger)a.count - 1; i >= 0; i--) if ([((OPCCNotif *)a[i]).ident hasPrefix:@"opcc-test-"]) [a removeObjectAtIndex:i];
        if (on) {
            NSString *sms = @"com.apple.MobileSMS";
            [a addObjectsFromArray:@[
              [self fakeIdent:@"opcc-test-1" bundle:sms app:@"Сообщения" title:@"Анна" msg:@"Привет! Ты сегодня будешь на встрече в 18:00?" ago:60 actions:@[@"Прочитано"]],
              [self fakeIdent:@"opcc-test-2" bundle:sms app:@"Сообщения" title:@"Анна" msg:@"Не забудь взять документы" ago:120 actions:@[@"Прочитано"]],
              [self fakeIdent:@"opcc-test-3" bundle:sms app:@"Сообщения" title:@"Дима" msg:@"Скинул фото с поездки 📷" ago:480 actions:@[@"Прочитано"]],
              [self fakeIdent:@"opcc-test-4" bundle:sms app:@"Сообщения" title:@"Рабочий чат" msg:@"Максим: созвон перенесли на 15:30, всем быть на связи." ago:840 actions:@[@"Прочитано"]],
              [self fakeIdent:@"opcc-test-5" bundle:sms app:@"Сообщения" title:@"Мама" msg:@"Позвони, когда освободишься" ago:2400 actions:@[@"Прочитано"]],
              [self fakeIdent:@"opcc-test-6" bundle:@"com.apple.mobilemail" app:@"Почта" title:@"Расписание на следующую неделю"
                          msg:@"Добрый день! Отправляю обновлённое расписание: в понедельник планёрка в 11:00, во вторник демонстрация нового релиза для клиентов, в четверг — ретроспектива и планирование спринта. Просьба подтвердить участие до пятницы и подготовить краткий отчёт по задачам." ago:1500 actions:@[@"Архивировать", @"Отметить"]],
              [self fakeIdent:@"opcc-test-7" bundle:@"com.apple.mobilecal" app:@"Календарь" title:@"Через 15 минут: Планёрка" msg:@"Переговорная 2, 11:00–11:30" ago:180 actions:@[@"Отложить"]],
              [self fakeIdent:@"opcc-test-8" bundle:@"com.apple.reminders" app:@"Напоминания" title:@"Купить продукты" msg:@"Молоко, хлеб, яйца" ago:3600 actions:@[@"Выполнено"]],
              [self fakeIdent:@"opcc-test-9" bundle:@"com.apple.weather" app:@"Погода" title:@"Дождь через 20 минут" msg:@"Возьмите зонт — ожидаются осадки." ago:7200 actions:@[]],
              [self fakeIdent:@"opcc-test-10" bundle:@"com.apple.Preferences" app:@"Настройки" title:@"Доступно обновление iOS" msg:@"Установите обновление, чтобы получить последние улучшения безопасности." ago:90000 actions:@[]],
            ]];
            [a sortUsingComparator:^NSComparisonResult(OPCCNotif *x, OPCCNotif *y) { return [y.date compare:x.date]; }];
        }
    }
    [self changed];
    if (on) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{      // тестовая капсула
        for (OPCCNotif *n in [self all]) if ([n.ident isEqualToString:@"opcc-test-7"]) { [OPCCBanner show:n force:YES]; break; }
    });
}
+ (void)runAction:(id)act {
    if ([act isKindOfClass:[OPCCFakeAction class]]) {          // тестовое действие: убираем уведомление, как «Прочитано»
        NSString *ident = ((OPCCFakeAction *)act).ownerIdent;
        @synchronized (self) { NSMutableArray *a = [self items]; for (NSInteger i = (NSInteger)a.count - 1; i >= 0; i--) if ([((OPCCNotif *)a[i]).ident isEqualToString:ident]) [a removeObjectAtIndex:i]; }
        [self changed]; return;
    }
    @try {
        id runner = KV(act, @"actionRunner"); SEL s = NSSelectorFromString(@"executeAction:fromOrigin:endpoint:withParameters:completion:");
        if (act && runner && [runner respondsToSelector:s]) ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(runner, s, act, nil, nil, nil, nil);
    } @catch (__unused NSException *e) {}
}
+ (void)openNotif:(OPCCNotif *)n {
    id act = n.defaultAction, runner = KV(act, @"actionRunner");
    if (act && runner) { [self runAction:act]; return; }
    [OPCCActions launchAppNow:n.bundleID];
}
+ (void)clear:(OPCCNotif *)n {
    @synchronized (self) { [[self items] removeObject:n]; }
    [self systemClear:n.request]; [self changed];
}
+ (void)clearAll {
    NSArray *all = [self all];
    for (OPCCNotif *n in all) [self systemClear:n.request];
    @synchronized (self) { [[self items] removeAllObjects]; }
    [self changed];
}
@end
