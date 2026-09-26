const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const report = [];
  for (const frame of JSON.parse(fs.readFileSync(path.join(__dirname, 'manifest.json'))).frames) {
    await page.goto(`file://${path.join(__dirname, 'frames', `${frame.id}.svg`)}`);
    const result = await page.evaluate(() => {
      const texts = [...document.querySelectorAll('text')];
      const overflow = texts.map(el => ({ text: el.textContent, box: el.getBBox() }))
        .filter(({ box: b }) => b.x < 0 || b.y < 0 || b.x + b.width > 1600 || b.y + b.height > 900)
        .map(({ text }) => text);
      return { textCount: texts.length, overflow };
    });
    report.push({ id: frame.id, ...result });
  }
  await page.goto(`file://${path.join(__dirname, 'index.html')}`);
  const loaded = await page.locator('img').evaluateAll(images => images.every(image => image.complete && image.naturalWidth > 0));
  await page.setViewportSize({ width: 390, height: 844 });
  const mobileGalleryOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  await browser.close();
  fs.writeFileSync(path.join(__dirname, 'verification.json'), JSON.stringify({ frames: report, galleryImagesLoaded: loaded, mobileGalleryOverflow, note: 'Mobile gallery only; gameplay mockups are desktop designs.' }, null, 2) + '\n');
  if (report.some(r => r.overflow.length) || !loaded || mobileGalleryOverflow) throw new Error('Design verification failed; inspect verification.json');
  console.log(`Verified ${report.length} SVG frames: text within canvas, gallery assets loaded, responsive gallery fits 390px.`);
}
main().catch(error => { console.error(error); process.exit(1); });
