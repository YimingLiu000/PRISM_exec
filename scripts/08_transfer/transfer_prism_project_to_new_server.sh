#!/usr/bin/env bash

# 用途：
# 1. 使用 rsync 将整个 PRISM 项目目录同步到新的服务器
# 2. 支持断点续传
# 3. 支持 dry-run 预演
#
# 使用方法：
#   bash transfer_prism_project_to_new_server.sh <源目录> <远端用户> <远端主机> <远端目录> [SSH端口] [SSH密码] [--dry-run]
#
# 示例：
#   bash transfer_prism_project_to_new_server.sh \
#     /home/data/vip0/project/11PRISM \
#     ubuntu \
#     ssh.sxqtx.com \
#     /home/ubuntu/PRISM \
#     13569 \
#     'your_password' \
#     --dry-run
#
# 再正式执行：
#   bash transfer_prism_project_to_new_server.sh \
#     /home/data/vip0/project/11PRISM \
#     ubuntu \
#     ssh.sxqtx.com \
#     /home/ubuntu/PRISM \
#     13569 \
#     'your_password'
#
# 参数说明：
#   $1  源目录
#   $2  远端用户名
#   $3  远端主机名或 IP
#   $4  远端目标目录
#   $5  SSH 端口（可选，默认 22）
#   $6  SSH 密码（可选；若为空则使用 SSH 交互/免密）
#   $7  --dry-run（可选）
#
# 安全提示：
# 1. 将密码直接写在命令行中会出现在 shell 历史中，存在泄露风险
# 2. 更推荐使用 SSH 免密登录
# 3. 如果必须带密码跑 nohup/后台任务，可以用本脚本的密码参数

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "用法：bash $0 <源目录> <远端用户> <远端主机> <远端目录> [SSH端口] [SSH密码] [--dry-run]"
  exit 1
fi

SRC_DIR="$1"
DEST_USER="$2"
DEST_HOST="$3"
DEST_DIR="$4"
SSH_PORT="${5:-22}"
SSH_PASSWORD="${6:-}"
DRY_RUN="${7:-}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[错误] 源目录不存在: ${SRC_DIR}"
  exit 1
fi

for exe in rsync ssh; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

USE_SSHPASS=false
if [[ -n "${SSH_PASSWORD}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "[错误] 你提供了 SSH 密码，但系统缺少 sshpass"
    echo "       请先安装 sshpass，或改用 SSH 免密登录"
    exit 1
  fi
  USE_SSHPASS=true
fi

SSH_OPTS=(-p "${SSH_PORT}")
RSYNC_OPTS=(-aHAX --numeric-ids --info=progress2 --partial --append-verify)

echo "[检查] 目标服务器连通性"
if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  echo "[DRY-RUN] 跳过实际 SSH mkdir"
else
  if [[ "${USE_SSHPASS}" == "true" ]]; then
    sshpass -p "${SSH_PASSWORD}" ssh "${SSH_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "mkdir -p '${DEST_DIR}'"
  else
    ssh "${SSH_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "mkdir -p '${DEST_DIR}'"
  fi
fi

echo "[同步] 源目录: ${SRC_DIR}/"
echo "[同步] 目标目录: ${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
echo "[同步] SSH 端口: ${SSH_PORT}"

if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  echo "[DRY-RUN] 仅预演，不实际传输"
  printf 'rsync '
  printf '%q ' "${RSYNC_OPTS[@]}"
  if [[ "${USE_SSHPASS}" == "true" ]]; then
    printf '%q ' "sshpass -p ${SSH_PASSWORD}" rsync "${RSYNC_OPTS[@]}" -e "ssh -p ${SSH_PORT}" "${SRC_DIR}/" "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
  else
    printf '%q ' -e "ssh -p ${SSH_PORT}" "${SRC_DIR}/" "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
  fi
  printf '\n'
else
  if [[ "${USE_SSHPASS}" == "true" ]]; then
    sshpass -p "${SSH_PASSWORD}" \
      rsync "${RSYNC_OPTS[@]}" \
      -e "ssh -p ${SSH_PORT}" \
      "${SRC_DIR}/" \
      "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
  else
    rsync "${RSYNC_OPTS[@]}" \
      -e "ssh -p ${SSH_PORT}" \
      "${SRC_DIR}/" \
      "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/"
  fi
fi

echo "[完成] 项目目录同步结束"
