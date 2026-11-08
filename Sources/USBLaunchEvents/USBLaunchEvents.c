#include "USBLaunchEvents.h"
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <IOKit/IOKitLib.h>

int lte_is_supported_usb_device(uint64_t registry_id) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registry_id));
    if (!service) return 0;
    CFTypeRef vendor = IORegistryEntryCreateCFProperty(service, CFSTR("idVendor"), kCFAllocatorDefault, 0);
    CFTypeRef product = IORegistryEntryCreateCFProperty(service, CFSTR("idProduct"), kCFAllocatorDefault, 0);
    int v = 0, p = 0;
    if (vendor && CFGetTypeID(vendor) == CFNumberGetTypeID()) CFNumberGetValue(vendor, kCFNumberIntType, &v);
    if (product && CFGetTypeID(product) == CFNumberGetTypeID()) CFNumberGetValue(product, kCFNumberIntType, &p);
    if (vendor) CFRelease(vendor);
    if (product) CFRelease(product);
    IOObjectRelease(service);
    return v == 0x2ca3 && p == 0x4006;
}
void lte_listen_usb_events(void (*callback)(uint64_t)) {
    // Must consume the stream early, even for disabled mode or stale events.
    xpc_set_event_stream_handler("com.apple.iokit.matching", dispatch_get_main_queue(), ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) return;
        uint64_t registry_id = xpc_dictionary_get_uint64(event, "IOMatchLaunchServiceID");
        if (registry_id && callback) callback(registry_id);
    });
}
