#!/usr/bin/env bash
#
# Baut, committet, pusht und veröffentlicht ImmoCheck auf GitHub Pages.
#
#   ./deploy.sh "Beschreibung der Änderung"
#
# Beim ersten Lauf wird das Repository angelegt und GitHub Pages eingeschaltet.
# Danach genügt jeder weitere Aufruf, um den öffentlichen Link zu aktualisieren.
#
set -euo pipefail

REPO_NAME="${REPO_NAME:-immocheck}"
NACHRICHT="${1:-Update}"

cd "$(dirname "$0")"

echo "==> Bauen"
node build.js

if [ ! -d .git ]; then
  echo "==> Git-Repository anlegen"
  git init -b main >/dev/null
fi

echo "==> Änderungen sichern"
git add -A
if git diff --cached --quiet; then
  echo "    nichts Neues zu sichern"
else
  git commit -m "$NACHRICHT" >/dev/null
  echo "    committet: $NACHRICHT"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "FEHLER: Die GitHub CLI (gh) fehlt. Installation: https://cli.github.com"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "==> Bei GitHub anmelden"
  gh auth login
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "==> Repository auf GitHub anlegen und hochladen"
  gh repo create "$REPO_NAME" --public --source=. --remote=origin --push \
    --description "ImmoCheck: Sicherheits- und Qualitaetskontrolle fuer Immobilien"
else
  echo "==> Hochladen"
  git push -u origin main
fi

BESITZER=$(gh repo view --json owner --jq .owner.login)
NAME=$(gh repo view --json name --jq .name)

if ! gh api "repos/$BESITZER/$NAME/pages" >/dev/null 2>&1; then
  echo "==> GitHub Pages einschalten"
  gh api -X POST "repos/$BESITZER/$NAME/pages" \
    -f "source[branch]=main" -f "source[path]=/" >/dev/null
  echo "    eingeschaltet, der erste Aufbau dauert etwa eine Minute"
fi

LINK=$(gh api "repos/$BESITZER/$NAME/pages" --jq .html_url 2>/dev/null || echo "")
echo
echo "Fertig."
[ -n "$LINK" ] && echo "Öffentlicher Link: $LINK"
echo "Repository:        https://github.com/$BESITZER/$NAME"
