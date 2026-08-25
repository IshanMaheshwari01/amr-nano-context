/*
 * Same tool, different question. Run against the assembly rather than the reads
 * so every contig carries a taxonomic label, which is what lets an ARG be
 * attributed to a host organism later.
 */
process KRAKEN2_CONTIGS {
    tag "${meta.id}"
    label 'process_high_memory'
    container params.container_kraken2

    input:
    tuple val(meta), path(assembly)
    path db

    output:
    tuple val(meta), path("${meta.id}.contigs.kraken2.out.txt"), emit: classified
    tuple val(meta), path("${meta.id}.contigs.kraken2.report.txt"), emit: report
    path "versions.yml",                                         emit: versions

    script:
    """
    kraken2 \\
        --db ${db} \\
        --threads ${task.cpus} \\
        --report ${meta.id}.contigs.kraken2.report.txt \\
        --output ${meta.id}.contigs.kraken2.out.txt \\
        --use-names \\
        ${assembly}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(kraken2 --version | head -n1 | sed 's/Kraken version //')
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}.contigs.kraken2.out.txt
    touch ${meta.id}.contigs.kraken2.report.txt
    touch versions.yml
    """
}
