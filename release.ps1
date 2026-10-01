# One-step release for Profiteer (Windows PowerShell).
# Run from this folder:   .\release.ps1
#
# It reads the version from Profiteer.toc, commits any changes, pushes to GitHub,
# and pushes a tag like v0.5.7. The tag triggers the GitHub Action that packages the
# addon and creates the GitHub release.
#
# Before the FIRST run, create an EMPTY repository on GitHub:
#   https://github.com/new   name: Profiteer, Public, no README / license / .gitignore

$remote = "https://github.com/DrKlampz/Profiteer.git"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host "Git isn't installed or isn't on your PATH." -ForegroundColor Red
  exit 1
}

$line = Get-Content .\Profiteer.toc | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
$version = ($line -replace '^## Version:\s*', '').Trim()
if (-not $version) {
  Write-Host "Couldn't read the version from Profiteer.toc." -ForegroundColor Red
  exit 1
}
$tag = "v$version"

if (-not (Test-Path .git)) {
  git init -b main
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

$remotes = git remote
if (-not $remotes) {
  git remote add origin $remote
}

git add -A
$pending = git status --porcelain
if ($pending) {
  git commit -m "Profiteer $version"
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

git push -u origin main
if ($LASTEXITCODE -ne 0) {
  Write-Host "Push failed. Check that the empty GitHub repo exists and that you're logged in to GitHub." -ForegroundColor Red
  exit 1
}

$existing = git tag --list $tag
if ($existing) {
  Write-Host "Tag $tag already exists, so no new release was made. Bump ## Version in Profiteer.toc first." -ForegroundColor Yellow
  exit 0
}

git tag $tag
git push origin $tag
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "Pushed $tag. GitHub Actions will now package and release it." -ForegroundColor Green
Write-Host "Watch it at: https://github.com/DrKlampz/Profiteer/actions"
