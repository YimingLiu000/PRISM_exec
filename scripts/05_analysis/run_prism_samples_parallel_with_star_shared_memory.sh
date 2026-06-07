#!/usr/bin/env bash

# Run multiple PRISM RNA-seq samples in parallel while reusing a STAR genome
# index that has already been loaded into shared memory.
#
# Before running this script, preload the STAR index once:
#   bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
# or, in this bundle layout:
#   bash ${PROJECT_ROOT}/scripts/04_host/star_shared_memory_control.sh load
#
# Usage:
#   bash run_prism_samples_parallel_with_star_shared_memory.sh sample_list.txt
#
# sample_list.txt format:
#   one sample name per line; blank lines and lines starting with # are ignored.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash $0 <sample_list.txt>"
  exit 1
fi

SAMPLE_LIST="$1"

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

if [[ ! -f "${SAMPLE_LIST}" ]]; then
  echo "[ERROR] Sample list file does not exist: ${SAMPLE_LIST}"
  exit 1
fi

MAX_PARALLEL="${MAX_PARALLEL:-2}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/02fastq/parallel_logs}"

if [[ -n "${RUN_SCRIPT:-}" ]]; then
  RUN_SCRIPT="$(cd "$(dirname "${RUN_SCRIPT}")" && pwd)/$(basename "${RUN_SCRIPT}")"
elif [[ -f "${SCRIPT_DIR}/run_prism_rnaseq.sh" ]]; then
  RUN_SCRIPT="${SCRIPT_DIR}/run_prism_rnaseq.sh"
elif [[ -f "${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh" ]]; then
  RUN_SCRIPT="${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh"
elif [[ -f "${PROJECT_ROOT}/scripts/05_analysis/run_prism_rnaseq.sh" ]]; then
  RUN_SCRIPT="${PROJECT_ROOT}/scripts/05_analysis/run_prism_rnaseq.sh"
else
  echo "[ERROR] run_prism_rnaseq.sh not found."
  echo "        Checked ${SCRIPT_DIR}, ${PROJECT_ROOT}/00script/05_analysis, and ${PROJECT_ROOT}/scripts/05_analysis"
  exit 1
fi

if [[ ! -f "${RUN_SCRIPT}" ]]; then
  echo "[ERROR] RUN_SCRIPT does not exist: ${RUN_SCRIPT}"
  exit 1
fi

mkdir -p "${LOG_DIR}"

echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] RUN_SCRIPT: ${RUN_SCRIPT}"
echo "[CHECK] LOG_DIR: ${LOG_DIR}"
echo "[CHECK] MAX_PARALLEL: ${MAX_PARALLEL}"

pids=()
samples=()

launch_job() {
  local sample="$1"
  local logfile="${LOG_DIR}/${sample}.log"
  echo "[START] ${sample} -> ${logfile}"
  (
    export PROJECT_ROOT="${PROJECT_ROOT}"
    export SAMPLE="${sample}"
    export STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-LoadAndKeep}"
    bash "${RUN_SCRIPT}" "${sample}"
  ) >"${logfile}" 2>&1 &
  pids+=("$!")
  samples+=("${sample}")
}

running_jobs() {
  jobs -rp | wc -l | awk '{print $1}'
}

while IFS= read -r sample || [[ -n "${sample}" ]]; do
  sample="${sample#"${sample%%[![:space:]]*}"}"
  sample="${sample%"${sample##*[![:space:]]}"}"
  [[ -z "${sample}" ]] && continue
  [[ "${sample}" == \#* ]] && continue

  while [[ "$(running_jobs)" -ge "${MAX_PARALLEL}" ]]; do
    sleep 5
  done
  launch_job "${sample}"
done < "${SAMPLE_LIST}"

failures=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  sample="${samples[$idx]}"
  if wait "${pid}"; then
    echo "[DONE] ${sample}"
  else
    echo "[ERROR] ${sample} failed. Check ${LOG_DIR}/${sample}.log"
    failures=$((failures + 1))
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERROR] ${failures} PRISM job(s) failed."
  exit 1
fi

echo "[DONE] All parallel PRISM jobs finished successfully."
