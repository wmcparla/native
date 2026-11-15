// Fold, open and turn the iPhone Duo simulator from a script (fork only).
//
//   duo-pose swap <position>          0 closed .. 1 open flat; SpringBoard sweeps and swaps displays
//   duo-pose pose <orientation> <hinge> [tabletop]  device orientation 1-6, hinge state 0-4 (3 open flat), tabletop pose 0-10
//   duo-pose get                      the pose SpringBoard holds
//
// The same SpringBoardServices calls vphoned makes on Birch's Duo VM
// (vphone-cli VPhoneDaemon/Native/vphoned_pose.m): the display tool service
// behind Apple's `suiatool swap`, and the test-automation pose override.
// Run inside the simulator with `xcrun simctl spawn`.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>

typedef struct {
    int64_t orientation;
    int32_t deviceOrientation;
    int32_t hingeState;
    int32_t tabletopPose;
} DevicePose;

typedef struct {
    int64_t state;
    double duration;
    int64_t deviceOrientation;
    int64_t profileOverride;
    bool waitForCompletion;
    int64_t targetMode;
    double targetHingePosition;
    double reserved;
} SwapSettings;

static void need(const char *cls, SEL sel, const char *encoding, Class *out) {
    Class c = NSClassFromString(@(cls));
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m) { fprintf(stderr, "%s has no %s\n", cls, sel_getName(sel)); exit(2); }
    if (encoding && strcmp(method_getTypeEncoding(m), encoding) != 0)
        fprintf(stderr, "warning: %s %s is %s, expected %s\n", cls, sel_getName(sel), method_getTypeEncoding(m), encoding);
    *out = c;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW)) {
            fprintf(stderr, "dlopen: %s\n", dlerror());
            return 2;
        }
        NSString *cmd = argc > 1 ? @(argv[1]) : @"get";
        if ([cmd isEqualToString:@"swap"] && argc > 2) {
            Class c;
            SEL sel = NSSelectorFromString(@"swapDisplayWithSettings:completion:");
            need("SBSDisplayToolService", sel, "v88@0:8{?=qdqqBqdd}16@?80", &c);
            SwapSettings s = {.duration = -1, .waitForCompletion = true, .targetMode = 1,
                              .targetHingePosition = atof(argv[2])};
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            NSDate *start = [NSDate date];
            id client = [c new];
            ((void (*)(id, SEL, SwapSettings, void (^)(void)))objc_msgSend)(client, sel, s, ^{
                dispatch_semaphore_signal(done);
            });
            long waited = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
            printf("swap %s: %s after %.2f s\n", argv[2], waited == 0 ? "replied" : "no reply",
                   -start.timeIntervalSinceNow);
            ((void (*)(id, SEL))objc_msgSend)(client, NSSelectorFromString(@"invalidate"));
            return waited == 0 ? 0 : 1;
        }
        if ([cmd isEqualToString:@"pose"] && argc > 3) {
            int tabletop = argc > 4 ? atoi(argv[4]) : 0;
            Class c;
            SEL sel = NSSelectorFromString(@"setDevicePoseOverride:");
            need("SBSTestAutomationService", sel, NULL, &c);
            DevicePose p = {atoi(argv[2]), atoi(argv[2]), atoi(argv[3]), tabletop};
            ((void (*)(id, SEL, DevicePose))objc_msgSend)([c new], sel, p);
            printf("pose orientation %d hinge %d tabletop %d sent\n", p.deviceOrientation, p.hingeState, p.tabletopPose);
            return 0;
        }
        Class c;
        SEL sel = NSSelectorFromString(@"getDevicePose");
        need("SBSTestAutomationService", sel, "{?=qiii}16@0:8", &c);
        DevicePose p = ((DevicePose (*)(id, SEL))objc_msgSend)([c new], sel);
        printf("orientation %lld device_orientation %d hinge %d tabletop %d\n", p.orientation,
               p.deviceOrientation, p.hingeState, p.tabletopPose);
        return 0;
    }
}
