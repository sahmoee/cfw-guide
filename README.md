<!-- Project documentation exported from the shared knowledge store. -->
# CFW Guide

An unofficial iPhone, iPad and installable web reader for the CFW Guide and AppleDB datasets. Includes searchable guides, exact device/build matching, bookmarks and an offline library.

## Layout

- `CFWGuide/`: native SwiftUI application, canonical content snapshots and artwork.
- `PWA/`: static web application and deployable offline content.
- `scripts/`: snapshot auditing, web packaging and regression checks.
- `project.yml`: reproducible XcodeGen project definition.

## Web development

Requirements: Python 3 and Node.js 20 or later. No npm dependencies are required.

```sh
python3 scripts/build-pwa.py
node scripts/test-pwa.mjs
python3 -m http.server 8790 --directory PWA
```

Open localhost:8790. Service workers require HTTPS or localhost. The first successful visit caches the full library; bookmarks remain in browser storage. To refresh content, replace the reviewed snapshots in `CFWGuide/Resources/`, run the audit and rebuild the PWA. Review upstream licenses and prerequisites before distributing changed guide content.

## Native development

Install Xcode and XcodeGen, then:

```sh
xcodegen generate
xcodebuild -project 'CFW Guide.xcodeproj' -scheme CFWGuide -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

For device installation, select your own development team in Xcode. Keep credentials and signing configuration outside source control. Preserve the existing bundle identifier when updating an installed application to retain its data.

## Updates and checks

Edit native screens in `CFWGuide/`, web screens in `PWA/app.js` and styling in `PWA/style.css`. Run `node scripts/test-pwa.mjs` after changes. Run `python3 scripts/audit-content.py` with Xcode installed for the native content audit. Check navigation, search, bookmarks, device matching and offline reload in a browser before publishing. Generated Xcode projects and user state are excluded from Git.

## Hosting

The current deployment is https://cfw-guide.pages.dev. With your own authorized Cloudflare account and Wrangler installation:

```sh
npx wrangler pages project create cfw-guide --production-branch main
npx wrangler pages deploy PWA --project-name cfw-guide --branch main
```

Skip project creation if it already exists. Do not commit provider tokens. Deploy only after checks pass; retain the prior deployment for rollback.

## Privacy and security

No account, analytics, financial data or private server connection is required. Bookmarks are local. Guide HTML is filtered, remote embedded images are blocked, and security headers restrict active content. External links open their original sites and follow those sites' policies. Hosting providers still receive normal HTTP requests; this is not an anonymity service. Report suspected security issues privately through the repository maintainer before public disclosure. Do not include credentials or personal data in issues.

## Licensing

Guide content and AppleDB attribution and license terms are retained in `LICENSE.txt`. This project is unofficial and does not imply endorsement by upstream maintainers.
