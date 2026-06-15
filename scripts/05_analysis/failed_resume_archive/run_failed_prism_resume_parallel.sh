#!/usr/bin/env bash

# Put this script directly inside the directory that contains <sample>_prism
# folders. It resumes failed PRISM samples listed in a TXT file. This runner is
# intended for samples whose Kraken2, Minimap2, and STAR outputs already exist,
# so it refuses to launch samples with incomplete reusable upstream files.
#
# Usage:
#   bash run_failed_prism_resume_parallel.sh [failed_samples.txt] [max_parallel]
#
# Optional environment variables:
#   PROJECT_ROOT     PRISM project root.
#   FASTQ_DIR        Directory containing <sample>_prism result folders.
#   MAX_ACTIVE_JOBS  Parallel sample count if not passed as argument 2.
#   LOG_DIR          Resume log directory.
#   POLL_SECONDS     Scheduler polling interval. Default: 5.
#   PRISM_THREADS    Threads passed to PRISM.R. Default: 16.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_DIR="${SCAN_DIR:-${SCRIPT_DIR}}"
SAMPLE_LIST="${1:-${FAILED_LIST:-${SCAN_DIR}/failed_prism_resume_samples.txt}}"
MAX_ACTIVE_JOBS="${2:-${MAX_ACTIVE_JOBS:-6}}"

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
POLL_SECONDS="${POLL_SECONDS:-5}"
LOG_DIR="${LOG_DIR:-${SCAN_DIR}/resume_failed_prism_logs}"
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_DIR="${LOG_DIR}/${RUN_ID}"
SKIPPED_FILE="${RUN_DIR}/skipped_incomplete_upstream.txt"
FAILED_FILE="${RUN_DIR}/failed_samples.txt"
DONE_FILE="${RUN_DIR}/completed_samples.txt"

if [[ ! -f "${SAMPLE_LIST}" ]]; then
  echo "[ERROR] Sample list file does not exist: ${SAMPLE_LIST}"
  exit 1
fi

if [[ ! "${MAX_ACTIVE_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "[ERROR] max_parallel must be a positive integer: ${MAX_ACTIVE_JOBS}"
  exit 1
fi

if [[ ! -d "${FASTQ_DIR}" ]]; then
  echo "[ERROR] FASTQ_DIR does not exist: ${FASTQ_DIR}"
  exit 1
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

REF_ROOT="${REF_ROOT:-${PROJECT_ROOT}/02ref}"
KRAKEN_DB="${KRAKEN_DB:-${REF_ROOT}/kraken2/prism_kraken2_recommended}"
MINIMAP2_INDEX="${MINIMAP2_INDEX:-${REF_ROOT}/host/hg38.minimap2/hg38.mmi}"
STAR_GENOME_DIR="${STAR_GENOME_DIR:-${REF_ROOT}/host/hg38.star}"
BLAST_DB="${BLAST_DB:-${REF_ROOT}/blast/core_nt/core_nt}"
MODEL_ORG_TAXIDS="${MODEL_ORG_TAXIDS:-${PRISM_ROOT}/model_org_taxids.txt}"

KRAKEN2_EXTRA_OPTS="${KRAKEN2_EXTRA_OPTS-}"
STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-NoSharedMemory}"
PRISM_THREADS="${PRISM_THREADS:-16}"
USE_CUSTOM_DB="${USE_CUSTOM_DB:-FALSE}"

KRAKEN2_BIN="${KRAKEN2_BIN:-$(command -v kraken2 || true)}"
SEQKIT_BIN="${SEQKIT_BIN:-$(command -v seqkit || true)}"
MINIMAP2_BIN="${MINIMAP2_BIN:-$(command -v minimap2 || true)}"
STAR_BIN="${STAR_BIN:-$(command -v STAR || true)}"
BLASTN_BIN="${BLASTN_BIN:-$(command -v blastn || true)}"
RSCRIPT_BIN="${RSCRIPT_BIN:-$(command -v Rscript || true)}"

for exe_name in KRAKEN2_BIN SEQKIT_BIN MINIMAP2_BIN STAR_BIN BLASTN_BIN RSCRIPT_BIN; do
  exe_value="${!exe_name}"
  if [[ -z "${exe_value}" || ! -x "${exe_value}" ]]; then
    echo "[ERROR] Missing or non-executable dependency ${exe_name}: ${exe_value}"
    exit 1
  fi
done

for path in "${KRAKEN_DB}" "${MINIMAP2_INDEX}" "${STAR_GENOME_DIR}" "${MODEL_ORG_TAXIDS}"; do
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

BLAST_BIN_DIR="$(dirname "${BLASTN_BIN}")"

mkdir -p "${RUN_DIR}"
: > "${SKIPPED_FILE}"
: > "${FAILED_FILE}"
: > "${DONE_FILE}"

has_reusable_upstream() {
  local sample="$1"
  local data_dir="${FASTQ_DIR}/${sample}_prism/data"

  [[ -s "${data_dir}/${sample}.kraken.output.txt" ]] &&
    [[ -s "${data_dir}/${sample}.kraken.report.txt" ]] &&
    [[ -s "${data_dir}/${sample}.mpa.prism.txt" ]] &&
    [[ -s "${data_dir}/${sample}-minimap.sam" ]] &&
    [[ -s "${data_dir}/${sample}_1.fa" ]] &&
    [[ -s "${data_dir}/${sample}_2.fa" ]] &&
    [[ -s "${data_dir}/star/${sample}_Aligned.out.sam" ]]
}

running_jobs() {
  jobs -rp | wc -l | awk '{print $1}'
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

samples=()
seen_samples=" "
while IFS= read -r sample || [[ -n "${sample}" ]]; do
  sample="${sample#"${sample%%[![:space:]]*}"}"
  sample="${sample%"${sample##*[![:space:]]}"}"
  [[ -z "${sample}" ]] && continue
  [[ "${sample}" == \#* ]] && continue
  if [[ "${seen_samples}" == *" ${sample} "* ]]; then
    continue
  fi
  seen_samples="${seen_samples}${sample} "
  samples+=("${sample}")
done < "${SAMPLE_LIST}"

if [[ "${#samples[@]}" -eq 0 ]]; then
  echo "[ERROR] No samples found in sample list: ${SAMPLE_LIST}"
  exit 1
fi

pids=()
pid_samples=()
launch_count=0
skip_count=0

launch_job() {
  local sample="$1"
  local safe_sample
  safe_sample="$(safe_name "${sample}")"
  local logfile="${RUN_DIR}/${safe_sample}.log"

  if ! has_reusable_upstream "${sample}"; then
    echo "${sample}" >> "${SKIPPED_FILE}"
    echo "[SKIP] ${sample}: reusable upstream files are incomplete"
    skip_count=$((skip_count + 1))
    return
  fi

  echo "[START] ${sample} -> ${logfile}"
  (
    "${RSCRIPT_BIN}" "${PRISM_ROOT}/PRISM.R" \
      --sample "${sample}" \
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
      --threads "${PRISM_THREADS}" \
      --use_custom_db "${USE_CUSTOM_DB}"
  ) >"${logfile}" 2>&1 &
  pids+=("$!")
  pid_samples+=("${sample}")
  launch_count=$((launch_count + 1))
}

echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] PRISM_ROOT: ${PRISM_ROOT}"
echo "[CHECK] FASTQ_DIR: ${FASTQ_DIR}"
echo "[CHECK] RSCRIPT_BIN: ${RSCRIPT_BIN}"
echo "[CHECK] RUN_DIR: ${RUN_DIR}"
echo "[CHECK] MAX_ACTIVE_JOBS: ${MAX_ACTIVE_JOBS}"
echo "[CHECK] PRISM_THREADS: ${PRISM_THREADS}"
echo "[CHECK] STAR_GENOME_LOAD: ${STAR_GENOME_LOAD}"
echo "[CHECK] KRAKEN2_EXTRA_OPTS: ${KRAKEN2_EXTRA_OPTS}"
echo "[CHECK] Sample count: ${#samples[@]}"

for sample in "${samples[@]}"; do
  while [[ "$(running_jobs)" -ge "${MAX_ACTIVE_JOBS}" ]]; do
    sleep "${POLL_SECONDS}"
  done
  launch_job "${sample}"
done

failures=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  sample="${pid_samples[$idx]}"
  if wait "${pid}"; then
    echo "${sample}" >> "${DONE_FILE}"
    echo "[DONE] ${sample}"
  else
    echo "${sample}" >> "${FAILED_FILE}"
    echo "[ERROR] ${sample} failed. Check ${RUN_DIR}/$(safe_name "${sample}").log"
    failures=$((failures + 1))
  fi
done

echo "[SUMMARY] Launched: ${launch_count}; skipped incomplete upstream: ${skip_count}; failed: ${failures}"
echo "[SUMMARY] Logs: ${RUN_DIR}"
echo "[SUMMARY] Completed samples: ${DONE_FILE}"
echo "[SUMMARY] Failed samples: ${FAILED_FILE}"
echo "[SUMMARY] Skipped samples: ${SKIPPED_FILE}"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
