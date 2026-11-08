#ifndef USB_LAUNCH_EVENTS_H
#define USB_LAUNCH_EVENTS_H
#include <stdint.h>
void lte_listen_usb_events(void (*callback)(uint64_t));
int lte_is_supported_usb_device(uint64_t registry_id);
#endif
