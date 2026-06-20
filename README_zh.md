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
- `run_prism_rnaseq.sh`
  作用：对单个真实 RNA-seq 样本运行 PRISM；会检查依赖和数据库路径，将 `${PROJECT_ROOT}/01rawdata` 中的成对 `.fastq.gz` 解压到 `${PROJECT_ROOT}/02fastq`，然后调用 PRISM 主流程。
- `run_prism_rnaseq_test.sh`
  作用：基于准备好的数据库与索引运行 PRISM 测试流程
- `run_prism_repo_testdata.sh`
  作用：使用 PRISM 仓库自带 `repo/test data/D18.fa` 做小型测试，将 FASTA 临时转换为 FASTQ 后调用当前 PRISM 资源与主流程
- `run_prism_samples_parallel_with_star_shared_memory.sh`
  作用：读取样本列表，按 `MAX_PARALLEL` 控制并发数，逐个调用 `run_prism_rnaseq.sh`，并在 STAR shared memory 模式下调度多个样本并行运行
- `run_prism_samples_parallel_with_serial_kraken2.sh`
  作用：读取样本列表，启动多个可重叠的 PRISM 样本任务，但通过全局 `flock` 锁保证同一时间只有一个样本执行 Kraken2；适合 `KRAKEN2_EXTRA_OPTS=""`、Kraken2 数据库完整加载到内存且服务器内存只能容纳一个 Kraken2 数据库的场景
- `run_prism_streaming_rsync_serial_kraken2.sh`
  作用：使用 `rsync` 从远程数据服务器按清单顺序流式同步样本；下载队列和计算队列相互独立，样本下载完成后进入 PRISM 计算队列，Kraken2 仍通过全局 `flock` 串行执行，单样本完成后删除该样本的 `.fastq.gz` 和解压后的 `.fastq` 输入文件，仅保留 PRISM 结果。
- `run_prism_streaming_baidupcs_serial_kraken2.sh`
  作用：使用 `BaiduPCS-Go` 从百度网盘按清单顺序流式下载样本；下载队列不等待计算队列，已下载样本进入 PRISM 计算队列，Kraken2 全局串行执行，单样本完成后清理该样本输入文件，仅保留结果。
- `extract_fungal_abundance.R`
  作用：从 PRISM 最终结果中提取真菌 read、物种汇总和最终 FASTA

作用总结：
- 对单个真实 RNA-seq 样本调用 PRISM 主流程
- 使用仓库自带测试数据快速验证当前环境、数据库和索引是否能跑通 PRISM
- 对最终结果做真菌专门提取
- 支持在预加载宿主索引后进行多样本并行调度；并行时每个样本独立输出到 `${PROJECT_ROOT}/02fastq/<sample>_prism`
- 支持多样本重叠运行但 Kraken2 串行执行，使 Kraken2 充分加载内存运行，同时让前一个样本的下游步骤和后一个样本的 Kraken2 步骤衔接起来
- 支持边下载边计算：通过 `rsync` 或 `BaiduPCS-Go` 流式获取样本，下载完成的样本立即进入计算队列，计算追上下载时自动等待下一个样本下载完成，并在每个样本完成后释放输入文件占用的磁盘空间

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

### 7.1 单个真实 RNA-seq 样本

正式运行真实 RNA-seq 样本时，建议使用：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

也可以通过环境变量传入样本名：

```bash
SAMPLE=FUSCCTNBC001 bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
```

默认情况下，脚本会读取：

```bash
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R1.fastq.gz
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R2.fastq.gz
```

并解压生成：

```bash
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_RNAseq_R1.fastq
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_RNAseq_R2.fastq
```

PRISM 输出目录为：

```bash
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_prism
```

主要结果文件为：

```bash
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_prism/FUSCCTNBC001-counts.csv
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_prism/FUSCCTNBC001-results.csv
${PROJECT_ROOT}/02fastq/FUSCCTNBC001_prism/data/FUSCCTNBC001_PRISM.log
```

如果你的输入文件后缀不是 `_RNAseq_R1.fastq.gz` / `_RNAseq_R2.fastq.gz`，可以在运行前覆盖：

```bash
export FQ1_END="_R1.fastq"
export FQ2_END="_R2.fastq"
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

这里的规则是：脚本会寻找 `${SAMPLE}${FQ1_END}.gz` 和 `${SAMPLE}${FQ2_END}.gz`。

### 7.2 测试运行

如果只是想用测试脚本验证数据库、索引和环境是否能跑通，可以执行：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq_test.sh
```

### 7.3 Kraken2 额外参数说明

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
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

如果你想关闭默认的内存映射，也可以设为空：

```bash
export KRAKEN2_EXTRA_OPTS=""
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

如果你想在 `--memory-mapping` 基础上再追加其它 Kraken2 参数，也可以这样写：

```bash
export KRAKEN2_EXTRA_OPTS="--memory-mapping --quick"
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

### 7.4 多个样本并行运行（STAR shared memory）

多样本并行运行时，推荐保持 PRISM 主流程为“单样本一次运行”，由外层脚本读取样本列表并调度多个样本。并行脚本会逐个调用：

```bash
${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
```

#### 7.4.1 准备样本列表

样本列表每行写一个样本名前缀，不写 FASTQ 后缀。空行和以 `#` 开头的注释行会被忽略。

```bash
cat > sample_list.txt <<EOF
FUSCCTNBC001
FUSCCTNBC002
FUSCCTNBC003
EOF
```

每个样本默认需要对应以下输入文件：

```bash
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R1.fastq.gz
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R2.fastq.gz
```

如果你的文件后缀不同，可以在并行运行前统一设置：

```bash
export FQ1_END="_R1.fastq"
export FQ2_END="_R2.fastq"
```

#### 7.4.2 建议先做单样本验证

正式并行前，建议先挑一个样本确认输入、数据库、软件路径和 PRISM 主流程都正常：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

#### 7.4.3 预加载 STAR shared memory

如果希望多个并行 STAR 进程复用同一份宿主 genome index，先执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
```

并行脚本会自动为每个样本设置：

```bash
STAR_GENOME_LOAD=LoadAndKeep
```

因此单个样本进入 STAR 步骤时会复用已经加载到 shared memory 的索引。

#### 7.4.4 设置并发数和线程数

`MAX_PARALLEL` 控制同时运行多少个样本，`PRISM_THREADS` 控制每个样本内部传给 Kraken2 / Minimap2 / BLAST 等工具的线程数。

建议先保守运行：

```bash
export MAX_PARALLEL=2
export PRISM_THREADS=8
export KRAKEN2_EXTRA_OPTS="--memory-mapping"
export USE_CUSTOM_DB=FALSE
```

总线程压力大致可以按下面估算：

```bash
MAX_PARALLEL × PRISM_THREADS
```

如果服务器内存、CPU 和磁盘 I/O 都稳定，再逐步提高 `MAX_PARALLEL` 或 `PRISM_THREADS`。

#### 7.4.5 启动并行运行

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_star_shared_memory.sh sample_list.txt
```

如果有样本失败，脚本会在最后返回非零退出码，并提示对应样本日志。

#### 7.4.6 运行结束后释放 STAR shared memory

所有并行任务结束后，执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
```

#### 7.4.7 查看结果和日志

每个样本的最终结果位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-counts.csv
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-results.csv
```

每个样本的 PRISM 主流程日志位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/data/<sample>_PRISM.log
```

并行调度脚本的样本级日志位于：

```bash
${PROJECT_ROOT}/02fastq/parallel_logs/<sample>.log
```

### 7.5 多个样本重叠运行，但 Kraken2 串行执行

如果服务器内存只能容纳一个完整加载的 Kraken2 数据库，但你又希望 Kraken2 不使用 `--memory-mapping`、而是完整加载到内存以提高分类速度，推荐使用：

```bash
${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_serial_kraken2.sh
```

这个脚本的调度逻辑是：

1. 多个样本的 PRISM 进程可以重叠存在。
2. 所有样本共用一个 Kraken2 锁，同一时间只有一个样本真正执行 Kraken2。
3. 第一个样本完成 Kraken2 后会继续运行 Minimap2、STAR、BLAST 和后续 PRISM profiling。
4. 第二个样本会在第一个样本 Kraken2 结束后立即获得锁并开始 Kraken2。

这样可以避免多个 Kraken2 同时加载数据库导致内存不足，同时减少 Kraken2 步骤之间的空窗时间。

#### 7.5.1 准备样本列表

样本列表每行写一个样本名前缀，不写 FASTQ 后缀。空行和以 `#` 开头的注释行会被忽略。

```bash
cat > sample_list.txt <<EOF
FUSCCTNBC001
FUSCCTNBC002
FUSCCTNBC003
EOF
```

每个样本默认需要对应以下输入文件：

```bash
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R1.fastq.gz
${PROJECT_ROOT}/01rawdata/FUSCCTNBC001_RNAseq_R2.fastq.gz
```

如果你的文件后缀不同，可以在运行前统一设置：

```bash
export FQ1_END="_R1.fastq"
export FQ2_END="_R2.fastq"
```

#### 7.5.2 建议先做单样本验证

正式重叠运行前，建议先挑一个样本确认输入、数据库、软件路径和 PRISM 主流程都正常：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh FUSCCTNBC001
```

#### 7.5.3 预加载 STAR shared memory

如果希望多个 STAR 进程复用同一份宿主 genome index，先执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
```

`run_prism_samples_parallel_with_serial_kraken2.sh` 默认会给每个样本设置：

```bash
STAR_GENOME_LOAD=LoadAndKeep
```

因此该脚本可以和 `star_shared_memory_control.sh load` 衔接使用。

#### 7.5.4 设置 Kraken2 完整加载和重叠运行参数

如果要让 Kraken2 完整加载数据库到内存，运行前设置：

```bash
export KRAKEN2_EXTRA_OPTS=""
```

推荐先使用下面的保守参数：

```bash
export PRISM_THREADS=16
export MAX_ACTIVE_JOBS=4
export KRAKEN2_QUEUE_DEPTH=2
export USE_CUSTOM_DB=FALSE
export KRAKEN2_EXTRA_OPTS=""
```

参数含义：

- `PRISM_THREADS`：每个样本内部传给 PRISM 外部工具的线程数。
- `MAX_ACTIVE_JOBS`：最多允许多少个 PRISM 样本进程同时存在。
- `KRAKEN2_QUEUE_DEPTH`：保持多少个样本排在 Kraken2 前后，用来减少 Kraken2 空窗；默认 `2`。
- `KRAKEN2_EXTRA_OPTS=""`：关闭 `--memory-mapping`，让 Kraken2 完整加载数据库。

注意：Kraken2 本身由脚本加锁串行执行，所以不会因为 `MAX_ACTIVE_JOBS > 1` 而同时启动多个 Kraken2。

#### 7.5.5 启动重叠运行

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_serial_kraken2.sh sample_list.txt
```

如果有样本失败，脚本会在最后返回非零退出码，并提示对应样本日志。

#### 7.5.6 运行结束后释放 STAR shared memory

所有任务结束后，执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
```

#### 7.5.7 查看结果和日志

每个样本的最终结果位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-counts.csv
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-results.csv
```

每个样本的 PRISM 主流程日志位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/data/<sample>_PRISM.log
```

重叠运行脚本的样本级日志位于：

```bash
${PROJECT_ROOT}/02fastq/serial_kraken2_logs/<run_id>/<sample>.log
```

日志中如果看到下面的信息，说明 Kraken2 串行锁正在生效：

```bash
[KRAKEN2-LOCK] <sample> waiting for Kraken2 lock
[KRAKEN2-LOCK] <sample> acquired Kraken2 lock
[KRAKEN2-LOCK] <sample> released Kraken2 lock
```

#### 7.5.8 换行符检查

如果脚本从 Windows 同步到 Linux 后出现下面这类报错：

```bash
$'\r': command not found
set: pipefail: invalid option name
```

说明 shell 脚本仍是 Windows CRLF 换行。请在服务器上执行：

```bash
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_serial_kraken2.sh
```

如果服务器没有 `dos2unix`，可以用：

```bash
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_serial_kraken2.sh
```

然后检查语法：

```bash
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_samples_parallel_with_serial_kraken2.sh
```

### 7.6 rsync 边下载边计算，并保持 Kraken2 串行执行

如果服务器硬盘空间有限，不适合一次性把所有样本下载到 `${PROJECT_ROOT}/01rawdata`，推荐使用：

```bash
${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_rsync_serial_kraken2.sh
```

这个脚本的调度逻辑是：

1. 下载队列和计算队列相互独立。
2. 下载队列按清单顺序持续下载样本，不等待计算完成。
3. 一个样本的 R1/R2 两个 `.fastq.gz` 都同步完成后，该样本立即进入计算队列。
4. 如果下载速度慢、计算追上下载进度，计算队列会自动等待下一个样本下载完成。
5. Kraken2 仍然通过全局 `flock` 锁串行执行，同一时间只有一个样本运行 Kraken2。
6. 每个样本计算结束后，脚本会删除该样本下载的 `.fastq.gz` 和解压后的 `.fastq` 输入文件，只保留 PRISM 结果。

#### 7.6.1 准备远程样本路径清单

清单文件每行写一个远程样本目录，或者写一个远程 FASTQ.GZ 文件路径。空行和以 `#` 开头的注释行会被忽略。

推荐写远程样本目录：

```bash
cat > remote_sample_dirs.txt <<EOF
/data/rnaseq/FUSCCTNBC001
/data/rnaseq/FUSCCTNBC002
/data/rnaseq/FUSCCTNBC006.rep
EOF
```

默认情况下，每个远程样本目录中需要有：

```bash
<sample>_RNAseq_R1.fastq.gz
<sample>_RNAseq_R2.fastq.gz
```

例如样本名为 `FUSCCTNBC006.rep` 时，脚本会寻找：

```bash
/data/rnaseq/FUSCCTNBC006.rep/FUSCCTNBC006.rep_RNAseq_R1.fastq.gz
/data/rnaseq/FUSCCTNBC006.rep/FUSCCTNBC006.rep_RNAseq_R2.fastq.gz
```

因此样本名中包含点号 `.` 不影响识别；关键是远程目录名和 FASTQ 文件名前缀要一致。

如果你的清单写的是 FASTQ 文件路径，也可以只写 R1 或 R2 中任意一个，脚本会自动取其所在目录并推断样本名：

```bash
cat > remote_sample_dirs.txt <<EOF
/data/rnaseq/FUSCCTNBC001/FUSCCTNBC001_RNAseq_R1.fastq.gz
/data/rnaseq/FUSCCTNBC002/FUSCCTNBC002_RNAseq_R1.fastq.gz
EOF
```

如果 FASTQ 后缀不是默认的 `_RNAseq_R1.fastq.gz` 和 `_RNAseq_R2.fastq.gz`，运行前统一设置：

```bash
export FQ1_END="_R1.fastq"
export FQ2_END="_R2.fastq"
```

#### 7.6.2 先确认 rsync/ssh 能连通远程服务器

当前远程服务器和 SSH 参数推荐这样测试：

```bash
ssh -p 25061 -i ~/.ssh/id_ed25519_rsync_A -o BatchMode=yes -o ConnectTimeout=10 ubuntu@biotrainee.cn "echo SSH_OK"
```

如果这一步需要输入密码，说明证书免密登录还没有配置好。脚本可以运行，但长任务中更推荐先配好免密登录。

如果报错，使用以下命令输出日志：

```bash
ssh -vvv -p 25061 -i ~/.ssh/id_ed25519_rsync_A ubuntu@biotrainee.cn
```

#### 7.6.3 设置运行参数

在正式运行前，建议先设置以下变量：

```bash
export PROJECT_ROOT=/your/path/to/PRISM

export RSYNC_REMOTE=ubuntu@biotrainee.cn
export RSYNC_SSH_PORT=25061
export RSYNC_SSH_OPTS="-i ~/.ssh/id_ed25519_rsync_A"
export RSYNC_OPTS="-av --partial --append-verify --info=progress2 --timeout=600"
export PARALLEL_MATES=TRUE

export USE_CUSTOM_DB=FALSE
export KRAKEN2_EXTRA_OPTS=""
export STAR_GENOME_LOAD=LoadAndKeep

export PRISM_THREADS=16
export MAX_ACTIVE_JOBS=4
export KRAKEN2_QUEUE_DEPTH=2
```

rsync 相关参数含义：

- `RSYNC_REMOTE`：远程服务器登录前缀，这里是 `ubuntu@biotrainee.cn`。
- `RSYNC_SSH_PORT`：远程 SSH 端口，这里是 `25061`。
- `RSYNC_SSH_OPTS`：传给 `ssh` 的额外参数，这里用 `-i ~/.ssh/id_ed25519_rsync_A` 指定 rsync 专用证书。
- `RSYNC_OPTS`：传给 `rsync` 的参数；`--partial` 和 `--append-verify` 支持断点续传，`--info=progress2` 显示整体传输进度，`--timeout=600` 避免长时间无响应。
- `PARALLEL_MATES=TRUE`：同一个样本的 R1 和 R2 两个文件同时下载；如果远程服务器或网络压力较大，可以改成 `FALSE`。

计算相关参数含义：

- `USE_CUSTOM_DB=FALSE`：直接使用完整 BLAST 数据库，不构建临时 custom BLAST 数据库；这是当前推荐设置。
- `KRAKEN2_EXTRA_OPTS=""`：不使用 `--memory-mapping`，让 Kraken2 完整加载数据库到内存。
- `PRISM_THREADS`：每个样本运行给予的线程数。
- `MAX_ACTIVE_JOBS`：最多允许多少个 PRISM 样本进程同时存在。
- `KRAKEN2_QUEUE_DEPTH`：允许多少个已就绪样本排在 Kraken2 前后；默认建议 `2`，用于减少 Kraken2 空窗时间。

`--use_custom_db` 问题说明：在失败样本 resume 排查中，`FUSCCTNBC003` 使用 `--use_custom_db TRUE` 时，subsample BLAST 结果文件中的 `staxids` 列全部为 `0`。PRISM 后续依赖 `staxids` 将 BLAST 命中匹配回 Kraken/MPA 的微生物 taxid；当 `staxids` 全为 `0` 时，`prism_filter()` 会把所有 BLAST 命中视为非目标微生物命中，multimapping 阶段得不到任何 uniquely identifiable microbial species，最终写出空的 `results.csv` 和 `counts.csv`。同一样本改用 `--use_custom_db FALSE` 后可以得到结果，说明该零结果来自 custom BLAST DB 的 accession-to-taxid 映射问题，而不是样本本身没有微生物信号。因此常规运行、失败样本 resume 和 streaming 下载分析均建议设置为 `FALSE`；只有确认 custom DB 生成的 taxid map 非空且 BLAST 输出真实 NCBI taxid 后，再考虑开启 `TRUE`。

#### 7.6.4 可选：预加载 STAR shared memory

如果希望多个 STAR 进程复用同一份宿主 genome index，运行前执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
```

该 streaming 脚本默认会向单样本 PRISM 流程传递：

```bash
STAR_GENOME_LOAD=LoadAndKeep
```

所以可以和 `star_shared_memory_control.sh load` 衔接使用。

#### 7.6.5 启动 rsync 边下载边计算

确认 `remote_sample_dirs.txt` 准备好后执行：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_rsync_serial_kraken2.sh remote_sample_dirs.txt
```

运行过程中，脚本会把远程文件同步到：

```bash
${PROJECT_ROOT}/01rawdata
```

然后由 `run_prism_rnaseq.sh` 解压并计算，输出仍然位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism
```

#### 7.6.6 查看结果和日志

每个样本的最终结果位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-counts.csv
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-results.csv
```

每个样本的 PRISM 主流程日志位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/data/<sample>_PRISM.log
```

streaming rsync 调度日志位于：

```bash
${PROJECT_ROOT}/02fastq/streaming_rsync_serial_kraken2_logs/<run_id>/
```

其中：

- `<sample>.prism.log`：该样本外层 PRISM 调度日志。
- `downloads/<sample>.rsync.log`：该样本 rsync 下载日志。
- `kraken2_events/`：Kraken2 串行锁事件记录。
- `download_ready/`：已下载完成、可以进入计算队列的样本标记。
- `download_failed/`：下载失败的样本标记。

日志中如果看到下面的信息，说明 Kraken2 串行锁正在生效：

```bash
[KRAKEN2-LOCK] <sample> waiting for Kraken2 lock
[KRAKEN2-LOCK] <sample> acquired Kraken2 lock
[KRAKEN2-LOCK] <sample> released Kraken2 lock
```

#### 7.6.7 运行结束后释放 STAR shared memory

所有任务结束后，执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
```

#### 7.6.8 换行符检查

如果脚本从 Windows 同步到 Linux 后出现下面这类报错：

```bash
$'\r': command not found
set: pipefail: invalid option name
```

说明 shell 脚本仍是 Windows CRLF 换行。请在服务器上执行：

```bash
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_rsync_serial_kraken2.sh
```

如果服务器没有 `dos2unix`，可以用：

```bash
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_rsync_serial_kraken2.sh
```

然后检查语法：

```bash
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_rsync_serial_kraken2.sh
```

### 7.7 BaiduPCS-Go 边下载边计算，并保持 Kraken2 串行执行

如果原始 RNA-seq 数据保存在百度网盘上，且服务器硬盘空间有限，不适合一次性把所有样本全部下载到 `${PROJECT_ROOT}/01rawdata`，可以使用：

```bash
${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_baidupcs_serial_kraken2.sh
```

这个脚本的调度逻辑是：

1. 下载队列和计算队列是分开的两个队列。
2. 下载队列按清单顺序持续调用 `BaiduPCS-Go` 下载样本，不等待计算队列完成。
3. 一个样本的 R1/R2 两个 `.fastq.gz` 都下载完成后，该样本立即进入 PRISM 计算队列。
4. 如果下载速度慢、计算进度追上下载进度，计算队列会暂停等待，直到下一个样本下载完成后再启动新的计算。
5. Kraken2 仍然通过全局 `flock` 锁串行执行，同一时间只有一个样本运行 Kraken2。
6. 每个样本计算结束后，脚本会删除该样本下载的 `.fastq.gz` 和解压后的 `.fastq` 输入文件，只保留 PRISM 结果。

#### 7.7.1 准备百度网盘样本路径清单

清单文件每行写一个百度网盘样本目录，或者写一个百度网盘 FASTQ.GZ 文件路径。空行和以 `#` 开头的注释行会被忽略。

推荐写样本目录：

```bash
cat > baidu_sample_paths.txt <<EOF
/RNAseq/FUSCCTNBC001
/RNAseq/FUSCCTNBC002
/RNAseq/FUSCCTNBC003
EOF
```

默认情况下，每个样本目录中需要有：

```bash
<sample>_RNAseq_R1.fastq.gz
<sample>_RNAseq_R2.fastq.gz
```

例如样本名为 `FUSCCTNBC001` 时，脚本会下载：

```bash
/RNAseq/FUSCCTNBC001/FUSCCTNBC001_RNAseq_R1.fastq.gz
/RNAseq/FUSCCTNBC001/FUSCCTNBC001_RNAseq_R2.fastq.gz
```

也可以只在清单中写 R1 或 R2 中任意一个 FASTQ.GZ 文件路径，脚本会自动取其所在目录并推断样本名：

```bash
cat > baidu_sample_paths.txt <<EOF
/RNAseq/FUSCCTNBC001/FUSCCTNBC001_RNAseq_R1.fastq.gz
/RNAseq/FUSCCTNBC002/FUSCCTNBC002_RNAseq_R1.fastq.gz
EOF
```

如果 FASTQ 后缀不是默认的 `_RNAseq_R1.fastq.gz` 和 `_RNAseq_R2.fastq.gz`，运行前统一设置：

```bash
export FQ1_END="_R1.fastq"
export FQ2_END="_R2.fastq"
```

这里的规则是：脚本会寻找 `${SAMPLE}${FQ1_END}.gz` 和 `${SAMPLE}${FQ2_END}.gz`。

#### 7.7.2 确认 BaiduPCS-Go 可用

运行前需要先在服务器上准备好 `BaiduPCS-Go`，并确认已经登录百度网盘账号。

可以把 `BaiduPCS-Go` 放在脚本同目录：

```bash
${PROJECT_ROOT}/00script/05_analysis/BaiduPCS-Go
```

也可以在运行前显式指定：

```bash
export BAIDUPCS=/path/to/BaiduPCS-Go
```

建议先手动测试能否访问网盘路径，例如：

```bash
${BAIDUPCS} ls "/RNAseq"
```

如果这一步提示未登录或权限不足，需要先用 `BaiduPCS-Go` 完成登录和路径确认，再启动长任务。

#### 7.7.3 设置运行参数

在正式运行前，建议先设置以下变量：

```bash
export PROJECT_ROOT=/your/path/to/PRISM

export BAIDUPCS=/path/to/BaiduPCS-Go
export BAIDUPCS_DOWNLOAD_OPTS="--ow -p 8"

export USE_CUSTOM_DB=FALSE
export KRAKEN2_EXTRA_OPTS=""
export STAR_GENOME_LOAD=LoadAndKeep

export PRISM_THREADS=16
export MAX_ACTIVE_JOBS=4
export KRAKEN2_QUEUE_DEPTH=2
```

BaiduPCS-Go 相关参数含义：

- `BAIDUPCS`：`BaiduPCS-Go` 可执行文件路径；如果不设置，脚本会优先查找脚本同目录下的 `BaiduPCS-Go`，然后查找 PATH。
- `BAIDUPCS_DOWNLOAD_OPTS`：传给 `BaiduPCS-Go d` 的下载参数；默认是 `--ow`，表示覆盖已有同名文件。可以按网络情况追加并发、重试等参数，例如 `--ow -p 8`。

计算相关参数含义：

- `USE_CUSTOM_DB=FALSE`：直接使用完整 BLAST 数据库，不构建临时 custom BLAST 数据库；这是当前推荐设置。
- `KRAKEN2_EXTRA_OPTS=""`：不使用 `--memory-mapping`，让 Kraken2 完整加载数据库到内存。
- `MAX_ACTIVE_JOBS`：最多允许多少个 PRISM 样本进程同时存在。
- `KRAKEN2_QUEUE_DEPTH`：允许多少个已下载完成的样本排在 Kraken2 前后；默认建议 `2`，用于减少 Kraken2 空窗时间。

`--use_custom_db` 问题说明同上：若临时 custom BLAST DB 的 accession-to-taxid 映射失败，BLAST 输出的 `staxids` 可能全部变成 `0`，造成 PRISM 假性零结果。对 streaming 下载和 resume 任务，建议保持 `USE_CUSTOM_DB=FALSE`。

#### 7.7.4 可选：预加载 STAR shared memory

如果希望多个 STAR 进程复用同一份宿主 genome index，运行前执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh load
```

该 streaming 脚本默认会向单样本 PRISM 流程传递：

```bash
STAR_GENOME_LOAD=LoadAndKeep
```

所以可以和 `star_shared_memory_control.sh load` 衔接使用。

#### 7.7.5 启动 BaiduPCS-Go 边下载边计算

确认 `baidu_sample_paths.txt` 准备好后执行：

```bash
bash ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_baidupcs_serial_kraken2.sh baidu_sample_paths.txt
```

运行过程中，脚本会把百度网盘文件下载到：

```bash
${PROJECT_ROOT}/01rawdata
```

然后由 `run_prism_rnaseq.sh` 解压并计算，输出仍然位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism
```

#### 7.7.6 查看结果和日志

每个样本的最终结果位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-counts.csv
${PROJECT_ROOT}/02fastq/<sample>_prism/<sample>-results.csv
```

每个样本的 PRISM 主流程日志位于：

```bash
${PROJECT_ROOT}/02fastq/<sample>_prism/data/<sample>_PRISM.log
```

streaming BaiduPCS-Go 调度日志位于：

```bash
${PROJECT_ROOT}/02fastq/streaming_baidupcs_serial_kraken2_logs/<run_id>/
```

其中：

- `<sample>.prism.log`：该样本外层 PRISM 调度日志。
- `downloads/<sample>.baidupcs.log`：该样本 BaiduPCS-Go 下载日志。
- `kraken2_events/`：Kraken2 串行锁事件记录。
- `download_done/`：已下载完成、可以进入计算队列的样本标记。
- `download_failed/`：下载失败的样本标记。

日志中如果看到下面的信息，说明 Kraken2 串行锁正在生效：

```bash
[KRAKEN2-LOCK] <sample> waiting for Kraken2 lock
[KRAKEN2-LOCK] <sample> acquired Kraken2 lock
[KRAKEN2-LOCK] <sample> released Kraken2 lock
```

#### 7.7.7 运行结束后释放 STAR shared memory

所有任务结束后，执行：

```bash
bash ${PROJECT_ROOT}/00script/04_host/star_shared_memory_control.sh remove
```

#### 7.7.8 换行符检查

如果脚本从 Windows 同步到 Linux 后出现下面这类报错：

```bash
$'\r': command not found
set: pipefail: invalid option name
```

说明 shell 脚本仍是 Windows CRLF 换行。请在服务器上执行：

```bash
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
dos2unix ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_baidupcs_serial_kraken2.sh
```

如果服务器没有 `dos2unix`，可以用：

```bash
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
sed -i 's/\r$//' ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_baidupcs_serial_kraken2.sh
```

然后检查语法：

```bash
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_rnaseq.sh
bash -n ${PROJECT_ROOT}/00script/05_analysis/run_prism_streaming_baidupcs_serial_kraken2.sh
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
