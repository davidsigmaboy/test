// MemGuard.m
// Keeps RAM usage under control so the app does not purge its feed/video cache.
//  1. Swallows memory warnings (the app reacts to them by dropping cached videos).
//  2. Every few seconds checks free memory (os_proc_available_memory) and,
//     if it is low, trims what can be trimmed: malloc free pages, NSURLCache,
//     SDWebImage / YYCache memory caches if present.
// Build flags: -DBLOCK_WARNINGS=0 to keep memory warnings, -DLOW_MB=800 to change the threshold.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <os/proc.h>

#ifndef BLOCK_WARNINGS
#define BLOCK_WARNINGS 1
#endif
#ifndef LOW_MB
#define LOW_MB 700          // trim when available memory drops below this
#endif
#ifndef INTERVAL_SEC
#define INTERVAL_SEC 5
#endif

static void MGSwizzle(Class c, SEL s, IMP newImp) {
    Method m = class_getInstanceMethod(c, s);
    if (m) method_setImplementation(m, newImp);
}

static void MGTrim(void) {
    malloc_zone_pressure_relief(NULL, 0);
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    // Image caches: only the in-memory part, video files on disk are untouched.
    Class sd = NSClassFromString(@"SDImageCache");
    id sdShared = [sd respondsToSelector:@selector(sharedImageCache)] ? [sd performSelector:@selector(sharedImageCache)] : nil;
    if ([sdShared respondsToSelector:@selector(clearMemory)]) [sdShared performSelector:@selector(clearMemory)];
    Class yy = NSClassFromString(@"YYImageCache");
    id yyShared = [yy respondsToSelector:@selector(sharedCache)] ? [yy performSelector:@selector(sharedCache)] : nil;
    id yyMem = [yyShared respondsToSelector:@selector(memoryCache)] ? [yyShared performSelector:@selector(memoryCache)] : nil;
    if ([yyMem respondsToSelector:@selector(removeAllObjects)]) [yyMem performSelector:@selector(removeAllObjects)];
}

#if BLOCK_WARNINGS
static void (*orig_post)(id, SEL, NSNotificationName, id, NSDictionary *);
static void hook_post(id self, SEL _cmd, NSNotificationName name, id obj, NSDictionary *info) {
    if ([name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) return;
    orig_post(self, _cmd, name, obj, info);
}
static void hook_noop(id self, SEL _cmd, id app) {}
static void hook_vc(id self, SEL _cmd) {}
#endif

static dispatch_source_t gTimer;

static void MGStart(void) {
#if BLOCK_WARNINGS
    Method m = class_getInstanceMethod(NSNotificationCenter.class, @selector(postNotificationName:object:userInfo:));
    orig_post = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_post);

    id delegate = UIApplication.sharedApplication.delegate;
    if (delegate) MGSwizzle(object_getClass(delegate), @selector(applicationDidReceiveMemoryWarning:), (IMP)hook_noop);
    // UIViewController's own warning handler is left alone on purpose.
#endif
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, INTERVAL_SEC * NSEC_PER_SEC),
                              INTERVAL_SEC * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(gTimer, ^{
        size_t avail = os_proc_available_memory();
        if (avail < (size_t)LOW_MB * 1024 * 1024) {
            NSLog(@"[MemGuard] low memory (%zu MB free), trimming", avail / 1048576);
            MGTrim();
        }
    });
    dispatch_resume(gTimer);
    NSLog(@"[MemGuard] started, free=%zu MB", os_proc_available_memory() / 1048576);
}

__attribute__((constructor))
static void MGInit(void) {
    // App delegate does not exist yet inside the constructor: wait for launch.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { MGStart(); }];
    // If the app is already running (injected late), start right away.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gTimer && UIApplication.sharedApplication.delegate) MGStart();
    });
}
