#!/usr/bin/env python3
"""Editable PowerPoint slides detailing the Onboard Router / Switch Fabric."""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

DARK = RGBColor(0x07, 0x14, 0x20)
PAPER = RGBColor(0xF7, 0xF9, 0xFB)
PANEL = RGBColor(0xFF, 0xFF, 0xFF)
LINE = RGBColor(0xD0, 0xD8, 0xE0)
INK = RGBColor(0x0C, 0x16, 0x20)
MUTED = RGBColor(0x4A, 0x5A, 0x66)
STEEL = RGBColor(0x14, 0x2E, 0x44)
RX = RGBColor(0x0E, 0x6B, 0x7A)
RX_LIGHT = RGBColor(0x1A, 0x9A, 0xAB)
TX = RGBColor(0xA0, 0x5C, 0x18)
TX_LIGHT = RGBColor(0xC2, 0x77, 0x2A)
ROUTER = RGBColor(0x1B, 0x3F, 0x66)
ROUTER_EDGE = RGBColor(0x4A, 0x7D, 0xB0)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
CHIP = RGBColor(0xE8, 0xF0, 0xF6)
FOOTER = RGBColor(0x5A, 0x70, 0x80)
DARK_PANEL = RGBColor(0x0A, 0x1A, 0x26)

W = Inches(13.333)
H = Inches(7.5)
MX = Inches(0.55)

OUT = Path(__file__).resolve().parent / "DRA_Fabric_Editable_Slides.pptx"
LOGO = Path(__file__).resolve().parent / "assets" / "altera-logo.png"


def set_run(run, size, bold=False, color=INK, font="Calibri"):
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


def blank(prs):
    return prs.slides.add_slide(prs.slide_layouts[6])


def rect(slide, l, t, w, h, fill, line=None, pt=1.0):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, w, h)
    fill_solid(sh, fill)
    if line is None:
        no_line(sh)
    else:
        stroke(sh, line, pt)
    return sh


def rounded(slide, l, t, w, h, fill, line=None, pt=1.0, adj=0.1):
    sh = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, l, t, w, h)
    sh.adjustments[0] = adj
    fill_solid(sh, fill)
    if line is None:
        no_line(sh)
    else:
        stroke(sh, line, pt)
    return sh


def textbox(slide, l, t, w, h, paragraphs, valign=MSO_ANCHOR.TOP):
    box = slide.shapes.add_textbox(l, t, w, h)
    tf = box.text_frame
    tf.word_wrap = True
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


def card(slide, l, t, w, h, title, bullets, accent=ROUTER, dark=False):
    bg = DARK_PANEL if dark else PANEL
    edge = ROUTER_EDGE if dark else LINE
    title_c = WHITE if dark else INK
    body_c = RGBColor(0x9B, 0xB0, 0xC0) if dark else MUTED
    rounded(slide, l, t, w, h, bg, edge, 1.0)
    rect(slide, l, t, Inches(0.07), h, accent)
    paras = [(title, 13, True, title_c, PP_ALIGN.LEFT, "Calibri", 6)]
    for b in bullets:
        paras.append((b, 11, False, body_c, PP_ALIGN.LEFT, "Calibri", 3))
    textbox(slide, l + Inches(0.2), t + Inches(0.12), w - Inches(0.3), h - Inches(0.2), paras)


def footer(slide, page, dark=False):
    c = FOOTER if not dark else RGBColor(0x7A, 0x93, 0xA6)
    if LOGO.exists() and not dark:
        slide.shapes.add_picture(str(LOGO), Inches(0.4), Inches(7.12), height=Inches(0.2))
    textbox(
        slide,
        Inches(1.5) if not dark else Inches(0.4),
        Inches(7.12),
        Inches(3),
        Inches(0.22),
        [("Altera Confidential", 8, False, c, PP_ALIGN.LEFT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    textbox(
        slide,
        Inches(5.0),
        Inches(7.12),
        Inches(5),
        Inches(0.22),
        [("Onboard Router / Switch Fabric", 8, False, c, PP_ALIGN.CENTER, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )
    textbox(
        slide,
        Inches(12.3),
        Inches(7.12),
        Inches(0.7),
        Inches(0.22),
        [(str(page), 9, False, c, PP_ALIGN.RIGHT, "Calibri", 0)],
        valign=MSO_ANCHOR.MIDDLE,
    )


def arrow_line(slide, x1, y1, x2, y2, color):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, x1, y1, x2, y2)
    c.line.color.rgb = color
    c.line.width = Pt(1.75)
    return c


def labeled(slide, l, t, w, h, title, sub, fill, edge, title_c=WHITE, sub_c=None):
    rounded(slide, l, t, w, h, fill, edge, 1.0)
    paras = [
        (title, 11, True, title_c, PP_ALIGN.CENTER, "Calibri", 2),
        (sub, 9, False, sub_c or RGBColor(0x9B, 0xB0, 0xC0), PP_ALIGN.CENTER, "Calibri", 0),
    ]
    textbox(slide, l + Inches(0.05), t + Inches(0.08), w - Inches(0.1), h - Inches(0.12), paras, MSO_ANCHOR.MIDDLE)


def build():
    prs = Presentation()
    prs.slide_width = W
    prs.slide_height = H

    # ========== SLIDE 1: Role & context ==========
    s = blank(prs)
    set_bg(s, DARK)
    rect(s, 0, 0, Inches(0.12), H, RX_LIGHT)
    textbox(
        s,
        MX,
        Inches(0.25),
        Inches(10),
        Inches(0.25),
        [("ALTERA  |  SPACE / NTN PAYLOAD", 10, True, RX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        s,
        MX,
        Inches(0.55),
        Inches(12),
        Inches(0.45),
        [("Onboard Router / Switch Fabric", 28, False, WHITE, PP_ALIGN.LEFT, "Georgia", 0)],
    )
    textbox(
        s,
        MX,
        Inches(1.05),
        Inches(12),
        Inches(0.35),
        [
            (
                "Regenerative digital cross-connect between RX cluster, TX cluster, and Feeder-link stage",
                13,
                False,
                RGBColor(0x9B, 0xB0, 0xC0),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            )
        ],
    )

    # Topology diagram
    labeled(
        s,
        Inches(0.7),
        Inches(1.7),
        Inches(3.2),
        Inches(1.1),
        "RX Device Cluster",
        "4× AGRW027/039  ·  Beams 1–32\nPost DVB-RCS2 / NTN Low-PHY",
        RGBColor(0x0E, 0x2A, 0x35),
        RX_LIGHT,
    )
    labeled(
        s,
        Inches(9.4),
        Inches(1.7),
        Inches(3.2),
        Inches(1.1),
        "TX Device Cluster",
        "5× AGRW027/039  ·  Beams 1–40\nPre DVB-S2X / NTN Low-PHY",
        RGBColor(0x2A, 0x1E, 0x12),
        TX_LIGHT,
    )
    labeled(
        s,
        Inches(3.9),
        Inches(3.3),
        Inches(5.5),
        Inches(1.25),
        "Onboard Router / Switch Fabric",
        "58 Gbps-class SerDes trunks  ·  Packet / TB switching\n(not raw ADC/DAC samples)",
        ROUTER,
        ROUTER_EDGE,
    )
    labeled(
        s,
        Inches(4.7),
        Inches(5.1),
        Inches(3.9),
        Inches(1.0),
        "Feeder-link Stage",
        "Gateway modem  ·  TT&C overlay  ·  Ground trunk",
        RGBColor(0x16, 0x32, 0x4F),
        ROUTER_EDGE,
    )

    # connectors
    arrow_line(s, Inches(3.9), Inches(2.25), Inches(3.9), Inches(2.25), RX_LIGHT)  # noop keep simple
    arrow_line(s, Inches(2.3), Inches(2.8), Inches(5.2), Inches(3.3), RX_LIGHT)
    arrow_line(s, Inches(11.0), Inches(2.8), Inches(8.1), Inches(3.3), TX_LIGHT)
    arrow_line(s, Inches(6.65), Inches(4.55), Inches(6.65), Inches(5.1), RGBColor(0xC9, 0xD7, 0xE3))

    textbox(
        s,
        MX,
        Inches(6.3),
        Inches(12),
        Inches(0.55),
        [
            (
                "Direct-RF sample paths stay inside each device. The fabric only moves demodulated user-plane,",
                12,
                False,
                RGBColor(0x9B, 0xB0, 0xC0),
                PP_ALIGN.LEFT,
                "Calibri",
                2,
            ),
            (
                "control-plane, and feeder traffic — preserving separate TX/RX silicon for RF isolation.",
                12,
                False,
                RGBColor(0x9B, 0xB0, 0xC0),
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
        ],
    )
    footer(s, 1, dark=True)

    # ========== SLIDE 2: Ports, SerDes, traffic ==========
    s = blank(prs)
    set_bg(s, PAPER)
    rect(s, 0, 0, W, Inches(0.07), RX_LIGHT)
    textbox(
        s,
        MX,
        Inches(0.2),
        Inches(10),
        Inches(0.22),
        [("ONBOARD FABRIC — DETAIL", 10, True, RX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        s,
        MX,
        Inches(0.42),
        Inches(12),
        Inches(0.4),
        [("Ports, SerDes class, and traffic engineering", 24, False, STEEL, PP_ALIGN.LEFT, "Georgia", 0)],
    )

    card(
        s,
        MX,
        Inches(1.05),
        Inches(4.0),
        Inches(2.55),
        "Port groups",
        [
            "RX ports — 4 devices (Beams 1–32)",
            "TX ports — 5 devices (Beams 1–40)",
            "Feeder ports — gateway / TT&C",
            "Control — HPS / management",
            "Logical Clos / crossbar preferred",
        ],
        ROUTER,
    )
    card(
        s,
        Inches(4.75),
        Inches(1.05),
        Inches(4.0),
        Inches(2.55),
        "58 Gbps-class SerDes",
        [
            "Lane class (PAM4), not aggregate",
            "Altera F-tile / equivalent",
            "2–4 lanes per RX/TX device",
            "4–8 lanes to feeder trunk",
            "1+1 / N+1 spare for FDIR",
        ],
        RX,
    )
    card(
        s,
        Inches(8.95),
        Inches(1.05),
        Inches(3.85),
        Inches(2.55),
        "What crosses the fabric",
        [
            "Post-Low-PHY packets / TBs",
            "NOT 64 Gsps ADC/DAC IQ",
            "Beam maps & ACM control",
            "Sync / timing messages",
            "Telemetry & health",
        ],
        TX,
    )

    # Table-like rows for traffic classes
    textbox(
        s,
        MX,
        Inches(3.8),
        Inches(12),
        Inches(0.3),
        [("Traffic classes", 14, True, STEEL, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    rows = [
        ("Class", "Direction", "Content", "Priority"),
        ("User plane", "RX→TX / RX↔Feeder / Feeder→TX", "Demodulated packets / transport blocks", "High, shaped"),
        ("Control plane", "Bidirectional", "Beam maps, ACM, NTN signaling", "Highest"),
        ("Sync / timing", "Fabric-wide", "Schedules, timing packets", "Reserved"),
        ("Telemetry", "Devices → Feeder / HPS", "BER, thermal, HPS logs", "Best effort"),
        ("Multicast", "Fabric → TX set", "Broadcast / group beams", "Configurable"),
    ]
    table = s.shapes.add_table(len(rows), 4, MX, Inches(4.15), Inches(12.2), Inches(2.55)).table
    widths = [Inches(2.0), Inches(3.6), Inches(4.4), Inches(2.2)]
    for i, w in enumerate(widths):
        table.columns[i].width = w
    for r, row in enumerate(rows):
        for c, val in enumerate(row):
            cell = table.cell(r, c)
            cell.text = val
            run = cell.text_frame.paragraphs[0].runs[0]
            if r == 0:
                set_run(run, 10, True, WHITE)
                cell.fill.solid()
                cell.fill.fore_color.rgb = STEEL
            else:
                set_run(run, 10, c == 0, INK if c == 0 else MUTED)
                cell.fill.solid()
                cell.fill.fore_color.rgb = PANEL if r % 2 else CHIP
    footer(s, 2)

    # ========== SLIDE 3: Switching functions ==========
    s = blank(prs)
    set_bg(s, PAPER)
    rect(s, 0, 0, W, Inches(0.07), TX_LIGHT)
    textbox(
        s,
        MX,
        Inches(0.2),
        Inches(10),
        Inches(0.22),
        [("ONBOARD FABRIC — FUNCTIONS", 10, True, TX_LIGHT, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        s,
        MX,
        Inches(0.42),
        Inches(12),
        Inches(0.4),
        [("Switching functions and control plane", 24, False, STEEL, PP_ALIGN.LEFT, "Georgia", 0)],
    )

    funcs = [
        ("UL→DL cross-connect", ["Regenerative beam-to-beam", "forwarding after Low-PHY", "Mesh across color reuse"]),
        ("Feeder gateway", ["Concentrate user traffic", "to/from ground modem", "Often fattest trunk"]),
        ("Beam remap", ["Update forwarding tables", "on steer / recolor", "Aligns with DBFN maps"]),
        ("FDIR / spare", ["Steer around failed device", "Use TX Device 5 spare", "in DVB-S2X-only mode"]),
        ("Replication", ["1:N broadcast / NTN", "SIB-like content", "Ephemeris floods"]),
        ("RF isolation keep", ["TX/RX silicon stay split", "Only digital meets here", "Cleanest TX→RX isolation"]),
    ]
    for i, (title, bullets) in enumerate(funcs):
        col = i % 3
        row = i // 3
        card(
            s,
            MX + col * Inches(4.15),
            Inches(1.05) + row * Inches(2.35),
            Inches(3.95),
            Inches(2.15),
            title,
            bullets,
            ROUTER if i % 2 == 0 else (RX if i < 3 else TX),
        )

    textbox(
        s,
        MX,
        Inches(5.85),
        Inches(12.2),
        Inches(0.95),
        [
            (
                "Control plane: each device HPS (Arm Cortex-A53) owns local config; fabric controller owns route/beam tables,",
                12,
                False,
                MUTED,
                PP_ALIGN.LEFT,
                "Calibri",
                3,
            ),
            (
                "SerDes health, and FDIR. Same logical fabric ports apply to Option A (AGRW SoC) and Option B (Agilex 7 + AFE7950).",
                12,
                False,
                MUTED,
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            ),
        ],
    )
    footer(s, 3)

    # ========== SLIDE 4: Example lane plan ==========
    s = blank(prs)
    set_bg(s, PAPER)
    rect(s, 0, 0, W, Inches(0.07), ROUTER_EDGE)
    textbox(
        s,
        MX,
        Inches(0.2),
        Inches(10),
        Inches(0.22),
        [("ONBOARD FABRIC — SIZING", 10, True, ROUTER_EDGE, PP_ALIGN.LEFT, "Calibri", 0)],
    )
    textbox(
        s,
        MX,
        Inches(0.42),
        Inches(12),
        Inches(0.4),
        [("Example SerDes lane plan (Direct-RF SoC option)", 22, False, STEEL, PP_ALIGN.LEFT, "Georgia", 0)],
    )
    textbox(
        s,
        MX,
        Inches(0.9),
        Inches(12),
        Inches(0.35),
        [
            (
                "Illustrative starting point — close after traffic engineering (modulation, coding, duty cycle, overbooking).",
                12,
                False,
                MUTED,
                PP_ALIGN.LEFT,
                "Calibri",
                0,
            )
        ],
    )

    rows = [
        ("Link", "Suggested lanes", "Approx capacity class", "Notes"),
        ("Each RX device ↔ fabric", "2–4 × 58G", "~100–200 Gbps raw", "Post-Low-PHY UL + control"),
        ("Each TX device ↔ fabric", "2–4 × 58G", "~100–200 Gbps raw", "DL framer input + replication"),
        ("Fabric ↔ feeder stage", "4–8 × 58G", "~200–400 Gbps raw", "Gateway aggregate + protect"),
        ("Control / debug", "1–2 × lower-rate", "Mgmt Ethernet / PCIe", "Out-of-band OK"),
        ("Aggregate (order)", "—", "Multi-100G fabric", "Efficiency < line rate"),
    ]
    table = s.shapes.add_table(len(rows), 4, MX, Inches(1.4), Inches(12.2), Inches(3.4)).table
    for i, w in enumerate([Inches(3.4), Inches(2.4), Inches(2.8), Inches(3.6)]):
        table.columns[i].width = w
    for r, row in enumerate(rows):
        for c, val in enumerate(row):
            cell = table.cell(r, c)
            cell.text = val
            run = cell.text_frame.paragraphs[0].runs[0]
            if r == 0:
                set_run(run, 11, True, WHITE)
                cell.fill.solid()
                cell.fill.fore_color.rgb = STEEL
            else:
                set_run(run, 11, c == 0, INK if c == 0 else MUTED)
                cell.fill.solid()
                cell.fill.fore_color.rgb = PANEL if r % 2 else CHIP

    card(
        s,
        MX,
        Inches(5.05),
        Inches(6.0),
        Inches(1.75),
        "Bandwidth reminder",
        [
            "Fabric carries post-demod bits, not 64 Gsps samples",
            "Size for peak ACM + ~20–40% overhead",
            "Feeder trunk often dominates",
        ],
        RX,
    )
    card(
        s,
        Inches(6.8),
        Inches(5.05),
        Inches(5.95),
        Inches(1.75),
        "Option B (Agilex 7 + TI)",
        [
            "Same logical ports: 4 RX + 5 TX + feeder",
            "SerDes from each Agilex 7 into fabric",
            "JESD204C stays local FPGA↔AFE7950",
        ],
        TX,
    )
    footer(s, 4)

    prs.save(OUT)
    print(f"Wrote {OUT}")
    return OUT


if __name__ == "__main__":
    build()
