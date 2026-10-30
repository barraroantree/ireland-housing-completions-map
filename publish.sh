#!/usr/bin/env bash
# Rebuild the map from the latest CSO NDQ09 release and push it if anything
# changed. Run monthly by .github/workflows/update.yml (1st of the month);
# can also be run by hand from the repo root:  ./publish.sh [--force]
set -euo pipefail
cd "$(dirname "$0")"

git pull --ff-only --quiet
Rscript R/build_map.R "$@"

git add index.html data/ndq09_completions_lea.csv last_checked.txt
if git diff --cached --quiet; then
  echo "Nothing to commit."
  exit 0
fi

latest=$(sed -n 's/^latest NDQ09 quarter: //p' last_checked.txt)
if git diff --cached --quiet -- data/; then
  msg="Check for new NDQ09 data (latest still $latest)"
else
  msg="Update map to NDQ09 data for $latest"
fi
git commit --quiet -m "$msg"
git push --quiet
echo "$msg"
