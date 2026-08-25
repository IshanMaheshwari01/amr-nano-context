process KRAKEN2_READS {
    tag "${meta.id}"
    label 'process_high_memory'
    container params.container_kraken2

    input:
    tuple val(meta), path(reads)
    path db

    output:
    tuple val(meta), path("${meta.id}.kraken2.report.txt"), emit: report
    tuple val(meta), path("${meta.id}.kraken2.out.txt.gz"), emit: classified
    path "versions.yml",                                    emit: versions

    script:
    """
    kraken2 \\
        --db ${db} \\
        --threads ${task.cpus} \\
        --report ${meta.id}.kraken2.report.txt \\
        --output ${meta.id}.kraken2.out.txt \\
        ${reads}

    gzip ${meta.id}.kraken2.out.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(kraken2 --version | head -n1 | sed 's/Kraken version //')
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}.kraken2.report.txt
    echo "" | gzip > ${meta.id}.kraken2.out.txt.gz
    touch versions.yml
    """
}
