#!/usr/bin/env python3
"""
Build a single editable 16:9 PowerPoint slide that recreates the
RX/TX DRA architecture diagram with native shapes (not a flat image).
"""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import nsmap, qn
from pptx.util import Emu, Inches, Pt
from lxml import etree

# Palette matched to reference slide
DARK = RGBColor(0x07, 0x14, 0x20)
PANEL_RX = RGBColor(0x0A, 0x1A, 0x26)
PANEL_TX = RGBColor(0x1A, 0x14, 0x0C)
BOX_RX = RGBColor(0x12, 0x34, 0x45)
BOX_RX_DEEP = RGBColor(0x0E, 0x2A, 0x35)
BOX_RX_DEV = RGBColor(0x15, 0x48, 0x54)
BOX_TX = RGBColor(0x2A, 0x1E, 0x12)
BOX_TX_DEEP = RGBColor(0x24, 0x18, 0x0E)
BOX_TX_DEV = RGBColor(0x3A, 0x28, 0x14)
RX = RGBColor(0x1A, 0x9A, 0xAB)
RX_LIGHT = RGBColor(0x5F, 0xD0, 0xE0)
TX = RGBColor(0xC2, 0x77, 0x2A)
TX_LIGHT = RGBColor(0xE0, 0xA4, 0x5F)
ROUTER = RGBColor(0x1B, 0x3F, 0x66)
ROUTER_EDGE = RGBColor(0x4A, 0x7D, 0xB0)
WHITE = RGBColor(0xF2, 0xF6, 0xF9)
MUTED = RGBColor(0x9B, 0xB0, 0xC0)
MUTED_TX = RGBColor(0xC4, 0xA8, 0x8A)
FOOTER = RGBColor(0x5A, 0x70, 0x80)
LEGEND_BG = RGBColor(0x0E, 0x1F, 0x2C)
LINE = RGBColor(0x2A, 0x45, 0x58)

W = Inches(13.333)
H = Inches(7.5)

OUT = Path(__file__).resolve().parent / "DRA_Architecture_Editable_Slide.pptx"
LOGO = Path(__file__).resolve().parent / "assets" / "altera-logo.png"


def set_run(run, size, bold=False, color=WHITE, font="Calibri"):
    run.font.name = font
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color


def fill_solid(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color


def no_line(shape):
    shape.line.fill.background()


def stroke(shape, color, pt=1.0):
    shape.line.color.rgb = color
    shape.line.width = Pt(pt)


def set_bg(slide, color):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def rounded(slide, left, top, width, height, fill, line=None, line_pt=1.0, adj=0.08):
    sh = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    sh.adjustments[0] = adj
    fill_solid(sh, fill)
    if line is None:
        no_line(sh)
    else:
        stroke(sh, line, line_pt)
    return sh


def rect(slide, left, top, width, height, fill, line=None, line_pt=1.0):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    fill_solid(sh, fill)
    if line is None:
        no_line(sh)
    else:
        stroke(sh, line, line_pt)
    return sh


def textbox(slide, left, top, width, height, paragraphs, valign=MSO_ANCHOR.TOP):
    """paragraphs: list of (text, size, bold, color, align, font, space_after)"""
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    try:
        anchor = {MSO_ANCHOR.TOP: "t", MSO_ANCHOR.MIDDLE: "ctr", MSO_ANCHOR.BOTTOM: "b"}[valign]
        tf._txBody.bodyPr.set("anchor", anchor)
    except Exception:
        pass
    for i, item in enumerate(paragraphs):
        text, size, bold, color, align, font, space_after = item
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = text
        p.alignment = align
        p.space_after = Pt(space_after)
        if p.runs:
            set_run(p.runs[0], size, bold, color, font)
    return box


def labeled_box(
    slide,
    left,
    top,
    width,
    height,
    lines,
    fill,
    edge=None,
    edge_pt=1.0,
    font_size_title=10,
    font_size_sub=8,
    round_adj=0.1,
):
    sh = rounded(slide, left, top, width, height, fill, edge, edge_pt, round_adj)
    paras = []
    for i, (txt, is_title) in enumerate(lines):
        paras.append(
            (
                txt,
                font_size_title if is_title else font_size_sub,
                True if is_title else False,
                WHITE if is_title else MUTED,
                PP_ALIGN.CENTER,
                "Calibri",
                1 if i < len(lines) - 1 else 0,
            )
        )
    textbox(
        slide,
        left + Inches(0.04),
        top + Inches(0.06),
        width - Inches(0.08),
        height - Inches(0.1),
        paras,
        valign=MSO_ANCHOR.MIDDLE,
    )
    return sh


def arrow_right(slide, x1, y, x2, color):
    """Simple chevron / right arrow as a thin connector + triangle."""
    # line
    connector = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, x1, y, x2 - Inches(0.08), y)
    connector.line.color.rgb = color
    connector.line.width = Pt(1.5)
    # triangle tip
    tip = slide.shapes.add_shape(
        MSO_SHAPE.RIGHT_ARROW,
        x2 - Inches(0.12),
        y - Inches(0.055),
        Inches(0.14),
        Inches(0.11),
    )
    fill_solid(tip, color)
    no_line(tip)
    return tip


def arrow_down(slide, x, y1, y2, color):
    connector = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, x, y1, x, y2 - Inches(0.06))
    connector.line.color.rgb = color
    connector.line.width = Pt(1.75)
    tip = slide.shapes.add_shape(
        MSO_SHAPE.DOWN_ARROW,
        x - Inches(0.055),
        y2 - Inches(0.12),
        Inches(0.11),
        Inches(0.14),
    )
    fill_solid(tip, color)
    no_line(tip)
    return tip


def set_dash(shape):
    """Make shape outline dashed."""
    ln = shape.line._ln
    # prstDash
    prst = etree.SubElement(ln, qn("a:prstDash"))
    prst.set("val", "dash")


def build():
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    set_bg(slide, DARK)

    # ---- Header ----
    textbox(
        slide,
        Inches(0.35),
        Inches(0.12),
        Inches(8),
        Inches(0.25),
        [("ALTERA  |  SPACE / NTN PAYLOAD", 9, True, RX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        slide,
        Inches(0.35),
        Inches(0.32),
        Inches(9.2),
        Inches(0.4),
        [("RX / TX Direct Radiating Array Architecture", 22, False, WHITE, PP_ALIGN.LEFT, "Georgia", 0)],
    )
    textbox(
        slide,
        Inches(0.35),
        Inches(0.68),
        Inches(9.0),
        Inches(0.28),
        [
            (
                "AGRW027/039 device clusters  |  Direct-RF 64 Gsps  |  Separate TX/RX silicon paths (9 devices)",
                10,
                False,
                MUTED,
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            )
        ],
    )

    # Legend
    rounded(slide, Inches(10.15), Inches(0.18), Inches(2.9), Inches(0.72), LEGEND_BG, LINE, 1.0)
    rect(slide, Inches(10.35), Inches(0.32), Inches(0.18), Inches(0.14), RX)
    textbox(
        slide,
        Inches(10.6),
        Inches(0.28),
        Inches(2.3),
        Inches(0.22),
        [("RX Uplink 14.0-14.5 GHz | 32 beams", 8, False, MUTED, PP_ALIGN.LEFT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    rect(slide, Inches(10.35), Inches(0.55), Inches(0.18), Inches(0.14), TX)
    textbox(
        slide,
        Inches(10.6),
        Inches(0.51),
        Inches(2.3),
        Inches(0.22),
        [("TX Downlink 10.7-12.75 GHz | 40/32 beams", 8, False, MUTED, PP_ALIGN.LEFT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )

    # ========== RX PANEL ==========
    rx_top = Inches(1.05)
    rx_h = Inches(2.55)
    rounded(slide, Inches(0.28), rx_top, Inches(12.77), rx_h, PANEL_RX, RGBColor(0x1F, 0x4A, 0x55), 1.25)
    rect(slide, Inches(0.28), rx_top, Inches(0.07), rx_h, RX)

    textbox(
        slide,
        Inches(0.5),
        Inches(1.12),
        Inches(3),
        Inches(0.2),
        [("RX DRA  —  UPLINK", 9, True, RX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        slide,
        Inches(0.5),
        Inches(1.28),
        Inches(10),
        Inches(0.28),
        [
            (
                "14.0–14.5 GHz  ·  32 spot beams  ·  4× AGRW027/039 (ADC side)",
                12,
                False,
                WHITE,
                PP_ALIGN.LEFT,
                "Georgia",
                0,
            )
        ],
    )

    # Front-end chain
    y_fe = Inches(1.65)
    h_fe = Inches(0.58)
    labeled_box(
        slide,
        Inches(0.5),
        y_fe,
        Inches(1.25),
        h_fe,
        [("Antenna /", True), ("Feed Array", True)],
        BOX_RX,
        RGBColor(0x2A, 0x7A, 0x88),
        font_size_title=9,
        font_size_sub=9,
    )
    arrow_right(slide, Inches(1.78), y_fe + Inches(0.29), Inches(2.0), RX_LIGHT)
    labeled_box(
        slide,
        Inches(2.02),
        y_fe,
        Inches(1.05),
        h_fe,
        [("LNA", True), ("Front-End", False)],
        BOX_RX,
        RGBColor(0x2A, 0x7A, 0x88),
        font_size_title=10,
        font_size_sub=8,
    )
    arrow_right(slide, Inches(3.1), y_fe + Inches(0.29), Inches(3.32), RX_LIGHT)

    # RX device cluster
    cluster_l = Inches(3.35)
    cluster_w = Inches(5.55)
    rounded(slide, cluster_l, Inches(1.58), cluster_w, Inches(0.78), BOX_RX_DEEP, RX, 1.25)
    textbox(
        slide,
        cluster_l + Inches(0.1),
        Inches(1.6),
        Inches(3),
        Inches(0.18),
        [("RX DEVICE CLUSTER", 8, True, RX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    devices = [
        ("Device 1", "8 ADC · Beams 1–8"),
        ("Device 2", "8 ADC · Beams 9–16"),
        ("Device 3", "8 ADC · Beams 17–24"),
        ("Device 4", "8 ADC · Beams 25–32"),
    ]
    dw = Inches(1.25)
    for i, (t, s) in enumerate(devices):
        labeled_box(
            slide,
            cluster_l + Inches(0.12) + i * (dw + Inches(0.1)),
            Inches(1.8),
            dw,
            Inches(0.48),
            [(t, True), (s, False)],
            BOX_RX_DEV,
            font_size_title=9,
            font_size_sub=7,
            round_adj=0.12,
        )

    # Per-device DSP pipeline
    textbox(
        slide,
        Inches(0.5),
        Inches(2.48),
        Inches(4),
        Inches(0.18),
        [("PER DEVICE DSP PIPELINE", 8, True, MUTED, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    pipe = [
        (Inches(0.5), Inches(1.55), [("Direct-RF ADC", True), ("64 Gsps · 1st Nyquist", False)]),
        (Inches(2.2), Inches(0.78), [("DDC", True)]),
        (Inches(3.15), Inches(1.85), [("Digital Beamforming", True), ("4-color · 8-way spatial reuse", False)]),
        (Inches(5.18), Inches(1.7), [("UL Channelizer", True), ("4 × 125 MHz / beam", False)]),
        (Inches(7.08), Inches(2.05), [("DVB-RCS2 / 3GPP-NTN", True), ("Low-PHY handoff", False)]),
    ]
    y_p = Inches(2.68)
    h_p = Inches(0.5)
    for i, (x, w, lines) in enumerate(pipe):
        labeled_box(
            slide,
            x,
            y_p,
            w,
            h_p,
            lines,
            BOX_RX,
            RGBColor(0x2A, 0x7A, 0x88),
            font_size_title=9,
            font_size_sub=7,
        )
        if i < len(pipe) - 1:
            nx = pipe[i + 1][0]
            arrow_right(slide, x + w + Inches(0.02), y_p + Inches(0.25), nx - Inches(0.02), RX_LIGHT)

    textbox(
        slide,
        Inches(0.5),
        Inches(3.28),
        Inches(12.2),
        Inches(0.28),
        [
            (
                "Quad-core Arm Cortex-A53 (HPS) per device  ·  Multi-device phase-sync IP for coherent beamforming",
                8,
                False,
                RGBColor(0x7A, 0x93, 0xA6),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
            (
                "Conservative isolation option: TX and RX on physically separate silicon / RF paths",
                8,
                False,
                RGBColor(0x7A, 0x93, 0xA6),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
        ],
    )

    # Arrow RX -> Router
    arrow_down(slide, Inches(6.65), Inches(3.6), Inches(3.78), RGBColor(0xC9, 0xD7, 0xE3))

    # ========== ROUTER ==========
    rounded(slide, Inches(2.1), Inches(3.82), Inches(9.1), Inches(0.58), ROUTER, ROUTER_EDGE, 1.25, 0.12)
    textbox(
        slide,
        Inches(2.2),
        Inches(3.88),
        Inches(8.9),
        Inches(0.48),
        [
            ("Onboard Router / Switch Fabric", 14, False, WHITE, PP_ALIGN.CENTER, "Georgia", 2),
            (
                "58 Gbps SerDes interconnect between device clusters and Feeder-link stage",
                9,
                False,
                RGBColor(0xB8, 0xD0, 0xE8),
                PP_ALIGN.CENTER,
                "Calibri",
                0,
            ),
        ],
        valign=MSO_ANCHOR.MIDDLE,
    )

    arrow_down(slide, Inches(6.65), Inches(4.42), Inches(4.58), RGBColor(0xC9, 0xD7, 0xE3))

    # ========== TX PANEL ==========
    tx_top = Inches(4.62)
    tx_h = Inches(2.4)
    rounded(slide, Inches(0.28), tx_top, Inches(12.77), tx_h, PANEL_TX, RGBColor(0x5A, 0x3A, 0x1A), 1.25)
    rect(slide, Inches(0.28), tx_top, Inches(0.07), tx_h, TX)

    textbox(
        slide,
        Inches(0.5),
        Inches(4.68),
        Inches(3),
        Inches(0.18),
        [("TX DRA  —  DOWNLINK", 9, True, TX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        slide,
        Inches(0.5),
        Inches(4.84),
        Inches(11.5),
        Inches(0.26),
        [
            (
                "10.7–12.75 GHz  ·  40 spot beams (NTN) / 32 (DVB-S2X)  ·  5× AGRW027/039 (DAC side)",
                12,
                False,
                WHITE,
                PP_ALIGN.LEFT,
                "Georgia",
                0,
            )
        ],
    )

    # TX DSP pipeline
    textbox(
        slide,
        Inches(0.5),
        Inches(5.15),
        Inches(4),
        Inches(0.16),
        [("PER DEVICE DSP PIPELINE", 8, True, MUTED_TX, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    tx_pipe = [
        (Inches(0.5), Inches(1.85), [("DVB-S2X / 3GPP-NTN", True), ("Low-PHY framer", False)]),
        (Inches(2.55), Inches(1.9), [("Digital Beamforming", True), ("4-color · 8–10 way spatial reuse", False)]),
        (Inches(4.65), Inches(0.78), [("DUC", True)]),
        (Inches(5.65), Inches(1.7), [("Direct-RF DAC", True), ("64 Gsps synthesis", False)]),
    ]
    y_tp = Inches(5.32)
    h_tp = Inches(0.48)
    for i, (x, w, lines) in enumerate(tx_pipe):
        labeled_box(
            slide,
            x,
            y_tp,
            w,
            h_tp,
            lines,
            BOX_TX,
            RGBColor(0x8A, 0x5A, 0x28),
            font_size_title=9,
            font_size_sub=7,
        )
        if i < len(tx_pipe) - 1:
            nx = tx_pipe[i + 1][0]
            arrow_right(slide, x + w + Inches(0.02), y_tp + Inches(0.24), nx - Inches(0.02), TX_LIGHT)

    # TX device cluster
    txc_l = Inches(0.5)
    txc_w = Inches(8.85)
    rounded(slide, txc_l, Inches(5.95), txc_w, Inches(0.72), BOX_TX_DEEP, TX, 1.25)
    textbox(
        slide,
        txc_l + Inches(0.1),
        Inches(5.97),
        Inches(4),
        Inches(0.16),
        [("TX DEVICE CLUSTER", 8, True, TX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    tx_devs = [
        ("Device 1", "8 DAC · Beams 1–8", False),
        ("Device 2", "8 DAC · Beams 9–16", False),
        ("Device 3", "8 DAC · Beams 17–24", False),
        ("Device 4", "8 DAC · Beams 25–32", False),
        ("Device 5 *", "8 DAC · Beams 33–40", True),
    ]
    tdw = Inches(1.6)
    for i, (t, s, dashed) in enumerate(tx_devs):
        sh = labeled_box(
            slide,
            txc_l + Inches(0.12) + i * (tdw + Inches(0.1)),
            Inches(6.15),
            tdw,
            Inches(0.44),
            [(t, True), (s, False)],
            BOX_TX_DEV,
            TX_LIGHT if dashed else None,
            1.0 if dashed else 0,
            font_size_title=9,
            font_size_sub=7,
            round_adj=0.12,
        )
        if dashed:
            set_dash(sh)

    arrow_right(slide, Inches(9.4), Inches(6.3), Inches(9.65), TX_LIGHT)
    labeled_box(
        slide,
        Inches(9.68),
        Inches(6.05),
        Inches(1.15),
        Inches(0.55),
        [("HPA", True), ("Front-End", False)],
        BOX_TX,
        RGBColor(0x8A, 0x5A, 0x28),
        font_size_title=10,
        font_size_sub=8,
    )
    arrow_right(slide, Inches(10.88), Inches(6.3), Inches(11.12), TX_LIGHT)
    labeled_box(
        slide,
        Inches(11.15),
        Inches(6.05),
        Inches(1.55),
        Inches(0.55),
        [("Antenna /", True), ("Feed Array", True)],
        BOX_TX,
        RGBColor(0x8A, 0x5A, 0x28),
        font_size_title=9,
        font_size_sub=9,
    )

    textbox(
        slide,
        Inches(0.5),
        Inches(6.75),
        Inches(12.2),
        Inches(0.28),
        [
            (
                "* Device 5 carries 4 spare/idle DAC channels when operating in DVB-S2X-only mode (32 beams)",
                8,
                False,
                RGBColor(0xA8, 0x90, 0x70),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
            (
                "Total: 9 devices (5 TX + 4 RX)  ·  Cleanest TX→RX isolation  ·  Phase-sync across cluster",
                8,
                False,
                RGBColor(0xA8, 0x90, 0x70),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
        ],
    )

    # ========== Footer ==========
    if LOGO.exists():
        slide.shapes.add_picture(str(LOGO), Inches(0.35), Inches(7.12), height=Inches(0.22))

    textbox(
        slide,
        Inches(1.55),
        Inches(7.14),
        Inches(2.2),
        Inches(0.22),
        [("Altera Confidential", 8, False, FOOTER, PP_ALIGN.LEFT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    textbox(
        slide,
        Inches(4.0),
        Inches(7.14),
        Inches(5.5),
        Inches(0.22),
        [("AGRW027/039  ·  Ku-band DRA Payload Architecture", 8, False, FOOTER, PP_ALIGN.CENTER, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    textbox(
        slide,
        Inches(10.5),
        Inches(7.14),
        Inches(2.0),
        Inches(0.22),
        [("Altera Confidential", 8, False, FOOTER, PP_ALIGN.RIGHT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    textbox(
        slide,
        Inches(12.55),
        Inches(7.14),
        Inches(0.5),
        Inches(0.22),
        [("3", 9, False, FOOTER, PP_ALIGN.RIGHT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )

    prs.save(OUT)
    print(f"Wrote {OUT}")
    return OUT


if __name__ == "__main__":
    build()
