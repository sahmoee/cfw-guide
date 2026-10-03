#!/usr/bin/env python3
"""Validate offline resources and the real Swift live guide refresh. Requires Swift and network."""
import json, re, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = root / "CFWGuide"
guide = json.loads((source / "Resources/guide.json").read_text())
assert len({p["path"] for p in guide["pages"]}) == len(guide["pages"])
for page in guide["pages"]:
    assert page["html"].strip()
    for asset in re.findall(r'cfwasset:///([^"\s]+)', page["html"]):
        assert (source / "Resources/SiteAssets" / asset).is_file(), asset
web = (source / "PageWebView.swift").read_text()
safe = web[web.index("    static func safePath"):web.index("    static func localFile")]
code = "import Foundation\n" + (source / "Models.swift").read_text() + (source / "Refresher.swift").read_text()
code += '@main struct Audit {\nstatic func main() async throws {\n precondition(AssetCache.safePath("/assets/images/a.png") == "assets/images/a.png")\n for bad in ["../private.png", "assets/../private.png", "assets/%2e%2e/private.png", "assets/test.json", "assets/./a.png", "assets//a.png"] { precondition(AssetCache.safePath(bad) == nil) }\n let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))\n let guide = try JSONDecoder().decode(GuideBundle.self, from: input)\n let updated = try await Refresher.downloadGuide(known: guide.pages.map(\\.path)) { _ in }\n precondition(Set(guide.pages.map(\\.path)).isSubset(of: Set(updated.pages.map(\\.path))))\n let data = try await Refresher.downloadData { _ in }\n precondition(!data.devices.isEmpty && !data.firmwares.isEmpty && !data.jailbreaks.isEmpty)\n print("PASS live AppleDB refresh: \\(data.devices.count) devices, \\(data.firmwares.count) firmware records")\n print("PASS asset confinement and live refresh: \\(updated.pages.count) pages, \\(updated.sections.count) sections")\n}\n}\n'
with tempfile.TemporaryDirectory(prefix="cfw-audit-") as temp:
    swift = Path(temp) / "Audit.swift"
    swift.write_text(code)
    binary = Path(temp) / "Audit"
    subprocess.run(["swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(source / "Resources/guide.json")], check=True, cwd=root)
print("PASS bundled page uniqueness and all offline guide images")
