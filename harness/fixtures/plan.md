# Move the archive to static pages

Three steps, one afternoon. Nothing to answer; cross it when you have read it.

## 1. Export

A script walks `content/archive` and writes one HTML file per entry into `public/archive/`.

## 2. Redirects

The 140 old URLs keep working through a single rule in `.htaccess`.

| Step | Files | Risk |
| --- | --- | --- |
| Export | 1 new | none |
| Redirects | 1 changed | low |

- [ ] export
- [ ] redirects
