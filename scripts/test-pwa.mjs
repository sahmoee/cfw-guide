import assert from "node:assert/strict";
import fs from "node:fs";
import { normalize, recommendation, validateSnapshot } from "../PWA/core.mjs";
const base = new URL("../PWA/", import.meta.url);
const json = (p) => JSON.parse(fs.readFileSync(new URL(p, base)));
const guide = json("guide.json"),
  data = json("data.json");
assert(validateSnapshot(guide, data));
assert.equal(normalize("https://ios.cfw.guide/faq/#a"), "/faq/");
assert.equal(normalize("/using-cydia.html"), "/using-cydia.html");
assert.equal(recommendation(data, "nonexistent", "unknown"), null);
assert.equal(
  recommendation(data, "iPhone10,6", "19A346").jailbreak.name,
  "Dopamine",
);
assert.throws(() => validateSnapshot({ pages: [] }, data));
const files = json("precache.json");
files.forEach((p) => assert(fs.existsSync(new URL(p, base)), p));
for (const required of [
  "index.html",
  "app.js",
  "core.mjs",
  "style.css",
  "guide.json",
  "data.json",
  "manifest.webmanifest",
  "icons/icon-192.png",
  "icons/icon-512.png",
])
  assert(files.includes(required), required);
for (const page of guide.pages)
  for (const match of page.html.matchAll(/cfwasset:\/\/\/([^"\s]+)/g))
    assert(files.includes(match[1]), match[1]);
console.log(
  "PASS complete content, exact-device recommendations, malformed snapshot rejection, routes, offline resource coverage",
);
