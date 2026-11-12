// FixImageContext.m
// Fixes: "UIGraphicsBeginImageContext() failed to allocate CGBitampContext" crash
// Hooks UIGraphicsBeginImageContext(WithOptions) / GetImageFromCurrentImageContext / End.
// If the system call throws, falls back to our own CGBitmapContext so the app doesn't crash.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "fishhook.h"

static void (*orig_Begin)(CGSize size);
static void (*orig_BeginOpts)(CGSize size, BOOL opaque, CGFloat scale);
static UIImage *(*orig_GetImage)(void);
static void (*orig_End)(void);

static NSString *const kStackKey = @"FixImageContext.stack";

// Per-thread stack. Entry: NSNull = real UIKit context, NSValue(pointer) = our fallback context.
static NSMutableArray *FICStack(void) {
    NSMutableDictionary *d = [NSThread currentThread].threadDictionary;
    NSMutableArray *s = d[kStackKey];
    if (!s) { s = [NSMutableArray new]; d[kStackKey] = s; }
    return s;
}

static CGContextRef FICMakeFallback(CGSize size, BOOL opaque, CGFloat scale) {
    if (scale <= 0) scale = UIScreen.mainScreen.scale;
    size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
    if (w == 0 || h == 0 || w > 16384 || h > 16384) return NULL;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo info = opaque ? (kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little)
                               : (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, info);
    CGColorSpaceRelease(cs);
    if (!ctx) return NULL;
    // UIKit coordinate system (origin top-left)
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, scale, -scale);
    UIGraphicsPushContext(ctx);
    return ctx;
}

static void hook_BeginOpts(CGSize size, BOOL opaque, CGFloat scale) {
    @try {
        orig_BeginOpts(size, opaque, scale);
        [FICStack() addObject:[NSNull null]];
        return;
    } @catch (NSException *e) {
        NSLog(@"[FixImageContext] caught: %@ -> fallback", e.reason);
    }
    CGContextRef ctx = FICMakeFallback(size, opaque, scale);
    if (ctx) {
        // store: pointer + scale
        [FICStack() addObject:@[[NSValue valueWithPointer:ctx], @(scale > 0 ? scale : UIScreen.mainScreen.scale)]];
    } else {
        NSLog(@"[FixImageContext] fallback failed, size=%@", NSStringFromCGSize(size));
        [FICStack() addObject:@"none"];
    }
}

static void hook_Begin(CGSize size) {
    hook_BeginOpts(size, NO, 1.0);
}

static UIImage *hook_GetImage(void) {
    NSMutableArray *s = FICStack();
    id top = s.lastObject;
    if ([top isKindOfClass:NSArray.class]) {
        CGContextRef ctx = (CGContextRef)[(NSValue *)top[0] pointerValue];
        CGImageRef cg = CGBitmapContextCreateImage(ctx);
        if (!cg) return nil;
        UIImage *img = [UIImage imageWithCGImage:cg scale:[top[1] doubleValue] orientation:UIImageOrientationUp];
        CGImageRelease(cg);
        return img;
    }
    if ([top isKindOfClass:NSString.class]) return nil;
    @try { return orig_GetImage(); } @catch (NSException *e) { return nil; }
}

static void hook_End(void) {
    NSMutableArray *s = FICStack();
    id top = s.lastObject;
    if (!top) return;               // unbalanced End: ignore instead of crashing
    [s removeLastObject];
    if ([top isKindOfClass:NSArray.class]) {
        CGContextRef ctx = (CGContextRef)[(NSValue *)top[0] pointerValue];
        UIGraphicsPopContext();
        CGContextRelease(ctx);
    } else if ([top isKindOfClass:NSString.class]) {
        return;
    } else {
        @try { orig_End(); } @catch (NSException *e) {}
    }
}

__attribute__((constructor))
static void FICInit(void) {
    struct rebinding r[] = {
        {"UIGraphicsBeginImageContext", hook_Begin, (void *)&orig_Begin},
        {"UIGraphicsBeginImageContextWithOptions", hook_BeginOpts, (void *)&orig_BeginOpts},
        {"UIGraphicsGetImageFromCurrentImageContext", hook_GetImage, (void *)&orig_GetImage},
        {"UIGraphicsEndImageContext", hook_End, (void *)&orig_End},
    };
    rebind_symbols(r, 4);
    NSLog(@"[FixImageContext] loaded");
}
