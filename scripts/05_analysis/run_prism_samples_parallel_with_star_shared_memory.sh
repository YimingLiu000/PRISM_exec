#!/usr/bin/env bash

# 用途：
# 1. 在 STAR genome index 预加载到 shared memory 后，按并发数调度多个样本并行运行 PRISM
# 2. 自动为每个样本设置：
#      STAR_GENOME_LOAD=LoadAndKeep
#
# 用法：
#   bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_star_shared_memory.sh sample_list.txt
#
# sample_list.txt 格式：
#   每行一个样本名

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法：bash $0 <sample_list.txt>"
  exit 1
fi

SAMPLE_LIST="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../00script/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  PROJECT_ROOT="${HOME}/PRISM"
fi

MAX_PARALLEL="${MAX_PARALLEL:-2}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/02fastq/parallel_logs}"
RUN_SCRIPT="${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh"

if [[ ! -f "${SAMPLE_LIST}" ]]; then
  echo "[错误] sample 列表文件不存在: ${SAMPLE_LIST}"
  exit 1
fi

mkdir -p "${LOG_DIR}"

launch_job() {
  local sample="$1"
  local logfile="${LOG_DIR}/${sample}.log"
  echo "[启动] ${sample} -> ${logfile}"
  (
    export PROJECT_ROOT="${PROJECT_ROOT}"
    export SAMPLE="${sample}"
    export STAR_GENOME_LOAD="LoadAndKeep"
    bash "${RUN_SCRIPT}"
  ) >"${logfile}" 2>&1 &
}

running_jobs() {
  jobs -rp | wc -l | awk '{print $1}'
}

while IFS= read -r sample || [[ -n "${sample}" ]]; do
  [[ -z "${sample}" ]] && continue
  while [[ "$(running_jobs)" -ge "${MAX_PARALLEL}" ]]; do
    sleep 5
  done
  launch_job "${sample}"
done < "${SAMPLE_LIST}"

wait
echo "[完成] 所有样本并行任务已结束"

