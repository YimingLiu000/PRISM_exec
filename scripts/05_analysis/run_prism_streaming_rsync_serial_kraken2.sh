#!/usr/bin/env bash

# Stream PRISM RNA-seq samples from a remote storage server with rsync while
# processing already downloaded samples. Only one Kraken2 process is allowed at
# a time, and per-sample input FASTQ.GZ/FASTQ files are removed after that
# sample finishes so result files are retained while input disk usage stays low.
#
# Remote manifest format:
#   one remote sample directory or FASTQ.GZ path per line; blank lines and lines
#   starting with # are ignored.
#
# Example remote manifest:
#   /data/rnaseq/FUSCCTNBC001
#   /data/rnaseq/FUSCCTNBC002
# or:
#   /data/rnaseq/FUSCCTNBC001/FUSCCTNBC001_RNAseq_R1.fastq.gz
#   /data/rnaseq/FUSCCTNBC002/FUSCCTNBC002_RNAseq_R1.fastq.gz
#
# By default each remote directory must contain:
#   <sample>_RNAseq_R1.fastq.gz
#   <sample>_RNAseq_R2.fastq.gz
#
# Usage:
#   bash run_prism_streaming_rsync_serial_kraken2.sh remote_sample_dirs.txt
#
# Required environment variables:
#   RSYNC_REMOTE        Remote rsync prefix, for example user@host
#
# Optional environment variables:
#   PROJECT_ROOT        PRISM project root.
#   RUN_SCRIPT          Single-sample PRISM runner. Default: run_prism_rnaseq.sh.
#   RAW_DIR             Local staging directory for downloaded FASTQ.GZ files.
#   FASTQ_DIR           Local FASTQ/output directory.
#   FQ1_END             Read 1 suffix before .gz. Default: _RNAseq_R1.fastq
#   FQ2_END             Read 2 suffix before .gz. Default: _RNAseq_R2.fastq
#   RSYNC_SSH_PORT      SSH port. Default: 22.
#   RSYNC_SSH_OPTS      Extra SSH options. Default: empty.
#   RSYNC_OPTS          Extra rsync options. Default: -av --partial --append-verify
#   DOWNLOAD_AHEAD      Downloaded/downloading samples allowed ahead of the next
#                       not-yet-launched PRISM sample. Default: 1.
#   MAX_ACTIVE_JOBS     Maximum total PRISM jobs alive at once. Default: 3.
#   KRAKEN2_QUEUE_DEPTH Number of downloaded jobs to keep queued for Kraken2. Default: 2.
#   KRAKEN2_EXTRA_OPTS  Kraken2 extra options. Default here: empty string.
#   STAR_GENOME_LOAD    STAR genomeLoad mode. Default: LoadAndKeep.
#   POLL_SECONDS        Scheduler polling interval. Default: 5.
#   LOG_DIR             Run log directory.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash $0 <remote_sample_dirs.txt>"
  exit 1
fi

REMOTE_MANIFEST="$1"

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

if [[ ! -f "${REMOTE_MANIFEST}" ]]; then
  echo "[ERROR] Remote manifest file does not exist: ${REMOTE_MANIFEST}"
  exit 1
fi

if [[ -z "${RSYNC_REMOTE:-}" ]]; then
  echo "[ERROR] RSYNC_REMOTE is required, for example: export RSYNC_REMOTE=user@host"
  exit 1
fi

for exe in rsync ssh flock find awk; do
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
MAX_ACTIVE_JOBS="${MAX_ACTIVE_JOBS:-3}"
DOWNLOAD_AHEAD="${DOWNLOAD_AHEAD:-1}"
KRAKEN2_QUEUE_DEPTH="${KRAKEN2_QUEUE_DEPTH:-2}"
POLL_SECONDS="${POLL_SECONDS:-5}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/02fastq/streaming_rsync_serial_kraken2_logs}"
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_DIR="${LOG_DIR}/${RUN_ID}"
WRAPPER_DIR="${RUN_DIR}/wrapper"
KRAKEN2_EVENTS_DIR="${RUN_DIR}/kraken2_events"
KRAKEN2_LOCK_FILE="${RUN_DIR}/kraken2.lock"
LOCKED_KRAKEN2_BIN="${WRAPPER_DIR}/kraken2_locked.sh"
DOWNLOAD_LOG_DIR="${RUN_DIR}/downloads"
DONE_DIR="${RUN_DIR}/download_done"
FAIL_DIR="${RUN_DIR}/download_failed"

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

remote_dirs=()
samples=()
seen_samples=" "
while IFS= read -r remote_path || [[ -n "${remote_path}" ]]; do
  remote_path="${remote_path#"${remote_path%%[![:space:]]*}"}"
  remote_path="${remote_path%"${remote_path##*[![:space:]]}"}"
  [[ -z "${remote_path}" ]] && continue
  [[ "${remote_path}" == \#* ]] && continue

  sample=""
  remote_dir=""
  base_name="$(basename "${remote_path}")"
  if [[ "${base_name}" == *"${FQ1_END}.gz" ]]; then
    sample="${base_name%"${FQ1_END}.gz"}"
    remote_dir="$(dirname "${remote_path}")"
  elif [[ "${base_name}" == *"${FQ2_END}.gz" ]]; then
    sample="${base_name%"${FQ2_END}.gz"}"
    remote_dir="$(dirname "${remote_path}")"
  else
    remote_dir="${remote_path%/}"
    sample="$(basename "${remote_dir}")"
  fi

  if [[ -z "${sample}" || "${sample}" == "." || "${sample}" == "/" ]]; then
    echo "[ERROR] Cannot derive sample name from remote path: ${remote_path}"
    exit 1
  fi

  if [[ "${seen_samples}" == *" ${sample} "* ]]; then
    continue
  fi
  seen_samples="${seen_samples}${sample} "
  remote_dirs+=("${remote_dir%/}")
  samples+=("${sample}")
done < "${REMOTE_MANIFEST}"

if [[ "${#samples[@]}" -eq 0 ]]; then
  echo "[ERROR] No remote sample directories found in: ${REMOTE_MANIFEST}"
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

download_sample() {
  local idx="$1"
  local sample="${samples[$idx]}"
  local remote_dir="${remote_dirs[$idx]}"
  local safe_sample
  safe_sample="$(safe_name "${sample}")"
  local log_file="${DOWNLOAD_LOG_DIR}/${safe_sample}.rsync.log"
  local remote_r1="${RSYNC_REMOTE}:${remote_dir}/${sample}${FQ1_END}.gz"
  local remote_r2="${RSYNC_REMOTE}:${remote_dir}/${sample}${FQ2_END}.gz"
  local local_r1="${RAW_DIR}/${sample}${FQ1_END}.gz"
  local local_r2="${RAW_DIR}/${sample}${FQ2_END}.gz"

  echo "[DOWNLOAD] ${sample}: ${remote_dir} -> ${RAW_DIR}" | tee -a "${log_file}"

  set +e
  rsync ${RSYNC_OPTS:--av --partial --append-verify} \
    -e "ssh -p ${RSYNC_SSH_PORT:-22} ${RSYNC_SSH_OPTS:-}" \
    "${remote_r1}" "${local_r1}" >>"${log_file}" 2>&1
  local status1=$?
  rsync ${RSYNC_OPTS:--av --partial --append-verify} \
    -e "ssh -p ${RSYNC_SSH_PORT:-22} ${RSYNC_SSH_OPTS:-}" \
    "${remote_r2}" "${local_r2}" >>"${log_file}" 2>&1
  local status2=$?
  set -e

  if [[ "${status1}" -eq 0 && "${status2}" -eq 0 && -f "${local_r1}" && -f "${local_r2}" ]]; then
    touch "${DONE_DIR}/${safe_sample}.done"
    echo "[DOWNLOAD-DONE] ${sample}" | tee -a "${log_file}"
  else
    touch "${FAIL_DIR}/${safe_sample}.failed"
    echo "[DOWNLOAD-ERROR] ${sample}; check ${log_file}" | tee -a "${log_file}"
    cleanup_partial_download "${sample}"
  fi
}

cleanup_sample_inputs() {
  local sample="$1"
  local paths=(
    "${RAW_DIR}/${sample}${FQ1_END}.gz"
    "${RAW_DIR}/${sample}${FQ2_END}.gz"
    "${FASTQ_DIR}/${sample}${FQ1_END}"
    "${FASTQ_DIR}/${sample}${FQ2_END}"
  )
  local path
  for path in "${paths[@]}"; do
    if [[ -f "${path}" ]]; then
      echo "[CLEANUP] Removing file: ${path}"
      rm -- "${path}"
    fi
  done
}

cleanup_partial_download() {
  local sample="$1"
  local paths=(
    "${RAW_DIR}/${sample}${FQ1_END}.gz"
    "${RAW_DIR}/${sample}${FQ2_END}.gz"
  )
  local path
  for path in "${paths[@]}"; do
    if [[ -f "${path}" ]]; then
      echo "[CLEANUP] Removing partial download: ${path}"
      rm -- "${path}"
    fi
  done
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

download_pid=""
download_idx=-1
next_download=0
next_run=0
launched_runs=0
completed_runs=0
failures=0

run_pids=()
run_samples=()

start_download_if_possible() {
  if [[ -n "${download_pid}" ]]; then
    return
  fi
  if [[ "${next_download}" -ge "${#samples[@]}" ]]; then
    return
  fi
  local download_backlog=$((next_download - next_run))
  if [[ "${download_backlog}" -ge "${DOWNLOAD_AHEAD}" ]]; then
    return
  fi

  download_idx="${next_download}"
  download_sample "${download_idx}" &
  download_pid="$!"
  next_download=$((next_download + 1))
}

reap_download_if_done() {
  if [[ -z "${download_pid}" ]]; then
    return
  fi
  if is_running_pid "${download_pid}"; then
    return
  fi
  wait "${download_pid}" || true
  download_pid=""
  download_idx=-1
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
echo "[CHECK] RSYNC_REMOTE: ${RSYNC_REMOTE}"
echo "[CHECK] RAW_DIR: ${RAW_DIR}"
echo "[CHECK] FASTQ_DIR: ${FASTQ_DIR}"
echo "[CHECK] DOWNLOAD_AHEAD: ${DOWNLOAD_AHEAD}"
echo "[CHECK] MAX_ACTIVE_JOBS: ${MAX_ACTIVE_JOBS}"
echo "[CHECK] KRAKEN2_QUEUE_DEPTH: ${KRAKEN2_QUEUE_DEPTH}"
echo "[CHECK] KRAKEN2_EXTRA_OPTS: ${KRAKEN2_EXTRA_OPTS-}"
echo "[CHECK] STAR_GENOME_LOAD: ${STAR_GENOME_LOAD:-LoadAndKeep}"
echo "[CHECK] Sample count: ${#samples[@]}"

while [[ "${completed_runs}" -lt "${#samples[@]}" ]]; do
  start_download_if_possible
  reap_download_if_done
  launch_ready_runs
  start_download_if_possible
  reap_finished_runs
  launch_ready_runs

  if [[ "${completed_runs}" -lt "${#samples[@]}" ]]; then
    sleep "${POLL_SECONDS}"
  fi
done

if [[ -n "${download_pid}" ]]; then
  wait "${download_pid}" || true
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERROR] ${failures} download/run task(s) failed."
  echo "[INFO] Logs: ${RUN_DIR}"
  exit 1
fi

echo "[DONE] All streaming rsync PRISM jobs finished successfully."
echo "[INFO] Logs: ${RUN_DIR}"
