#!/usr/bin/env bash

# Put this script directly inside the directory that contains <sample>_prism
# folders. It detects PRISM samples that failed after reusable Kraken2/host-
# depletion outputs already exist, writes sample names to a TXT file, and
# optionally moves damaged downstream files aside so fixed PRISM code can resume
# from Step 4.
#
# This script intentionally moves individual files to a quarantine directory
# instead of deleting anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_DIR="${SCAN_DIR:-${SCRIPT_DIR}}"

if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
else
  PROJECT_ROOT=""
  for candidate in "${SCRIPT_DIR}" "${SCRIPT_DIR}/.." "${SCRIPT_DIR}/../.." "${HOME}/PRISM"; do
    if [[ -d "${candidate}/repo" || -d "${candidate}/00script/repo" ]]; then
      PROJECT_ROOT="$(cd "${candidate}" && pwd)"
      break
    fi
  done
  if [[ -z "${PROJECT_ROOT}" ]]; then
    PROJECT_ROOT="${HOME}/PRISM"
  fi
fi

FASTQ_DIR="${FASTQ_DIR:-${SCAN_DIR}}"
OUT_FILE="${1:-${FAILED_LIST:-${SCAN_DIR}/failed_prism_resume_samples.txt}}"
MODE="${MODE:-detect}"
QUARANTINE_NAME="${QUARANTINE_NAME:-resume_quarantine_$(date +%Y%m%d_%H%M%S)}"

if [[ "${MODE}" != "detect" && "${MODE}" != "quarantine" ]]; then
  echo "[ERROR] MODE must be either detect or quarantine; got: ${MODE}"
  exit 1
fi

if [[ ! -d "${FASTQ_DIR}" ]]; then
  echo "[ERROR] FASTQ_DIR does not exist: ${FASTQ_DIR}"
  exit 1
fi

mkdir -p "$(dirname "${OUT_FILE}")"
: > "${OUT_FILE}"

is_empty_or_missing() {
  [[ ! -s "$1" ]]
}

has_reusable_upstream() {
  local sample="$1"
  local data_dir="$2"
  [[ -s "${data_dir}/${sample}.kraken.output.txt" ]] &&
    [[ -s "${data_dir}/${sample}.kraken.report.txt" ]] &&
    [[ -s "${data_dir}/${sample}.mpa.prism.txt" ]] &&
    [[ -s "${data_dir}/${sample}-minimap.sam" ]] &&
    [[ -s "${data_dir}/${sample}_1.fa" ]] &&
    [[ -s "${data_dir}/${sample}_2.fa" ]] &&
    [[ -s "${data_dir}/star/${sample}_Aligned.out.sam" ]]
}

looks_failed_downstream() {
  local sample="$1"
  local sample_dir="$2"
  local data_dir="$3"
  local log_file="${sample_dir}/${sample}.prism.log"
  local data_log="${data_dir}/${sample}_PRISM.log"

  is_empty_or_missing "${sample_dir}/${sample}-counts.csv" && return 0
  is_empty_or_missing "${sample_dir}/${sample}-results.csv" && return 0
  [[ -e "${data_dir}/${sample}_sub_fa1" ]] && is_empty_or_missing "${data_dir}/${sample}_sub_fa1" && return 0
  [[ -e "${data_dir}/${sample}_sub_fa1-blast.csv" ]] && is_empty_or_missing "${data_dir}/${sample}_sub_fa1-blast.csv" && return 0
  [[ -f "${log_file}" ]] && grep -Eq "No subsample BLAST hits found|Writing empty outputs|argument of length 0|Step failed" "${log_file}" && return 0
  [[ -f "${data_log}" ]] && grep -Eq "No subsample BLAST hits found|Writing empty outputs|argument of length 0|Step failed" "${data_log}" && return 0
  return 1
}

quarantine_file() {
  local src="$1"
  local quarantine_dir="$2"

  if [[ -e "${src}" ]]; then
    mkdir -p "${quarantine_dir}"
    local base
    base="$(basename "${src}")"
    local dest="${quarantine_dir}/${base}"
    if [[ -e "${dest}" ]]; then
      dest="${quarantine_dir}/${base}.$(date +%s).$$"
    fi
    mv -- "${src}" "${dest}"
    echo "[MOVE] ${src} -> ${dest}"
  fi
}

quarantine_downstream() {
  local sample="$1"
  local sample_dir="$2"
  local data_dir="$3"
  local quarantine_dir="${sample_dir}/${QUARANTINE_NAME}"

  quarantine_file "${sample_dir}/${sample}-counts.csv" "${quarantine_dir}"
  quarantine_file "${sample_dir}/${sample}-results.csv" "${quarantine_dir}"
  quarantine_file "${sample_dir}/${sample}_1.fa" "${quarantine_dir}"
  quarantine_file "${sample_dir}/${sample}_2.fa" "${quarantine_dir}"
  quarantine_file "${sample_dir}/new_headers.txt" "${quarantine_dir}"

  quarantine_file "${data_dir}/${sample}_sub_fa1" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}_sub_fa2" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}_sub_fa1-blast.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}_sub_fa2-blast.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}-final-blast1.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}-final-blast2.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}-filtered-blast.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}-unmapped.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}-xgmat.csv" "${quarantine_dir}/data"
  quarantine_file "${data_dir}/${sample}.tempout.txt" "${quarantine_dir}/data"
}

checked=0
failed=0
skipped=0

for sample_dir in "${FASTQ_DIR}"/*_prism; do
  [[ -d "${sample_dir}" ]] || continue
  sample="$(basename "${sample_dir}")"
  sample="${sample%_prism}"
  data_dir="${sample_dir}/data"
  checked=$((checked + 1))

  if [[ ! -d "${data_dir}" ]]; then
    skipped=$((skipped + 1))
    echo "[SKIP] ${sample}: missing data directory"
    continue
  fi

  if ! has_reusable_upstream "${sample}" "${data_dir}"; then
    skipped=$((skipped + 1))
    echo "[SKIP] ${sample}: reusable upstream files are incomplete"
    continue
  fi

  if looks_failed_downstream "${sample}" "${sample_dir}" "${data_dir}"; then
    failed=$((failed + 1))
    printf '%s\n' "${sample}" >> "${OUT_FILE}"
    echo "[FAILED] ${sample}"
    if [[ "${MODE}" == "quarantine" ]]; then
      quarantine_downstream "${sample}" "${sample_dir}" "${data_dir}"
    fi
  else
    echo "[OK] ${sample}"
  fi
done

echo "[DONE] Scan directory: ${FASTQ_DIR}"
echo "[DONE] Checked: ${checked}; failed resumable: ${failed}; skipped incomplete upstream: ${skipped}"
echo "[DONE] Failed sample list: ${OUT_FILE}"
if [[ "${MODE}" == "detect" ]]; then
  echo "[INFO] Re-run with MODE=quarantine to move damaged downstream files aside."
fi
