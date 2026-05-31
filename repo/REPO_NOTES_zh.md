# PRISM 仓库说明

## 这个仓库是什么

PRISM 是一个生物信息学分析流水线，用来在测序数据中识别“真实存在”的微生物物种，同时尽量过滤污染物和假阳性结果。

它不是一个 Web 项目，也不是以库为核心的工程。这个仓库本质上是一个以 `R` 命令行脚本为入口的分析流水线，主入口是 `PRISM.R`。

整个流程组合了以下组件：

- `Kraken2`：初步做快速物种分类
- `Minimap2`：去除宿主 reads
- `STAR`：进一步去除宿主 reads
- `BLAST`：做更精确的序列比对
- `GenBank` 注释：补充基因和产物信息
- 预训练的 `XGBoost` 模型 `prismxg.RDS`：给候选物种打分，判断更像真实存在还是污染

根据 README，PRISM 目标支持的数据类型包括：

- `RNA-seq`
- `WGS`
- `16S-seq`
- `scRNA-seq`

## 主入口

- `PRISM.R`：命令行驱动脚本
- `functions.R`：核心流水线实现

`PRISM.R` 负责：

- 解析命令行参数
- 校验必要输入
- 创建输出目录
- 加载 `functions.R`
- 按顺序执行整条分析流程

## 高层流程

`PRISM.R` 中的主流程大致分为 12 步：

1. 运行 `Kraken2`
2. 用 `Minimap2` 做宿主去除
3. 用 `STAR` 再做一轮宿主去除
4. 按 taxid 对候选微生物 reads 做下采样
5. 对下采样 reads 运行 `BLAST`
6. 做 multi-mapping 分析，找出“可唯一识别”的物种
7. 对完整保留 reads 集合再运行正式 `BLAST`
8. 过滤非微生物 / 人源 / 低质量命中
9. 合并 `GenBank` 基因与产物注释
10. 构造特征并运行 PRISM 机器学习模型
11. 保存最终 CSV 输出
12. 生成最终 PRISM FASTA 文件

## 关键函数

`functions.R` 中最核心的函数有：

- `prism_kraken`：运行 Kraken2、生成报告、提取微生物 reads
- `prism_minimap`：用 Minimap2 去除宿主比对 reads
- `prism_star`：用 STAR 去除宿主比对 reads
- `prism_subsample`：按 taxid 对候选微生物 reads 下采样
- `prism_blast`：对下采样或完整 reads 运行 BLAST
- `prism_multimapping`：识别具有足够唯一比对 reads 的物种
- `prism_filter`：保留高质量微生物 BLAST 命中，去掉 human/other
- `prism_genbank`：按区间把 BLAST 命中接上 GenBank 的基因/产物注释
- `prism_profile`：构造按物种聚合的特征并调用 XGBoost 模型
- `prism_FASTA`：写出最终保留微生物 reads 的 FASTA

## 重要文件

- `README.md`：使用与安装说明
- `README.Rmd`：README 的源文件
- `PRISM.R`：命令行入口
- `functions.R`：绝大部分核心逻辑实现
- `kreport2mpa.py`：把 Kraken 报告转换为 MPA 风格的辅助脚本
- `prismxg.RDS`：预训练 XGBoost 模型
- `model_org_taxids.txt`：模型生物 taxid 列表
- `test data/`：示例输出和测试数据
- `tests/testthat/`：部分单元测试和集成测试

## 输入与外部依赖

这个仓库没有把运行依赖全部打包进来。它要求调用者自己提供外部工具路径和参考数据路径。

README 中列出的外部工具依赖：

- `Kraken2`
- `Minimap2`
- `STAR`
- `BLAST+`
- `SeqKit`
- R 包：`optparse`、`ShortRead`、`tidyverse`、`furrr`、`data.table`、`vegan`

流水线运行还依赖以下外部数据库或索引：

- Kraken2 数据库
- Minimap2 的宿主 `.mmi` 索引
- STAR 的宿主基因组索引
- BLAST 数据库
- 单独下载的 `genbank/` 注释目录
- 一次性预处理得到的 `sorted_accession_map.txt`

当前克隆下来的仓库里并不包含 `genbank/` 目录，所以它现在并不能直接端到端运行，还需要额外下载数据资源。

## 输出结果

仓库说明中的主要输出有：

- `X-results.csv`：read 级别最终结果，包含分类、比对、注释和 PRISM 分数
- `X-counts.csv`：物种级别汇总，包含 read 数和预测分数
- `X_1.fa` 以及可选的 `X_2.fa`：最终保留的微生物 reads FASTA

此外，流水线还会在样本输出目录中保存大量中间文件和日志文件，例如 `sample_PRISM.log`。

## 代码结构观察

这是一个比较典型的科研型代码仓库，工程化程度中等，特点比较明显：

- 绝大部分逻辑都集中在一个大的 `functions.R`
- 调度逻辑集中在一个入口脚本里
- 大量步骤通过 `system(...)` 调用外部命令
- 通过输出文件是否存在来决定是否跳过某一步，支持断点续跑

优点是流程直观，读起来不绕。缺点是实现会比较依赖目录结构、文件名约定和外部二进制工具。

## 测试情况

仓库里有 `testthat` 测试，位于 `tests/testthat/`，目前主要覆盖：

- 部分函数的输入校验
- BLAST 过滤逻辑
- multi-mapping 逻辑
- 一些纯 R 逻辑的合成集成测试

从当前内容看，它并没有完整覆盖整条依赖外部工具的端到端流程。

## 我识别到的风险点

阅读代码后，我认为有几个比较明显的实现风险：

1. `PRISM.R` 中 `model_org_taxids` 的默认处理看起来可疑。
   CLI 默认值是 `"NA"`，代码会把它拼成 `paste0(prism_path, opt$model_org_taxids)`，结果更像是 `.../NA`，而不是仓库自带的 `model_org_taxids.txt`。

2. 一些函数依赖全局变量，而不是只依赖显式传参。
   例如 `prism_path`、`kr_report`、`mpa` 这些值在部分函数里不是通过参数完整传入，而是依赖外部环境，这会让测试和复用更脆弱。

3. `prism_star` 在主流程里接收了 `id_df`，但 `id_df` 是后面的步骤才创建的。
   当前之所以没出问题，主要是因为 `prism_star` 实际上并没有真正使用这个参数。

4. 运行环境门槛比较高。
   想完整跑通，需要多个外部生信工具、大型数据库、宿主索引，以及单独下载的 GenBank 资源。

5. 代码里有较多通过字符串拼接生成的 shell 命令。
   这对科研流水线来说很常见，也很实用，但从可维护性和可移植性上看风险会更高。

## 一句话总结

如果只用一句话来概括这个仓库：

PRISM 是一个由 R 驱动的微生物筛选与打分流水线，它结合快速物种分类、宿主去除、BLAST 精比对、GenBank 注释和预训练机器学习模型，用来把测序数据中的真实微生物信号和污染信号区分开来。
