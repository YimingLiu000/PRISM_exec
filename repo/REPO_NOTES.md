# PRISM Repository Notes

## What This Repository Is

PRISM is a bioinformatics pipeline for identifying microbial species that are truly present in sequencing data while filtering likely contaminants and false positives.

It is not a web application or a library-first project. The repository is organized around a command-line R pipeline whose main entrypoint is `PRISM.R`.

The pipeline combines:

- Kraken2 for initial taxonomic classification
- Minimap2 for host depletion
- STAR for additional host depletion
- BLAST for more precise sequence matching
- GenBank-derived annotations for gene/product labeling
- A pre-trained XGBoost model (`prismxg.RDS`) for scoring taxa as likely real vs contaminant

According to the README, the intended data types include RNA-seq, WGS, 16S-seq, and scRNA-seq.

## Main Entrypoint

- `PRISM.R`: command-line driver script
- `functions.R`: core pipeline implementation

`PRISM.R` parses CLI options, validates required parameters, creates output directories, sources `functions.R`, and then runs the full workflow step by step.

## High-Level Pipeline

The pipeline in `PRISM.R` runs in this order:

1. Kraken2 analysis
2. Minimap2 host depletion
3. STAR host depletion
4. Subsample microbial reads by taxid
5. BLAST on subsampled reads
6. Multi-mapping analysis to find uniquely identifiable taxa
7. BLAST on the full retained read set
8. Filter non-microbial / human / weak BLAST hits
9. Merge BLAST hits with GenBank gene/product annotations
10. Build features and run the PRISM ML scoring model
11. Save final CSV outputs
12. Generate final PRISM FASTA files

## Key Functions

These functions are the main building blocks in `functions.R`:

- `prism_kraken`: run Kraken2, create reports, extract microbial reads
- `prism_minimap`: remove host-mapped reads with Minimap2
- `prism_star`: remove host-mapped reads with STAR
- `prism_subsample`: subsample candidate microbial reads by taxid
- `prism_blast`: run BLAST on subsampled or full reads
- `prism_multimapping`: identify taxa with enough uniquely mappable reads
- `prism_filter`: keep high-quality microbial BLAST hits and reject human/other hits
- `prism_genbank`: attach gene/product annotations based on GenBank intervals
- `prism_profile`: build per-taxon features and apply the XGBoost model
- `prism_FASTA`: write final retained microbial FASTA files with PRISM annotations

## Important Files

- `README.md`: usage and setup instructions
- `README.Rmd`: source for the generated README
- `PRISM.R`: CLI pipeline entrypoint
- `functions.R`: implementation of nearly all pipeline logic
- `kreport2mpa.py`: helper script converting Kraken reports to MPA-like format
- `prismxg.RDS`: pre-trained XGBoost model used during scoring
- `model_org_taxids.txt`: taxids for model organisms used during filtering/BLAST setup
- `test data/`: sample outputs and example files
- `tests/testthat/`: unit/integration-style tests for selected in-R logic

## Inputs and External Dependencies

The repository does not fully vendor its runtime dependencies. It expects the caller to provide paths to external tools and reference assets.

External tools required by the README:

- Kraken2
- Minimap2
- STAR
- BLAST+
- SeqKit
- R packages: `optparse`, `ShortRead`, `tidyverse`, `furrr`, `data.table`, `vegan`

External data/indexes required by the pipeline:

- Kraken2 database
- Minimap2 host `.mmi` index
- STAR host genome index
- BLAST database
- GenBank-derived annotation directory (`genbank/`) downloaded separately
- BLAST accession-to-taxid mapping file (`sorted_accession_map.txt`) built as a one-time setup step

The repository as cloned does not include the `genbank/` folder referenced by the pipeline, so the project is not runnable end-to-end without downloading additional data.

## Outputs

The final outputs described by the repository are:

- `X-results.csv`: read-level final table with taxonomy, alignment, annotation, and PRISM score
- `X-counts.csv`: per-species summary with read counts and predicted score
- `X_1.fa` and optionally `X_2.fa`: retained microbial reads in FASTA format with annotated headers

The pipeline also writes many intermediate files under a sample-specific output directory and a log file named like `sample_PRISM.log`.

## Repository Structure Observations

This is a research-oriented codebase with a fairly direct implementation style:

- most logic lives in one large `functions.R`
- orchestration is centralized in one script
- many steps shell out to external tools via `system(...)`
- outputs are used as step checkpoints to allow reruns/skips

This makes the flow understandable, but also means the code is tightly coupled to filesystem layout and external binaries.

## Testing Status

There is a `testthat` test suite under `tests/testthat/`, but it mainly covers:

- input validation for selected functions
- BLAST filtering logic
- multimapping logic
- synthetic integration of pure-R parts of the pipeline

It does not appear to provide full end-to-end coverage of the external-tool workflow.

## Risks / Caveats Identified During Review

These are the main implementation risks I noticed while reading the repository:

1. `model_org_taxids` default handling in `PRISM.R` looks suspicious.
   The CLI default is `"NA"`, and the code builds `paste0(prism_path, opt$model_org_taxids)`, which would resolve to `.../NA` instead of the bundled `model_org_taxids.txt`.

2. Several functions rely on globals rather than only explicit parameters.
   Examples include use of `prism_path`, `kr_report`, and `mpa` from outside the local function scope. That makes isolated testing and reuse more fragile.

3. `prism_star` is called with `id_df` before `id_df` is created in the main pipeline.
   In practice this does not currently fail because `prism_star` does not use that argument meaningfully, but the dependency ordering is inconsistent.

4. The runtime environment burden is high.
   A successful run requires multiple external bioinformatics tools, several large reference databases, and separately downloaded GenBank-derived assets.

5. The code uses many shell commands embedded in R strings.
   That is pragmatic for this kind of pipeline, but increases portability and maintainability risk.

## Practical Summary

If I had to describe the repository in one sentence:

PRISM is an R-driven microbial read filtering and scoring pipeline that uses fast taxonomic screening, host depletion, BLAST refinement, GenBank annotation, and a pre-trained ML model to separate likely real microbes from contaminants in sequencing data.
