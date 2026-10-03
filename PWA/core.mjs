export function normalize(path) {
  return (
    "/" +
    path
      .replace(/^https:\/\/ios\.cfw\.guide/, "")
      .split(/[?#]/)[0]
      .replace(/^\/+|\/+$/g, "") +
    "/"
  )
    .replace(/^\/\/$/, "/")
    .replace(/\.html\/$/, ".html");
}
export function recommendation(data, device, build) {
  const jb = data.jailbreaks
    .filter((j) => !j.hideFromGuide)
    .sort((a, b) => a.priority - b.priority)
    .find((j) =>
      j.compatibility.some(
        (c) => c.devices.includes(device) && c.firmwares.includes(build),
      ),
    );
  if (!jb) return null;
  const guides = jb.guides
    .filter(
      (g) =>
        (!g.devices || g.devices.includes(device)) &&
        (!g.firmwares || g.firmwares.includes(build)),
    )
    .sort(
      (a, b) =>
        Number(!!b.devices && !!b.firmwares) -
        Number(!!a.devices && !!a.firmwares),
    );
  return { jailbreak: jb, guide: guides[0] };
}
export function validateSnapshot(guide, data) {
  if (
    !Array.isArray(guide.pages) ||
    guide.pages.length < 50 ||
    new Set(guide.pages.map((p) => p.path)).size !== guide.pages.length ||
    !guide.pages.every(
      (p) =>
        typeof p.html === "string" &&
        p.html.length &&
        typeof p.title === "string",
    ) ||
    !data.devices ||
    !Array.isArray(data.firmwares) ||
    !data.firmwares.length ||
    !Array.isArray(data.jailbreaks) ||
    !data.jailbreaks.length
  )
    throw Error("Incomplete content bundle");
  return true;
}
