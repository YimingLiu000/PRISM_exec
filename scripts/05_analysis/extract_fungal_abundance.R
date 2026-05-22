#!/usr/bin/env Rscript

# 用途：
# 1. 基于 taxonomy 中的 taxid 层级关系，从 PRISM 最终结果中筛出真菌
# 2. 输出真菌物种汇总表
# 3. 输出真菌 read 级结果表
# 4. 从 PRISM 最终 FASTA 中提取真菌序列
#
# 输入：
# 1. <sample>-results.csv
# 2. 可选的 <sample>-counts.csv（本脚本不依赖它做过滤）
# 3. <sample>_1.fa 和可选的 <sample>_2.fa
# 4. Kraken2 taxonomy 中的 nodes.dmp
#
# 输出：
# 1. <sample>-fungi-results.csv
# 2. <sample>-fungi-counts.csv
# 3. <sample>-fungi_1.fa
# 4. 可选的 <sample>-fungi_2.fa
#
# 说明：
# 1. 真菌判定基于 taxid 是否属于 Fungi (taxid 4751) 的后代节点
# 2. 不再使用名称关键词列表
# 3. 如果最终没有任何真菌结果，也会写出空表和空 FASTA

suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(ShortRead))

get_project_root <- function() {
  env_root <- Sys.getenv("PROJECT_ROOT", unset = "")
  if (nzchar(env_root) && dir.exists(env_root)) {
    return(normalizePath(env_root))
  }

  script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(script_arg) > 0) {
    script_file <- normalizePath(sub("^--file=", "", script_arg[1]))
    script_dir <- dirname(script_file)
    candidates <- c(
      normalizePath(file.path(script_dir, ".."), mustWork = FALSE),
      normalizePath(file.path(script_dir, "..", ".."), mustWork = FALSE),
      file.path(Sys.getenv("HOME"), "PRISM")
    )
    for (cand in candidates) {
      if (dir.exists(file.path(cand, "00script", "repo"))) {
        return(normalizePath(cand))
      }
    }
  }

  fallback <- file.path(Sys.getenv("HOME"), "PRISM")
  return(normalizePath(fallback, mustWork = FALSE))
}

load_fungal_taxids <- function(nodes_file, fungal_root = "4751") {
  if (!file.exists(nodes_file)) {
    stop("找不到 nodes.dmp: ", nodes_file)
  }

  lines <- readLines(nodes_file, warn = FALSE)
  split_line <- strsplit(lines, "\\|", fixed = FALSE)
  taxid <- trimws(vapply(split_line, `[`, character(1), 1))
  parent <- trimws(vapply(split_line, `[`, character(1), 2))

  children <- split(taxid, parent)
  fungal_taxids <- fungal_root
  queue <- fungal_root

  while (length(queue) > 0) {
    cur <- queue[[1]]
    queue <- queue[-1]
    child_vec <- children[[cur]]
    if (length(child_vec) == 0) {
      next
    }
    new_children <- setdiff(child_vec, fungal_taxids)
    if (length(new_children) > 0) {
      fungal_taxids <- c(fungal_taxids, new_children)
      queue <- c(queue, new_children)
    }
  }

  unique(as.character(fungal_taxids))
}

extract_fasta_by_ids <- function(in_fasta, out_fasta, keep_ids) {
  if (!file.exists(in_fasta)) {
    return(FALSE)
  }

  fa <- ShortRead::readFasta(in_fasta)
  hdr <- as.character(ShortRead::id(fa))
  ids <- sub("\\s.*", "", hdr)
  fa_keep <- fa[ids %in% keep_ids]
  ShortRead::writeFasta(fa_keep, file = out_fasta)
  TRUE
}

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("请提供 sample 名称，例如：Rscript extract_fungal_abundance.R FUSCCTNBC001")
}

sample_name <- args[1]
project_root <- get_project_root()
prism_root <- file.path(project_root, "00script", "repo")
result_dir <- file.path(project_root, "02fastq", paste0(sample_name, "_prism"))

results_file <- file.path(result_dir, paste0(sample_name, "-results.csv"))
counts_file <- file.path(result_dir, paste0(sample_name, "-counts.csv"))
fasta1_file <- file.path(result_dir, paste0(sample_name, "_1.fa"))
fasta2_file <- file.path(result_dir, paste0(sample_name, "_2.fa"))

fungi_results_file <- file.path(result_dir, paste0(sample_name, "-fungi-results.csv"))
fungi_counts_file <- file.path(result_dir, paste0(sample_name, "-fungi-counts.csv"))
fungi_fasta1_file <- file.path(result_dir, paste0(sample_name, "-fungi_1.fa"))
fungi_fasta2_file <- file.path(result_dir, paste0(sample_name, "-fungi_2.fa"))

taxonomy_dir_env <- Sys.getenv("KRAKEN_TAXONOMY_DIR", unset = "")
if (nzchar(taxonomy_dir_env)) {
  taxonomy_dir <- taxonomy_dir_env
} else {
  taxonomy_dir <- file.path(project_root, "02ref", "kraken2", "prism_kraken2_recommended", "taxonomy")
}
nodes_file <- file.path(taxonomy_dir, "nodes.dmp")

if (!file.exists(results_file)) {
  stop("找不到 PRISM read 级输出文件: ", results_file)
}

if (!file.exists(counts_file)) {
  message("提示：未找到 counts.csv，但本脚本仍可基于 results.csv 继续。")
}

fungal_taxids <- load_fungal_taxids(nodes_file)

res_dt <- fread(results_file)

required_cols <- c("id", "staxids", "tax_name", "pred")
if (!all(required_cols %in% colnames(res_dt))) {
  stop("results 文件列名不符合预期，至少需要: ", paste(required_cols, collapse = ", "))
}

res_dt[, staxids := sub(";.*", "", as.character(staxids))]
fungi_res_dt <- res_dt[staxids %in% fungal_taxids]

if (nrow(fungi_res_dt) > 0) {
  fungi_counts_dt <- fungi_res_dt[, .(
    n = .N,
    pred = mean(pred, na.rm = TRUE)
  ), by = .(tax_name, staxids)]
  fungi_counts_dt[, rel_abundance_within_fungi := n / sum(n)]
  setorder(fungi_counts_dt, -n)
} else {
  fungi_counts_dt <- data.table(
    tax_name = character(),
    staxids = character(),
    n = integer(),
    pred = numeric(),
    rel_abundance_within_fungi = numeric()
  )
}

fwrite(fungi_res_dt, fungi_results_file)
fwrite(fungi_counts_dt, fungi_counts_file)

keep_ids <- unique(as.character(fungi_res_dt$id))

if (length(keep_ids) > 0) {
  extract_fasta_by_ids(fasta1_file, fungi_fasta1_file, keep_ids)
  if (file.exists(fasta2_file)) {
    extract_fasta_by_ids(fasta2_file, fungi_fasta2_file, keep_ids)
  }
} else {
  writeLines(character(), fungi_fasta1_file)
  if (file.exists(fasta2_file)) {
    writeLines(character(), fungi_fasta2_file)
  }
}

cat("真菌 read 级结果已写出:\n")
cat(fungi_results_file, "\n")
cat("真菌物种汇总已写出:\n")
cat(fungi_counts_file, "\n")
cat("真菌最终 FASTA 已写出:\n")
cat(fungi_fasta1_file, "\n")
if (file.exists(fasta2_file)) {
  cat(fungi_fasta2_file, "\n")
}
cat("使用的 taxonomy 目录:\n")
cat(taxonomy_dir, "\n")
