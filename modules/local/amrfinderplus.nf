process AMRFINDERPLUS {
    tag "${meta.id}"
    label 'process_medium'
    container params.container_amrfinder

    input:
    tuple val(meta), path(assembly)

    output:
    tuple val(meta), path("${meta.id}_amrfinder.tsv"), emit: report
    path "versions.yml",                               emit: versions

    script:
    """
    # The container ships with a bundled database. Updating it inside the task
    # would break reproducibility, so the shipped version is used and recorded.
    amrfinder \\
        --nucleotide ${assembly} \\
        --plus \\
        --threads ${task.cpus} \\
        --output ${meta.id}_amrfinder.tsv \\
        --name ${meta.id}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        amrfinderplus: \$(amrfinder --version)
        amrfinderplus_db: \$(amrfinder --database_version 2>&1 | grep -i 'database version' | sed 's/.*: //' || echo 'unknown')
    END_VERSIONS
    """

    stub:
    """
    printf 'Name\\tContig id\\tStart\\tStop\\tStrand\\tElement symbol\\tElement name\\tScope\\tType\\tSubtype\\tClass\\tSubclass\\tMethod\\tTarget length\\tReference sequence length\\t%% Coverage of reference\\t%% Identity to reference\\n' > ${meta.id}_amrfinder.tsv
    touch versions.yml
    """
}
