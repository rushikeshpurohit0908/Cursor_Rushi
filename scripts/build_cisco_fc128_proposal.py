#!/usr/bin/env python3
"""Build Cisco FC128 / Agilex 7 M039 R47 technical proposal PPTX."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Inches, Pt

NAVY = RGBColor(0x0B, 0x2B, 0x45)
ALTERA_BLUE = RGBColor(0x00, 0x7A, 0xCC)
ACCENT = RGBColor(0x00, 0xA3, 0xE0)
CISCO_BLUE = RGBColor(0x04, 0x9E, 0xD8)
LIGHT_BG = RGBColor(0xF5, 0xF7, 0xFA)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
DARK = RGBColor(0x1A, 0x1A, 0x1A)
GRAY = RGBColor(0x5C, 0x6B, 0x7A)
MUTED = RGBColor(0x8A, 0x96, 0xA3)
GREEN = RGBColor(0x1F, 0x7A, 0x4C)
ORANGE = RGBColor(0xC4, 0x7A, 0x12)
ROW_ALT = RGBColor(0xEE, 0xF3, 0xF8)
HEADER_BG = RGBColor(0x0B, 0x2B, 0x45)
CLIENT = RGBColor(0x00, 0x7A, 0xCC)
SYSTEM = RGBColor(0x1F, 0x7A, 0x4C)
SECONDARY = RGBColor(0xC4, 0x7A, 0x12)

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)
FONT = "Liberation Sans"
ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "presentations" / "assets"
OUT_DIR = ROOT / "presentations"
TOTAL = 9


def set_run_font(run, size=14, bold=False, color=DARK, font_name=FONT):
    run.font.name = font_name
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    rPr = run._r.get_or_add_rPr()
    for tag in ("latin", "ea", "cs"):
        el = rPr.find(qn(f"a:{tag}"))
        if el is None:
            el = rPr.makeelement(qn(f"a:{tag}"), {})
            rPr.append(el)
        el.set("typeface", font_name)


def add_rect(slide, left, top, width, height, fill, line=None):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    if line is None:
        shape.line.fill.background()
    else:
        shape.line.color.rgb = line
        shape.line.width = Pt(1)
    return shape


def add_rounded(slide, left, top, width, height, fill):
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    shape.line.fill.background()
    try:
        shape.adjustments[0] = 0.1
    except Exception:
        pass
    return shape


def add_text_box(
    slide,
    left,
    top,
    width,
    height,
    text,
    *,
    size=14,
    bold=False,
    color=DARK,
    align=PP_ALIGN.LEFT,
    anchor=MSO_ANCHOR.TOP,
):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    try:
        tf._txBody.bodyPr.set(
            "anchor",
            {MSO_ANCHOR.TOP: "t", MSO_ANCHOR.MIDDLE: "ctr", MSO_ANCHOR.BOTTOM: "b"}[anchor],
        )
    except Exception:
        pass
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    set_run_font(run, size=size, bold=bold, color=color)
    return box


def add_bullets(slide, left, top, width, height, items, *, size=13, color=DARK, space=6):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(space)
        pPr = p._p.get_or_add_pPr()
        for child in list(pPr):
            if child.tag.endswith(("buNone", "buFont", "buChar", "buAutoNum")):
                pPr.remove(child)
        pPr.insert(0, pPr.makeelement(qn("a:buChar"), {"char": "•"}))
        pPr.insert(0, pPr.makeelement(qn("a:buFont"), {"typeface": FONT}))
        run = p.add_run()
        run.text = item
        set_run_font(run, size=size, color=color)
    return box


def footer(slide, page: int):
    add_rect(slide, Inches(0), Inches(7.15), SLIDE_W, Inches(0.35), NAVY)
    add_text_box(
        slide,
        Inches(0.4),
        Inches(7.18),
        Inches(7),
        Inches(0.28),
        "Altera Confidential  ·  Cisco FC128 Proposal  ·  AGM039 R47",
        size=10,
        color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE,
    )
    add_text_box(
        slide,
        Inches(10.5),
        Inches(7.18),
        Inches(2.4),
        Inches(0.28),
        f"{page} / {TOTAL}",
        size=10,
        color=WHITE,
        align=PP_ALIGN.RIGHT,
        anchor=MSO_ANCHOR.MIDDLE,
    )


def header_bar(slide, section_label: str):
    add_rect(slide, Inches(0), Inches(0), SLIDE_W, Inches(0.08), ACCENT)
    add_text_box(
        slide,
        Inches(0.5),
        Inches(0.18),
        Inches(12),
        Inches(0.3),
        section_label,
        size=11,
        bold=True,
        color=ALTERA_BLUE,
    )


def title_block(slide, title: str, subtitle: str | None = None):
    add_text_box(slide, Inches(0.5), Inches(0.45), Inches(12.2), Inches(0.55), title, size=26, bold=True, color=NAVY)
    if subtitle:
        add_text_box(slide, Inches(0.5), Inches(0.95), Inches(12.2), Inches(0.35), subtitle, size=13, color=GRAY)


def add_table(slide, left, top, width, height, headers, rows, col_widths=None, font_size=10):
    table_shape = slide.shapes.add_table(len(rows) + 1, len(headers), left, top, width, height)
    table = table_shape.table
    if col_widths:
        for i, w in enumerate(col_widths):
            table.columns[i].width = w
    for j, h in enumerate(headers):
        cell = table.cell(0, j)
        cell.text = ""
        p = cell.text_frame.paragraphs[0]
        run = p.add_run()
        run.text = h
        set_run_font(run, size=font_size, bold=True, color=WHITE)
        cell.fill.solid()
        cell.fill.fore_color.rgb = HEADER_BG
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    for i, row in enumerate(rows):
        for j, val in enumerate(row):
            cell = table.cell(i + 1, j)
            cell.text = ""
            p = cell.text_frame.paragraphs[0]
            run = p.add_run()
            run.text = str(val)
            set_run_font(run, size=font_size - 1, color=DARK)
            cell.fill.solid()
            cell.fill.fore_color.rgb = WHITE if i % 2 == 0 else ROW_ALT
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    return table_shape


def blank_slide(prs: Presentation):
    return prs.slides.add_slide(prs.slide_layouts[6])


def try_logo(slide, path: Path, left, top, width):
    if path.exists():
        slide.shapes.add_picture(str(path), left, top, width=width)


def build(out_path: Path):
    prs = Presentation()
    prs.slide_width = SLIDE_W
    prs.slide_height = SLIDE_H
    page = 0

    # ---- 1 Title ----
    page += 1
    s = blank_slide(prs)
    add_rect(s, Inches(0), Inches(0), Inches(0.18), SLIDE_H, ACCENT)
    add_rect(s, Inches(0), Inches(0), SLIDE_W, Inches(0.08), ALTERA_BLUE)
    try_logo(s, ASSET_DIR / "altera_wordmark.png", Inches(0.7), Inches(0.45), Inches(1.6))
    try_logo(s, ASSET_DIR / "cisco_wordmark.png", Inches(11.0), Inches(0.45), Inches(1.6))
    add_text_box(s, Inches(0.7), Inches(1.7), Inches(11.5), Inches(0.35), "TECHNICAL PROPOSAL", size=14, bold=True, color=ALTERA_BLUE)
    add_text_box(s, Inches(0.7), Inches(2.15), Inches(11.5), Inches(0.7), "Cisco 128G Fibre Channel", size=36, bold=True, color=NAVY)
    add_text_box(
        s,
        Inches(0.7),
        Inches(2.9),
        Inches(11.5),
        Inches(0.45),
        "Agilex™ 7 M-Series AGM039 · Package R47",
        size=20,
        color=GRAY,
    )
    # Spec chips
    chips = [
        ("FC128", "Fibre Channel"),
        ("8 × 112G", "Client side"),
        ("16 × 58G", "System side"),
        ("8 × 58G", "Secondary"),
        ("AGM039", "R47 package"),
    ]
    x = Inches(0.7)
    for value, label in chips:
        add_rounded(s, x, Inches(3.7), Inches(2.2), Inches(1.15), LIGHT_BG)
        add_text_box(s, x + Inches(0.12), Inches(3.85), Inches(1.95), Inches(0.4), value, size=16, bold=True, color=NAVY, align=PP_ALIGN.CENTER)
        add_text_box(s, x + Inches(0.12), Inches(4.3), Inches(1.95), Inches(0.35), label, size=11, color=GRAY, align=PP_ALIGN.CENTER)
        x += Inches(2.35)
    add_text_box(
        s,
        Inches(0.7),
        Inches(5.3),
        Inches(11.5),
        Inches(0.8),
        "Single-chip 8-port 128GFC datapath: FHT client SerDes to 116G PAM4,\n"
        "FGT system fabric at 58G PAM4 — bandwidth-matched gearbox for Cisco ASIC attach.",
        size=14,
        color=DARK,
    )
    footer(s, page)

    # ---- 2 Agenda ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Agenda")
    title_block(s, "Proposal contents", "Cisco FC128 on Agilex 7 M039 R47")
    agenda = [
        ("01", "Requirements & fit", "Stated I/O plan vs device resources"),
        ("02", "128GFC primer", "FC-PI-8 signaling, FEC, optics"),
        ("03", "Architecture", "Client → gearbox → system datapath"),
        ("04", "Package options", "R47A / R47B / R47C selection guide"),
        ("05", "Engagement plan", "Align → PoC → Pilot → Production"),
    ]
    y = Inches(1.55)
    for num, title, blurb in agenda:
        add_rect(s, Inches(0.5), y, Inches(12.3), Inches(0.9), LIGHT_BG)
        add_rect(s, Inches(0.5), y, Inches(0.12), Inches(0.9), ACCENT)
        add_text_box(s, Inches(0.85), y + Inches(0.15), Inches(0.8), Inches(0.55), num, size=22, bold=True, color=ALTERA_BLUE, anchor=MSO_ANCHOR.MIDDLE)
        add_text_box(s, Inches(1.8), y + Inches(0.15), Inches(10), Inches(0.35), title, size=18, bold=True, color=NAVY)
        add_text_box(s, Inches(1.8), y + Inches(0.5), Inches(10), Inches(0.3), blurb, size=12, color=GRAY)
        y += Inches(1.0)
    footer(s, page)

    # ---- 3 Requirements ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Requirements · Device Fit")
    title_block(s, "Stated requirements map to AGM039 R47", "Client 112G on FHT · System 58G on FGT")
    add_table(
        s,
        Inches(0.5),
        Inches(1.5),
        Inches(12.3),
        Inches(2.4),
        ["Domain", "Channels", "Rate", "Role", "Tile resource"],
        [
            ["Client (line)", "8", "112G PAM4", "8 × 128GFC ports", "FHT (to 116G PAM4)"],
            ["System (primary)", "16", "58G PAM4", "Cisco ASIC / fabric", "FGT (to 58G PAM4)"],
            ["System (secondary)", "8", "58G", "Protect / debug / expand", "FGT or FHT @ 58G"],
        ],
        col_widths=[Inches(2.6), Inches(1.5), Inches(1.8), Inches(3.4), Inches(3.0)],
        font_size=12,
    )
    # BW cards
    cards = [
        ("~897.6 Gbps", "Client aggregate\n8 × 112.2G", CLIENT),
        ("~928 Gbps", "System primary\n16 × 58G", SYSTEM),
        ("~3% headroom", "Primary path\nFEC / PCS margin", ORANGE),
        ("~464 Gbps", "Secondary bank\n8 × 58G spare", SECONDARY),
    ]
    x = Inches(0.5)
    for value, label, color in cards:
        add_rect(s, x, Inches(4.2), Inches(2.95), Inches(2.4), LIGHT_BG)
        add_rect(s, x, Inches(4.2), Inches(2.95), Inches(0.1), color)
        add_text_box(s, x + Inches(0.2), Inches(4.5), Inches(2.55), Inches(0.5), value, size=20, bold=True, color=NAVY)
        add_text_box(s, x + Inches(0.2), Inches(5.15), Inches(2.55), Inches(1.0), label, size=13, color=GRAY)
        x += Inches(3.15)
    footer(s, page)

    # ---- 4 FC128 primer ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Technology · 128GFC")
    title_block(s, "Fibre Channel 128G (FC-PI-8)", "PAM4 at 112.2 Gbps — mandatory FEC — SFP112 optics")
    left_items = [
        "Marketing name: 128GFC",
        "Line rate: 112.2 Gbps PAM4 (56.1 GBd)",
        "Nominal throughput: ~12.4 GB/s per lane",
        "Mandatory RS-FEC on every link",
        "Electrical + optical both PAM4 (CDR in module)",
        "Typical optics: SFP112 SR / LI / LW",
        "Backward compatible ~2 generations (64/32GFC)",
    ]
    add_rect(s, Inches(0.5), Inches(1.5), Inches(6.0), Inches(5.2), LIGHT_BG)
    add_text_box(s, Inches(0.75), Inches(1.7), Inches(5.5), Inches(0.35), "Physical layer essentials", size=16, bold=True, color=NAVY)
    add_bullets(s, Inches(0.75), Inches(2.2), Inches(5.5), Inches(4.2), left_items, size=14)

    add_rect(s, Inches(6.8), Inches(1.5), Inches(6.0), Inches(5.2), LIGHT_BG)
    add_rect(s, Inches(6.8), Inches(1.5), Inches(6.0), Inches(0.08), ACCENT)
    add_text_box(s, Inches(7.05), Inches(1.75), Inches(5.5), Inches(0.35), "Why FHT covers the client", size=16, bold=True, color=NAVY)
    add_bullets(
        s,
        Inches(7.05),
        Inches(2.3),
        Inches(5.5),
        Inches(4.0),
        [
            "Agilex 7 F-Tile FHT rated to 116 Gbps PAM4",
            "128GFC needs 112.2 Gbps — within FHT envelope",
            "FGT at 58G PAM4 matches system chip-to-chip",
            "Hardened RS/KP FEC blocks available in F-Tile",
            "Soft logic implements FC framing & BB_Credit",
            "CMIS path for modern SFP112 module manageability",
        ],
        size=14,
    )
    footer(s, page)

    # ---- 5 Architecture ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Architecture · Datapath")
    title_block(s, "8×112G client ↔ 16×58G system gearbox", "AGM039 soft logic + F-Tile SerDes")

    # Client box
    add_rounded(s, Inches(0.4), Inches(1.55), Inches(3.2), Inches(2.6), LIGHT_BG)
    add_rect(s, Inches(0.4), Inches(1.55), Inches(3.2), Inches(0.45), CLIENT)
    add_text_box(s, Inches(0.55), Inches(1.6), Inches(2.9), Inches(0.35), "CLIENT — FHT", size=14, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
    add_bullets(
        s,
        Inches(0.55),
        Inches(2.15),
        Inches(2.9),
        Inches(1.8),
        ["8 × 112G PAM4", "128GFC ports 0–7", "SFP112 / onboard", "PCS + RS-FEC"],
        size=12,
        space=4,
    )

    # FPGA center
    add_rounded(s, Inches(4.0), Inches(1.55), Inches(5.3), Inches(2.6), LIGHT_BG)
    add_rect(s, Inches(4.0), Inches(1.55), Inches(5.3), Inches(0.45), NAVY)
    add_text_box(s, Inches(4.15), Inches(1.6), Inches(5.0), Inches(0.35), "AGILEX 7 AGM039 (R47)", size=14, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
    add_bullets(
        s,
        Inches(4.15),
        Inches(2.15),
        Inches(5.0),
        Inches(1.8),
        ["FC framing · credit · link init", "Gearbox / lane stripe / rate-match", "Stats · CMIS · telemetry", "Optional HBM / DDR5 buffering"],
        size=12,
        space=4,
    )

    # System box
    add_rounded(s, Inches(9.7), Inches(1.55), Inches(3.2), Inches(2.6), LIGHT_BG)
    add_rect(s, Inches(9.7), Inches(1.55), Inches(3.2), Inches(0.45), SYSTEM)
    add_text_box(s, Inches(9.85), Inches(1.6), Inches(2.9), Inches(0.35), "SYSTEM — FGT", size=14, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
    add_bullets(
        s,
        Inches(9.85),
        Inches(2.15),
        Inches(2.9),
        Inches(1.8),
        ["16 × 58G primary", "8 × 58G secondary", "Cisco ASIC attach", "Raw or PCS mode"],
        size=12,
        space=4,
    )

    # Arrows as text labels
    add_text_box(s, Inches(3.5), Inches(2.5), Inches(0.55), Inches(0.4), "→", size=22, bold=True, color=ALTERA_BLUE, align=PP_ALIGN.CENTER)
    add_text_box(s, Inches(9.2), Inches(2.5), Inches(0.55), Inches(0.4), "→", size=22, bold=True, color=ALTERA_BLUE, align=PP_ALIGN.CENTER)

    add_rect(s, Inches(0.4), Inches(4.4), Inches(12.5), Inches(2.4), LIGHT_BG)
    add_text_box(s, Inches(0.65), Inches(4.55), Inches(12), Inches(0.35), "FPGA soft + hardened functions", size=14, bold=True, color=NAVY)
    add_bullets(
        s,
        Inches(0.65),
        Inches(5.0),
        Inches(12),
        Inches(1.6),
        [
            "128GFC PMA/PCS at 112.2G PAM4 with equalization and CDR on FHT",
            "Mandatory RS-FEC encode/decode; FC framing, R_RDY / BB_Credit, link initialization",
            "8×112G ↔ 16×58G gearbox with secondary 8×58G for dual-ASIC, protect, or diagnostics",
            "Management: CMIS for SFP112, counters, SEU scrubbing; optional PCIe 5.0/CXL on R47A",
        ],
        size=13,
        space=3,
    )
    footer(s, page)

    # ---- 6 Package ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Device · Package Selection")
    title_block(s, "AGM039 R47 options", "Freeze SKU with Cisco BOM — all cover the stated I/O plan")
    add_table(
        s,
        Inches(0.4),
        Inches(1.5),
        Inches(12.5),
        Inches(3.0),
        ["Package", "Tiles (typical)", "116G-class", "58G-class", "Choose when…"],
        [
            ["R47A", "3× F + 1× R", "8", "48", "Need PCIe 5.0 / CXL host attach"],
            ["R47B", "4× F + HBM2E", "8", "64", "Need deep on-package buffering"],
            ["R47C", "4× F", "16", "64", "Roadmap >8 client ports @ 112G"],
        ],
        col_widths=[Inches(1.6), Inches(2.4), Inches(1.6), Inches(1.6), Inches(5.3)],
        font_size=12,
    )
    add_rect(s, Inches(0.4), Inches(4.8), Inches(12.5), Inches(2.0), LIGHT_BG)
    add_text_box(s, Inches(0.65), Inches(5.0), Inches(12), Inches(0.35), "Baseline channel assignment", size=14, bold=True, color=NAVY)
    add_bullets(
        s,
        Inches(0.65),
        Inches(5.45),
        Inches(12),
        Inches(1.2),
        [
            "Client ports 0–7 → 8× FHT @ 112G PAM4  ·  System primary → 16× FGT @ 58G PAM4  ·  Secondary → 8× FGT @ 58G",
            "Recommendation: start with R47A for host connectivity; move to R47B if VOQ / store-and-forward depth requires HBM",
        ],
        size=13,
        space=4,
    )
    footer(s, page)

    # ---- 7 Why Altera ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Value · Why Agilex 7 M")
    title_block(s, "Fit for Cisco FC128", "Transceiver density, memory options, and local support")
    rows = [
        ["112G PAM4 client", "F-Tile FHT to 116G PAM4 covers 112.2G 128GFC"],
        ["Dense 58G fabric", "FGT to 58G PAM4 — 48 to 64 channels by R47 SKU"],
        ["Single-chip 8-port bridge", "One AGM039 holds client + both system banks"],
        ["Deep queues", "DDR5 external and/or HBM2E on R47B"],
        ["Host / control", "R-Tile PCIe 5.0 / CXL on R47A"],
        ["Program longevity", "Altera production roadmap + Cisco India FAE coverage"],
    ]
    add_table(
        s,
        Inches(0.5),
        Inches(1.5),
        Inches(12.3),
        Inches(5.2),
        ["Cisco need", "Altera answer"],
        rows,
        col_widths=[Inches(3.8), Inches(8.5)],
        font_size=13,
    )
    footer(s, page)

    # ---- 8 Engagement ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Engagement · Path to Production")
    title_block(s, "Phased plan", "Align package and SerDes protocol before silicon bring-up")
    phases = [
        ("0", "Align", "R47 SKU, system protocol,\nFEC ownership", ALTERA_BLUE),
        ("1", "Architecture", "BW/latency budget,\npin mux, thermal", CLIENT),
        ("2", "PoC", "1–2 clients + system\nloopback, BER evidence", SYSTEM),
        ("3", "Pilot", "Full 8×112 + 16×58,\nCMIS, stats", ORANGE),
        ("4", "Production", "Timing, SEU, PVT,\nmfg test vectors", NAVY),
    ]
    x = Inches(0.4)
    for num, title, blurb, color in phases:
        add_rect(s, x, Inches(1.6), Inches(2.4), Inches(3.2), LIGHT_BG)
        add_rect(s, x, Inches(1.6), Inches(2.4), Inches(0.12), color)
        add_text_box(s, x + Inches(0.2), Inches(1.9), Inches(2.0), Inches(0.4), f"Phase {num}", size=12, bold=True, color=color)
        add_text_box(s, x + Inches(0.2), Inches(2.4), Inches(2.0), Inches(0.45), title, size=18, bold=True, color=NAVY)
        add_text_box(s, x + Inches(0.2), Inches(3.1), Inches(2.0), Inches(1.4), blurb, size=12, color=GRAY)
        x += Inches(2.55)

    add_rect(s, Inches(0.4), Inches(5.1), Inches(12.5), Inches(1.7), LIGHT_BG)
    add_text_box(s, Inches(0.65), Inches(5.25), Inches(12), Inches(0.3), "Open items for Cisco", size=14, bold=True, color=NAVY)
    add_bullets(
        s,
        Inches(0.65),
        Inches(5.6),
        Inches(12),
        Inches(1.1),
        [
            "R47A vs B vs C · system SerDes protocol on 16×58G / 8×58G · soft vs hardened FEC latency · tri-rate 128/64/32GFC · SFP112 mechanical",
        ],
        size=13,
        space=2,
    )
    footer(s, page)

    # ---- 9 Ask ----
    page += 1
    s = blank_slide(prs)
    header_bar(s, "Ask · Next Step")
    title_block(s, "Recommended decision", "Approve AGM039 R47 as the FC128 FPGA baseline")
    add_rect(s, Inches(0.5), Inches(1.6), Inches(12.3), Inches(3.6), LIGHT_BG)
    add_rect(s, Inches(0.5), Inches(1.6), Inches(0.12), Inches(3.6), ACCENT)
    add_bullets(
        s,
        Inches(0.9),
        Inches(1.9),
        Inches(11.5),
        Inches(3.1),
        [
            "Baseline device: Agilex™ 7 M-Series AGM039, package family R47",
            "I/O plan: 8×112G client (128GFC) + 16×58G system + 8×58G secondary",
            "Immediate next step: joint architecture workshop to freeze SKU and system SerDes",
            "PoC exit criteria: multi-port link-up, FEC clean, BER evidence on client and system sides",
        ],
        size=16,
        space=10,
    )
    add_text_box(
        s,
        Inches(0.5),
        Inches(5.5),
        Inches(12.3),
        Inches(1.2),
        "Prepared for Cisco Systems  ·  Altera FAE / Account team\n"
        "Supporting docs: proposal/cisco_fc128/Cisco_FC128_Proposal.md  ·  Executive_Brief.md",
        size=13,
        color=GRAY,
    )
    footer(s, page)

    assert page == TOTAL
    out_path.parent.mkdir(parents=True, exist_ok=True)
    prs.save(str(out_path))
    print(f"Wrote {out_path} ({page} slides)")


if __name__ == "__main__":
    build(OUT_DIR / "Cisco_FC128_Agilex7_Proposal.pptx")
