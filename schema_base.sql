
-- =====================================================================
-- PostgreSQL Snowflake Schema for Plant Genomics @ ExpressionDB (Base)
-- Target: PostgreSQL 16
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS exp;
CREATE SCHEMA IF NOT EXISTS fact;
CREATE SCHEMA IF NOT EXISTS var;
CREATE SCHEMA IF NOT EXISTS evo;
CREATE SCHEMA IF NOT EXISTS ml;
CREATE SCHEMA IF NOT EXISTS staging;

SET search_path = ref, exp, fact, var, evo, ml, staging, public;

-- 1) REFERENCE DIMENSIONS
CREATE TABLE IF NOT EXISTS ref.taxonomic_rank (
  rank_id   SMALLSERIAL PRIMARY KEY,
  name      TEXT UNIQUE NOT NULL,
  level     SMALLINT NOT NULL
);

CREATE TABLE IF NOT EXISTS ref.taxon (
  taxon_id        BIGSERIAL PRIMARY KEY,
  scientific_name TEXT NOT NULL,
  common_name     TEXT,
  ncbi_taxon_id   INTEGER,
  rank_id         SMALLINT NOT NULL REFERENCES ref.taxonomic_rank(rank_id),
  parent_taxon_id BIGINT REFERENCES ref.taxon(taxon_id) ON DELETE SET NULL,
  UNIQUE (ncbi_taxon_id),
  UNIQUE (scientific_name)
);

CREATE TABLE IF NOT EXISTS ref.species (
  species_id   BIGSERIAL PRIMARY KEY,
  taxon_id     BIGINT NOT NULL REFERENCES ref.taxon(taxon_id) ON DELETE RESTRICT,
  is_c4        BOOLEAN,
  photosynthesis_type TEXT CHECK (photosynthesis_type IN ('C3','C4','CAM','C3-C4','Unknown')),
  genome_size_bp BIGINT,
  notes        TEXT,
  UNIQUE (taxon_id)
);

CREATE TABLE IF NOT EXISTS ref.genome_assembly (
  assembly_id  BIGSERIAL PRIMARY KEY,
  species_id   BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  source       TEXT,
  version      TEXT NOT NULL,
  release_date DATE,
  assembly_level TEXT,
  accession    TEXT,
  is_current   BOOLEAN DEFAULT FALSE,
  UNIQUE (species_id, name, version)
);

CREATE TABLE IF NOT EXISTS ref.chromosome (
  chrom_id     BIGSERIAL PRIMARY KEY,
  assembly_id  BIGINT NOT NULL REFERENCES ref.genome_assembly(assembly_id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  length_bp    BIGINT,
  is_mitochondrial BOOLEAN DEFAULT FALSE,
  is_chloroplast   BOOLEAN DEFAULT FALSE,
  UNIQUE (assembly_id, name)
);

CREATE TABLE IF NOT EXISTS ref.gene (
  gene_id      BIGSERIAL PRIMARY KEY,
  assembly_id  BIGINT NOT NULL REFERENCES ref.genome_assembly(assembly_id) ON DELETE CASCADE,
  stable_id    TEXT NOT NULL,
  biotype      TEXT,
  chrom_id     BIGINT REFERENCES ref.chromosome(chrom_id) ON DELETE SET NULL,
  start_bp     BIGINT,
  end_bp       BIGINT,
  strand       SMALLINT CHECK (strand IN (-1, 1)),
  gene_name    TEXT,
  description  TEXT,
  UNIQUE (assembly_id, stable_id)
);
CREATE INDEX IF NOT EXISTS idx_gene_region ON ref.gene (chrom_id, start_bp, end_bp);

CREATE TABLE IF NOT EXISTS ref.transcript (
  transcript_id BIGSERIAL PRIMARY KEY,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  stable_id     TEXT NOT NULL,
  biotype       TEXT,
  is_canonical  BOOLEAN,
  start_bp      BIGINT,
  end_bp        BIGINT,
  strand        SMALLINT CHECK (strand IN (-1, 1)),
  UNIQUE (gene_id, stable_id)
);

CREATE TABLE IF NOT EXISTS ref.exon (
  exon_id       BIGSERIAL PRIMARY KEY,
  transcript_id BIGINT NOT NULL REFERENCES ref.transcript(transcript_id) ON DELETE CASCADE,
  exon_number   INTEGER,
  start_bp      BIGINT,
  end_bp        BIGINT,
  strand        SMALLINT CHECK (strand IN (-1, 1))
);

CREATE TABLE IF NOT EXISTS ref.protein (
  protein_id    BIGSERIAL PRIMARY KEY,
  transcript_id BIGINT NOT NULL REFERENCES ref.transcript(transcript_id) ON DELETE CASCADE,
  stable_id     TEXT NOT NULL,
  length_aa     INTEGER,
  md5           CHAR(32),
  sequence      TEXT,
  UNIQUE (transcript_id, stable_id)
);

CREATE TABLE IF NOT EXISTS ref.ontology (
  ontology_id  SMALLSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  version      TEXT,
  UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS ref.ontology_term (
  term_id      BIGSERIAL PRIMARY KEY,
  ontology_id  SMALLINT NOT NULL REFERENCES ref.ontology(ontology_id) ON DELETE CASCADE,
  accession    TEXT NOT NULL,
  name         TEXT NOT NULL,
  definition   TEXT,
  is_obsolete  BOOLEAN DEFAULT FALSE,
  UNIQUE (ontology_id, accession)
);

CREATE TABLE IF NOT EXISTS ref.gene_ontology_annotation (
  goa_id       BIGSERIAL PRIMARY KEY,
  gene_id      BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  term_id      BIGINT NOT NULL REFERENCES ref.ontology_term(term_id) ON DELETE RESTRICT,
  evidence_code TEXT,
  source       TEXT,
  assigned_by  TEXT,
  UNIQUE (gene_id, term_id, evidence_code)
);

CREATE TABLE IF NOT EXISTS ref.pathway (
  pathway_id   BIGSERIAL PRIMARY KEY,
  source       TEXT NOT NULL,
  accession    TEXT NOT NULL,
  name         TEXT NOT NULL,
  description  TEXT,
  UNIQUE (source, accession)
);

CREATE TABLE IF NOT EXISTS ref.pathway_gene (
  pathway_id   BIGINT NOT NULL REFERENCES ref.pathway(pathway_id) ON DELETE CASCADE,
  gene_id      BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  PRIMARY KEY (pathway_id, gene_id)
);

CREATE TABLE IF NOT EXISTS ref.orthogroup (
  orthogroup_id BIGSERIAL PRIMARY KEY,
  source        TEXT NOT NULL,
  name          TEXT NOT NULL,
  UNIQUE (source, name)
);

CREATE TABLE IF NOT EXISTS ref.orthogroup_member (
  orthogroup_id BIGINT NOT NULL REFERENCES ref.orthogroup(orthogroup_id) ON DELETE CASCADE,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  PRIMARY KEY (orthogroup_id, gene_id)
);

CREATE TABLE IF NOT EXISTS ref.conserved_element (
  element_id   BIGSERIAL PRIMARY KEY,
  assembly_id  BIGINT NOT NULL REFERENCES ref.genome_assembly(assembly_id) ON DELETE CASCADE,
  chrom_id     BIGINT NOT NULL REFERENCES ref.chromosome(chrom_id) ON DELETE CASCADE,
  start_bp     BIGINT NOT NULL,
  end_bp       BIGINT NOT NULL,
  score        REAL,
  method       TEXT
);
CREATE INDEX IF NOT EXISTS idx_conserved_element_region ON ref.conserved_element (chrom_id, start_bp, end_bp);

-- 2) EXPERIMENT METADATA
CREATE TABLE IF NOT EXISTS exp.project (
  project_id   BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  source       TEXT,
  accession    TEXT,
  description  TEXT
);

CREATE TABLE IF NOT EXISTS exp.experiment (
  experiment_id BIGSERIAL PRIMARY KEY,
  project_id    BIGINT REFERENCES exp.project(project_id) ON DELETE SET NULL,
  species_id    BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE RESTRICT,
  assay_type    TEXT NOT NULL CHECK (assay_type IN ('RNA-Seq','scRNA-Seq','ATAC-Seq','WGS','WES','ChIP-Seq','Proteomics','Other')),
  design        JSONB,
  reference_assembly_id BIGINT REFERENCES ref.genome_assembly(assembly_id) ON DELETE SET NULL,
  created_at    TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS exp.condition (
  condition_id  BIGSERIAL PRIMARY KEY,
  tissue        TEXT,
  treatment     TEXT,
  time_point    TEXT,
  temperature_c REAL,
  co2_ppm       REAL,
  light_umol    REAL,
  custom_tags   JSONB
);

CREATE TABLE IF NOT EXISTS exp.sample (
  sample_id     BIGSERIAL PRIMARY KEY,
  experiment_id BIGINT NOT NULL REFERENCES exp.experiment(experiment_id) ON DELETE CASCADE,
  condition_id  BIGINT REFERENCES exp.condition(condition_id) ON DELETE SET NULL,
  replicate     INTEGER,
  biosample_acc TEXT,
  is_case       BOOLEAN,
  notes         TEXT
);

CREATE TABLE IF NOT EXISTS exp.library_prep (
  library_id    BIGSERIAL PRIMARY KEY,
  sample_id     BIGINT NOT NULL REFERENCES exp.sample(sample_id) ON DELETE CASCADE,
  library_type  TEXT,
  strandedness  TEXT,
  insert_size   INTEGER,
  protocol      TEXT
);

CREATE TABLE IF NOT EXISTS exp.run (
  run_id        BIGSERIAL PRIMARY KEY,
  library_id    BIGINT NOT NULL REFERENCES exp.library_prep(library_id) ON DELETE CASCADE,
  sra_run_acc   TEXT,
  platform      TEXT,
  read_length   INTEGER,
  layout        TEXT CHECK (layout IN ('SE','PE')),
  read_count    BIGINT,
  base_count    BIGINT
);

CREATE TABLE IF NOT EXISTS exp.alignment (
  alignment_id  BIGSERIAL PRIMARY KEY,
  run_id        BIGINT NOT NULL REFERENCES exp.run(run_id) ON DELETE CASCADE,
  tool          TEXT,
  params        TEXT,
  reference_assembly_id BIGINT REFERENCES ref.genome_assembly(assembly_id),
  aligned_reads BIGINT,
  mapped_pct    REAL,
  duplication_pct REAL,
  qc_json       JSONB
);

CREATE TABLE IF NOT EXISTS exp.quant_method (
  quant_method_id SMALLSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  version      TEXT,
  UNIQUE (name, version)
);

-- 3) FACT TABLES (partitioned by species_id)
CREATE TABLE IF NOT EXISTS fact.gene_expression (
  species_id     BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE RESTRICT,
  sample_id      BIGINT NOT NULL REFERENCES exp.sample(sample_id) ON DELETE CASCADE,
  gene_id        BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  quant_method_id SMALLINT NOT NULL REFERENCES exp.quant_method(quant_method_id),
  tpm            REAL,
  count_raw      BIGINT,
  count_norm     REAL,
  PRIMARY KEY (species_id, sample_id, gene_id, quant_method_id)
) PARTITION BY LIST (species_id);

CREATE TABLE IF NOT EXISTS fact.gene_expression_default PARTITION OF fact.gene_expression DEFAULT;
CREATE INDEX IF NOT EXISTS idx_gene_expr_gene ON fact.gene_expression_default (gene_id);
CREATE INDEX IF NOT EXISTS idx_gene_expr_sample ON fact.gene_expression_default (sample_id);

CREATE TABLE IF NOT EXISTS fact.transcript_expression (
  species_id     BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE RESTRICT,
  sample_id      BIGINT NOT NULL REFERENCES exp.sample(sample_id) ON DELETE CASCADE,
  transcript_id  BIGINT NOT NULL REFERENCES ref.transcript(transcript_id) ON DELETE CASCADE,
  quant_method_id SMALLINT NOT NULL REFERENCES exp.quant_method(quant_method_id),
  tpm            REAL,
  count_raw      BIGINT,
  count_norm     REAL,
  PRIMARY KEY (species_id, sample_id, transcript_id, quant_method_id)
) PARTITION BY LIST (species_id);

CREATE TABLE IF NOT EXISTS fact.transcript_expression_default PARTITION OF fact.transcript_expression DEFAULT;
CREATE INDEX IF NOT EXISTS idx_tx_expr_tx ON fact.transcript_expression_default (transcript_id);
CREATE INDEX IF NOT EXISTS idx_tx_expr_sample ON fact.transcript_expression_default (sample_id);

CREATE TABLE IF NOT EXISTS fact.orthogroup_abundance (
  orthogroup_id  BIGINT NOT NULL REFERENCES ref.orthogroup(orthogroup_id) ON DELETE CASCADE,
  species_id     BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  gene_count     INTEGER NOT NULL,
  median_expr_tpm REAL,
  PRIMARY KEY (orthogroup_id, species_id)
) PARTITION BY LIST (species_id);

CREATE TABLE IF NOT EXISTS fact.orthogroup_abundance_default PARTITION OF fact.orthogroup_abundance DEFAULT;
CREATE INDEX IF NOT EXISTS idx_og_ab_species ON fact.orthogroup_abundance_default (species_id);

CREATE TABLE IF NOT EXISTS fact.gene_conservation (
  species_id     BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  gene_id        BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  element_id     BIGINT NOT NULL REFERENCES ref.conserved_element(element_id) ON DELETE CASCADE,
  overlap_bp     INTEGER NOT NULL,
  PRIMARY KEY (species_id, gene_id, element_id)
) PARTITION BY LIST (species_id);

CREATE TABLE IF NOT EXISTS fact.gene_conservation_default PARTITION OF fact.gene_conservation DEFAULT;

-- 4) VARIANTS
CREATE TABLE IF NOT EXISTS var.variant_set (
  variant_set_id BIGSERIAL PRIMARY KEY,
  experiment_id  BIGINT REFERENCES exp.experiment(experiment_id) ON DELETE SET NULL,
  name           TEXT NOT NULL,
  reference_assembly_id BIGINT REFERENCES ref.genome_assembly(assembly_id) ON DELETE SET NULL,
  caller         TEXT,
  version        TEXT,
  created_at     TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS var.variant (
  variant_id     BIGSERIAL PRIMARY KEY,
  variant_set_id BIGINT NOT NULL REFERENCES var.variant_set(variant_set_id) ON DELETE CASCADE,
  chrom_id       BIGINT NOT NULL REFERENCES ref.chromosome(chrom_id) ON DELETE CASCADE,
  pos_bp         BIGINT NOT NULL,
  ref_allele     TEXT NOT NULL,
  alt_allele     TEXT NOT NULL,
  variant_type   TEXT CHECK (variant_type IN ('SNP','INS','DEL','MNV','SV','OTHER')),
  qual           REAL,
  filter         TEXT,
  info           JSONB
);
CREATE INDEX IF NOT EXISTS idx_variant_region ON var.variant (chrom_id, pos_bp);
CREATE INDEX IF NOT EXISTS idx_variant_info_gin ON var.variant USING GIN (info);

CREATE TABLE IF NOT EXISTS var.genotype (
  variant_id     BIGINT NOT NULL REFERENCES var.variant(variant_id) ON DELETE CASCADE,
  sample_id      BIGINT NOT NULL REFERENCES exp.sample(sample_id) ON DELETE CASCADE,
  gt             TEXT,
  gq             REAL,
  dp             INTEGER,
  ad_ref         INTEGER,
  ad_alt         INTEGER,
  phased         BOOLEAN,
  PRIMARY KEY (variant_id, sample_id)
);

CREATE TABLE IF NOT EXISTS var.variant_effect (
  effect_id      BIGSERIAL PRIMARY KEY,
  variant_id     BIGINT NOT NULL REFERENCES var.variant(variant_id) ON DELETE CASCADE,
  gene_id        BIGINT REFERENCES ref.gene(gene_id) ON DELETE SET NULL,
  transcript_id  BIGINT REFERENCES ref.transcript(transcript_id) ON DELETE SET NULL,
  consequence    TEXT,
  impact         TEXT,
  protein_change TEXT,
  annotations    JSONB
);
CREATE INDEX IF NOT EXISTS idx_variant_effect_gene ON var.variant_effect (gene_id);
CREATE INDEX IF NOT EXISTS idx_variant_effect_tx ON var.variant_effect (transcript_id);

-- 5) EVOLUTION
CREATE TABLE IF NOT EXISTS evo.msa_set (
  msa_id        BIGSERIAL PRIMARY KEY,
  orthogroup_id BIGINT REFERENCES ref.orthogroup(orthogroup_id) ON DELETE SET NULL,
  sequence_type TEXT CHECK (sequence_type IN ('DNA','CDS','Protein')),
  tool          TEXT,
  params        TEXT,
  created_at    TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evo.msa_member (
  msa_id        BIGINT NOT NULL REFERENCES evo.msa_set(msa_id) ON DELETE CASCADE,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  protein_id    BIGINT REFERENCES ref.protein(protein_id) ON DELETE SET NULL,
  order_index   INTEGER,
  PRIMARY KEY (msa_id, gene_id)
);

CREATE TABLE IF NOT EXISTS evo.phylogenetic_tree (
  tree_id       BIGSERIAL PRIMARY KEY,
  msa_id        BIGINT REFERENCES evo.msa_set(msa_id) ON DELETE SET NULL,
  newick        TEXT NOT NULL,
  method        TEXT,
  model         TEXT,
  created_at    TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evo.selection_stats (
  sel_id        BIGSERIAL PRIMARY KEY,
  msa_id        BIGINT REFERENCES evo.msa_set(msa_id) ON DELETE CASCADE,
  gene_id       BIGINT REFERENCES ref.gene(gene_id) ON DELETE SET NULL,
  dn_ds         REAL,
  site_json     JSONB,
  branch_json   JSONB
);

-- 6) ML
CREATE TABLE IF NOT EXISTS ml.label_set (
  label_set_id  SMALLSERIAL PRIMARY KEY,
  name          TEXT UNIQUE NOT NULL,
  description   TEXT
);

CREATE TABLE IF NOT EXISTS ml.gene_label (
  label_set_id  SMALLINT NOT NULL REFERENCES ml.label_set(label_set_id) ON DELETE CASCADE,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  label         TEXT NOT NULL,
  source        TEXT,
  confidence    REAL,
  PRIMARY KEY (label_set_id, gene_id)
);

CREATE TABLE IF NOT EXISTS ml.gene_feature (
  feature_id    BIGSERIAL PRIMARY KEY,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  species_id    BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  feature_group TEXT NOT NULL,
  version       TEXT NOT NULL,
  features      JSONB NOT NULL,
  created_at    TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ml_features_gin ON ml.gene_feature USING GIN (features);

CREATE TABLE IF NOT EXISTS ml.dataset_split (
  split_id      SMALLSERIAL PRIMARY KEY,
  name          TEXT UNIQUE NOT NULL,
  policy        TEXT
);

CREATE TABLE IF NOT EXISTS ml.split_member (
  split_id      SMALLINT NOT NULL REFERENCES ml.dataset_split(split_id) ON DELETE CASCADE,
  gene_id       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  role          TEXT CHECK (role IN ('train','valid','test')),
  PRIMARY KEY (split_id, gene_id, role)
);

-- 7) STAGING
CREATE TABLE IF NOT EXISTS staging.rnaseq_quant (
  id            BIGSERIAL PRIMARY KEY,
  load_batch_id TEXT NOT NULL,
  species_name  TEXT,
  assembly_name TEXT,
  sample_name   TEXT,
  gene_stable_id TEXT,
  transcript_stable_id TEXT,
  quant_method  TEXT,
  tpm           REAL,
  read_count    BIGINT,
  extra_json    JSONB,
  loaded_at     TIMESTAMP DEFAULT now()
);

-- 8) PARTITION HELPERS
CREATE OR REPLACE FUNCTION fact.create_species_partitions(p_species_id BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  tbl TEXT;
BEGIN
  tbl := format('fact.gene_expression_s%I', p_species_id);
  EXECUTE format('
    CREATE TABLE IF NOT EXISTS %s PARTITION OF fact.gene_expression FOR VALUES IN (%s);
    CREATE INDEX IF NOT EXISTS idx_ge_gene_s%1$s ON %s (gene_id);
    CREATE INDEX IF NOT EXISTS idx_ge_sample_s%1$s ON %s (sample_id);
  ', tbl, p_species_id, tbl, tbl);

  tbl := format('fact.transcript_expression_s%I', p_species_id);
  EXECUTE format('
    CREATE TABLE IF NOT EXISTS %s PARTITION OF fact.transcript_expression FOR VALUES IN (%s);
    CREATE INDEX IF NOT EXISTS idx_te_tx_s%1$s ON %s (transcript_id);
    CREATE INDEX IF NOT EXISTS idx_te_sample_s%1$s ON %s (sample_id);
  ', tbl, p_species_id, tbl, tbl);

  tbl := format('fact.orthogroup_abundance_s%I', p_species_id);
  EXECUTE format('
    CREATE TABLE IF NOT EXISTS %s PARTITION OF fact.orthogroup_abundance FOR VALUES IN (%s);
    CREATE INDEX IF NOT EXISTS idx_ogab_species_s%1$s ON %s (species_id);
  ', tbl, p_species_id, tbl);
END;
$$;

-- 9) VIEW
CREATE OR REPLACE VIEW fact.v_gene_summary AS
SELECT
  g.gene_id,
  s.species_id,
  s.photosynthesis_type,
  g.gene_name,
  g.stable_id AS gene_stable_id,
  ARRAY_AGG(DISTINCT og.orthogroup_id) FILTER (WHERE og.orthogroup_id IS NOT NULL) AS orthogroups,
  COUNT(DISTINCT ge.sample_id) AS n_expr_samples,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ge.tpm) AS median_tpm
FROM ref.gene g
JOIN ref.genome_assembly ga ON ga.assembly_id = g.assembly_id
JOIN ref.species s ON s.species_id = ga.species_id
LEFT JOIN ref.orthogroup_member ogm ON ogm.gene_id = g.gene_id
LEFT JOIN ref.orthogroup og ON og.orthogroup_id = ogm.orthogroup_id
LEFT JOIN fact.gene_expression ge ON ge.gene_id = g.gene_id AND ge.species_id = s.species_id
GROUP BY g.gene_id, s.species_id, s.photosynthesis_type, g.gene_name, g.stable_id;
