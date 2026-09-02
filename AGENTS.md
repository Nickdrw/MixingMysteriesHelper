# Agent Notes

## Git And Releases

- Before preparing a commit message, inspect recent history and match the existing style.
- Prefer feature-oriented commit subjects that describe the user-facing behavior or outcome over subjects that only name technical implementation details.
- Before creating a tag, inspect existing tags and match the repository convention.
- Use this project-specific version-bump vocabulary, even though it differs from standard Semantic Versioning terminology:
  - **Major bump** increments the first component and resets the others: `2.3.0` -> `3.0.0`.
  - **Feature bump** increments the middle component and resets the final component: `2.3.0` -> `2.4.0`. This is called a minor bump in standard Semantic Versioning.
  - **Minor bump** increments only the final component: `2.3.0` -> `2.3.1`. A patch bump is an accepted synonym.
- When the user names a bump type, apply the mapping above exactly; do not reinterpret it based on the perceived size of the changes.
- When the user requests a version bump without naming a bump type or exact version, ask which version to use.
- Keep user-facing fixes and features in their own clean commit before making a release commit. A version-bump commit must change only release/version metadata; never fold implementation changes into `chore: bump addon version to X.Y.Z`.
- Version bump commits use `chore: bump addon version to X.Y.Z`.
- Release tags are annotated and named `vX.Y.Z`; use `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
- This addon publishes releases to CurseForge only; do not configure or use Wago publishing.
- Push releases with `git push origin main --tags`.
