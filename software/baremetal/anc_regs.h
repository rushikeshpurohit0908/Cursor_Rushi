#ifndef ANC_REGS_H
#define ANC_REGS_H

#include <stdint.h>

/* LWH2F physical base — Agilex 5 SoC HPS TRM */
#define ANC_LWH2F_BASE        0x20000000u
#define ANC_LWH2F_SIZE        0x00200000u

#define ANC_REG_CONTROL       0x00u
#define ANC_REG_STATUS        0x04u
#define ANC_REG_MU            0x08u
#define ANC_REG_MEM_ADDR      0x0Cu
#define ANC_REG_MEM_DATA      0x10u
#define ANC_REG_SAMPLE_COUNT  0x14u
#define ANC_REG_AI_OVERRIDE   0x18u
#define ANC_REG_OUTPUT_GAIN   0x1Cu
#define ANC_REG_MEM_SEL       0x20u
#define ANC_REG_LEAK          0x24u
#define ANC_REG_MODE          0x28u
#define ANC_REG_I2C_CTRL      0x2Cu
#define ANC_REG_I2C_DATA      0x30u
#define ANC_REG_NOTCH_FREQ    0x34u
#define ANC_REG_VERSION       0x3Cu

#define ANC_CTRL_ENABLE       (1u << 0)
#define ANC_CTRL_BYPASS       (1u << 1)
#define ANC_CTRL_RESET_ADAPT  (1u << 2)
#define ANC_CTRL_CODEC_INIT   (1u << 3)
#define ANC_CTRL_NOTCH_EN     (1u << 4)

#define ANC_MODE_HYBRID       0u
#define ANC_MODE_FF_FROZEN    1u
#define ANC_MODE_FF_VIRTUAL   2u
#define ANC_MODE_CALIB        3u

#define ANC_MEM_SECONDARY     0u
#define ANC_MEM_ADAPTIVE      1u
#define ANC_MEM_PRIMARY       2u

#define ANC_VERSION_EXPECTED  0x00020000u

#define ANC_STATUS_RUNNING    (1u << 0)
#define ANC_STATUS_CLIP       (1u << 1)
#define ANC_STATUS_AI_SHIFT   4
#define ANC_STATUS_CODEC_RDY  (1u << 8)
#define ANC_STATUS_I2C_BUSY   (1u << 9)

static inline uint32_t anc_read(volatile uint32_t *base, uint32_t off)
{
    return base[off / 4u];
}

static inline void anc_write(volatile uint32_t *base, uint32_t off, uint32_t v)
{
    base[off / 4u] = v;
}

static inline void anc_set_mode(volatile uint32_t *base, uint32_t mode)
{
    anc_write(base, ANC_REG_MODE, mode & 3u);
}

static inline void anc_enable(volatile uint32_t *base, int on)
{
    uint32_t c = anc_read(base, ANC_REG_CONTROL);
    if (on)
        c = (c | ANC_CTRL_ENABLE) & ~ANC_CTRL_BYPASS;
    else
        c &= ~ANC_CTRL_ENABLE;
    anc_write(base, ANC_REG_CONTROL, c);
}

static inline void anc_load_fir(volatile uint32_t *base, uint32_t sel,
                                const int32_t *c, unsigned n)
{
    unsigned i;
    anc_write(base, ANC_REG_MEM_SEL, sel);
    for (i = 0; i < n; i++) {
        anc_write(base, ANC_REG_MEM_ADDR, i);
        anc_write(base, ANC_REG_MEM_DATA, (uint32_t)c[i]);
    }
}

#endif
