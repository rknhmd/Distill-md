// Real-world-generator fixture: a pptxgenjs deck with a merged-cell
// table, speaker notes, and an embedded image.
// Usage: NODE_PATH=$(npm root -g) node make-real-pptx.cjs <output-dir>
const pptxgen = require("pptxgenjs");
const path = require("path");

// 16x16 blue PNG, generated once (same bytes as build-ooxml-fixtures.py
// would produce for rgb(30,60,220)) — inlined so node needs no deps.
const bluePNG =
  "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAJElEQVR4nGNgPHOWgYmBiYGJ" +
  "gYmBiYGJgYmBiYGJgYmBiYGJgQEAOAYBFXGLBSAAAAAASUVORK5CYII=";

const outDir = process.argv[2] || ".";
const pres = new pptxgen();

const slide1 = pres.addSlide();
slide1.addText("Budget Review", { placeholder: "title", x: 0.5, y: 0.4, w: 9, h: 0.8, fontSize: 32, bold: true });
slide1.addTable(
  [
    [
      { text: "Department", options: { bold: true } },
      { text: "H1", options: { bold: true } },
      { text: "H2", options: { bold: true } },
    ],
    ["Engineering", "120", "135"],
    [{ text: "Company total", options: { colspan: 2 } }, "255"],
    [{ text: "Spans down", options: { rowspan: 2 } }, "a1", "a2"],
    ["b1", "b2"],
  ],
  { x: 0.5, y: 1.5, w: 9 }
);
slide1.addNotes("Fixture notes: verify tables and notes both survive conversion.");

const slide2 = pres.addSlide();
slide2.addText("Plain slide", { x: 0.5, y: 0.4, w: 9, h: 0.8, fontSize: 32, bold: true });
slide2.addText("Just a text box, no table.", { x: 0.5, y: 1.5, w: 9, h: 0.6, fontSize: 16 });
slide2.addImage({ data: "image/png;base64," + bluePNG, x: 0.5, y: 2.5, w: 1, h: 1 });

pres.writeFile({ fileName: path.join(outDir, "real.pptx") }).then(() => {
  console.log("wrote real.pptx");
});
