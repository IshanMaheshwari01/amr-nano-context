process AMRFINDERPLUS {
    tag "${meta.id}"
    label 'process_medium'
    container params.container_amrfinder

    input:
    tuple val(meta), path(assembly)
    path db

    output:
    tuple val(meta), path("${meta.id}_amrfinder.tsv"), emit: report
    path "versions.yml",                               emit: versions

    script:
    """
    # The biocontainer ships without a database, so it is mounted in rather than
    # downloaded at runtime: fetching inside the task would give a different
    # database on every run and make results non-reproducible.
    #
    # 'latest' is a symlink to the versioned directory in a normal install; some
    # layouts point straight at the versioned directory instead.
    if [ -d "${db}/latest" ]; then
        DB_DIR="${db}/latest"
    else
        DB_DIR="${db}"
    fi

    amrfinder \\
        --nucleotide ${assembly} \\
        --database "\$DB_DIR" \\
        --plus \\
        --threads ${task.cpus} \\
        --output ${meta.id}_amrfinder.tsv \\
        --name ${meta.id}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        amrfinderplus: \$(amrfinder --version)
        amrfinderplus_db: \$(basename \$(readlink -f "\$DB_DIR"))
    END_VERSIONS
    """

    stub:
    """
    printf 'Name\\tContig id\\tStart\\tStop\\tStrand\\tElement symbol\\tElement name\\tScope\\tType\\tSubtype\\tClass\\tSubclass\\tMethod\\tTarget length\\tReference sequence length\\t%% Coverage of reference\\t%% Identity to reference\\n' > ${meta.id}_amrfinder.tsv
    touch versions.yml
    """
}
