# PRISM 数据准备与运行说明

## 目标

这个目录用于支持 PRISM 的环境配置、数据库准备、RNA-seq 分析和真菌结果提取。

当前约定：

- PRISM 仓库源码放在：`${PROJECT_ROOT}/00script/repo`
- 原始 RNA-seq 数据放在：`${PROJECT_ROOT}/01rawdata`
- 参考数据库与索引放在：`${PROJECT_ROOT}/02ref`
- 运行输出放在：`${PROJECT_ROOT}/02fastq`

补充说明：

- `PRISM_linux_bundle/repo/` 现在直接包含了 `00script/repo/` 的源码副本
- 复制时已经排除了 `.git` 等 git 元数据

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

包含：
- `environment_prism.yml`
  作用：创建 PRISM 所需的 conda 环境

作用总结：
- 安装 R 包、Kraken2/BLAST/宿主索引构建工具等基础依赖

### 2. `02_kraken`
Kraken2 / k2 数据库下载与构建。

包含：
- `download_prism_kraken2_sources.sh`
  作用：下载 PRISM 推荐 Kraken2 数据库的源数据
- `download_prism_kraken2_sources_retry.sh`
  作用：下载中断后自动自检并重试
- `build_prism_kraken2_recommended.sh`
  作用：基于已下载好的源数据构建最终 Kraken2 数据库
- `download_prackendb.sh`
  作用：并行下载官方提供的 PrackenDB 归档
- `unpack_prackendb.sh`
  作用：将 PrackenDB 解压到下游分析所需的标准目录

作用总结：
- 支持两种 Kraken2 数据准备方式
  1. 先下载源数据后自行构建
  2. 直接下载官方已构建数据库并解压

### 3. `03_blast`
BLAST / core_nt 数据库下载、解压与 map 生成。

包含：
- `download_prism_blast_core_nt_sources.sh`
  作用：并行下载 NCBI BLAST `core_nt` 分卷源文件，校验 md5，并自动解压到标准目录
- `unpack_prism_blast_core_nt_sources.sh`
  作用：当你已经把 `core_nt_archives` 从别的机器同步过来时，仅做校验与解压，不重新下载
- `generate_sorted_accession_map.sh`
  作用：基于标准目录中的 `core_nt` 数据库生成 `sorted_accession_map.txt`

作用总结：
- 支持两种 BLAST `core_nt` 数据准备方式
  1. 先下载源数据后自行准备
  2. 对已经同步好的 `core_nt_archives` 做单独解压

### 4. `04_host`
宿主参考与宿主索引。

包含：
- `download_prism_host_reference.sh`
  作用：下载宿主参考基因组源数据
- `build_prism_host_indexes.sh`
  作用：基于宿主源数据构建 Minimap2 和 STAR 索引
- `star_shared_memory_control.sh`
  作用：使用 STAR 原生 `--genomeLoad` 机制预加载或移除 shared memory 中的 genome index

作用总结：
- 为 PRISM 的多轮宿主去除步骤准备宿主参考索引
- 为多样本并行时的 STAR shared memory 复用提供控制入口

### 5. `05_analysis`
PRISM 分析与真菌结果提取。

包含：
- `run_prism_rnaseq_test.sh`
  作用：基于准备好的数据库与索引运行 PRISM 测试流程
- `run_prism_repo_testdata.sh`
  作用：使用 PRISM 仓库自带 `repo/test data/D18.fa` 做小型测试，将 FASTA 临时转换为 FASTQ 后调用当前 PRISM 资源与主流程
- `run_prism_samples_parallel_with_star_shared_memory.sh`
  作用：在 STAR shared memory 模式下按并发数调度多个样本并行运行
- `extract_fungal_abundance.R`
  作用：从 PRISM 最终结果中提取真菌 read、物种汇总和最终 FASTA

作用总结：
- 调用 PRISM 主流程
- 使用仓库自带测试数据快速验证当前环境、数据库和索引是否能跑通 PRISM
- 对最终结果做真菌专门提取
- 支持在预加载宿主索引后进行多样本并行调度

### 6. `06_docs`
中文说明文档。

包含：
- `PRISM_DATABASE_PREP_zh.md`
  作用：源码目录中的中文数据准备与运行说明

作用总结：
- 保存和 `README_zh.md` 对应的中文说明

### 7. `07_patch_installs`
Kraken2 PR #1015 修复版安装脚本。

包含：
- `install_kraken2_pr1015.sh`
  作用：在线安装 Kraken2 PR #1015 修复版
- `install_kraken2_pr1015_offline.sh`
  作用：离线安装 Kraken2 PR #1015 修复版

作用总结：
- 当标准环境中的 Kraken2 下载存在已知问题时，覆盖安装修复版

### 8. `08_transfer`
项目迁移脚本。

包含：
- `transfer_prism_project_to_new_server.sh`
  作用：使用 `rsync` 将整个项目目录传输到新的服务器，支持断点续传与可选镜像同步

作用总结：
- 在旧服务器和新服务器之间迁移整个 PRISM 项目

### 9. `00script` 根目录中的其他脚本

当前 `00script` 根目录还保留了其他脚本：

- `check_prism_required_data.sh`
  作用：检查当前项目目录下的数据库、宿主索引、`sorted_accession_map.txt` 和 `genbank` 是否齐全

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
- 分析脚本默认会给 Kraken2 加上 `--memory-mapping`
- 如果你想覆盖它，可以在运行前设置：

```bash
export KRAKEN2_EXTRA_OPTS="--memory-mapping"
```

或者改成别的 Kraken2 额外参数

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

### 3.1 下载机

```bash
bash ${PROJECT_ROOT}/00script/03_blast/download_prism_blast_core_nt_sources.sh
```

源数据目录：

```bash
${PROJECT_ROOT}/02ref/blast_sources/core_nt
```

### 3.2 服务器

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

### 4.3 可选：STAR shared memory 预加载

如果你计划并行运行多个样本，并希望多个 STAR 进程复用同一份宿主 genome index，可先执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
```

所有并行任务结束后，再执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
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

### Kraken2 额外参数说明

当前运行脚本默认会给 Kraken2 加上：

```bash
--memory-mapping
```

这样可以减少 Kraken2 在分类时一次性把整个数据库完整加载进内存的压力，适合内存较紧张的服务器环境。

如果你想显式指定或覆盖 Kraken2 的额外参数，可以在运行前设置环境变量：

```bash
export KRAKEN2_EXTRA_OPTS="--memory-mapping"
```

然后再执行：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh
```

如果你想关闭默认的内存映射，也可以设为空：

```bash
export KRAKEN2_EXTRA_OPTS=""
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh
```

如果你想在 `--memory-mapping` 基础上再追加其它 Kraken2 参数，也可以这样写：

```bash
export KRAKEN2_EXTRA_OPTS="--memory-mapping --quick"
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh
```

### 可选：多个样本并行运行（STAR shared memory）

如果你已经预加载了 STAR genome index，并准备好了一个样本列表文件（每行一个样本名），可以执行：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_star_shared_memory.sh sample_list.txt
```

该脚本会自动为每个样本设置：

```bash
STAR_GENOME_LOAD=LoadAndKeep
```

并按 `MAX_PARALLEL` 控制并发数。

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

## 11. 迁移到新服务器

如果你需要把整个 PRISM 项目从旧服务器同步到新服务器，可以先用 dry-run 预演：

```bash
bash ${PROJECT_ROOT}/00script/08_transfer/transfer_prism_project_to_new_server.sh \
  /home/data/vip0/project/11PRISM \
  ubuntu \
  ssh.sxqtx.com \
  /home/ubuntu/PRISM \
  13569 \
  --dry-run
```

确认无误后，再正式执行：

```bash
bash ${PROJECT_ROOT}/00script/08_transfer/transfer_prism_project_to_new_server.sh \
  /home/data/vip0/project/11PRISM \
  ubuntu \
  ssh.sxqtx.com \
  /home/ubuntu/PRISM \
  13569
```

如果你不能使用 SSH 免密登录，也可以直接把密码作为第 6 个参数传入（不推荐长期使用，因为密码会暴露在 shell 历史中）：

```bash
bash ${PROJECT_ROOT}/00script/08_transfer/transfer_prism_project_to_new_server.sh \
  /home/data/vip0/project/11PRISM \
  ubuntu \
  ssh.sxqtx.com \
  /home/ubuntu/PRISM \
  13569 \
  'your_password'
```

说明：

- 第 1 个参数：源目录
- 第 2 个参数：远端用户名
- 第 3 个参数：远端主机名/IP
- 第 4 个参数：远端目标目录
- 第 5 个参数：SSH 端口（这里是 `13569`）
- 第 6 个参数：可选，SSH 密码
- 第 7 个参数：可选，写 `--dry-run` 时只预演命令，不会真正传输
- 如果要用密码模式，系统需要安装 `sshpass`
