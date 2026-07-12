#!/usr/bin/env python3
"""Builds the hand-crafted OOXML fixtures: feature.docx (headings, runs,
lists, table, hyperlinks, embedded image x2 for dedupe), deck.pptx
(slides incl. a merged-cell table + speaker notes, numeric ordering),
budget.xlsx (shared/inline strings, sparse cells, formula, date/time
styles), budget1904.xlsx (1904 date system).
Usage: build-ooxml-fixtures.py <samples-dir>
"""
import struct, sys, zipfile, zlib
from pathlib import Path

OUT = Path(sys.argv[1])

def make_png(r, g, b, size=16):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes([r, g, b]) * size for _ in range(size))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

def write_zip(name, entries):
    path = OUT / name
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for arcname, data in entries.items():
            z.writestr(arcname, data)
    print(f"wrote {name}")

# ---------------------------------------------------------------- DOCX
DOC_XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>
<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Project Plan</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Written by </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>Rakan</w:t></w:r><w:r><w:t xml:space="preserve"> in </w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>July</w:t></w:r><w:r><w:t>.</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Tasks</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Design the UI</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Dark mode too</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>Step one ordered</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>Step two ordered</w:t></w:r></w:p>
<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold split</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"> across runs</w:t></w:r><w:r><w:t> then normal.</w:t></w:r></w:p>
<w:tbl>
<w:tr><w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Role</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>Ada</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Engineer | Lead</w:t></w:r></w:p></w:tc></w:tr>
</w:tbl>
<w:p><w:r><w:t>Line with</w:t></w:r><w:r><w:br/><w:t>a break inside.</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Visit </w:t></w:r><w:hyperlink r:id="rId9"><w:r><w:rPr><w:b/></w:rPr><w:t>the docs</w:t></w:r></w:hyperlink><w:r><w:t xml:space="preserve"> and the </w:t></w:r><w:hyperlink w:anchor="section2"><w:r><w:t>internal section</w:t></w:r></w:hyperlink><w:r><w:t>.</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">Chart: </w:t></w:r><w:r><w:drawing><a:blip xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" r:embed="rId20"/></w:drawing></w:r><w:r><w:t xml:space="preserve"> and again </w:t></w:r><w:r><w:drawing><a:blip xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" r:embed="rId20"/></w:drawing></w:r></w:p>
</w:body></w:document>
"""

NUMBERING_XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl><w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>
"""

DOC_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/docs(v2)" TargetMode="External"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId20" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/img1.png"/></Relationships>
"""

write_zip("feature.docx", {
    "word/document.xml": DOC_XML,
    "word/numbering.xml": NUMBERING_XML,
    "word/_rels/document.xml.rels": DOC_RELS,
    "word/media/img1.png": make_png(200, 30, 30),
})

# ---------------------------------------------------------------- PPTX
SLD_NS = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')

SLIDE1 = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld {SLD_NS}><p:cSld><p:spTree>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Distill Roadmap</a:t></a:r></a:p></p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="subTitle" idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Q3 Planning Session</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>
"""

def body_slide(title, first_bullet, idx):
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld {SLD_NS}><p:cSld><p:spTree>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>{title}</a:t></a:r></a:p></p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="{idx}"/></p:nvPr></p:nvSpPr><p:txBody>
<a:p><a:r><a:t>{first_bullet.split(" ", 1)[0]} </a:t></a:r><a:r><a:t>{first_bullet.split(" ", 1)[1]}</a:t></a:r></a:p>
<a:p><a:pPr lvl="1"/><a:r><a:t>DOCX and PPTX extractors</a:t></a:r></a:p>
<a:p><a:pPr lvl="1"/><a:r><a:t>XLSX via CoreXLSX</a:t></a:r></a:p>
<a:p><a:r><a:t>Ship it</a:t></a:r></a:p>
</p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum" idx="2"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>2</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>
"""

SLIDE4 = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld {SLD_NS}><p:cSld><p:spTree>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Quarterly Numbers</a:t></a:r></a:p></p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Figures reviewed by finance</a:t></a:r></a:p></p:txBody></p:sp>
<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="9" name="Table 1"/></p:nvGraphicFramePr>
<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
<a:tbl>
<a:tblGrid><a:gridCol w="2000000"/><a:gridCol w="2000000"/><a:gridCol w="2000000"/></a:tblGrid>
<a:tr h="370840">
<a:tc><a:txBody><a:p><a:r><a:t>Region</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>Q1</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>Q2</a:t></a:r></a:p></a:txBody></a:tc>
</a:tr>
<a:tr h="370840">
<a:tc><a:txBody><a:p><a:r><a:t>EMEA</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>4.2</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>4.8 | up</a:t></a:r></a:p></a:txBody></a:tc>
</a:tr>
<a:tr h="370840">
<a:tc gridSpan="2"><a:txBody><a:p><a:r><a:t>Total (all regions)</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc hMerge="1"><a:txBody><a:p/></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>9.0</a:t></a:r></a:p></a:txBody></a:tc>
</a:tr>
<a:tr h="370840">
<a:tc rowSpan="2"><a:txBody><a:p><a:r><a:t>Notes span two rows</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>first</a:t></a:r></a:p><a:p><a:r><a:t>second para</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>x</a:t></a:r></a:p></a:txBody></a:tc>
</a:tr>
<a:tr h="370840">
<a:tc vMerge="1"><a:txBody><a:p/></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>below</a:t></a:r></a:p></a:txBody></a:tc>
<a:tc><a:txBody><a:p><a:r><a:t>y</a:t></a:r></a:p></a:txBody></a:tc>
</a:tr>
</a:tbl>
</a:graphicData></a:graphic></p:graphicFrame>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="2"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Bullet after the table</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>
"""

NOTES2 = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:notes {SLD_NS}><p:cSld><p:spTree>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Remember to demo drag-and-drop live.</a:t></a:r></a:p><a:p><a:r><a:t>Mention the sandbox.</a:t></a:r></a:p></p:txBody></p:sp>
<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum" idx="5"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>2</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:notes>
"""

write_zip("deck.pptx", {
    "ppt/slides/slide1.xml": SLIDE1,
    "ppt/slides/slide2.xml": body_slide("Phase 2 Goals", "Office formats", 1),
    "ppt/slides/slide4.xml": SLIDE4,
    "ppt/slides/slide10.xml": body_slide("The End", "Questions? here", 9),
    "ppt/notesSlides/notesSlide2.xml": NOTES2,
})

# ---------------------------------------------------------------- XLSX
CT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>{sheet2}<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
"""
SHEET2_CT = '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
"""

def wb_xml(two_sheets, date1904=False):
    pr = '<workbookPr date1904="1"/>' if date1904 else ""
    s2 = '<sheet name="Notes" sheetId="2" r:id="rId2"/>' if two_sheets else ""
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            f'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">{pr}'
            f'<sheets><sheet name="Budget" sheetId="1" r:id="rId1"/>{s2}</sheets></workbook>')

def wb_rels(two_sheets):
    s2 = ('<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet2.xml"/>') if two_sheets else ""
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>{s2}'
            f'<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>')

SHARED = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="8" uniqueCount="8"><si><t>Item</t></si><si><t>Cost</t></si><si><t>Laptop | Pro</t></si><si><t>Desk</t></si><si><t>Total</t></si><si><t>Dates</t></si><si><t>Times</t></si><si><t>Raw serial</t></si></sst>
"""

STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy&quot;年&quot;mm&quot;月&quot;dd&quot;日&quot;"/></numFmts>
<cellXfs count="5">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="0"/>
<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="22" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="20" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
</cellXfs>
</styleSheet>
"""

SHEET1 = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>1999.99</v></c></row>
<row r="3"><c r="A3" t="s"><v>3</v></c><c r="C3"><v>42.5</v></c></row>
<row r="6"><c r="A6" t="s"><v>4</v></c><c r="B6"><f>SUM(B2:B3)</f><v>2042.49</v></c></row>
<row r="8"><c r="A8" t="s"><v>5</v></c><c r="B8" s="1"><v>46203</v></c><c r="C8" s="2"><v>46203.5</v></c></row>
<row r="9"><c r="A9" t="s"><v>6</v></c><c r="B9" s="3"><v>0.75</v></c><c r="C9" s="4"><v>46203</v></c></row>
<row r="10"><c r="A10" t="s"><v>7</v></c><c r="B10"><v>46203</v></c></row>
</sheetData></worksheet>
"""

SHEET2 = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Inline note</t></is></c><c r="B1" t="b"><v>1</v></c></row>
</sheetData></worksheet>
"""

SHEET1_1904 = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Shipped</t></is></c><c r="B1" s="1"><v>44742</v></c></row>
</sheetData></worksheet>
"""

write_zip("budget.xlsx", {
    "[Content_Types].xml": CT.format(sheet2=SHEET2_CT),
    "_rels/.rels": ROOT_RELS,
    "xl/workbook.xml": wb_xml(two_sheets=True),
    "xl/_rels/workbook.xml.rels": wb_rels(two_sheets=True),
    "xl/sharedStrings.xml": SHARED,
    "xl/styles.xml": STYLES,
    "xl/worksheets/sheet1.xml": SHEET1,
    "xl/worksheets/sheet2.xml": SHEET2,
})

write_zip("budget1904.xlsx", {
    "[Content_Types].xml": CT.format(sheet2=""),
    "_rels/.rels": ROOT_RELS,
    "xl/workbook.xml": wb_xml(two_sheets=False, date1904=True),
    "xl/_rels/workbook.xml.rels": wb_rels(two_sheets=False),
    "xl/sharedStrings.xml": SHARED,
    "xl/styles.xml": STYLES,
    "xl/worksheets/sheet1.xml": SHEET1_1904,
})
