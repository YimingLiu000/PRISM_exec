#!/usr/bin/env bash

# 用途：
# 1. 在当前 conda 环境中，从源码安装 Kraken2 GitHub PR #1015 修复版
# 2. 让当前环境优先使用该修复版的 `k2` / `kraken2` / `kraken2-build`
#
# 说明：
# 1. 这个脚本不会删除 conda 里已有的 kraken2 包
# 2. 它会把修复版安装到：
#    ${CONDA_PREFIX}/opt/kraken2-pr1015
# 3. 然后写入 conda activate 脚本，使每次激活环境时自动优先使用修复版

set -euo pipefail

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "[错误] 当前没有激活 conda 环境。请先执行: conda activate prism"
  exit 1
fi

for exe in git bash make perl python; do
  if ! command -v "${exe}" >/dev/null 2>&1; then
    echo "[错误] 缺少命令: ${exe}"
    exit 1
  fi
done

WORK_ROOT="${CONDA_PREFIX}/src/kraken2-pr1015"
INSTALL_ROOT="${CONDA_PREFIX}/opt/kraken2-pr1015"
ACTIVATE_DIR="${CONDA_PREFIX}/etc/conda/activate.d"
ACTIVATE_FILE="${ACTIVATE_DIR}/kraken2_pr1015.sh"

rm -rf "${WORK_ROOT}"
mkdir -p "${WORK_ROOT}"
cd "${WORK_ROOT}"

echo "[下载] 使用 SSH 克隆 Kraken2 源码"
git clone git@github.com:DerrickWood/kraken2.git
cd kraken2

echo "[切换] 获取 PR #1015 修复版"
git fetch origin pull/1015/head:pr1015
git checkout pr1015

echo "[安装] 安装到 ${INSTALL_ROOT}"
rm -rf "${INSTALL_ROOT}"
mkdir -p "${INSTALL_ROOT}"
./install_kraken2.sh "${INSTALL_ROOT}"

mkdir -p "${ACTIVATE_DIR}"
cat > "${ACTIVATE_FILE}" <<EOF
export PATH=${INSTALL_ROOT}:\$PATH
EOF

export PATH="${INSTALL_ROOT}:${PATH}"

echo "[完成] 已安装 Kraken2 PR #1015 修复版"
echo "[说明] 安装目录: ${INSTALL_ROOT}"
echo "[说明] 激活脚本: ${ACTIVATE_FILE}"
echo "[说明] 当前优先命令路径:"
which k2 || true
which kraken2 || true
which kraken2-build || true
