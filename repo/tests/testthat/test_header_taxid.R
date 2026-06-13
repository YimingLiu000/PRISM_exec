library(testthat)
source(file.path(dirname(testthat::test_path()), "../../functions.R"))

test_that("FASTA header taxids are parsed across common formats", {
  headers <- c(
    "E00515:407:HLJKJCCXY:3:1101:24789:2100 kraken:taxid|260659 1:N:0:GTGAAACG+AGATCTCG",
    "A01415:265:HMMMFDRXY:1:2127:16767:5384 kraken:taxid|76859 1:N:0:TCAGCCTT+CTGTATGC kraken:taxid|851 kraken:taxid|851",
    "read_1 kraken:taxid|562",
    "read_2 taxid=4751 trailing text",
    "read_3 taxid 10239",
    "read_4 TAXID:9606",
    "read_without_taxid"
  )

  expect_identical(
    prism_extract_header_taxid(headers),
    c("260659", "851", "562", "4751", "10239", "9606", NA_character_)
  )
})

test_that("Kraken k-mer taxids remain character across empty and mixed inputs", {
  empty <- prism_parse_kmer_counts(NA_character_)
  mixed <- prism_parse_kmer_counts("562:12 9606:3 A:4 0:2")

  expect_identical(empty$taxid, character())
  expect_type(mixed$taxid, "character")
  expect_setequal(mixed$taxid, c("562", "9606", "A", "0"))
  expect_equal(mixed$n[mixed$taxid == "562"], 12)
})
