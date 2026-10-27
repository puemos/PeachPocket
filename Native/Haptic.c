#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    int32_t waveform[24] = {6, 6, 6, 6, 6, 6, 6, 6, 6, 6};
    useconds_t gap[24] = {150000, 150000, 450000, 150000, 150000, 450000, 150000, 150000, 150000, 160000};
    int count = 10;
    if (argc > 2) { puts("Invalid vibration arguments."); return 2; }
    if (argc == 2) {
        char *cursor = argv[1];
        count = 0;
        long total = 0;
        while (*cursor) {
            char *end = NULL;
            long kind = strtol(cursor, &end, 10);
            if (end == cursor || *end != ':' || (kind != 4 && kind != 6) || count >= 24) { puts("Invalid vibration pattern."); return 2; }
            cursor = end + 1;
            long delay = strtol(cursor, &end, 10);
            if (end == cursor || (*end && *end != ',') || delay < 60 || delay > 600) { puts("Invalid vibration timing."); return 2; }
            total += delay;
            if (total > 2800) { puts("Pattern is too long to finish before sleep."); return 2; }
            waveform[count] = (int32_t)kind;
            gap[count++] = (useconds_t)(delay * 1000);
            if (*end == ',' && !end[1]) { puts("Invalid vibration pattern."); return 2; }
            cursor = *end ? end + 1 : end;
        }
        if (!count) { puts("Add at least one tap."); return 2; }
    }
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) != KERN_SUCCESS) {
        puts("Trackpad not found."); return 1;
    }
    uint64_t deviceID = 0;
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef capable = IORegistryEntryCreateCFProperty(entry, CFSTR("ForceSupported"), kCFAllocatorDefault, 0);
        CFTypeRef identifier = IORegistryEntryCreateCFProperty(entry, CFSTR("Multitouch ID"), kCFAllocatorDefault, 0);
        if (capable && CFGetTypeID(capable) == CFBooleanGetTypeID() && CFBooleanGetValue(capable) && identifier && CFGetTypeID(identifier) == CFNumberGetTypeID()) {
            CFNumberGetValue(identifier, kCFNumberSInt64Type, &deviceID);
        }
        if (capable) CFRelease(capable);
        if (identifier) CFRelease(identifier);
        IOObjectRelease(entry);
        if (deviceID) break;
    }
    IOObjectRelease(iterator);
    if (!deviceID) { puts("No Force Touch actuator found."); return 1; }
    void *library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!library) { puts("Direct trackpad vibration is unavailable on this macOS."); return 1; }
    CFTypeRef (*create)(uint64_t) = (CFTypeRef (*)(uint64_t))dlsym(library, "MTActuatorCreateFromDeviceID");
    IOReturn (*openActuator)(CFTypeRef) = (IOReturn (*)(CFTypeRef))dlsym(library, "MTActuatorOpen");
    IOReturn (*closeActuator)(CFTypeRef) = (IOReturn (*)(CFTypeRef))dlsym(library, "MTActuatorClose");
    IOReturn (*actuate)(CFTypeRef, int32_t, uint32_t, float, float) = (IOReturn (*)(CFTypeRef, int32_t, uint32_t, float, float))dlsym(library, "MTActuatorActuate");
    if (!create || !openActuator || !closeActuator || !actuate) { puts("Actuator interface unavailable."); dlclose(library); return 1; }
    CFTypeRef actuator = create(deviceID);
    if (!actuator) { puts("Could not connect to the trackpad actuator."); dlclose(library); return 1; }
    IOReturn result = openActuator(actuator);
    if (result == kIOReturnSuccess) {
        for (int i = 0; i < count; i++) {
            result = actuate(actuator, waveform[i], 0, 0.0f, 0.0f);
            if (result != kIOReturnSuccess) break;
            usleep(gap[i]);
        }
        closeActuator(actuator);
    }
    CFRelease(actuator);
    dlclose(library);
    if (result != kIOReturnSuccess) { printf("Trackpad rejected vibration (0x%08x).\n", result); return 1; }
    printf("%d physical taps sent.\n", count);
    return 0;
}
