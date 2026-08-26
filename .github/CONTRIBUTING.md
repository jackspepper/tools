# Contributing to `jackspepper/tools`

Thank you for contributing! This monorepo hosts a collection of scientific utilities, scripts, Quarto pipelines, and R packages.

This guide explains how the repository is structured, how to develop and test tools, the CI checks enforced on Pull Requests, and the automated release tagging process.

---

## 1. Repository Structure & Tool Types

The repository is organized into top-level subdirectories, each representing a tool. Tools fall into one of two categories:

### A. R Packages (e.g. [`qPCR_pipeline`](../qPCR_pipeline/), [`toolfetch`](../toolfetch/))
- Contains a standard R package directory layout (`DESCRIPTION`, `NAMESPACE`, `R/`, `man/`, `inst/`, etc.).
- **Version file**: Versioning is declared in the `Version:` field of the top-level `DESCRIPTION` file.
- **Package name**: Declared in the `Package:` field of `DESCRIPTION` (e.g., `qpcrpipeline` inside `qPCR_pipeline/`).

### B. Standalone Tools (e.g. [`nd2_composite`](../nd2_composite/), [`96_well_plate_editor`](../96_well_plate_editor/), [`incucyte_parse_confluency`](../incucyte_parse_confluency/))
- Standalone Python scripts, browser tools (HTML/JS), or Quarto (`.qmd`) analysis pipelines.
- **Version file**: Versioning is declared in a plain text `VERSION` file at the root of the tool's directory (e.g., `0.1.0`).
- **Tool name**: The folder name itself.

---

## 2. Developer Workflow

### Step 1: Create a Feature Branch
Create a descriptive branch for your work:
```bash
git checkout -b feature/my-new-feature
# or: git checkout -b fix/tool-bugfix
```

### Step 2: Make Code Changes & Increment Version

Every functional code modification requires a version bump before opening a Pull Request.

- **For R Packages**:
  1. Make changes under `R/`, `src/`, `inst/`, `data/`, etc.
  2. Increment the `Version:` field in `DESCRIPTION` (following [Semantic Versioning](https://semver.org/), e.g., `0.3.2` $\rightarrow$ `0.3.3` or `0.3.2.9000`).
  3. Update documentation (`roxygen2::roxygenise()`) if exported functions changed.
  4. Update the package `README.md` and `NEWS.md` (if present).

- **For Standalone Tools**:
  1. Make changes to the tool's scripts or documents.
  2. Increment the version number in the tool's `VERSION` file (e.g., `0.1.0` $\rightarrow$ `0.1.1`).
  3. Update the tool's `README.md` describing any new features, arguments, or requirements.

- **For Adding a Brand New Tool**:
  1. Create a dedicated folder: `my_new_tool/`.
  2. For an R package: include `DESCRIPTION` (with `Package:` and `Version:`) and `README.md`.
  3. For a standalone tool: include `VERSION` (e.g. `0.1.0`) and `README.md`.
  4. Add a one-line description and link to your new tool in the root [`README.md`](../README.md).

### Step 3: Open a Pull Request
Push your branch to GitHub and open a Pull Request targeting `main`.

---

## 3. Pull Request CI Checks

When you open or update a PR targeting `main`, GitHub Actions runs two automated checks:

### Check 1: Tool Versioning (`enforce-tool-versioning.yml`)
Located at [`.github/workflows/enforce-tool-versioning.yml`](./workflows/enforce-tool-versioning.yml).

- **How it works**:
  - Compares the PR branch against the target branch (`main`).
  - For **R Packages**: Triggers if files in `R/`, `src/`, `inst/`, `data/`, `NAMESPACE`, or `DESCRIPTION` changed. Verifies that `new_version > old_version` using R's `numeric_version()`.
  - For **Standalone Tools**: Triggers if any files other than `VERSION` and `README.md` changed. Verifies that `new_version > old_version`.
  - Newly added tools with an initial version pass automatically.
- **Failure Action**: If a version was not bumped when functional code changed, the check fails, generates a Step Summary, and posts a reminder comment on the PR detailing the required action.

### Check 2: README Compliance (`readme-check.yml`)
Located at [`.github/workflows/readme-check.yml`](./workflows/readme-check.yml).

- **Per-Tool README**: Whenever files in a tool folder are changed, that folder's `README.md` must also be updated in the PR.
- **Root README Link**: The root [`README.md`](../README.md) must contain a link pointing to every top-level tool folder.
- **Bypass Mechanism**: For minor/cosmetic PRs where documentation updates are truly not needed, you can bypass the per-tool README check by:
  - Adding the `no-readme` label to the PR, or
  - Including `[skip-readme]` in the PR title or any commit message.

---

## 4. Automated Release Tagging

Workflow location: [`.github/workflows/auto-tag-releases.yml`](./workflows/auto-tag-releases.yml).

When a Pull Request is merged into `main` (or changes are pushed directly):
1. The workflow detects which packages or tools had their version bumped compared to the previous commit.
2. An annotated Git tag is created and pushed automatically using the following formula:
   - **R Packages**: `<PackageName>-v<Version>` (e.g. `qpcrpipeline-v0.3.3`, `toolfetch-v0.4.0`)
   - **Standalone Tools**: `<ToolFolderName>-v<Version>` (e.g. `nd2_composite-v0.1.1`, `96_well_plate_editor-v0.1.0`)
3. Existing tags are never overwritten.
4. Maintainers can also manually trigger the workflow from the Actions tab with `force_tag_all: true` to backfill tags for all existing tools if needed.

---

## 5. Testing & Installing Tools

### Testing Development Branches with `toolfetch`
You can use `toolfetch` in R to test tools from your feature branch before merging:

```r
library(toolfetch)

# List available tools on a specific development branch
tools_list(branch = "feature/my-feature", refresh = TRUE)

# Fetch a tool from a development branch
tools_fetch("my_tool", branch = "feature/my-feature", force = TRUE)
```

### Installing Released R Packages via `pak`
Users can install specific released versions using `pak`'s subdirectory and `@tag` syntax:

```r
# Install latest main branch version
pak::pkg_install("jackspepper/tools/qPCR_pipeline")

# Install a specific pinned release tag
pak::pkg_install("jackspepper/tools/qPCR_pipeline@qpcrpipeline-v0.3.2")
pak::pkg_install("jackspepper/tools/toolfetch@toolfetch-v0.4.0")
```

### Fetching Released Tools via `toolfetch`
```r
library(toolfetch)

# Fetch a standalone tool pinned to a specific release tag
tools_fetch("nd2_composite", branch = "nd2_composite-v0.1.0")

# Fetch and auto-install an R package pinned to a tag
tools_fetch("qPCR_pipeline", branch = "qpcrpipeline-v0.3.2", install = "auto")
```
