#!/usr/bin/env bash

# 用途：
# 1. 使用 STAR 原生 `--genomeLoad` 能力管理宿主基因组 shared memory
# 2. 支持预加载（LoadAndExit）和移除（Remove）
#
# 用法：
#   bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
#   bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
#
# 可选环境变量：
#   PROJECT_ROOT        项目目录
#   STAR_BIN            STAR 可执行文件路径；默认自动从 PATH 查找
#   STAR_GENOME_DIR     STAR genomeDir；默认 ${PROJECT_ROOT}/02ref/host/hg38.star
#   STAR_THREADS        线程数；默认 8

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法：bash $0 <load|remove>"
  exit 1
fi

ACTION="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
elif [[ -d "${SCRIPT_DIR}/../../00script/repo" ]]; then
  PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
else
  PROJECT_ROOT="${HOME}/PRISM"
fi

STAR_BIN="${STAR_BIN:-$(command -v STAR)}"
STAR_GENOME_DIR="${STAR_GENOME_DIR:-${PROJECT_ROOT}/02ref/host/hg38.star}"
STAR_THREADS="${STAR_THREADS:-8}"

if [[ -z "${STAR_BIN}" || ! -x "${STAR_BIN}" ]]; then
  echo "[错误] 未找到 STAR 可执行文件"
  exit 1
fi

if [[ ! -d "${STAR_GENOME_DIR}" ]]; then
  echo "[错误] STAR genomeDir 不存在: ${STAR_GENOME_DIR}"
  exit 1
fi

case "${ACTION}" in
  load)
    echo "[STAR] 预加载 shared memory genome index"
    "${STAR_BIN}" \
      --genomeDir "${STAR_GENOME_DIR}" \
      --genomeLoad LoadAndExit \
      --runThreadN "${STAR_THREADS}"
    ;;
  remove)
    echo "[STAR] 移除 shared memory genome index"
    "${STAR_BIN}" \
      --genomeDir "${STAR_GENOME_DIR}" \
      --genomeLoad Remove \
      --runThreadN "${STAR_THREADS}"
    ;;
  *)
    echo "[错误] 不支持的动作: ${ACTION}"
    echo "仅支持：load / remove"
    exit 1
    ;;
esac

