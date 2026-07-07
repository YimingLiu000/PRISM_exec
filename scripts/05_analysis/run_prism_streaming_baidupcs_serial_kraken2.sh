#!/usr/bin/env bash

# Stream PRISM RNA-seq samples from Baidu Netdisk with BaiduPCS-Go while
# processing already downloaded samples. The download queue and PRISM compute
# queue are independent: downloading keeps moving through the manifest with a
# bounded number of concurrent sample downloads and does not wait for compute
# jobs to catch up. Only one Kraken2 process is allowed at a time, and each
# sample's input FASTQ.GZ/FASTQ files are removed after that sample finishes so
# PRISM result files are retained.
#
# Baidu manifest format:
#   one Baidu Netdisk sample path or FASTQ.GZ path per line; blank lines and
#   lines starting with # are ignored. FASTQ.GZ paths are downloaded exactly as
#   listed; if only one mate is listed, the other mate is inferred from the same
#   directory and the default read suffix. Non-GZ paths are treated as
#   <parent>/<sample>, and FASTQ.GZ files are inferred directly under <parent>.
#
# Example Baidu manifest:
#   /RNAseq/FUSCCTNBC001
#   /RNAseq/FUSCCTNBC002
# or:
#   /RNAseq/FUSCCTNBC001_RNAseq_R1.fastq.gz
#   /RNAseq/FUSCCTNBC002_RNAseq_R1.fastq.gz
#
# In both forms, all FASTQ.GZ files are expected to be flat in the parent
# directory:
#   <sample>_RNAseq_R1.fastq.gz
#   <sample>_RNAseq_R2.fastq.gz
#
# Usage:
#   bash run_prism_streaming_baidupcs_serial_kraken2.sh baidu_sample_paths.txt
#
# Optional environment variables:
#   PROJECT_ROOT              PRISM project root.
#   RUN_SCRIPT                Single-sample PRISM runner. Default: run_prism_rnaseq.sh.
#   BAIDUPCS                  BaiduPCS-Go executable. Default: sibling BaiduPCS-Go,
#                             then PATH lookup.
#   BAIDUPCS_DOWNLOAD_OPTS    Extra BaiduPCS-Go download options. Default: --ow.
#                             Example: '-p 8 --retry 5'
#   MAX_DOWNLOAD_JOBS         Maximum sample downloads alive at once. Default: 2.
#   PARALLEL_MATES            Download R1 and R2 for one sample concurrently.
#                             Default: TRUE.
#   RAW_DIR                   Local staging directory for downloaded FASTQ.GZ files.
#   FASTQ_DIR                 Local FASTQ/output directory.
#   FQ1_END                   Read 1 suffix before .gz. Default: _RNAseq_R1.fastq
#                             A full .gz suffix such as _1.fq.gz is also accepted.
#   FQ2_END                   Read 2 suffix before .gz. Default: _RNAseq_R2.fastq
#                             A full .gz suffix such as _2.fq.gz is also accepted.
#   MAX_ACTIVE_JOBS           Maximum total PRISM jobs alive at once. Default: 3.
#   KRAKEN2_QUEUE_DEPTH       Number of downloaded jobs to keep queued for Kraken2.
#                             Default: 2.
#   KRAKEN2_EXTRA_OPTS        Kraken2 extra options. Default here: empty string.
#   STAR_GENOME_LOAD          STAR genomeLoad mode. Default: LoadAndKeep.
#   POLL_SECONDS              Scheduler polling interval. Default: 5.
#   LOG_DIR                   Run log directory.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash $0 <baidu_sample_paths.txt>"
  exit 1
fi

BAIDU_MANIFEST="$1"

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

if [[ ! -f "${BAIDU_MANIFEST}" ]]; then
  echo "[ERROR] Baidu manifest file does not exist: ${BAIDU_MANIFEST}"
  exit 1
fi

if [[ -z "${BAIDUPCS:-}" ]]; then
  if [[ -x "${SCRIPT_DIR}/BaiduPCS-Go" ]]; then
    BAIDUPCS="${SCRIPT_DIR}/BaiduPCS-Go"
  else
    BAIDUPCS="$(command -v BaiduPCS-Go || true)"
  fi
fi

if [[ -z "${BAIDUPCS}" || ! -x "${BAIDUPCS}" ]]; then
  echo "[ERROR] Missing executable BaiduPCS-Go."
  echo "        Put BaiduPCS-Go beside this script, or set BAIDUPCS=/path/to/BaiduPCS-Go."
  exit 1
fi

for exe in flock find awk; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[ERROR] Missing executable: ${exe}"
    exit 1
  fi
done

REAL_KRAKEN2_BIN="${REAL_KRAKEN2_BIN:-$(command -v kraken2 || true)}"
if [[ -z "${REAL_KRAKEN2_BIN}" || ! -x "${REAL_KRAKEN2_BIN}" ]]; then
  echo "[ERROR] Missing real kraken2 executable: ${REAL_KRAKEN2_BIN}"
  exit 1
fi

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
  exit 1
fi

RAW_DIR="${RAW_DIR:-${PROJECT_ROOT}/01rawdata}"
FASTQ_DIR="${FASTQ_DIR:-${PROJECT_ROOT}/02fastq}"
FQ1_END="${FQ1_END:-_RNAseq_R1.fastq}"
FQ2_END="${FQ2_END:-_RNAseq_R2.fastq}"
if [[ "${FQ1_END}" == *.gz ]]; then
  FQ1_END="${FQ1_END%.gz}"
fi
if [[ "${FQ2_END}" == *.gz ]]; then
  FQ2_END="${FQ2_END%.gz}"
fi
BAIDUPCS_DOWNLOAD_OPTS="${BAIDUPCS_DOWNLOAD_OPTS:---ow}"
MAX_DOWNLOAD_JOBS="${MAX_DOWNLOAD_JOBS:-2}"
PARALLEL_MATES="${PARALLEL_MATES:-TRUE}"
MAX_ACTIVE_JOBS="${MAX_ACTIVE_JOBS:-3}"
KRAKEN2_QUEUE_DEPTH="${KRAKEN2_QUEUE_DEPTH:-2}"
POLL_SECONDS="${POLL_SECONDS:-5}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/02fastq/streaming_baidupcs_serial_kraken2_logs}"
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_DIR="${LOG_DIR}/${RUN_ID}"
WRAPPER_DIR="${RUN_DIR}/wrapper"
KRAKEN2_EVENTS_DIR="${RUN_DIR}/kraken2_events"
KRAKEN2_LOCK_FILE="${RUN_DIR}/kraken2.lock"
LOCKED_KRAKEN2_BIN="${WRAPPER_DIR}/kraken2_locked.sh"
DOWNLOAD_LOG_DIR="${RUN_DIR}/downloads"
DONE_DIR="${RUN_DIR}/download_done"
FAIL_DIR="${RUN_DIR}/download_failed"

if ! [[ "${MAX_DOWNLOAD_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "[ERROR] MAX_DOWNLOAD_JOBS must be a positive integer: ${MAX_DOWNLOAD_JOBS}"
  exit 1
fi

mkdir -p "${RAW_DIR}" "${FASTQ_DIR}" "${RUN_DIR}" "${WRAPPER_DIR}" \
  "${KRAKEN2_EVENTS_DIR}" "${DOWNLOAD_LOG_DIR}" "${DONE_DIR}" "${FAIL_DIR}"

cat > "${LOCKED_KRAKEN2_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${REAL_KRAKEN2_BIN:-}" || ! -x "${REAL_KRAKEN2_BIN}" ]]; then
  echo "[KRAKEN2-LOCK][ERROR] REAL_KRAKEN2_BIN is missing or not executable: ${REAL_KRAKEN2_BIN:-}" >&2
  exit 1
fi

if [[ -z "${KRAKEN2_LOCK_FILE:-}" || -z "${KRAKEN2_EVENTS_DIR:-}" ]]; then
  echo "[KRAKEN2-LOCK][ERROR] KRAKEN2_LOCK_FILE or KRAKEN2_EVENTS_DIR is not set." >&2
  exit 1
fi

sample="${SAMPLE:-unknown_sample}"
safe_sample="$(printf '%s' "${sample}" | tr -c 'A-Za-z0-9_.-' '_')"

echo "[KRAKEN2-LOCK] ${sample} waiting for Kraken2 lock: ${KRAKEN2_LOCK_FILE}" >&2
exec 9>"${KRAKEN2_LOCK_FILE}"
flock -x 9

touch "${KRAKEN2_EVENTS_DIR}/${safe_sample}.$$.acquired"
echo "[KRAKEN2-LOCK] ${sample} acquired Kraken2 lock." >&2

set +e
"${REAL_KRAKEN2_BIN}" "$@"
status=$?
set -e

touch "${KRAKEN2_EVENTS_DIR}/${safe_sample}.$$.done"
echo "[KRAKEN2-LOCK] ${sample} released Kraken2 lock with status ${status}." >&2
exit "${status}"
EOF
chmod +x "${LOCKED_KRAKEN2_BIN}"

samples=()
remote_r1s=()
remote_r2s=()
seen_samples=" "
while IFS= read -r remote_path || [[ -n "${remote_path}" ]]; do
  remote_path="${remote_path#"${remote_path%%[![:space:]]*}"}"
  remote_path="${remote_path%"${remote_path##*[![:space:]]}"}"
  [[ -z "${remote_path}" ]] && continue
  [[ "${remote_path}" == \#* ]] && continue

  sample=""
  remote_parent=""
  remote_r1=""
  remote_r2=""
  base_name="$(basename "${remote_path}")"
  if [[ "${base_name}" == *"${FQ1_END}.gz" ]]; then
    sample="${base_name%"${FQ1_END}.gz"}"
    remote_r1="${remote_path}"
    remote_parent="$(dirname "${remote_path}")"
    remote_r2="${remote_parent}/${sample}${FQ2_END}.gz"
  elif [[ "${base_name}" == *"${FQ2_END}.gz" ]]; then
    sample="${base_name%"${FQ2_END}.gz"}"
    remote_r2="${remote_path}"
    remote_parent="$(dirname "${remote_path}")"
    remote_r1="${remote_parent}/${sample}${FQ1_END}.gz"
  else
    if [[ "${remote_path}" != */* ]]; then
      echo "[ERROR] Sample entry must include its Baidu parent directory: ${remote_path}"
      echo "        Use /path/to/parent/${remote_path}, or provide a full FASTQ.GZ path."
      exit 1
    fi
    sample="${base_name}"
    remote_parent="$(dirname "${remote_path}")"
    remote_r1="${remote_parent}/${sample}${FQ1_END}.gz"
    remote_r2="${remote_parent}/${sample}${FQ2_END}.gz"
  fi

  if [[ -z "${sample}" || "${sample}" == "." || "${sample}" == "/" ]]; then
    echo "[ERROR] Cannot derive sample name from Baidu path: ${remote_path}"
    exit 1
  fi

  if [[ "${seen_samples}" == *" ${sample} "* ]]; then
    for idx in "${!samples[@]}"; do
      if [[ "${samples[$idx]}" == "${sample}" ]]; then
        if [[ "${base_name}" == *"${FQ1_END}.gz" ]]; then
          remote_r1s[$idx]="${remote_path}"
        elif [[ "${base_name}" == *"${FQ2_END}.gz" ]]; then
          remote_r2s[$idx]="${remote_path}"
        fi
        break
      fi
    done
    continue
  fi
  seen_samples="${seen_samples}${sample} "
  samples+=("${sample}")
  remote_r1s+=("${remote_r1}")
  remote_r2s+=("${remote_r2}")
done < "${BAIDU_MANIFEST}"

if [[ "${#samples[@]}" -eq 0 ]]; then
  echo "[ERROR] No Baidu sample directories found in: ${BAIDU_MANIFEST}"
  exit 1
fi

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

kraken2_acquired_count() {
  find "${KRAKEN2_EVENTS_DIR}" -maxdepth 1 -type f -name '*.acquired' | wc -l | awk '{print $1}'
}

is_running_pid() {
  local pid="$1"
  jobs -rp | awk -v target="${pid}" '$1 == target { found = 1 } END { exit(found ? 0 : 1) }'
}

delete_file_if_present() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    echo "[CLEANUP] Removing file: ${path}"
    rm -- "${path}"
  fi
}

cleanup_sample_inputs() {
  local sample="$1"
  delete_file_if_present "${RAW_DIR}/${sample}${FQ1_END}.gz"
  delete_file_if_present "${RAW_DIR}/${sample}${FQ2_END}.gz"
  delete_file_if_present "${FASTQ_DIR}/${sample}${FQ1_END}"
  delete_file_if_present "${FASTQ_DIR}/${sample}${FQ2_END}"
}

cleanup_partial_download() {
  local sample="$1"
  delete_file_if_present "${RAW_DIR}/${sample}${FQ1_END}.gz"
  delete_file_if_present "${RAW_DIR}/${sample}${FQ2_END}.gz"
}

download_one_file() {
  local remote_file="$1"
  local log_file="$2"

  # shellcheck disable=SC2086
  "${BAIDUPCS}" d ${BAIDUPCS_DOWNLOAD_OPTS} --saveto "${RAW_DIR}" "${remote_file}" >>"${log_file}" 2>&1
}

download_sample() {
  local idx="$1"
  local sample="${samples[$idx]}"
  local safe_sample
  safe_sample="$(safe_name "${sample}")"
  local log_file="${DOWNLOAD_LOG_DIR}/${safe_sample}.baidupcs.log"
  local remote_r1="${remote_r1s[$idx]}"
  local remote_r2="${remote_r2s[$idx]}"
  local local_r1="${RAW_DIR}/${sample}${FQ1_END}.gz"
  local local_r2="${RAW_DIR}/${sample}${FQ2_END}.gz"

  echo "[DOWNLOAD] ${sample}: ${remote_r1} + ${remote_r2} -> ${RAW_DIR}" | tee -a "${log_file}"

  set +e
  local status1=0
  local status2=0
  if [[ "${PARALLEL_MATES}" == "TRUE" || "${PARALLEL_MATES}" == "true" || "${PARALLEL_MATES}" == "1" ]]; then
    download_one_file "${remote_r1}" "${log_file}" &
    local pid1="$!"
    download_one_file "${remote_r2}" "${log_file}" &
    local pid2="$!"
    wait "${pid1}"; status1=$?
    wait "${pid2}"; status2=$?
  else
    download_one_file "${remote_r1}" "${log_file}"; status1=$?
    download_one_file "${remote_r2}" "${log_file}"; status2=$?
  fi
  set -e

  if [[ "${status1}" -eq 0 && "${status2}" -eq 0 && -f "${local_r1}" && -f "${local_r2}" ]]; then
    touch "${DONE_DIR}/${safe_sample}.done"
    echo "[DOWNLOAD-DONE] ${sample}" | tee -a "${log_file}"
  else
    touch "${FAIL_DIR}/${safe_sample}.failed"
    echo "[DOWNLOAD-ERROR] ${sample}; status R1=${status1}, R2=${status2}; expected ${local_r1} and ${local_r2}; check ${log_file}" | tee -a "${log_file}"
    cleanup_partial_download "${sample}"
  fi
}

run_sample() {
  local sample="$1"
  local safe_sample
  safe_sample="$(safe_name "${sample}")"
  local logfile="${RUN_DIR}/${safe_sample}.prism.log"

  echo "[RUN] ${sample} -> ${logfile}"
  set +e
  (
    export PROJECT_ROOT="${PROJECT_ROOT}"
    export RAW_DIR="${RAW_DIR}"
    export FASTQ_DIR="${FASTQ_DIR}"
    export FQ1_END="${FQ1_END}"
    export FQ2_END="${FQ2_END}"
    export SAMPLE="${sample}"
    export KRAKEN2_BIN="${LOCKED_KRAKEN2_BIN}"
    export REAL_KRAKEN2_BIN="${REAL_KRAKEN2_BIN}"
    export KRAKEN2_LOCK_FILE="${KRAKEN2_LOCK_FILE}"
    export KRAKEN2_EVENTS_DIR="${KRAKEN2_EVENTS_DIR}"
    export KRAKEN2_EXTRA_OPTS="${KRAKEN2_EXTRA_OPTS-}"
    export STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-LoadAndKeep}"
    bash "${RUN_SCRIPT}" "${sample}"
  ) >"${logfile}" 2>&1
  local status=$?
  set -e

  cleanup_sample_inputs "${sample}"
  return "${status}"
}

next_download=0
next_run=0
launched_runs=0
completed_runs=0
failures=0

download_pids=()
download_samples=()
run_pids=()
run_samples=()

start_download_if_possible() {
  while [[ "${next_download}" -lt "${#samples[@]}" && "${#download_pids[@]}" -lt "${MAX_DOWNLOAD_JOBS}" ]]; do
    local sample="${samples[$next_download]}"
    download_sample "${next_download}" &
    download_pids+=("$!")
    download_samples+=("${sample}")
    next_download=$((next_download + 1))
  done
}

reap_finished_downloads() {
  local new_pids=()
  local new_samples=()
  local idx
  for idx in "${!download_pids[@]}"; do
    local pid="${download_pids[$idx]}"
    local sample="${download_samples[$idx]}"
    if is_running_pid "${pid}"; then
      new_pids+=("${pid}")
      new_samples+=("${sample}")
    else
      wait "${pid}" || true
      echo "[DOWNLOAD-FINISHED] ${sample}"
    fi
  done
  download_pids=("${new_pids[@]}")
  download_samples=("${new_samples[@]}")
}

launch_ready_runs() {
  while [[ "${next_run}" -lt "${#samples[@]}" ]]; do
    local sample="${samples[$next_run]}"
    local safe_sample
    safe_sample="$(safe_name "${sample}")"

    if [[ -f "${FAIL_DIR}/${safe_sample}.failed" ]]; then
      echo "[ERROR] Download failed for ${sample}; skipping run."
      failures=$((failures + 1))
      completed_runs=$((completed_runs + 1))
      next_run=$((next_run + 1))
      continue
    fi

    if [[ ! -f "${DONE_DIR}/${safe_sample}.done" ]]; then
      break
    fi

    local active="${#run_pids[@]}"
    local acquired
    acquired="$(kraken2_acquired_count)"
    local not_yet_acquired=$((launched_runs - acquired))

    if [[ "${active}" -ge "${MAX_ACTIVE_JOBS}" ]]; then
      break
    fi
    if [[ "${not_yet_acquired}" -ge "${KRAKEN2_QUEUE_DEPTH}" && "${active}" -gt 0 ]]; then
      break
    fi

    run_sample "${sample}" &
    run_pids+=("$!")
    run_samples+=("${sample}")
    launched_runs=$((launched_runs + 1))
    next_run=$((next_run + 1))
  done
}

reap_finished_runs() {
  local new_pids=()
  local new_samples=()
  local idx
  for idx in "${!run_pids[@]}"; do
    local pid="${run_pids[$idx]}"
    local sample="${run_samples[$idx]}"
    if is_running_pid "${pid}"; then
      new_pids+=("${pid}")
      new_samples+=("${sample}")
    else
      if wait "${pid}"; then
        echo "[DONE] ${sample}"
      else
        echo "[ERROR] ${sample} failed. Check ${RUN_DIR}/$(safe_name "${sample}").prism.log"
        failures=$((failures + 1))
      fi
      completed_runs=$((completed_runs + 1))
    fi
  done
  run_pids=("${new_pids[@]}")
  run_samples=("${new_samples[@]}")
}

echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] RUN_SCRIPT: ${RUN_SCRIPT}"
echo "[CHECK] RUN_DIR: ${RUN_DIR}"
echo "[CHECK] BAIDUPCS: ${BAIDUPCS}"
echo "[CHECK] BAIDUPCS_DOWNLOAD_OPTS: ${BAIDUPCS_DOWNLOAD_OPTS}"
echo "[CHECK] MAX_DOWNLOAD_JOBS: ${MAX_DOWNLOAD_JOBS}"
echo "[CHECK] PARALLEL_MATES: ${PARALLEL_MATES}"
echo "[CHECK] RAW_DIR: ${RAW_DIR}"
echo "[CHECK] FASTQ_DIR: ${FASTQ_DIR}"
echo "[CHECK] FQ1_END: ${FQ1_END}"
echo "[CHECK] FQ2_END: ${FQ2_END}"
echo "[CHECK] MAX_ACTIVE_JOBS: ${MAX_ACTIVE_JOBS}"
echo "[CHECK] KRAKEN2_QUEUE_DEPTH: ${KRAKEN2_QUEUE_DEPTH}"
echo "[CHECK] KRAKEN2_EXTRA_OPTS: ${KRAKEN2_EXTRA_OPTS-}"
echo "[CHECK] STAR_GENOME_LOAD: ${STAR_GENOME_LOAD:-LoadAndKeep}"
echo "[CHECK] Sample count: ${#samples[@]}"

while [[ "${completed_runs}" -lt "${#samples[@]}" ]]; do
  reap_finished_downloads
  reap_finished_runs
  launch_ready_runs
  start_download_if_possible
  reap_finished_downloads
  launch_ready_runs

  if [[ "${completed_runs}" -lt "${#samples[@]}" ]]; then
    sleep "${POLL_SECONDS}"
  fi
done

reap_finished_downloads

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERROR] ${failures} download/run task(s) failed."
  echo "[INFO] Logs: ${RUN_DIR}"
  exit 1
fi

echo "[DONE] All streaming BaiduPCS-Go PRISM jobs finished successfully."
echo "[INFO] Logs: ${RUN_DIR}"
