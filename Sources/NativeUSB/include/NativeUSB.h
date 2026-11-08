#ifndef NATIVE_USB_H
#define NATIVE_USB_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    uint64_t registry_id;
    uint32_t location;
    uint16_t vendor;
    uint16_t product;
} NMDevice;
typedef struct NMUSB NMUSB;
// Returns the total number of supported AT interfaces; never opens any interface.
int nm_devices(NMDevice *devices, size_t capacity);
// Opens only the selected AT interface without seizing another owner's interface.
NMUSB *nm_open(uint64_t registry_id, char *error, size_t capacity);
int nm_write(NMUSB *usb, const void *bytes, uint32_t length, uint32_t timeout);
// Zero means a timed-out read. Negative means disconnect or another USB error.
int nm_read(NMUSB *usb, void *bytes, uint32_t capacity, uint32_t timeout);
uint32_t nm_last_error(NMUSB *usb);
void nm_close(NMUSB *usb);
#endif
