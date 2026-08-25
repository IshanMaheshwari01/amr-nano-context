#!/usr/bin/env nextflow
/*
 * amr-nano-context
 * Long-read metagenomic resistome profiling with genomic context resolution.
 *
 * Reports each antimicrobial resistance gene together with the contig it sits on,
 * whether that contig looks chromosomal or plasmid-borne, and which organism it
 * most likely belongs to. Short-read resistome profiling reports the gene alone.
 */

include { SEQKIT_STATS      } from './modules/local/seqkit_stats'
include { NANOQ             } from './modules/local/nanoq'
include { NANOPLOT          } from './modules/local/nanoplot'
include { KRAKEN2_READS     } from './modules/local/kraken2_reads'
include { BRACKEN           } from './modules/local/bracken'
include { FLYE              } from './modules/local/flye'
include { KRAKEN2_CONTIGS   } from './modules/local/kraken2_contigs'
include { AMRFINDERPLUS     } from './modules/local/amrfinderplus'
include { ABRICATE          } from './modules/local/abricate'
include { GENOMAD           } from './modules/local/genomad'
include { ARG_CONTEXT       } from './modules/local/arg_context'
include { VALIDATE_RESISTOME} from './modules/local/validate_resistome'
include { MULTIQC           } from './modules/local/multiqc'

def helpMessage() {
    log.info """
    amr-nano-context

    Usage:
      nextflow run . -profile docker --input assets/samplesheet.csv --outdir results \\
          --kraken2_db /path/to/k2_standard_08gb --genomad_db /path/to/genomad_db

    Required:
      --input           CSV samplesheet: sample,fastq,truth_set
      --outdir          Output directory
      --kraken2_db      Path to an extracted Kraken2 database directory
      --genomad_db      Path to an extracted geNomad database directory

    Optional:
      --min_read_len    Minimum read length after filtering  [default: ${params.min_read_len}]
      --min_read_q      Minimum mean read quality            [default: ${params.min_read_q}]
      --flye_mode       Flye read mode                       [default: ${params.flye_mode}]
      --min_arg_id      Minimum percent identity for an ARG call [default: ${params.min_arg_id}]
      --min_arg_cov     Minimum percent coverage for an ARG call [default: ${params.min_arg_cov}]
      --plasmid_score   geNomad plasmid score to call plasmid    [default: ${params.plasmid_score}]
      --skip_validation Skip resistome validation even if truth_set is given
    """.stripIndent()
}

workflow {

    // Nextflow 26 does not allow statements at the top level of a script, so
    // these live inside the entry workflow rather than above it.
    if (params.help) {
        helpMessage()
        return
    }

    if (!params.input)  { error "Missing --input samplesheet. Run with --help." }
    if (!params.outdir) { error "Missing --outdir." }

    // ---- samplesheet ------------------------------------------------------
    // sample,fastq,truth_set     (truth_set may be empty)
    ch_input = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sample) error "Samplesheet row is missing a 'sample' value: ${row}"
            if (!row.fastq)  error "Samplesheet row '${row.sample}' is missing a 'fastq' value"
            def meta = [ id: row.sample ]
            def fq   = file(row.fastq, checkIfExists: true)
            def truth = row.truth_set?.trim() ? file(row.truth_set, checkIfExists: true) : []
            tuple(meta, fq, truth)
        }

    ch_reads = ch_input.map { meta, fq, truth -> tuple(meta, fq) }
    ch_truth = ch_input.map { meta, fq, truth -> tuple(meta, truth) }

    ch_versions = Channel.empty()

    // ---- read QC ----------------------------------------------------------
    SEQKIT_STATS( ch_reads )
    NANOQ( ch_reads )
    NANOPLOT( NANOQ.out.reads )

    ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions, NANOQ.out.versions, NANOPLOT.out.versions)

    // ---- taxonomic profile of reads ---------------------------------------
    ch_k2db = Channel.value(file(params.kraken2_db, checkIfExists: true))

    KRAKEN2_READS( NANOQ.out.reads, ch_k2db )
    BRACKEN( KRAKEN2_READS.out.report, ch_k2db )
    ch_versions = ch_versions.mix(KRAKEN2_READS.out.versions, BRACKEN.out.versions)

    // ---- assembly ---------------------------------------------------------
    FLYE( NANOQ.out.reads )
    ch_versions = ch_versions.mix(FLYE.out.versions)

    // ---- resistome + context ----------------------------------------------
    AMRFINDERPLUS( FLYE.out.assembly )
    ABRICATE( FLYE.out.assembly )
    KRAKEN2_CONTIGS( FLYE.out.assembly, ch_k2db )

    ch_gndb = Channel.value(file(params.genomad_db, checkIfExists: true))
    GENOMAD( FLYE.out.assembly, ch_gndb )

    ch_versions = ch_versions.mix(
        AMRFINDERPLUS.out.versions, ABRICATE.out.versions,
        KRAKEN2_CONTIGS.out.versions, GENOMAD.out.versions
    )

    // Join everything on meta so a sample's five result files travel together.
    ch_context_in = AMRFINDERPLUS.out.report
        .join( ABRICATE.out.report )
        .join( GENOMAD.out.summary )
        .join( KRAKEN2_CONTIGS.out.classified )
        .join( FLYE.out.info )

    ARG_CONTEXT( ch_context_in )
    ch_versions = ch_versions.mix(ARG_CONTEXT.out.versions)

    // ---- validation against a known resistome ------------------------------
    if (!params.skip_validation) {
        ch_validate_in = ARG_CONTEXT.out.table
            .join( ch_truth )
            .filter { meta, table, truth -> truth as boolean }
        VALIDATE_RESISTOME( ch_validate_in )
        ch_versions = ch_versions.mix(VALIDATE_RESISTOME.out.versions)
    }

    // ---- report ------------------------------------------------------------
    ch_multiqc_files = Channel.empty()
        .mix( SEQKIT_STATS.out.stats.map { it[1] } )
        .mix( NANOQ.out.report.map { it[1] } )
        .mix( KRAKEN2_READS.out.report.map { it[1] } )
        .mix( ARG_CONTEXT.out.mqc.map { it[1] } )
        .collect()

    MULTIQC( ch_multiqc_files, file("$projectDir/assets/multiqc_config.yml") )

    ch_versions
        .unique()
        .collectFile(name: 'software_versions.yml', storeDir: "${params.outdir}/pipeline_info")
}
