# PRISM Linux Bundle

This repository packages the materials needed to run and understand PRISM for RNA-seq microbial detection, with a focus on fungal result extraction.

## What PRISM Does

PRISM is a modular pipeline for identifying truly present microbial species in low-biomass sequencing data. It combines:

- Kraken2 for initial taxonomic screening
- Minimap2 and STAR for host depletion
- BLAST for finer alignment and unique-hit analysis
- GenBank annotations for gene/product context
- A pretrained XGBoost model for contamination scoring

## Bundle Contents

- `scripts/`: installation, database-prep, and analysis scripts
- `README_zh.md`: Chinese execution guide
- `PRISM_algorithm_interpretation_zh.md`: algorithm summary
- `paper.pdf`: the source paper

## Recommended Workflow

1. Set a project root:

```bash
export PROJECT_ROOT=/your/path/to/PRISM
```

2. Create the conda environment:

```bash
conda env create -f ${PROJECT_ROOT}/00script/environment_prism.yml
```

3. Prepare databases and indexes in two stages:
- Download sources on a fast network machine
- Build final databases on the server

4. Run PRISM on RNA-seq data
5. Extract fungal results from the final outputs

## Repository Layout

```bash
${PROJECT_ROOT}/
├── 00script/
│   └── repo/
├── 01rawdata/
├── 02ref/
└── 02fastq/
```

## Notes

- Database preparation is split into download-only and build-only scripts.
- Fungal extraction is taxonomy-based, not keyword-based.
- The workflow is designed to be portable across machines.

