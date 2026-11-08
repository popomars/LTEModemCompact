#ifndef SYSTEM_NETWORK_STATS_H
#define SYSTEM_NETWORK_STATS_H
#include <stdint.h>
typedef struct {
    uint64_t received;
    uint64_t sent;
    uint32_t index;
    int32_t changed_seconds;
    int32_t changed_microseconds;
} lte_interface_counters;
// Read-only 64-bit kernel counters. Returns 0 on success, -1 if unavailable.
int lte_read_interface_counters(const char *name, lte_interface_counters *result);
#endif
