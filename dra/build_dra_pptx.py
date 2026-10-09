#!/usr/bin/env python3
"""Generate RX/TX DRA architecture PowerPoint (16:9)."""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt, Emu

# Palette — deep aerospace (not purple / cream / broadsheet)
INK = RGBColor(0x0C, 0x16, 0x20)
MUTED = RGBColor(0x4A, 0x5A, 0x66)
PAPER = RGBColor(0xF7, 0xF9, 0xFB)
PANEL = RGBColor(0xFF, 0xFF, 0xFF)
LINE = RGBColor(0xD0, 0xD8, 0xE0)
RX = RGBColor(0x0E, 0x6B, 0x7A)
RX_LIGHT = RGBColor(0x1A, 0x9A, 0xAB)
TX = RGBColor(0xA0, 0x5C, 0x18)
TX_LIGHT = RGBColor(0xC2, 0x77, 0x2A)
STEEL = RGBColor(0x14, 0x2E, 0x44)
ROUTER = RGBColor(0x1B, 0x3F, 0x66)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
CHIP = RGBColor(0xE6, 0xF3, 0xF5)
CHIP_TX = RGBColor(0xF7, 0xEE, 0xE2)
DARK = RGBColor(0x07, 0x14, 0x20)

W = Inches(13.333)
H = Inches(7.5)
MX = Inches(0.65)
MY = Inches(0.4)

OUT = Path(__file__).resolve().parent / "DRA_Uplink_Downlink.pptx"
SVG_PNG = Path(__file__).resolve().parent / "block_diagram.png"


def set_run(run, size=18, bold=False, color=INK, font="Calibri"):
    run.font.name = font
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color


def fill_shape(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def stroke_shape(shape, color, width_pt=1.0):
    shape.line.color.rgb = color
    shape.line.width = Pt(width_pt)


def add_rect(slide, left, top, width, height, fill, stroke=None):
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shape.adjustments[0] = 0.08
    fill_shape(shape, fill)
    if stroke:
        stroke_shape(shape, stroke, 1.0)
    return shape


def add_box(slide, left, top, width, height, fill):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    fill_shape(shape, fill)
    return shape


def add_text(slide, left, top, width, height, lines, align=PP_ALIGN.LEFT, valign=MSO_ANCHOR.TOP):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    try:
        tf._txBody.bodyPr.set("anchor", {MSO_ANCHOR.TOP: "t", MSO_ANCHOR.MIDDLE: "ctr", MSO_ANCHOR.BOTTOM: "b"}[valign])
    except Exception:
        pass
    for i, (text, size, bold, color, font) in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = text
        p.alignment = align
        if p.runs:
            set_run(p.runs[0], size, bold, color, font)
        p.space_after = Pt(4)
    return box


def set_bg(slide, color):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def blank(prs):
    return prs.slides.add_slide(prs.slide_layouts[6])


def header(slide, eyebrow, title, subtitle=None, dark=False):
    add_box(slide, 0, 0, W, Inches(0.08), RX_LIGHT if not dark else RX)
    ey_c = RX_LIGHT if not dark else RGBColor(0x5F, 0xD0, 0xE0)
    ti_c = STEEL if not dark else WHITE
    su_c = MUTED if not dark else RGBColor(0x9B, 0xB0, 0xC0)
    add_text(slide, MX, MY, Inches(12), Inches(0.3), [(eyebrow.upper(), 11, True, ey_c, "Calibri")])
    add_text(slide, MX, Inches(0.65), Inches(12), Inches(0.55), [(title, 30, False, ti_c, "Georgia")])
    if subtitle:
        add_text(slide, MX, Inches(1.2), Inches(12), Inches(0.4), [(subtitle, 14, False, su_c, "Calibri")])


def card(slide, left, top, width, height, title, bullets, accent=RX):
    add_rect(slide, left, top, width, height, PANEL, LINE)
    add_box(slide, left, top, Inches(0.08), height, accent)
    lines = [(title, 15, True, INK, "Calibri")]
    for b in bullets:
        lines.append((b, 13, False, MUTED, "Calibri"))
    add_text(slide, left + Inches(0.22), top + Inches(0.16), width - Inches(0.35), height - Inches(0.25), lines)


def device_cell(slide, left, top, width, height, title, sub, fill, accent):
    add_rect(slide, left, top, width, height, fill, accent)
    add_text(
        slide,
        left + Inches(0.08),
        top + Inches(0.12),
        width - Inches(0.16),
        height - Inches(0.16),
        [
            (title, 13, True, INK, "Calibri"),
            (sub, 11, False, MUTED, "Calibri"),
        ],
        align=PP_ALIGN.CENTER,
    )


def pipe_step(slide, left, top, width, height, title, sub, fill, accent):
    add_rect(slide, left, top, width, height, fill, accent)
    add_text(
        slide,
        left + Inches(0.06),
        top + Inches(0.1),
        width - Inches(0.12),
        height - Inches(0.12),
        [
            (title, 12, True, INK, "Calibri"),
            (sub, 10, False, MUTED, "Calibri"),
        ],
        align=PP_ALIGN.CENTER,
    )


def build():
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H

    # ---- 1 Title ----
    s = blank(prs)
    set_bg(s, DARK)
    add_box(s, 0, 0, Inches(0.18), H, RX_LIGHT)
    add_text(s, MX, Inches(1.8), Inches(11), Inches(0.35),
             [("ALTERA · SPACE / NTN PAYLOAD", 12, True, RX_LIGHT, "Calibri")])
    add_text(s, MX, Inches(2.25), Inches(11.5), Inches(1.2),
             [("RX / TX Direct Radiating Array", 40, False, WHITE, "Georgia"),
              ("Architecture", 40, False, WHITE, "Georgia")])
    add_text(s, MX, Inches(4.0), Inches(11), Inches(0.9),
             [("Ku-band uplink & downlink · AGRW027/039 device clusters", 16, False, RGBColor(0x9B, 0xB0, 0xC0), "Calibri"),
              ("Direct-RF 64 Gsps · Digital beamforming · 58 Gbps SerDes fabric", 16, False, RGBColor(0x9B, 0xB0, 0xC0), "Calibri")])
    add_text(s, MX, Inches(6.6), Inches(11), Inches(0.3),
             [("Conservative option: physically separate TX / RX silicon paths (9 devices)", 12, False, RGBColor(0x7A, 0x93, 0xA6), "Calibri")])

    # ---- 2 System overview ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "System Overview", "End-to-end DRA payload signal path",
           "Antenna → RF front-end → device cluster DSP → router fabric → opposite-side cluster")
    card(s, MX, Inches(1.85), Inches(5.9), Inches(2.3), "RX DRA — Uplink",
         ["14.0–14.5 GHz, 32 spot beams",
          "4× AGRW027/039 (ADC side)",
          "8 ADC channels / device",
          "DVB-RCS2 / 3GPP-NTN Low-PHY handoff"], RX)
    card(s, Inches(6.9), Inches(1.85), Inches(5.9), Inches(2.3), "TX DRA — Downlink",
         ["10.7–12.75 GHz",
          "40 beams (NTN) / 32 (DVB-S2X)",
          "5× AGRW027/039 (DAC side)",
          "DVB-S2X / 3GPP-NTN Low-PHY framer"], TX)
    card(s, MX, Inches(4.4), Inches(12.0), Inches(2.4), "Onboard Router / Switch Fabric",
         ["58 Gbps SerDes interconnect between device clusters and Feeder-link stage",
          "Bridges uplink Low-PHY handoff to downlink framer / beamforming path",
          "Supports coherent multi-device operation with phase-sync IP across the cluster"], ROUTER)

    # ---- 3 Full block diagram image ----
    s = blank(prs)
    set_bg(s, DARK)
    if SVG_PNG.exists():
        # Full-bleed diagram slide (diagram already has its own title chrome)
        # Fit to slide with small margin while preserving aspect (1600x1100)
        margin = Inches(0.2)
        avail_w = W - 2 * margin
        avail_h = H - 2 * margin
        aspect = 1600 / 1100
        if avail_w / avail_h > aspect:
            pic_h = avail_h
            pic_w = pic_h * aspect
        else:
            pic_w = avail_w
            pic_h = pic_w / aspect
        left = (W - pic_w) / 2
        top = (H - pic_h) / 2
        s.shapes.add_picture(str(SVG_PNG), left, top, width=pic_w, height=pic_h)
    else:
        header(s, "Block Diagram", "Full RX → Router → TX architecture", dark=True)
        add_text(s, MX, Inches(3.0), Inches(12), Inches(1),
                 [("block_diagram.png not found — run export first", 16, False, WHITE, "Calibri")])

    # ---- 4 RX cluster ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "RX DRA — Uplink", "4-device ADC cluster · 32 spot beams",
           "Antenna / Feed Array → LNA Front-End → RX Device Cluster")
    labels = [
        ("Device 1", "8 ADC ch · Beams 1–8"),
        ("Device 2", "8 ADC ch · Beams 9–16"),
        ("Device 3", "8 ADC ch · Beams 17–24"),
        ("Device 4", "8 ADC ch · Beams 25–32"),
    ]
    x0 = MX
    cell_w = Inches(2.9)
    gap = Inches(0.18)
    for i, (t, sub) in enumerate(labels):
        device_cell(s, x0 + i * (cell_w + gap), Inches(1.9), cell_w, Inches(1.35), t, sub, CHIP, RX)
    add_text(s, MX, Inches(3.5), Inches(12), Inches(0.35),
             [("Per-device DSP pipeline", 14, True, STEEL, "Calibri")])
    steps = [
        ("Direct-RF ADC", "64 Gsps · 1st Nyquist"),
        ("DDC", "Digital downconvert"),
        ("DBFN", "4-color · 8-way spatial"),
        ("UL Channelizer", "4 × 125 MHz / beam"),
        ("Low-PHY", "DVB-RCS2 / 3GPP-NTN"),
    ]
    sw = Inches(2.25)
    for i, (t, sub) in enumerate(steps):
        pipe_step(s, MX + i * (sw + Inches(0.15)), Inches(3.95), sw, Inches(1.15), t, sub, PANEL, RX)
    add_text(s, MX, Inches(5.5), Inches(12), Inches(1.2),
             [("Front-end: Antenna/Feed Array → LNA → Device cluster", 13, False, MUTED, "Calibri"),
              ("Handoff into onboard router / switch fabric for feeder and TX path", 13, False, MUTED, "Calibri")])

    # ---- 5 TX cluster ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "TX DRA — Downlink", "5-device DAC cluster · 40 / 32 spot beams",
           "Device Cluster → HPA Front-End → Antenna / Feed Array")
    labels = [
        ("Device 1", "8 DAC · Beams 1–8"),
        ("Device 2", "8 DAC · Beams 9–16"),
        ("Device 3", "8 DAC · Beams 17–24"),
        ("Device 4", "8 DAC · Beams 25–32"),
        ("Device 5 *", "8 DAC · Beams 33–40"),
    ]
    cell_w = Inches(2.3)
    gap = Inches(0.12)
    for i, (t, sub) in enumerate(labels):
        device_cell(s, MX + i * (cell_w + gap), Inches(1.9), cell_w, Inches(1.25), t, sub, CHIP_TX, TX)
    add_text(s, MX, Inches(3.4), Inches(12), Inches(0.35),
             [("Per-device DSP pipeline", 14, True, STEEL, "Calibri")])
    steps = [
        ("Low-PHY Framer", "DVB-S2X / 3GPP-NTN"),
        ("DBFN", "4-color · 8–10 way"),
        ("DUC", "Digital upconvert"),
        ("Direct-RF DAC", "64 Gsps synthesis"),
    ]
    sw = Inches(2.85)
    for i, (t, sub) in enumerate(steps):
        pipe_step(s, MX + i * (sw + Inches(0.2)), Inches(3.85), sw, Inches(1.15), t, sub, PANEL, TX)
    add_text(s, MX, Inches(5.35), Inches(12), Inches(1.3),
             [("* Device 5 carries 4 spare/idle DAC channels in DVB-S2X-only mode (32 beams)", 13, False, MUTED, "Calibri"),
              ("NTN mode uses full 40-beam map; DVB-S2X-only parks spare channels on Device 5", 13, False, MUTED, "Calibri")])

    # ---- 6 DSP detail ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "Digital Signal Processing", "Beamforming, reuse, and channelization",
           "Same 4-color reuse concept on both links; spatial reuse scaled to beam count")
    card(s, MX, Inches(1.85), Inches(5.9), Inches(4.6), "Uplink DSP (per RX device)",
         ["Direct-RF ADC at 64 Gsps (1st Nyquist sampling)",
          "DDC into digital baseband / IF",
          "Digital Beamforming Network",
          "  · 4-color frequency reuse",
          "  · 8-way spatial reuse",
          "UL channelizer: 4 × 125 MHz per beam",
          "Handoff: DVB-RCS2 or 3GPP-NTN Low-PHY"], RX)
    card(s, Inches(6.9), Inches(1.85), Inches(5.9), Inches(4.6), "Downlink DSP (per TX device)",
         ["DVB-S2X / 3GPP-NTN Low-PHY framer",
          "Digital Beamforming Network",
          "  · 4-color frequency reuse",
          "  · 8–10 way spatial reuse",
          "DUC to RF synthesis band",
          "Direct-RF DAC at 64 Gsps",
          "HPA front-end → antenna / feed array"], TX)

    # ---- 7 Isolation & control ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "Platform Notes", "Isolation, compute, and synchronization",
           "Conservative silicon split for RF cleanliness and coherent array control")
    card(s, MX, Inches(1.85), Inches(3.9), Inches(4.5), "TX / RX Isolation",
         ["Physically separate silicon & RF paths",
          "9 devices total: 5 TX + 4 RX",
          "Cleanest TX→RX isolation option",
          "Independent ADC vs DAC clusters"], RX)
    card(s, Inches(4.75), Inches(1.85), Inches(3.9), Inches(4.5), "Control Plane",
         ["Quad-core Arm Cortex-A53 (HPS)",
          "Per-device control & telemetry",
          "Configures DDC/DUC, DBFN, PHY",
          "Health / status reporting"], ROUTER)
    card(s, Inches(8.5), Inches(1.85), Inches(4.15), Inches(4.5), "Phase Sync",
         ["Multi-device phase-sync IP",
          "Cluster-wide coherent beamforming",
          "Required for spatial reuse",
          "Aligns ADC/DAC sampling clocks"], TX)

    # ---- 8 Key specs summary ----
    s = blank(prs)
    set_bg(s, PAPER)
    header(s, "Key Specifications", "Quick reference table")

    rows = [
        ("Domain", "RX Uplink", "TX Downlink"),
        ("Band", "14.0–14.5 GHz", "10.7–12.75 GHz"),
        ("Beams", "32 spot beams", "40 (NTN) / 32 (DVB-S2X)"),
        ("Devices", "4 × AGRW027/039", "5 × AGRW027/039"),
        ("Converters", "8 ADC ch / device", "8 DAC ch / device"),
        ("Sample rate", "64 Gsps (1st Nyquist)", "64 Gsps synthesis"),
        ("Beamforming", "4-color · 8-way", "4-color · 8–10 way"),
        ("Channelization", "4 × 125 MHz / beam", "—"),
        ("Air interface", "DVB-RCS2 / 3GPP-NTN", "DVB-S2X / 3GPP-NTN"),
        ("Interconnect", "58 Gbps SerDes fabric", "58 Gbps SerDes fabric"),
    ]
    table_shape = s.shapes.add_table(len(rows), 3, MX, Inches(1.7), Inches(12.0), Inches(5.2))
    table = table_shape.table
    table.columns[0].width = Inches(2.6)
    table.columns[1].width = Inches(4.7)
    table.columns[2].width = Inches(4.7)
    for r, row in enumerate(rows):
        for c, val in enumerate(row):
            cell = table.cell(r, c)
            cell.text = val
            p = cell.text_frame.paragraphs[0]
            run = p.runs[0]
            if r == 0:
                set_run(run, 12, True, WHITE)
                cell.fill.solid()
                cell.fill.fore_color.rgb = STEEL
            else:
                set_run(run, 12, c == 0, INK if c == 0 else MUTED)
                cell.fill.solid()
                cell.fill.fore_color.rgb = PANEL if r % 2 else RGBColor(0xEE, 0xF3, 0xF6)

    # ---- 9 Closing ----
    s = blank(prs)
    set_bg(s, DARK)
    add_box(s, 0, 0, Inches(0.18), H, TX_LIGHT)
    add_text(s, MX, Inches(2.2), Inches(11), Inches(0.35),
             [("SUMMARY", 12, True, RX_LIGHT, "Calibri")])
    add_text(s, MX, Inches(2.7), Inches(11.5), Inches(1.4),
             [("Nine-device DRA payload with", 32, False, WHITE, "Georgia"),
              ("separated RX and TX paths", 32, False, WHITE, "Georgia")])
    add_text(s, MX, Inches(4.5), Inches(11), Inches(1.5), [
        ("32-beam Ku uplink + 40/32-beam Ku downlink", 15, False, RGBColor(0x9B, 0xB0, 0xC0), "Calibri"),
        ("Direct-RF 64 Gsps ADC/DAC · digital beamforming · 58 Gbps fabric", 15, False, RGBColor(0x9B, 0xB0, 0xC0), "Calibri"),
        ("Arm HPS control plane · multi-device phase sync for coherent arrays", 15, False, RGBColor(0x9B, 0xB0, 0xC0), "Calibri"),
    ])

    prs.save(OUT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    build()
