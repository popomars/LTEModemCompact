#include "SystemNetworkStats.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/route.h>
#include <stdlib.h>
#include <string.h>

int lte_read_interface_counters(const char *name, lte_interface_counters *result) {
    if (!name || !result) return -1;
    unsigned int index = if_nametoindex(name);
    if (!index) return -1;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, (int)index};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) || !length) return -1;
    unsigned char *buffer = malloc(length);
    if (!buffer) return -1;
    if (sysctl(mib, 6, buffer, &length, NULL, 0)) { free(buffer); return -1; }
    int found = -1;
    for (size_t offset = 0; length - offset >= 4;) {
        uint16_t message_length;
        memcpy(&message_length, buffer + offset, sizeof(message_length));
        if (message_length < 4 || message_length > length - offset) break;
        if (buffer[offset + 3] == RTM_IFINFO2 && message_length >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 message;
            memcpy(&message, buffer + offset, sizeof(message));
            if (message.ifm_index == index) {
                result->received = message.ifm_data.ifi_ibytes;
                result->sent = message.ifm_data.ifi_obytes;
                result->index = index;
                result->changed_seconds = message.ifm_data.ifi_lastchange.tv_sec;
                result->changed_microseconds = message.ifm_data.ifi_lastchange.tv_usec;
                found = 0;
                break;
            }
        }
        offset += message_length;
    }
    free(buffer);
    return found;
}
