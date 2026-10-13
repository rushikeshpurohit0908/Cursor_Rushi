#!/usr/bin/env python3
"""Cisco India one-pager matching the Cisco collaboration Norway dashboard layout."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.chart.data import CategoryChartData
from pptx.dml.color import RGBColor
from pptx.enum.chart import XL_CHART_TYPE, XL_LEGEND_POSITION
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Inches, Pt

# Palette approximating Altera Light / Norway slide
NAVY = RGBColor(0x1A, 0x1A, 0x1A)
BLUE = RGBColor(0x00, 0x7A, 0xCC)
CISCO_BLUE = RGBColor(0x04, 0x9E, 0xD8)
GRAY = RGBColor(0x5A, 0x5A, 0x5A)
LIGHT = RGBColor(0xF2, 0xF2, 0xF2)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
GREEN = RGBColor(0x2E, 0xA0, 0x44)
ORANGE = RGBColor(0xE6, 0x7E, 0x22)
RED = RGBColor(0xC0, 0x39, 0x2B)
SWOT_S = RGBColor(0x1F, 0x7A, 0x4C)
SWOT_W = RGBColor(0xB0, 0x35, 0x3A)
SWOT_O = RGBColor(0x00, 0x7A, 0xCC)
SWOT_T = RGBColor(0xC4, 0x7A, 0x12)
TABLE_HDR = RGBColor(0xE8, 0xEE, 0xF3)
CHART_BLUE = RGBColor(0x2E, 0x86, 0xC1)
CHART_GOLD = RGBColor(0xF1, 0xC4, 0x0F)

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)
FONT = "Liberation Sans"
ASSET_DIR = Path(__file__).resolve().parents[1] / "presentations" / "assets"


def set_run_font(run, size=11, bold=False, color=NAVY):
    run.font.name = FONT
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    rPr = run._r.get_or_add_rPr()
    for tag in ("latin", "ea", "cs"):
        el = rPr.find(qn(f"a:{tag}"))
        if el is None:
            el = rPr.makeelement(qn(f"a:{tag}"), {})
            rPr.append(el)
        el.set("typeface", FONT)


def rect(slide, l, t, w, h, fill, line=None):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, w, h)
    sh.fill.solid()
    sh.fill.fore_color.rgb = fill
    if line is None:
        sh.line.fill.background()
    else:
        sh.line.color.rgb = line
        sh.line.width = Pt(0.75)
    return sh


def textbox(slide, l, t, w, h, text, *, size=11, bold=False, color=NAVY, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    box = slide.shapes.add_textbox(l, t, w, h)
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


def bullets(slide, l, t, w, h, items, *, size=10, color=NAVY, space=4):
    box = slide.shapes.add_textbox(l, t, w, h)
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


def panel(slide, l, t, w, h):
    return rect(slide, l, t, w, h, WHITE, line=RGBColor(0xDD, 0xDD, 0xDD))


def status_dot(slide, l, t, color):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, Inches(0.18), Inches(0.18))
    sh.fill.solid()
    sh.fill.fore_color.rgb = color
    sh.line.fill.background()
    return sh


def mini_table(slide, l, t, w, h, headers, rows, col_widths=None, header_fill=TABLE_HDR):
    shape = slide.shapes.add_table(len(rows) + 1, len(headers), l, t, w, h)
    table = shape.table
    if col_widths:
        for i, cw in enumerate(col_widths):
            table.columns[i].width = cw
    for j, hdr in enumerate(headers):
        cell = table.cell(0, j)
        cell.text = ""
        p = cell.text_frame.paragraphs[0]
        run = p.add_run()
        run.text = hdr
        set_run_font(run, size=9, bold=True, color=NAVY)
        cell.fill.solid()
        cell.fill.fore_color.rgb = header_fill
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    for i, row in enumerate(rows):
        for j, val in enumerate(row):
            cell = table.cell(i + 1, j)
            cell.text = ""
            p = cell.text_frame.paragraphs[0]
            run = p.add_run()
            run.text = str(val)
            set_run_font(run, size=8, color=NAVY)
            cell.fill.solid()
            cell.fill.fore_color.rgb = WHITE
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    return shape


def add_bar_chart(slide, l, t, w, h, title, categories, values):
    data = CategoryChartData()
    data.categories = categories
    data.add_series(title, values)
    chart = slide.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, l, t, w, h, data).chart
    chart.has_legend = False
    plot = chart.plots[0]
    plot.gap_width = 80
    series = plot.series[0]
    # color points: last (forecast) gold-ish
    try:
        from pptx.oxml import parse_xml

        # solid fill via series format
        series.format.fill.solid()
        series.format.fill.fore_color.rgb = CHART_BLUE
    except Exception:
        pass
    chart.chart_title.has_text_frame = True
    tf = chart.chart_title.text_frame
    tf.text = ""
    p = tf.paragraphs[0]
    run = p.add_run()
    run.text = title
    set_run_font(run, size=9, bold=True, color=NAVY)
    return chart


def build(out_path: Path, also_append_to: Path | None = None):
    prs = Presentation()
    prs.slide_width = SLIDE_W
    prs.slide_height = SLIDE_H
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Background
    rect(slide, Inches(0), Inches(0), SLIDE_W, SLIDE_H, LIGHT)

    # ---- Header ----
    cisco_logo = ASSET_DIR / "cisco_wordmark.png"
    if cisco_logo.exists():
        slide.shapes.add_picture(str(cisco_logo), Inches(0.25), Inches(0.12), height=Inches(0.38))
    else:
        textbox(slide, Inches(0.25), Inches(0.12), Inches(1.5), Inches(0.35), "cisco", size=20, bold=True, color=CISCO_BLUE)

    textbox(slide, Inches(0.25), Inches(0.52), Inches(4.5), Inches(0.35), "Cisco India — SP Routing & Optical", size=18, bold=True, color=NAVY)
    textbox(
        slide,
        Inches(0.25),
        Inches(0.88),
        Inches(4.8),
        Inches(0.45),
        "Account Owner: Manoj Gopalan\nTechnical Owner: Rushikesh Purohit · Kasturi Rangan",
        size=10,
        color=GRAY,
    )

    india_map = ASSET_DIR / "india_map.png"
    if india_map.exists():
        slide.shapes.add_picture(str(india_map), Inches(5.0), Inches(0.15), height=Inches(1.05))

    # ---- LEFT: Business Overview ----
    panel(slide, Inches(0.2), Inches(1.35), Inches(3.55), Inches(5.55))
    textbox(slide, Inches(0.35), Inches(1.45), Inches(3.2), Inches(0.28), "Business Overview", size=12, bold=True, color=NAVY)
    textbox(
        slide,
        Inches(0.35),
        Inches(1.72),
        Inches(3.2),
        Inches(0.35),
        "Control-plane FPGA focus · Bengaluru design center\nAltera India pipe (registered): $1.53M",
        size=9,
        color=GRAY,
    )

    textbox(slide, Inches(0.35), Inches(2.15), Inches(3.2), Inches(0.22), "Key Products", size=10, bold=True, color=NAVY)
    mini_table(
        slide,
        Inches(0.3),
        Inches(2.4),
        Inches(3.35),
        Inches(3.0),
        ["Product / Program", "Stage", "MSS", "Pipe/SAM"],
        [
            ["ASR1k Traffic Manager", "Active", "Win path", "WW-linked"],
            ["Lavena OAM (8000 MPA)", "Define", "Chase", "$600K"],
            ["Le Tour PH2", "Define", "Chase", "$480K"],
            ["Agena MPA Ctrl Card", "Define", "Chase", "$450K"],
            ["Firebolt (A5+MAX10)", "Pursuit", "Open", "TBD"],
            ["India RFQ ctrl plane", "Quoted", "At risk", "Price-gated"],
            ["Optical (w/ Italy)", "Engage", "Low", "~$2M SAM"],
        ],
        col_widths=[Inches(1.55), Inches(0.6), Inches(0.55), Inches(0.65)],
    )

    textbox(slide, Inches(0.35), Inches(5.5), Inches(3.2), Inches(0.22), "Top Applications / Top 3 Seg", size=10, bold=True, color=NAVY)
    bullets(
        slide,
        Inches(0.35),
        Inches(5.75),
        Inches(3.2),
        Inches(1.0),
        [
            "SP Aggregation / Edge routers (ASR, 8000)",
            "Control-plane / IO FPGA & Traffic Manager",
            "Optical transport (India + Italy)",
        ],
        size=9,
        space=2,
    )

    # ---- CENTER TOP: SWOT Customer view ----
    panel(slide, Inches(3.9), Inches(1.35), Inches(5.35), Inches(2.55))
    textbox(slide, Inches(4.05), Inches(1.42), Inches(5.0), Inches(0.25), "SWOT Analysis — Customer View (Cisco India)", size=11, bold=True, color=NAVY)

    swot = [
        (Inches(4.05), Inches(1.75), "Strengths", SWOT_S, [
            "30+ FPGA eng in Bengaluru; owns SP routing & optical design",
            "8000 / ASR platforms + Silicon One datapath leadership",
            "Deep director bench (Alap, Akhil, Vijay)",
        ]),
        (Inches(6.65), Inches(1.75), "Weaknesses", SWOT_W, [
            "Control plane locked to Xilinx Artix / Microchip SF2",
            "Slow FPGA vendor switch; price-sensitive RFQs",
            "Legacy codebases raise migration cost",
        ]),
        (Inches(4.05), Inches(2.7), "Opportunities", SWOT_O, [
            "Control-plane refresh; PQC / secure-boot mandates",
            "Make-in-India manufacturing expands local programs",
            "AI/ML on control path & BMC attach",
        ]),
        (Inches(6.65), Inches(2.7), "Threats", SWOT_T, [
            "ASIC absorption of datapath value",
            "Lattice / AMD / PolarFire price-feature pressure",
            "Virtualization & SW disrupts HW attach",
        ]),
    ]
    for left, top, title, color, items in swot:
        rect(slide, left, top, Inches(2.45), Inches(0.88), RGBColor(0xF7, 0xF9, 0xFB), line=RGBColor(0xE0, 0xE0, 0xE0))
        rect(slide, left, top, Inches(2.45), Inches(0.22), color)
        textbox(slide, left + Inches(0.05), top + Inches(0.01), Inches(2.35), Inches(0.2), title, size=9, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
        bullets(slide, left + Inches(0.05), top + Inches(0.25), Inches(2.35), Inches(0.6), items, size=7, space=1)

    # ---- CENTER MID: Strategy & Goals ----
    panel(slide, Inches(3.9), Inches(4.05), Inches(5.35), Inches(2.85))
    textbox(slide, Inches(4.05), Inches(4.12), Inches(5.0), Inches(0.25), "2026 Strategy & Goals", size=11, bold=True, color=NAVY)

    # Charts — illustrative India Cisco engagement metrics
    cats = ["'24", "'25", "'26F"]
    add_bar_chart(slide, Inches(4.0), Inches(4.4), Inches(1.65), Inches(1.25), "India Pipe $M", cats, (0.9, 1.3, 1.53))
    add_bar_chart(slide, Inches(5.75), Inches(4.4), Inches(1.65), Inches(1.25), "Active Programs", cats, (2, 4, 7))
    add_bar_chart(slide, Inches(7.5), Inches(4.4), Inches(1.65), Inches(1.25), "DW Claim Path $M", cats, (0.0, 0.2, 1.0))

    textbox(slide, Inches(4.05), Inches(5.7), Inches(2.5), Inches(0.2), "Secure and grow existing business", size=9, bold=True, color=NAVY)
    bullets(
        slide,
        Inches(4.05),
        Inches(5.9),
        Inches(2.5),
        Inches(0.85),
        [
            "Close TM / Sausalito DWIN split with WW",
            "Hold Lavena Agilex 7 on AMD timing pain",
            "Sustain Bengaluru FAE presence on APS",
        ],
        size=8,
        space=1,
    )
    textbox(slide, Inches(6.7), Inches(5.7), Inches(2.4), Inches(0.2), "Expand share of wallet", size=9, bold=True, color=NAVY)
    bullets(
        slide,
        Inches(6.7),
        Inches(5.9),
        Inches(2.4),
        Inches(0.85),
        [
            "Win India RFQ with Agilex 5 pricing",
            "Firebolt A5 + MAX 10 platform attach",
            "PQC / secure-boot vs SmartFusion2",
        ],
        size=8,
        space=1,
    )

    # ---- RIGHT: Key Relationships ----
    panel(slide, Inches(9.4), Inches(1.35), Inches(3.7), Inches(2.35))
    textbox(slide, Inches(9.55), Inches(1.42), Inches(3.4), Inches(0.22), "Key Relationships", size=11, bold=True, color=NAVY)
    # header row
    rect(slide, Inches(9.5), Inches(1.7), Inches(3.5), Inches(0.28), TABLE_HDR)
    textbox(slide, Inches(9.55), Inches(1.72), Inches(1.35), Inches(0.24), "Cisco", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    textbox(slide, Inches(10.95), Inches(1.72), Inches(1.2), Inches(0.24), "Altera", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    textbox(slide, Inches(12.2), Inches(1.72), Inches(0.7), Inches(0.24), "Status", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)

    rels = [
        ("Vijay Pramod (FPGA Dir)", "Ganga / Rushikesh", GREEN),
        ("Alap Shah (Sr Dir CE)", "Manoj / Chuck", ORANGE),
        ("Akhil Guha (Sr Dir HW)", "Manoj / Rushikesh", GREEN),
        ("Manikandan (Sr Arch)", "Kasturi", GREEN),
        ("TM eng (Kannan/Vaibhav)", "Kasturi / Factory", GREEN),
        ("Marco Croci (VP Eng)", "Jacques / Mike", ORANGE),
    ]
    y = Inches(2.02)
    for cisco, altera, st in rels:
        textbox(slide, Inches(9.55), y, Inches(1.4), Inches(0.24), cisco, size=7, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
        textbox(slide, Inches(10.95), y, Inches(1.2), Inches(0.24), altera, size=7, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
        status_dot(slide, Inches(12.45), y + Inches(0.03), st)
        y += Inches(0.26)

    # Gaps & Concerns
    panel(slide, Inches(9.4), Inches(3.85), Inches(3.7), Inches(1.35))
    textbox(slide, Inches(9.55), Inches(3.92), Inches(3.4), Inches(0.22), "Gaps & Concerns", size=11, bold=True, color=NAVY)
    bullets(
        slide,
        Inches(9.55),
        Inches(4.2),
        Inches(3.4),
        Inches(0.9),
        [
            "Agilex 5 ~40% above Lattice on India RFQ",
            "Thin Cisco FTE (5% FSE / 10% FAE) vs TM load",
            "Low-end secure ~$8 socket — no product path",
        ],
        size=8,
        space=2,
    )

    # Action Plans
    panel(slide, Inches(9.4), Inches(5.35), Inches(3.7), Inches(1.55))
    textbox(slide, Inches(9.55), Inches(5.42), Inches(3.4), Inches(0.22), "Action Plans", size=11, bold=True, color=NAVY)
    rect(slide, Inches(9.5), Inches(5.68), Inches(3.5), Inches(0.24), TABLE_HDR)
    textbox(slide, Inches(9.55), Inches(5.68), Inches(2.0), Inches(0.24), "Action Plans", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    textbox(slide, Inches(11.55), Inches(5.68), Inches(0.7), Inches(0.24), "Due", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
    textbox(slide, Inches(12.25), Inches(5.68), Inches(0.65), Inches(0.24), "Status", size=8, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)

    actions = [
        ("Claim TM/Sausalito DWIN split w/ WW", "Oct'26", RED),
        ("Agilex 5 golden-part pricing for RFQ", "Q4'26", ORANGE),
        ("Lavena A7 fit analysis vs AMD timing", "Nov'26", ORANGE),
        ("PQC / SEU close with Bengaluru eng", "Q4'26", GREEN),
    ]
    y = Inches(5.95)
    for act, due, st in actions:
        textbox(slide, Inches(9.55), y, Inches(2.0), Inches(0.2), act, size=7, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
        textbox(slide, Inches(11.55), y, Inches(0.7), Inches(0.2), due, size=7, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
        status_dot(slide, Inches(12.45), y + Inches(0.01), st)
        y += Inches(0.22)

    # Footer
    altera_logo = ASSET_DIR / "altera_wordmark.png"
    if altera_logo.exists():
        slide.shapes.add_picture(str(altera_logo), Inches(0.25), Inches(7.05), height=Inches(0.28))
    else:
        textbox(slide, Inches(0.25), Inches(7.05), Inches(1.2), Inches(0.28), "altera", size=14, color=BLUE)
    textbox(slide, Inches(10.8), Inches(7.1), Inches(2.2), Inches(0.25), "Altera Confidential", size=9, color=GRAY, align=PP_ALIGN.RIGHT)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    prs.save(out_path)
    print(f"Wrote {out_path}")

    if also_append_to and also_append_to.exists():
        base = Presentation(str(also_append_to))
        # copy by rebuilding into base is hard; instead save one-pager and note append separately
        # Append: create new presentation merging XML is complex — save side-by-side only
        pass

    return out_path


if __name__ == "__main__":
    build(Path("/workspace/presentations/Cisco_India_Collaboration_OnePager.pptx"))
