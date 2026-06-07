#!/usr/bin/env bash

# Run PRISM on one RNA-seq sample.
#
# Required:
#   SAMPLE=<sample_name> bash run_prism_rnaseq.sh
# or:
#   bash run_prism_rnaseq.sh <sample_name>
#
# Optional environment variables:
#   PROJECT_ROOT       PRISM project root. Defaults to the bundle/project root.
#   RAW_DIR            Directory containing gzipped FASTQ input files.
#   FASTQ_DIR          Directory where uncompressed FASTQ and PRISM outputs are written.
#   FQ1_END            Read 1 suffix used by PRISM. Default: _RNAseq_R1.fastq
#   FQ2_END            Read 2 suffix used by PRISM. Default: _RNAseq_R2.fastq
#   STAR_GENOME_LOAD   STAR --genomeLoad mode. Default: NoSharedMemory
#   KRAKEN2_EXTRA_OPTS Extra Kraken2 options. Default: --memory-mapping
#   PRISM_THREADS      Thread count passed to PRISM. Default: 16
#   USE_CUSTOM_DB      Whether PRISM should build/use a custom BLAST DB. Default: FALSE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../00script/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  PROJECT_ROOT="${HOME}/PRISM"
fi

if [[ -d "${PROJECT_ROOT}/repo" ]]; then
  PRISM_ROOT="${PROJECT_ROOT}/repo"
elif [[ -d "${PROJECT_ROOT}/00script/repo" ]]; then
  PRISM_ROOT="${PROJECT_ROOT}/00script/repo"
else
  echo "[ERROR] PRISM repo directory not found under PROJECT_ROOT: ${PROJECT_ROOT}"
  echo "        Expected either ${PROJECT_ROOT}/repo or ${PROJECT_ROOT}/00script/repo"
  exit 1
fi

SAMPLE="${1:-${SAMPLE:-}}"
if [[ -z "${SAMPLE}" ]]; then
  echo "Usage: SAMPLE=<sample_name> bash $0"
  echo "   or: bash $0 <sample_name>"
  exit 1
fi

RAW_DIR="${RAW_DIR:-${PROJECT_ROOT}/01rawdata}"
FASTQ_DIR="${FASTQ_DIR:-${PROJECT_ROOT}/02fastq}"
REF_ROOT="${REF_ROOT:-${PROJECT_ROOT}/02ref}"

FQ1_END="${FQ1_END:-_RNAseq_R1.fastq}"
FQ2_END="${FQ2_END:-_RNAseq_R2.fastq}"
RAW_R1_GZ="${RAW_DIR}/${SAMPLE}${FQ1_END}.gz"
RAW_R2_GZ="${RAW_DIR}/${SAMPLE}${FQ2_END}.gz"
FASTQ_R1="${FASTQ_DIR}/${SAMPLE}${FQ1_END}"
FASTQ_R2="${FASTQ_DIR}/${SAMPLE}${FQ2_END}"

KRAKEN_DB="${KRAKEN_DB:-${REF_ROOT}/kraken2/prism_kraken2_recommended}"
MINIMAP2_INDEX="${MINIMAP2_INDEX:-${REF_ROOT}/host/hg38.minimap2/hg38.mmi}"
STAR_GENOME_DIR="${STAR_GENOME_DIR:-${REF_ROOT}/host/hg38.star}"
BLAST_DB="${BLAST_DB:-${REF_ROOT}/blast/core_nt/core_nt}"
ACCESSION_MAP="${ACCESSION_MAP:-${PRISM_ROOT}/sorted_accession_map.txt}"
MODEL_ORG_TAXIDS="${MODEL_ORG_TAXIDS:-${PRISM_ROOT}/model_org_taxids.txt}"

KRAKEN2_EXTRA_OPTS="${KRAKEN2_EXTRA_OPTS---memory-mapping}"
STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-NoSharedMemory}"
PRISM_THREADS="${PRISM_THREADS:-16}"
USE_CUSTOM_DB="${USE_CUSTOM_DB:-FALSE}"

KRAKEN2_BIN="${KRAKEN2_BIN:-$(command -v kraken2 || true)}"
SEQKIT_BIN="${SEQKIT_BIN:-$(command -v seqkit || true)}"
MINIMAP2_BIN="${MINIMAP2_BIN:-$(command -v minimap2 || true)}"
STAR_BIN="${STAR_BIN:-$(command -v STAR || true)}"
BLASTN_BIN="${BLASTN_BIN:-$(command -v blastn || true)}"
RSCRIPT_BIN="${RSCRIPT_BIN:-$(command -v Rscript || true)}"
PIGZ_BIN="${PIGZ_BIN:-$(command -v pigz || true)}"

echo "[CHECK] Sample: ${SAMPLE}"
echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] PRISM_ROOT: ${PRISM_ROOT}"
echo "[CHECK] STAR_GENOME_LOAD: ${STAR_GENOME_LOAD}"
echo "[CHECK] KRAKEN2_EXTRA_OPTS: ${KRAKEN2_EXTRA_OPTS}"

for exe_name in KRAKEN2_BIN SEQKIT_BIN MINIMAP2_BIN STAR_BIN BLASTN_BIN RSCRIPT_BIN; do
  exe_value="${!exe_name}"
  if [[ -z "${exe_value}" || ! -x "${exe_value}" ]]; then
    echo "[ERROR] Missing or non-executable dependency ${exe_name}: ${exe_value}"
    exit 1
  fi
done

if [[ -z "${PIGZ_BIN}" || ! -x "${PIGZ_BIN}" ]]; then
  echo "[ERROR] Missing pigz executable. It is required to decompress FASTQ.GZ inputs."
  exit 1
fi

if [[ ! -d "${RAW_DIR}" ]]; then
  echo "[ERROR] Raw data directory does not exist: ${RAW_DIR}"
  exit 1
fi

if [[ ! -d "${PRISM_ROOT}/genbank" ]]; then
  echo "[ERROR] Missing required PRISM genbank directory: ${PRISM_ROOT}/genbank"
  exit 1
fi

if [[ ! -f "${MODEL_ORG_TAXIDS}" ]]; then
  echo "[ERROR] Missing model organism taxids file: ${MODEL_ORG_TAXIDS}"
  exit 1
fi

if [[ "${USE_CUSTOM_DB}" == "TRUE" && ! -f "${ACCESSION_MAP}" ]]; then
  echo "[ERROR] Missing sorted accession map: ${ACCESSION_MAP}"
  echo "        This file is required when USE_CUSTOM_DB=TRUE."
  exit 1
elif [[ ! -f "${ACCESSION_MAP}" ]]; then
  echo "[WARN] Missing sorted accession map: ${ACCESSION_MAP}"
  echo "       Continuing because USE_CUSTOM_DB=${USE_CUSTOM_DB}."
fi

for path in "${KRAKEN_DB}" "${MINIMAP2_INDEX}" "${STAR_GENOME_DIR}"; do
  if [[ ! -e "${path}" ]]; then
    echo "[ERROR] Required path does not exist: ${path}"
    exit 1
  fi
done

if [[ ! -e "${BLAST_DB}.nhr" && ! -e "${BLAST_DB}.00.nhr" && ! -e "${BLAST_DB}.ndb" ]]; then
  echo "[ERROR] BLAST database prefix appears invalid: ${BLAST_DB}"
  echo "        Pass the database prefix, not only the containing directory."
  exit 1
fi

if [[ ! -f "${RAW_R1_GZ}" ]]; then
  echo "[ERROR] Missing read 1 input: ${RAW_R1_GZ}"
  exit 1
fi

if [[ ! -f "${RAW_R2_GZ}" ]]; then
  echo "[ERROR] Missing read 2 input: ${RAW_R2_GZ}"
  exit 1
fi

mkdir -p "${FASTQ_DIR}"

if [[ ! -f "${FASTQ_R1}" ]]; then
  echo "[DECOMPRESS] ${RAW_R1_GZ} -> ${FASTQ_R1}"
  "${PIGZ_BIN}" -dc "${RAW_R1_GZ}" > "${FASTQ_R1}"
else
  echo "[SKIP] FASTQ exists: ${FASTQ_R1}"
fi

if [[ ! -f "${FASTQ_R2}" ]]; then
  echo "[DECOMPRESS] ${RAW_R2_GZ} -> ${FASTQ_R2}"
  "${PIGZ_BIN}" -dc "${RAW_R2_GZ}" > "${FASTQ_R2}"
else
  echo "[SKIP] FASTQ exists: ${FASTQ_R2}"
fi

BLAST_BIN_DIR="$(dirname "${BLASTN_BIN}")"

echo "[RUN] Starting PRISM for ${SAMPLE}"
"${RSCRIPT_BIN}" "${PRISM_ROOT}/PRISM.R" \
  --sample "${SAMPLE}" \
  --data_path "${FASTQ_DIR}" \
  --kraken_path "${KRAKEN2_BIN}" \
  --kraken_db_path "${KRAKEN_DB}" \
  --seqkit_path "${SEQKIT_BIN}" \
  --minimap2_path "${MINIMAP2_BIN}" \
  --minimap2_index "${MINIMAP2_INDEX}" \
  --kraken_extra_opts="${KRAKEN2_EXTRA_OPTS}" \
  --star_path "${STAR_BIN}" \
  --star_genome_dir "${STAR_GENOME_DIR}" \
  --star_genome_load "${STAR_GENOME_LOAD}" \
  --model_org_taxids "${MODEL_ORG_TAXIDS}" \
  --blast_path "${BLAST_BIN_DIR}" \
  --blast_db_path "${BLAST_DB}" \
  --prism_path "${PRISM_ROOT}" \
  --paired TRUE \
  --fq1_end "${FQ1_END}" \
  --fq2_end "${FQ2_END}" \
  --threads "${PRISM_THREADS}" \
  --use_custom_db "${USE_CUSTOM_DB}"

echo "[DONE] PRISM finished for ${SAMPLE}"
echo "[RESULT] Output directory: ${FASTQ_DIR}/${SAMPLE}_prism"
echo "[RESULT] Species counts: ${FASTQ_DIR}/${SAMPLE}_prism/${SAMPLE}-counts.csv"
echo "[RESULT] Read-level results: ${FASTQ_DIR}/${SAMPLE}_prism/${SAMPLE}-results.csv"
echo "[RESULT] PRISM log: ${FASTQ_DIR}/${SAMPLE}_prism/data/${SAMPLE}_PRISM.log"
