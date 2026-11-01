# Vendored dependencies

All files are ordinary repository files; no installation or network access is needed to build or test.

Source files and licenses are copied unchanged from these pinned release archives:

- **OpenZeppelin/openzeppelin-contracts v5.0.2**: [v5.0.2](https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2)
  - Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
  - Vendored path: `lib/openzeppelin-contracts/` (6 files).

- **foundry-rs/forge-std v1.9.7**: [v1.9.7](https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7)
  - Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
  - Vendored path: `lib/forge-std/` (30 files).

Only the OpenZeppelin ERC-20 implementation and its transitive dependencies are included. Forge Standard Library is test-only; its `src/` tree and both licenses are included.

OpenZeppelin is MIT licensed. Forge Standard Library is MIT OR Apache-2.0 licensed. See the license files in each dependency directory.
