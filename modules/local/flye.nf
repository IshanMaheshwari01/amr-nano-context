process FLYE {
    tag "${meta.id}"
    label 'process_high'
    container params.container_flye

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_assembly.fasta"),      emit: assembly
    tuple val(meta), path("${meta.id}_assembly_info.txt"),   emit: info
    tuple val(meta), path("${meta.id}_assembly_graph.gfa"),  emit: graph, optional: true
    path "versions.yml",                                     emit: versions

    script:
    def args = task.ext.args ?: '--meta'
    """
    flye \\
        ${params.flye_mode} ${reads} \\
        ${args} \\
        --threads ${task.cpus} \\
        --out-dir flye_out

    mv flye_out/assembly.fasta       ${meta.id}_assembly.fasta
    mv flye_out/assembly_info.txt    ${meta.id}_assembly_info.txt
    if [ -f flye_out/assembly_graph.gfa ]; then
        mv flye_out/assembly_graph.gfa ${meta.id}_assembly_graph.gfa
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        flye: \$(flye --version)
    END_VERSIONS
    """

    stub:
    """
    echo ">contig_1" > ${meta.id}_assembly.fasta
    echo "ACGTACGTACGT" >> ${meta.id}_assembly.fasta
    printf '#seq_name\\tlength\\tcov.\\tcirc.\\trepeat\\tmult.\\talt_group\\tgraph_path\\n' > ${meta.id}_assembly_info.txt
    printf 'contig_1\\t12\\t10\\tN\\tN\\t1\\t*\\t1\\n' >> ${meta.id}_assembly_info.txt
    touch versions.yml
    """
}
