process SEQKIT_STATS {
    tag "${meta.id}"
    label 'process_low'
    container params.container_seqkit

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_seqkit_stats.tsv"), emit: stats
    path "versions.yml",                                  emit: versions

    script:
    """
    seqkit stats --all --tabular --threads ${task.cpus} ${reads} > ${meta.id}_seqkit_stats.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: \$(seqkit version | sed 's/seqkit v//')
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_seqkit_stats.tsv
    touch versions.yml
    """
}
