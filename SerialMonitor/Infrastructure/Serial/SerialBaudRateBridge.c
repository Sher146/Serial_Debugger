#include <stdint.h>
#include <sys/ioctl.h>
#include <IOKit/serial/ioss.h>

// Swift cannot import IOSSIOSPEED because it is a function-like C macro.
int serial_monitor_set_custom_baud_rate(int file_descriptor, uint64_t baud_rate) {
    speed_t speed = (speed_t)baud_rate;
    return ioctl(file_descriptor, IOSSIOSPEED, &speed);
}
