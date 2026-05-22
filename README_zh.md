# PRISM 数据准备与运行说明

## 目标

这个目录用于支持 PRISM 的环境配置、数据库准备、RNA-seq 分析和真菌结果提取。

当前约定：

- PRISM 仓库源码放在：`${PROJECT_ROOT}/00script/repo`
- 原始 RNA-seq 数据放在：`${PROJECT_ROOT}/01rawdata`
- 参考数据库与索引放在：`${PROJECT_ROOT}/02ref`
- 运行输出放在：`${PROJECT_ROOT}/02fastq`

## 先说明变量写法

建议你先定义项目目录变量：

```bash
export PROJECT_ROOT=/your/path/to/PRISM
```

后续文档中的 `${PROJECT_ROOT}` 才是可以直接复制执行的 shell 写法。

## 00script 目录结构与用途

`PRISM_linux_bundle/scripts/` 目录已经按完全相同的子目录结构整理，便于你直接对照 `00script/` 使用。

### 1. `01_env`
环境配置。

### 2. `02_kraken`
Kraken2 / k2 数据库下载与构建。

### 3. `03_blast`
BLAST / core_nt 数据库下载、解压与 map 生成。

包含：
- `download_prism_blast_core_nt_sources.sh`
  作用：并行下载 NCBI BLAST `core_nt` 分卷源文件，校验 md5，并自动解压到标准目录
- `generate_sorted_accession_map.sh`
  作用：基于标准目录中的 `core_nt` 数据库生成 `sorted_accession_map.txt`
- `download_core_nt_db.sh`
  作用：下载 Kraken 官方上传的 `k2_core_nt_20251015.tar.gz`
- `unpack_core_nt_db.sh`
  作用：将官方 `core_nt` 归档直接解压到下游分析所需的标准目录

作用总结：
- 支持两种 BLAST `core_nt` 数据准备方式
  1. 先下载源数据后自行构建/整理
  2. 直接下载官方已构建数据库并解压

### 4. `04_host`
宿主参考与宿主索引。

### 5. `05_analysis`
PRISM 分析与真菌结果提取。

### 6. `06_docs`
中文说明文档。

### 7. `07_patch_installs`
Kraken2 PR #1015 修复版安装脚本。

## 1. 环境配置

### 1.1 创建 conda 环境

```bash
conda env create -f ${PROJECT_ROOT}/00script/01_env/environment_prism.yml
conda activate prism
```

### 1.2 可选：安装 Kraken2 PR #1015 修复版

#### 服务器可以直接访问 GitHub

```bash
bash ${PROJECT_ROOT}/00script/07_patch_installs/install_kraken2_pr1015.sh
```

#### 服务器不能访问 GitHub

先在能访问 GitHub 的机器上手动准备源码：

```bash
git clone git@github.com:DerrickWood/kraken2.git
cd kraken2
git fetch origin pull/1015/head:pr1015
git checkout pr1015
cd ..
tar -czf kraken2-pr1015-src.tar.gz kraken2
```

把压缩包上传到服务器，建议放到：

```bash
${PROJECT_ROOT}/02ref/src/kraken2-pr1015-src.tar.gz
```

然后在服务器上执行：

```bash
bash ${PROJECT_ROOT}/00script/07_patch_installs/install_kraken2_pr1015_offline.sh
```

说明：

- 数据库下载/构建阶段可以使用 `k2`
- 后续 PRISM 分析仍旧继续调用 `kraken2`

## 2. Kraken2 数据库

你现在有两种方式准备 Kraken2 数据库，这两种方式最终都应落到：

```bash
${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

因此下游分析脚本中的：

```bash
KRAKEN_DB=${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

不需要修改。

### 方式 A：直接下载 Kraken 官方已构建数据库

#### 下载压缩包

```bash
bash ${PROJECT_ROOT}/00script/02_kraken/download_prackendb.sh
```

默认下载到：

```bash
${PROJECT_ROOT}/02ref/kraken2_prackendb/k2_NCBI_reference_20251007.tar.gz
```

#### 解压到标准目录

```bash
bash ${PROJECT_ROOT}/00script/02_kraken/unpack_prackendb.sh
```

默认会直接解压到：

```bash
${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

### 方式 B：下载源数据后自行构建

#### 下载机

```bash
bash ${PROJECT_ROOT}/00script/02_kraken/download_prism_kraken2_sources.sh
```

如果网络不稳定、容易中断，建议优先使用：

```bash
bash ${PROJECT_ROOT}/00script/02_kraken/download_prism_kraken2_sources_retry.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
```

#### 服务器

把源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/02_kraken/build_prism_kraken2_recommended.sh
```

最终数据库目录：

```bash
${PROJECT_ROOT}/02ref/kraken2/prism_kraken2_recommended
```

## 3. BLAST core_nt

你现在也有两种方式准备 BLAST `core_nt`，这两种方式最终都应落到：

```bash
${PROJECT_ROOT}/02ref/blast/core_nt
```

因此下游分析脚本中的：

```bash
BLAST_DB=${PROJECT_ROOT}/02ref/blast/core_nt/core_nt
```

不需要修改。

### 方式 A：直接下载 Kraken 官方已构建 core_nt 数据库

#### 下载压缩包

```bash
bash ${PROJECT_ROOT}/00script/03_blast/download_core_nt_db.sh
```

默认下载到：

```bash
${PROJECT_ROOT}/02ref/blast/core_nt_download/k2_core_nt_20251015.tar.gz
```

#### 解压到标准目录

```bash
bash ${PROJECT_ROOT}/00script/03_blast/unpack_core_nt_db.sh
```

默认会直接解压到：

```bash
${PROJECT_ROOT}/02ref/blast/core_nt
```

### 方式 B：下载源数据后自行准备

#### 下载机

```bash
bash ${PROJECT_ROOT}/00script/03_blast/download_prism_blast_core_nt_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/blast_sources/core_nt
```

#### 服务器

把源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/03_blast/generate_sorted_accession_map.sh
```

最终会生成并复制：

```bash
${PROJECT_ROOT}/00script/repo/sorted_accession_map.txt
```

## 4. 宿主索引

### 4.1 下载机

```bash
bash ${PROJECT_ROOT}/00script/04_host/download_prism_host_reference.sh
```

宿主源数据目录：

```bash
${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq
```

### 4.2 服务器

把宿主源数据目录复制到服务器同路径后：

```bash
bash ${PROJECT_ROOT}/00script/04_host/build_prism_host_indexes.sh
```

默认输出目录：

```bash
${PROJECT_ROOT}/02ref/host
```

## 5. genbank 目录

需要手动把 PRISM 的 `genbank/` 目录放到：

```bash
${PROJECT_ROOT}/00script/repo/genbank
```

## 6. 检查资源是否齐全

```bash
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 7. 运行 PRISM

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh
```

## 8. 提取真菌结果

```bash
Rscript ${PROJECT_ROOT}/00script/05_analysis/extract_fungal_abundance.R FUSCCTNBC001
```

## 9. 推荐执行顺序

```bash
export PROJECT_ROOT=/your/path/to/PRISM
conda env create -f ${PROJECT_ROOT}/00script/01_env/environment_prism.yml
conda activate prism

# 可选：如果需要，先安装 Kraken2 PR #1015 修复版
# bash ${PROJECT_ROOT}/00script/07_patch_installs/install_kraken2_pr1015.sh

# 下载机上执行
bash ${PROJECT_ROOT}/00script/02_kraken/download_prism_kraken2_sources.sh
bash ${PROJECT_ROOT}/00script/03_blast/download_prism_blast_core_nt_sources.sh
bash ${PROJECT_ROOT}/00script/04_host/download_prism_host_reference.sh

# 把以下目录复制到服务器同路径
# ${PROJECT_ROOT}/02ref/kraken2_sources/prism_kraken2_recommended
# ${PROJECT_ROOT}/02ref/blast_sources/core_nt
# ${PROJECT_ROOT}/02ref/host_sources/GRCh38_refseq

# 服务器上执行
bash ${PROJECT_ROOT}/00script/02_kraken/build_prism_kraken2_recommended.sh
bash ${PROJECT_ROOT}/00script/03_blast/generate_sorted_accession_map.sh
bash ${PROJECT_ROOT}/00script/04_host/build_prism_host_indexes.sh
bash ${PROJECT_ROOT}/00script/check_prism_required_data.sh
```

## 10. 注意事项

1. `core_nt` 很大，下载和磁盘占用都不小。
2. Kraken2、BLAST、宿主索引都建议分成“下载机”和“服务器构建机”两段式。
3. `PRISM.R` 当前对 `model_org_taxids` 默认值处理有问题，运行时务必显式传：

```bash
--model_org_taxids ${PROJECT_ROOT}/00script/repo/model_org_taxids.txt
```
