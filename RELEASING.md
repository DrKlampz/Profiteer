# Releasing Profiteer

## One-time setup
1. Create an EMPTY public repository at https://github.com/new named `Profiteer`
   (no README, license or .gitignore: they are already in this folder).
2. In this folder run `.\release.ps1`. It commits, pushes, and tags the version in `Profiteer.toc`.
3. On Wago: Addons > Create Addon > GitHub Addon Creation > pick `Profiteer`.
   (This creates a new Wago page wired to GitHub releases, like Guildie and Postage.)

## Every release after that
1. Bump `## Version:` in `Profiteer.toc` and add a section to `CHANGELOG.md`.
2. Run `.\release.ps1`.

## Optional: CurseForge / Wago uploads from the Action
Add repository secrets `CF_API_KEY` and `WAGO_API_TOKEN`, and put `## X-Curse-Project-ID:` /
`## X-Wago-ID:` in the TOC. Without them the workflow still creates the GitHub release.
