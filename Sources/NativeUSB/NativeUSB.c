#include "NativeUSB.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>
#include <IOKit/usb/USB.h>
#include <stdio.h>
#include <stdlib.h>

struct NMUSB { IOUSBInterfaceInterface550 **interface; UInt8 input; UInt8 output; IOReturn last_error; };

static int property(io_registry_entry_t entry, CFStringRef name, int *value) {
    CFTypeRef item = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, name,
        kCFAllocatorDefault, kIORegistryIterateParents | kIORegistryIterateRecursively);
    int ok = item && CFGetTypeID(item) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)item, kCFNumberIntType, value);
    if (item) CFRelease(item);
    return ok;
}

static int supported(io_service_t service, NMDevice *device) {
    int vendor = 0, product = 0, number = -1, cls = -1, sub = -1, proto = -1, location = 0;
    property(service, CFSTR("idVendor"), &vendor);
    property(service, CFSTR("idProduct"), &product);
    property(service, CFSTR("bInterfaceNumber"), &number);
    property(service, CFSTR("bInterfaceClass"), &cls);
    property(service, CFSTR("bInterfaceSubClass"), &sub);
    property(service, CFSTR("bInterfaceProtocol"), &proto);
    property(service, CFSTR("locationID"), &location);
    // Only the identity and AT layout verified on this project's QDC507 hardware.
    // In particular, never touch ECM, audio or ff/42/01 (ADB).
    if (vendor != 0x2ca3 || product != 0x4006 || number != 2 || cls != 0xff ||
        (sub == 0x42 && proto == 1)) return 0;
    uint64_t registry = 0;
    if (IORegistryEntryGetRegistryEntryID(service, &registry) != KERN_SUCCESS) return 0;
    *device = (NMDevice){registry, (uint32_t)location, (uint16_t)vendor, (uint16_t)product};
    return 1;
}

int nm_devices(NMDevice *devices, size_t capacity) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iterator) != KERN_SUCCESS) return -1;
    int count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        NMDevice device;
        if (supported(service, &device)) {
            if ((size_t)count < capacity) devices[count] = device;
            count++;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return count;
}

NMUSB *nm_open(uint64_t registry_id, char *error, size_t capacity) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registry_id));
    NMDevice device;
    if (!service || !supported(service, &device)) {
        if (service) IOObjectRelease(service);
        snprintf(error, capacity, "设备已移除或 AT 描述符不匹配"); return NULL;
    }
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    IOUSBInterfaceInterface550 **interface = NULL;
    if (result == kIOReturnSuccess && plugin) {
        HRESULT query = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID550), (LPVOID *)&interface);
        (*plugin)->Release(plugin);
        if (query != S_OK) interface = NULL;
    }
    if (!interface) { snprintf(error, capacity, "无法访问 USB AT 接口 (0x%08x)", result); return NULL; }
    result = (*interface)->USBInterfaceOpen(interface);
    if (result != kIOReturnSuccess) {
        (*interface)->Release(interface);
        snprintf(error, capacity, "AT 接口被占用、未获配件许可或不可访问 (0x%08x)", result); return NULL;
    }
    NMUSB *usb = calloc(1, sizeof(*usb));
    if (!usb) { (*interface)->USBInterfaceClose(interface); (*interface)->Release(interface); return NULL; }
    usb->interface = interface;
    UInt8 endpoints = 0;
    (*interface)->GetNumEndpoints(interface, &endpoints);
    for (UInt8 pipe = 1; pipe <= endpoints; pipe++) {
        UInt8 direction, number, type, interval; UInt16 packet;
        result = (*interface)->GetPipeProperties(interface, pipe, &direction, &number, &type, &packet, &interval);
        if (result != kIOReturnSuccess || type != kUSBBulk) continue;
        if (direction == kUSBIn && number == 4) usb->input = pipe;
        if (direction == kUSBOut && number == 3) usb->output = pipe;
    }
    if (!usb->input || !usb->output) {
        snprintf(error, capacity, "AT 端点必须为 bulk 0x84/0x03"); nm_close(usb); return NULL;
    }
    return usb;
}

int nm_write(NMUSB *usb, const void *bytes, uint32_t length, uint32_t timeout) {
    return (*usb->interface)->WritePipeTO(usb->interface, usb->output, (void *)bytes, length, timeout, timeout) == kIOReturnSuccess ? 0 : -1;
}
int nm_read(NMUSB *usb, void *bytes, uint32_t capacity, uint32_t timeout) {
    UInt32 count = capacity;
    IOReturn result = (*usb->interface)->ReadPipeTO(usb->interface, usb->input, bytes, &count, timeout, timeout);
    usb->last_error = result;
    if (result == kIOReturnSuccess) return (int)count;
    if (result == kIOReturnTimeout || result == kIOUSBTransactionTimeout) return 0;
    return -1;
}
uint32_t nm_last_error(NMUSB *usb) { return usb->last_error; }
void nm_close(NMUSB *usb) {
    if (!usb) return;
    (*usb->interface)->USBInterfaceClose(usb->interface);
    (*usb->interface)->Release(usb->interface);
    free(usb);
}
