
-- =====================================================================
-- ExpressionDB Schema (Extended) - complexes/subunits, homology, CDS/mature proteins,
-- coexpression, external xrefs, organism groups
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS exp;

SET search_path = ref, exp, public;

-- Organism metadata & grouping
ALTER TABLE IF EXISTS ref.species
  ADD COLUMN IF NOT EXISTS short_name TEXT,
  ADD COLUMN IF NOT EXISTS long_name  TEXT,
  ADD COLUMN IF NOT EXISTS genus      TEXT,
  ADD COLUMN IF NOT EXISTS family     TEXT,
  ADD COLUMN IF NOT EXISTS order_name TEXT,
  ADD COLUMN IF NOT EXISTS code6      TEXT UNIQUE;

CREATE TABLE IF NOT EXISTS ref.organism_group (
  group_id     BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  group_type   TEXT NOT NULL,
  description  TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_group_type_name ON ref.organism_group (group_type, name);

CREATE TABLE IF NOT EXISTS ref.species_group_membership (
  species_id   BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  group_id     BIGINT NOT NULL REFERENCES ref.organism_group(group_id) ON DELETE CASCADE,
  PRIMARY KEY (species_id, group_id)
);

-- Complex / subcomplex / subunit + gene mapping
CREATE TABLE IF NOT EXISTS ref.biocomplex (
  complex_id   BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  system       TEXT,
  description  TEXT,
  UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS ref.subcomplex (
  subcomplex_id BIGSERIAL PRIMARY KEY,
  complex_id    BIGINT NOT NULL REFERENCES ref.biocomplex(complex_id) ON DELETE CASCADE,
  code          TEXT NOT NULL,
  name          TEXT,
  description   TEXT,
  UNIQUE (complex_id, code)
);

CREATE TABLE IF NOT EXISTS ref.subunit (
  subunit_id    BIGSERIAL PRIMARY KEY,
  complex_id    BIGINT NOT NULL REFERENCES ref.biocomplex(complex_id) ON DELETE CASCADE,
  subcomplex_id BIGINT REFERENCES ref.subcomplex(subcomplex_id) ON DELETE SET NULL,
  code          TEXT NOT NULL,
  alt_names     TEXT[],
  is_chl_encoded BOOLEAN,
  description   TEXT,
  UNIQUE (complex_id, code)
);

CREATE TABLE IF NOT EXISTS ref.gene_subunit (
  gene_id      BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  subunit_id   BIGINT NOT NULL REFERENCES ref.subunit(subunit_id) ON DELETE CASCADE,
  evidence_code TEXT,
  source       TEXT,
  confidence   REAL,
  PRIMARY KEY (gene_id, subunit_id)
);

-- Homology pairs
CREATE TABLE IF NOT EXISTS ref.homology_set (
  homology_set_id BIGSERIAL PRIMARY KEY,
  source          TEXT NOT NULL,
  method          TEXT,
  version         TEXT,
  created_at      TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ref.homology_pair (
  homology_set_id BIGINT NOT NULL REFERENCES ref.homology_set(homology_set_id) ON DELETE CASCADE,
  gene_id_a       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  gene_id_b       BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  relationship    TEXT CHECK (relationship IN ('ortholog','paralog','co-ortholog','inparalog','xenolog','unknown')),
  percent_identity REAL,
  alignment_coverage REAL,
  bitscore        REAL,
  evalue          DOUBLE PRECISION,
  dn_ds           REAL,
  synteny_block   TEXT,
  PRIMARY KEY (homology_set_id, gene_id_a, gene_id_b),
  CHECK (gene_id_a < gene_id_b)
);
CREATE INDEX IF NOT EXISTS idx_homology_gene_a ON ref.homology_pair (gene_id_a);
CREATE INDEX IF NOT EXISTS idx_homology_gene_b ON ref.homology_pair (gene_id_b);

-- CDS & mature protein
CREATE TABLE IF NOT EXISTS ref.cds (
  cds_id        BIGSERIAL PRIMARY KEY,
  transcript_id BIGINT NOT NULL REFERENCES ref.transcript(transcript_id) ON DELETE CASCADE,
  phase         SMALLINT CHECK (phase IN (0,1,2)),
  length_bp     INTEGER,
  md5           CHAR(32),
  sequence      TEXT,
  UNIQUE (transcript_id)
);

CREATE TABLE IF NOT EXISTS ref.mature_protein (
  mature_protein_id BIGSERIAL PRIMARY KEY,
  protein_id     BIGINT NOT NULL REFERENCES ref.protein(protein_id) ON DELETE CASCADE,
  method         TEXT,
  cleavage_start INTEGER DEFAULT 1,
  cleavage_end   INTEGER,
  signal_peptide BOOLEAN,
  transit_peptide BOOLEAN,
  ptm_json       JSONB,
  sequence       TEXT NOT NULL,
  md5            CHAR(32),
  UNIQUE (protein_id, method)
);

-- Coexpression
CREATE TABLE IF NOT EXISTS exp.coexpression_network (
  network_id    BIGSERIAL PRIMARY KEY,
  species_id    BIGINT REFERENCES ref.species(species_id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  source        TEXT,
  method        TEXT,
  transform     TEXT,
  n_samples     INTEGER,
  created_at    TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS exp.coexpression_edge (
  network_id    BIGINT NOT NULL REFERENCES exp.coexpression_network(network_id) ON DELETE CASCADE,
  gene_id_a     BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  gene_id_b     BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  weight        REAL NOT NULL,
  metric        TEXT,
  pvalue        DOUBLE PRECISION,
  qvalue        DOUBLE PRECISION,
  PRIMARY KEY (network_id, gene_id_a, gene_id_b),
  CHECK (gene_id_a < gene_id_b)
);
CREATE INDEX IF NOT EXISTS idx_coexp_gene_a ON exp.coexpression_edge (gene_id_a);
CREATE INDEX IF NOT EXISTS idx_coexp_gene_b ON exp.coexpression_edge (gene_id_b);

-- External DB xrefs
CREATE TABLE IF NOT EXISTS ref.external_db (
  external_db_id SMALLSERIAL PRIMARY KEY,
  name           TEXT UNIQUE NOT NULL,
  url            TEXT
);

CREATE TABLE IF NOT EXISTS ref.species_xref (
  external_db_id SMALLINT NOT NULL REFERENCES ref.external_db(external_db_id) ON DELETE CASCADE,
  species_id     BIGINT NOT NULL REFERENCES ref.species(species_id) ON DELETE CASCADE,
  external_id    TEXT NOT NULL,
  PRIMARY KEY (external_db_id, species_id),
  UNIQUE (external_db_id, external_id)
);

CREATE TABLE IF NOT EXISTS ref.assembly_xref (
  external_db_id SMALLINT NOT NULL REFERENCES ref.external_db(external_db_id) ON DELETE CASCADE,
  assembly_id    BIGINT NOT NULL REFERENCES ref.genome_assembly(assembly_id) ON DELETE CASCADE,
  external_id    TEXT NOT NULL,
  PRIMARY KEY (external_db_id, assembly_id),
  UNIQUE (external_db_id, external_id)
);

CREATE TABLE IF NOT EXISTS ref.gene_xref (
  external_db_id SMALLINT NOT NULL REFERENCES ref.external_db(external_db_id) ON DELETE CASCADE,
  gene_id        BIGINT NOT NULL REFERENCES ref.gene(gene_id) ON DELETE CASCADE,
  external_id    TEXT NOT NULL,
  PRIMARY KEY (external_db_id, gene_id),
  UNIQUE (external_db_id, external_id)
);

CREATE TABLE IF NOT EXISTS ref.transcript_xref (
  external_db_id SMALLINT NOT NULL REFERENCES ref.external_db(external_db_id) ON DELETE CASCADE,
  transcript_id  BIGINT NOT NULL REFERENCES ref.transcript(transcript_id) ON DELETE CASCADE,
  external_id    TEXT NOT NULL,
  PRIMARY KEY (external_db_id, transcript_id),
  UNIQUE (external_db_id, external_id)
);

CREATE TABLE IF NOT EXISTS ref.protein_xref (
  external_db_id SMALLINT NOT NULL REFERENCES ref.external_db(external_db_id) ON DELETE CASCADE,
  protein_id     BIGINT NOT NULL REFERENCES ref.protein(protein_id) ON DELETE CASCADE,
  external_id    TEXT NOT NULL,
  PRIMARY KEY (external_db_id, protein_id),
  UNIQUE (external_db_id, external_id)
);

INSERT INTO ref.external_db (name, url) VALUES
  ('PhytoMine', 'https://phytozome.jgi.doe.gov/phytomine'),
  ('EnsemblPlants', 'https://plants.ensembl.org'),
  ('NCBI', 'https://www.ncbi.nlm.nih.gov'),
  ('UniProt', 'https://www.uniprot.org')
ON CONFLICT (name) DO NOTHING;

-- Views
CREATE OR REPLACE VIEW ref.v_gene_subunit AS
SELECT g.gene_id, g.gene_name, g.stable_id AS gene_stable_id,
       sc.code AS subcomplex_code, su.code AS subunit_code,
       bc.name AS complex_name, su.is_chl_encoded, gs.evidence_code, gs.source, gs.confidence
FROM ref.gene g
JOIN ref.gene_subunit gs ON gs.gene_id = g.gene_id
JOIN ref.subunit su ON su.subunit_id = gs.subunit_id
LEFT JOIN ref.subcomplex sc ON sc.subcomplex_id = su.subcomplex_id
JOIN ref.biocomplex bc ON bc.complex_id = su.complex_id;

CREATE OR REPLACE VIEW exp.v_coexp_neighbors AS
SELECT e.network_id, e.gene_id_a AS gene_id, e.gene_id_b AS neighbor_id, e.weight, e.metric
FROM exp.coexpression_edge e
UNION ALL
SELECT e.network_id, e.gene_id_b AS gene_id, e.gene_id_a AS neighbor_id, e.weight, e.metric
FROM exp.coexpression_edge e;

CREATE OR REPLACE VIEW ref.v_gene_protein_sequences AS
SELECT g.gene_id, t.transcript_id, p.protein_id,
       c.sequence AS cds_sequence, p.length_aa,
       mp.sequence AS mature_sequence, mp.method AS mature_method
FROM ref.gene g
JOIN ref.transcript t ON t.gene_id = g.gene_id
LEFT JOIN ref.cds c ON c.transcript_id = t.transcript_id
LEFT JOIN ref.protein p ON p.transcript_id = t.transcript_id
LEFT JOIN ref.mature_protein mp ON mp.protein_id = p.protein_id;
