#!/usr/bin/env bash

# Run multiple PRISM RNA-seq samples while allowing only one Kraken2 process at
# a time. This is intended for servers where Kraken2 should fully load the
# database into memory for speed, but memory can hold only one Kraken2 database
# load at once.
#
# The full PRISM jobs can overlap. Only the Kraken2 executable is wrapped with a
# global flock lock. Once sample A finishes Kraken2, sample B can immediately
# acquire the lock and start Kraken2 while sample A continues downstream.
#
# Usage:
#   bash run_prism_samples_parallel_with_serial_kraken2.sh sample_list.txt
#
# Optional environment variables:
#   PROJECT_ROOT          PRISM project root.
#   RUN_SCRIPT            Single-sample runner. Default: run_prism_rnaseq.sh.
#   MAX_ACTIVE_JOBS       Maximum total PRISM jobs alive at once. Default: 4.
#   MAX_PARALLEL          Alias for MAX_ACTIVE_JOBS if MAX_ACTIVE_JOBS is unset.
#   KRAKEN2_QUEUE_DEPTH   Number of jobs to keep before/across Kraken2. Default: 2.
#   PRISM_THREADS         Threads passed to each PRISM job. Default inherited by
#                         run_prism_rnaseq.sh.
#   KRAKEN2_EXTRA_OPTS    Kraken2 extra options. Default here: empty string.
#   STAR_GENOME_LOAD      STAR genomeLoad mode. Default: LoadAndKeep.
#   LOG_DIR               Sample-level log directory.
#   POLL_SECONDS          Scheduler polling interval. Default: 5.

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

REAL_KRAKEN2_BIN="${REAL_KRAKEN2_BIN:-$(command -v kraken2 || true)}"
if [[ -z "${REAL_KRAKEN2_BIN}" || ! -x "${REAL_KRAKEN2_BIN}" ]]; then
  echo "[ERROR] Missing real kraken2 executable: ${REAL_KRAKEN2_BIN}"
  exit 1
fi

FLOCK_BIN="${FLOCK_BIN:-$(command -v flock || true)}"
if [[ -z "${FLOCK_BIN}" || ! -x "${FLOCK_BIN}" ]]; then
  echo "[ERROR] Missing flock executable. Install util-linux or provide FLOCK_BIN."
  exit 1
fi

MAX_ACTIVE_JOBS="${MAX_ACTIVE_JOBS:-${MAX_PARALLEL:-4}}"
KRAKEN2_QUEUE_DEPTH="${KRAKEN2_QUEUE_DEPTH:-2}"
POLL_SECONDS="${POLL_SECONDS:-5}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/02fastq/serial_kraken2_logs}"
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_DIR="${LOG_DIR}/${RUN_ID}"
WRAPPER_DIR="${RUN_DIR}/wrapper"
KRAKEN2_EVENTS_DIR="${RUN_DIR}/kraken2_events"
KRAKEN2_LOCK_FILE="${RUN_DIR}/kraken2.lock"
LOCKED_KRAKEN2_BIN="${WRAPPER_DIR}/kraken2_locked.sh"

mkdir -p "${RUN_DIR}" "${WRAPPER_DIR}" "${KRAKEN2_EVENTS_DIR}"

cat > "${LOCKED_KRAKEN2_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${REAL_KRAKEN2_BIN:-}" || ! -x "${REAL_KRAKEN2_BIN}" ]]; then
  echo "[KRAKEN2-LOCK][ERROR] REAL_KRAKEN2_BIN is missing or not executable: ${REAL_KRAKEN2_BIN:-}" >&2
  exit 1
fi

if [[ -z "${FLOCK_BIN:-}" || ! -x "${FLOCK_BIN}" ]]; then
  echo "[KRAKEN2-LOCK][ERROR] FLOCK_BIN is missing or not executable: ${FLOCK_BIN:-}" >&2
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
"${FLOCK_BIN}" -x 9

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
while IFS= read -r sample || [[ -n "${sample}" ]]; do
  sample="${sample#"${sample%%[![:space:]]*}"}"
  sample="${sample%"${sample##*[![:space:]]}"}"
  [[ -z "${sample}" ]] && continue
  [[ "${sample}" == \#* ]] && continue
  samples+=("${sample}")
done < "${SAMPLE_LIST}"

if [[ "${#samples[@]}" -eq 0 ]]; then
  echo "[ERROR] No samples found in sample list: ${SAMPLE_LIST}"
  exit 1
fi

running_jobs() {
  jobs -rp | wc -l | awk '{print $1}'
}

kraken2_acquired_count() {
  find "${KRAKEN2_EVENTS_DIR}" -maxdepth 1 -type f -name '*.acquired' | wc -l | awk '{print $1}'
}

pids=()
pid_samples=()

launch_job() {
  local sample="$1"
  local logfile="${RUN_DIR}/${sample}.log"
  echo "[START] ${sample} -> ${logfile}"
  (
    export PROJECT_ROOT="${PROJECT_ROOT}"
    export SAMPLE="${sample}"
    export KRAKEN2_BIN="${LOCKED_KRAKEN2_BIN}"
    export REAL_KRAKEN2_BIN="${REAL_KRAKEN2_BIN}"
    export FLOCK_BIN="${FLOCK_BIN}"
    export KRAKEN2_LOCK_FILE="${KRAKEN2_LOCK_FILE}"
    export KRAKEN2_EVENTS_DIR="${KRAKEN2_EVENTS_DIR}"
    export KRAKEN2_EXTRA_OPTS="${KRAKEN2_EXTRA_OPTS-}"
    export STAR_GENOME_LOAD="${STAR_GENOME_LOAD:-LoadAndKeep}"
    bash "${RUN_SCRIPT}" "${sample}"
  ) >"${logfile}" 2>&1 &
  pids+=("$!")
  pid_samples+=("${sample}")
}

echo "[CHECK] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[CHECK] RUN_SCRIPT: ${RUN_SCRIPT}"
echo "[CHECK] RUN_DIR: ${RUN_DIR}"
echo "[CHECK] REAL_KRAKEN2_BIN: ${REAL_KRAKEN2_BIN}"
echo "[CHECK] LOCKED_KRAKEN2_BIN: ${LOCKED_KRAKEN2_BIN}"
echo "[CHECK] KRAKEN2_LOCK_FILE: ${KRAKEN2_LOCK_FILE}"
echo "[CHECK] MAX_ACTIVE_JOBS: ${MAX_ACTIVE_JOBS}"
echo "[CHECK] KRAKEN2_QUEUE_DEPTH: ${KRAKEN2_QUEUE_DEPTH}"
echo "[CHECK] KRAKEN2_EXTRA_OPTS: ${KRAKEN2_EXTRA_OPTS-}"
echo "[CHECK] STAR_GENOME_LOAD: ${STAR_GENOME_LOAD:-LoadAndKeep}"
echo "[CHECK] Sample count: ${#samples[@]}"

next_idx=0
while [[ "${next_idx}" -lt "${#samples[@]}" ]]; do
  active="$(running_jobs)"
  acquired="$(kraken2_acquired_count)"
  launched="${next_idx}"
  not_yet_acquired=$((launched - acquired))

  if [[ "${active}" -lt "${MAX_ACTIVE_JOBS}" ]] && \
     ([[ "${not_yet_acquired}" -lt "${KRAKEN2_QUEUE_DEPTH}" ]] || [[ "${active}" -eq 0 ]]); then
    launch_job "${samples[${next_idx}]}"
    next_idx=$((next_idx + 1))
    continue
  fi

  sleep "${POLL_SECONDS}"
done

failures=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  sample="${pid_samples[$idx]}"
  if wait "${pid}"; then
    echo "[DONE] ${sample}"
  else
    echo "[ERROR] ${sample} failed. Check ${RUN_DIR}/${sample}.log"
    failures=$((failures + 1))
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERROR] ${failures} PRISM job(s) failed."
  echo "[INFO] Logs: ${RUN_DIR}"
  exit 1
fi

echo "[DONE] All PRISM jobs finished successfully."
echo "[INFO] Logs: ${RUN_DIR}"
