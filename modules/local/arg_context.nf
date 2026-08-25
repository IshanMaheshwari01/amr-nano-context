/*
 * The point of the pipeline. Joins five per-sample tables into one row per ARG
 * that carries the gene, its replicon type and its likely host organism.
 */
process ARG_CONTEXT {
    tag "${meta.id}"
    label 'process_low'
    container params.container_pandas

    input:
    tuple val(meta), path(amrfinder), path(abricate), path(genomad), path(kraken_contigs), path(flye_info)

    output:
    tuple val(meta), path("${meta.id}_arg_context.tsv"),      emit: table
    tuple val(meta), path("${meta.id}_arg_context_mqc.tsv"),  emit: mqc
    tuple val(meta), path("${meta.id}_arg_summary.json"),     emit: summary
    path "versions.yml",                                      emit: versions

    script:
    """
    arg_context.py \\
        --sample ${meta.id} \\
        --amrfinder ${amrfinder} \\
        --abricate ${abricate} \\
        --genomad ${genomad} \\
        --kraken-contigs ${kraken_contigs} \\
        --flye-info ${flye_info} \\
        --min-id ${params.min_arg_id} \\
        --min-cov ${params.min_arg_cov} \\
        --plasmid-score ${params.plasmid_score} \\
        --max-plasmid-len ${params.max_plasmid_len} \\
        --out ${meta.id}_arg_context.tsv \\
        --out-mqc ${meta.id}_arg_context_mqc.tsv \\
        --out-summary ${meta.id}_arg_summary.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //')
        pandas: \$(python3 -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """

    stub:
    """
    printf 'sample\\targ\\tclass\\tcontig\\tmobility\\thost_taxon\\n' > ${meta.id}_arg_context.tsv
    printf 'sample\\targ\\tclass\\tcontig\\tmobility\\thost_taxon\\n' > ${meta.id}_arg_context_mqc.tsv
    echo '{}' > ${meta.id}_arg_summary.json
    touch versions.yml
    """
}
