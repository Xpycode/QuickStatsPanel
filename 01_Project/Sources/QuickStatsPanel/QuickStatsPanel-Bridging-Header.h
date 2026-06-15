//
//  QuickStatsPanel-Bridging-Header.h
//  QuickStatsPanel
//
//  C declarations for Apple's PRIVATE, un-entitled **IOReport** framework — the
//  permission-free path to live SoC energy counters (D-019 Power tile). IOReport
//  ships no public header and has no Swift overlay, so we declare the prototypes
//  ourselves here and link the symbols directly (`OTHER_LDFLAGS: -lIOReport`,
//  resolves against /usr/lib/libIOReport.tbd in the dyld shared cache — no dlopen,
//  no relocated-framework Library-Validation issue). Precedent: NeoAsitop (Swift),
//  socpowerbud (ObjC), macmon (Rust). No public API contract — channel names can
//  drift per chip generation, so the Swift side degrades to "hidden tile" rather
//  than crashing when the Energy Model channels don't resolve.
//
//  Type choices are deliberate so Swift bridges these cleanly:
//    • Copy/Create functions return CF types → imported as `Unmanaged<…>!`
//      (we own a +1; release explicitly — see IOReport.swift's CF accounting).
//    • NSString* getters → imported as `String!` (compare/route on plain Strings).
//    • IOReportSubscriptionRef (pointer to opaque struct) → Swift `OpaquePointer?`.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

typedef struct __IOReportSubscription* IOReportSubscriptionRef;   // → Swift OpaquePointer
typedef CFDictionaryRef IOReportSampleRef;
typedef int (^ioreportiterateblock)(IOReportSampleRef ch);

extern CFMutableDictionaryRef IOReportCopyAllChannels(uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void* a, CFMutableDictionaryRef desired,
        CFMutableDictionaryRef* subbedOut, uint64_t channel_id, CFTypeRef b);   // subbedOut is OUT
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
        CFMutableDictionaryRef subbed, CFTypeRef a);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef a);
extern void IOReportIterate(CFDictionaryRef samples, ioreportiterateblock);
extern NSString* IOReportChannelGetGroup(CFDictionaryRef);
extern NSString* IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString* IOReportChannelGetUnitLabel(CFDictionaryRef);
extern int       IOReportChannelGetFormat(CFDictionaryRef);
extern long      IOReportSimpleGetIntegerValue(CFDictionaryRef, int);
