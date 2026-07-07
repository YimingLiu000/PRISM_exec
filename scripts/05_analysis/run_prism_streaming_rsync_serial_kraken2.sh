#!/usr/bin/env bash

# Stream PRISM RNA-seq samples from a remote storage server with rsync.
#
# This script deliberately separates the download queue from the compute queue:
#   1. The download queue walks through the manifest in order and keeps syncing
#      samples. It does not wait for PRISM computation to catch up.
#   2. Each successfully downloaded sample is marked ready for computation.
#   3. The compute queue starts PRISM jobs only for ready samples. If download is
#      slower than compute, computation waits until the next sample is ready.
#   4. Kraken2 is still serialized with a global flock lock, so only one sample
#      can run Kraken2 at a time.
#   5. After each sample finishes PRISM, only that sample's explicit input files
#      are removed: two downloaded FASTQ.GZ files and two decompressed FASTQ
#      files. Result directories are retained.
#
# Remote manifest format:
#   one remote sample path or FASTQ.GZ path per line; blank lines and lines
#   starting with # are ignored. FASTQ.GZ paths are synced exactly as listed; if
#   only one mate is listed, the other mate is inferred from the same directory
#   and the default read suffix. Non-GZ paths are treated as <parent>/<sample>,
#   and FASTQ.GZ files are inferred directly under <parent>.
#
# Example remote manifest:
#   /data/rnaseq/FUSCCTNBC001
#   /data/rnaseq/FUSCCTNBC002
# or:
#   /data/rnaseq/FUSCCTNBC001_RNAseq_R1.fastq.gz
#   /data/rnaseq/FUSCCTNBC002_RNAseq_R1.fastq.gz
#
# In both forms, all FASTQ.GZ files are expected to be flat in the parent
# directory:
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
#                       A full .gz suffix such as _1.fq.gz is also accepted.
#   FQ2_END             Read 2 suffix before .gz. Default: _RNAseq_R2.fastq
#                       A full .gz suffix such as _2.fq.gz is also accepted.
#   RSYNC_SSH_PORT      SSH port. Default: 22.
#   RSYNC_SSH_OPTS      Extra SSH options. Default: empty.
#   RSYNC_OPTS          Extra rsync options. Default: -av --partial --append-verify
#   PARALLEL_MATES      Download R1 and R2 for one sample concurrently. Default: TRUE.
#   MAX_ACTIVE_JOBS     Maximum total PRISM jobs alive at once. Default: 3.
#   KRAKEN2_QUEUE_DEPTH Number of ready jobs allowed before/across Kraken2. Default: 2.
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
if [[ "${FQ1_END}" == *.gz ]]; then
  FQ1_END="${FQ1_END%.gz}"
fi
if [[ "${FQ2_END}" == *.gz ]]; then
  FQ2_END="${FQ2_END%.gz}"
fi
RSYNC_OPTS="${RSYNC_OPTS:--av --partial --append-verify}"
RSYNC_SSH_PORT="${RSYNC_SSH_PORT:-22}"
RSYNC_SSH_OPTS="${RSYNC_SSH_OPTS:-}"
PARALLEL_MATES="${PARALLEL_MATES:-TRUE}"
MAX_ACTIVE_JOBS="${MAX_ACTIVE_JOBS:-3}"
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
READY_DIR="${RUN_DIR}/download_ready"
FAIL_DIR="${RUN_DIR}/download_failed"
DOWNLOAD_QUEUE_DONE="${RUN_DIR}/download_queue.done"

mkdir -p "${RAW_DIR}" "${FASTQ_DIR}" "${RUN_DIR}" "${WRAPPER_DIR}" \
  "${KRAKEN2_EVENTS_DIR}" "${DOWNLOAD_LOG_DIR}" "${READY_DIR}" "${FAIL_DIR}"

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
      echo "[ERROR] Sample entry must include its remote parent directory: ${remote_path}"
      echo "        Use /path/to/parent/${remote_path}, or provide a full FASTQ.GZ path."
      exit 1
    fi
    sample="${base_name}"
    remote_parent="$(dirname "${remote_path}")"
    remote_r1="${remote_parent}/${sample}${FQ1_END}.gz"
    remote_r2="${remote_parent}/${sample}${FQ2_END}.gz"
  fi

  if [[ -z "${sample}" || "${sample}" == "." || "${sample}" == "/" ]]; then
    echo "[ERROR] Cannot derive sample name from remote path: ${remote_path}"
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
done < "${REMOTE_MANIFEST}"

if [[ "${#samples[@]}" -eq 0 ]]; then
  echo "[ERROR] No remote sample directories found in: ${REMOTE_MANIFEST}"
  exit 1
fi

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

is_running_pid() {
  local pid="$1"
  jobs -rp | awk -v target="${pid}" '$1 == target { found = 1 } END { exit(found ? 0 : 1) }'
}

kraken2_acquired_count() {
  find "${KRAKEN2_EVENTS_DIR}" -maxdepth 1 -type f -name '*.acquired' | wc -l | awk '{print $1}'
}

rsync_one_file() {
  local remote_file="$1"
  local local_file="$2"
  local log_file="$3"
  local ssh_cmd="ssh -p ${RSYNC_SSH_PORT} ${RSYNC_SSH_OPTS}"

  # RSYNC_OPTS is intentionally split by the shell here so users can pass normal
  # rsync option strings such as: -av --partial --append-verify --info=progress2
  rsync ${RSYNC_OPTS} -e "${ssh_cmd}" "${remote_file}" "${local_file}" >>"${log_file}" 2>&1
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

download_sample() {
  local idx="$1"
  local sample="${samples[$idx]}"
  local safe_sample
  safe_sample="$(safe_name "${sample}")"
  local log_file="${DOWNLOAD_LOG_DIR}/${safe_sample}.rsync.log"
  local remote_r1="${RSYNC_REMOTE}:${remote_r1s[$idx]}"
  local remote_r2="${RSYNC_REMOTE}:${remote_r2s[$idx]}"
  local local_r1="${RAW_DIR}/${sample}${FQ1_END}.gz"
  local local_r2="${RAW_DIR}/${sample}${FQ2_END}.gz"
  local status1=0
  local status2=0

  echo "[DOWNLOAD] ${sample}: ${remote_r1} + ${remote_r2} -> ${RAW_DIR}" | tee -a "${log_file}"

  set +e
  if [[ "${PARALLEL_MATES}" == "TRUE" || "${PARALLEL_MATES}" == "true" || "${PARALLEL_MATES}" == "1" ]]; then
    rsync_one_file "${remote_r1}" "${local_r1}" "${log_file}" &
    local pid1="$!"
    rsync_one_file "${remote_r2}" "${local_r2}" "${log_file}" &
    local pid2="$!"
    wait "${pid1}"; status1=$?
    wait "${pid2}"; status2=$?
  else
    rsync_one_file "${remote_r1}" "${local_r1}" "${log_file}"; status1=$?
    rsync_one_file "${remote_r2}" "${local_r2}" "${log_file}"; status2=$?
  fi
  set -e

  if [[ "${status1}" -eq 0 && "${status2}" -eq 0 && -f "${local_r1}" && -f "${local_r2}" ]]; then
    touch "${READY_DIR}/${safe_sample}.ready"
    echo "[DOWNLOAD-READY] ${sample}" | tee -a "${log_file}"
  else
    touch "${FAIL_DIR}/${safe_sample}.failed"
    echo "[DOWNLOAD-ERROR] ${sample}; status R1=${status1}, R2=${status2}; expected ${local_r1} and ${local_r2}; check ${log_file}" | tee -a "${log_file}"
    cleanup_partial_download "${sample}"
  fi
}

download_queue() {
  local idx
  for idx in "${!samples[@]}"; do
    download_sample "${idx}"
  done
  touch "${DOWNLOAD_QUEUE_DONE}"
  echo "[DOWNLOAD-DONE] Download queue finished."
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

download_pid=""
next_compute=0
launched_runs=0
completed_items=0
failures=0
download_queue_failed=0

run_pids=()
run_samples=()

launch_ready_runs() {
  while [[ "${next_compute}" -lt "${#samples[@]}" ]]; do
    local sample="${samples[$next_compute]}"
    local safe_sample
    safe_sample="$(safe_name "${sample}")"

    if [[ -f "${FAIL_DIR}/${safe_sample}.failed" ]]; then
      echo "[ERROR] Download failed for ${sample}; skipping compute."
      failures=$((failures + 1))
      completed_items=$((completed_items + 1))
      next_compute=$((next_compute + 1))
      continue
    fi

    if [[ ! -f "${READY_DIR}/${safe_sample}.ready" ]]; then
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
    next_compute=$((next_compute + 1))
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
      completed_items=$((completed_items + 1))
    fi
  done
  run_pids=("${new_pids[@]}")
  run_samples=("${new_samples[@]}")
}

reap_download_queue_if_done() {
  if [[ -z "${download_pid}" ]]; then
    return
  fi
  if is_running_pid "${download_pid}"; then
    return
  fi
  if ! wait "${download_pid}"; then
    download_queue_failed=1
    echo "[ERROR] Download queue process failed unexpectedly."
  fi
  download_pid=""
}

trap 'echo "[INTERRUPT] Stopping background jobs."; if [[ -n "${download_pid:-}" ]]; then kill "${download_pid}" 2>/dev/null || true; fi; for pid in "${run_pids[@]:-}"; do kill "${pid}" 2>/dev/null || true; done; exit 130' INT TERM

echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] RUN_SCRIPT: ${RUN_SCRIPT}"
echo "[CHECK] RUN_DIR: ${RUN_DIR}"
echo "[CHECK] RSYNC_REMOTE: ${RSYNC_REMOTE}"
echo "[CHECK] RSYNC_SSH_PORT: ${RSYNC_SSH_PORT}"
echo "[CHECK] RSYNC_SSH_OPTS: ${RSYNC_SSH_OPTS}"
echo "[CHECK] RSYNC_OPTS: ${RSYNC_OPTS}"
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

download_queue &
download_pid="$!"
echo "[DOWNLOAD] Download queue started with pid ${download_pid}."

while [[ "${completed_items}" -lt "${#samples[@]}" ]]; do
  reap_download_queue_if_done
  reap_finished_runs
  launch_ready_runs

  if [[ "${download_queue_failed}" -ne 0 && -z "${download_pid}" && "${#run_pids[@]}" -eq 0 ]]; then
    break
  fi

  if [[ "${completed_items}" -lt "${#samples[@]}" ]]; then
    sleep "${POLL_SECONDS}"
  fi
done

reap_download_queue_if_done

if [[ "${download_queue_failed}" -ne 0 ]]; then
  failures=$((failures + 1))
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERROR] ${failures} download/run task(s) failed."
  echo "[INFO] Logs: ${RUN_DIR}"
  exit 1
fi

echo "[DONE] All streaming rsync PRISM jobs finished successfully."
echo "[INFO] Logs: ${RUN_DIR}"
