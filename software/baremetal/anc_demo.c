/* Minimal HPS userspace / bare-metal demo.
 * Linux: mmap /dev/mem at ANC_LWH2F_BASE and call anc_enable().
 * Bare-metal: cast ANC_LWH2F_BASE to a pointer (after MMU setup).
 */

#include "anc_regs.h"
#include <stdio.h>

#ifdef __linux__
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

int main(void)
{
#ifdef __linux__
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("/dev/mem");
        return 1;
    }
    volatile uint32_t *base = mmap(NULL, ANC_LWH2F_SIZE, PROT_READ | PROT_WRITE,
                                   MAP_SHARED, fd, ANC_LWH2F_BASE);
    if (base == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
#else
    volatile uint32_t *base = (volatile uint32_t *)ANC_LWH2F_BASE;
#endif

    uint32_t ver = anc_read(base, ANC_REG_VERSION);
    printf("ANC version 0x%08x (expect 0x%08x)\n", ver, ANC_VERSION_EXPECTED);

    anc_write(base, ANC_REG_CONTROL, ANC_CTRL_CODEC_INIT);
    anc_write(base, ANC_REG_MU, 0x4000);
    anc_write(base, ANC_REG_LEAK, 0x0008);
    anc_set_mode(base, ANC_MODE_HYBRID);
    anc_enable(base, 1);

    uint32_t st = anc_read(base, ANC_REG_STATUS);
    printf("status=0x%08x samples=%u\n", st, anc_read(base, ANC_REG_SAMPLE_COUNT));

#ifdef __linux__
    munmap((void *)base, ANC_LWH2F_SIZE);
    close(fd);
#endif
    return 0;
}
