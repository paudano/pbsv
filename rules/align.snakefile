"""
Align cells for PBSV.
"""

def _pbsv_align_get_bams_per_sample(wildcards):
    """
    Get all BAMs for one sample.
    """

    # Set BAM file pattern
    bam_pattern = 'temp/align/{SAMPLE}/movie/movie_{MOVIE}.bam'

    # Get subread table
    subread_table = pd.read_table('init/subread_table.tab', header=0)

    subread_table = subread_table.loc[subread_table['SAMPLE'] == wildcards.sample]

    if subread_table.shape[0] == 0:
        raise RuntimeError('No input for sample in subread table: {}'.format(wildcards.sample))

    # Return a list of BAM files
    return [bam_pattern.format(**row) for index, row in subread_table.iterrows()]


# pbsv_align_merge_bam
#
# Merge bams per sample (collapse movies).
rule pbsv_align_merge_bam:
    input:
        bam=_pbsv_align_get_bams_per_sample
    output:
        bam='align/{sample}/mapped_reads.bam',
        bai='align/{sample}/mapped_reads.bam.bai'
    shell:
        """samtools merge -O BAM -@ 4 {output.bam} {input.bam}; """
        """samtools index {output.bam}"""

# pbsv_align_get_bam
#
# Split samples into table files.
rule pbsv_align_get_bam:
    input:
        ref_fa=config['reference'],
        tab='init/{sample}/cell_table.tab'
    output:
        bam=temp('temp/align/{sample}/movie/movie_{movie}.bam'),
        bai=temp('temp/align/{sample}/movie/movie_{movie}.bam.bai')
    benchmark:
        'align/{sample}/bm/align/movie_{movie}.tab'
    run:

        # Read cell table
        df = pd.read_table(input.tab, header=0, usecols=('MOVIE', 'SUBREADS'), index_col='MOVIE', squeeze=True)

        try:
            movie = np.int32(wildcards.movie)
        except:
            raise RuntimeError('Movie wildcard is not an integer: {movie}'.format(**wildcards))

        if movie not in df.index:
            raise RuntimeError('Movie {} is not in the sample cell table: {}'.format(wildcards.movie, input.tab))

        # Initialize temporary location for samtools sort
        os.makedirs(TEMP_DIR, exist_ok=True)

        temp_dir = tempfile.mkdtemp(dir=TEMP_DIR, prefix='pbsv_align_sort_', suffix='_{}'.format(wildcards.sample))

        # Set parameter dictionary
        param_dict = {
            'SAMPLE': wildcards.sample,
            'MOVIE': movie,
            'INPUT_FILE': df.loc[movie],
            'REF_FA': input.ref_fa,
            'OUTPUT_FILE': output.bam,
            'TEMP_DIR': temp_dir
        }

        # Report temp directory
        print('Aligning: {sample} movie {movie}'.format(**wildcards))
        print('Temp directory: {}'.format(temp_dir))

        # Align
        shell((
            """pbsv fasta {INPUT_FILE} | """
            """minimap2 -x map-pb -a --eqx -L -O 5,56 -E 4,1 -B 5 --secondary=no -z 400,50 -r 2k -Y -R"""
                """ "@RG\\tID:rg{SAMPLE}-{MOVIE}\\tSM:{SAMPLE}" {REF_FA} - | """
            """samtools sort -T {TEMP_DIR}/sort_ > """
            """{OUTPUT_FILE}; """
            """rm -rf {TEMP_DIR}; """
            """samtools index {OUTPUT_FILE}"""
        ).format(**param_dict))