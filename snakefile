import os

from os import path
from snakemake.utils import min_version, validate
from jsonschema import validate as js_validate
import yaml

min_version("7.18")

# ---------------------------------------------------

# load configuration from config.yml
with open("config.yml") as f:
    config = yaml.safe_load(f)

# define schema for configuration file
config_schema = {
    "type": "object",
    "properties": {
        "workdir": {"type": "string"},
        "sample_name": {"type": "string"},
        "reads_fastq": {"type": "string"},
        "run_pychopper": {"type": "boolean"},
        "pychopper_opts": {"type": "string"},
        "concatenate": {"type": "boolean"},
        "genome": {"type": "string"},
        "minimap2_opts": {"type": "string"},
        "threads": {"type": "integer"}
    },
    "required": ["workdir", "sample_name", "reads_fastq", "run_pychopper", "concatenate", "genome", "threads"]
}

# validate the configuration file against the schema
js_validate(config, config_schema)

# set variables from configuration
workdir = config["workdir"]
sample = config["sample_name"]

rule all:
    input:
        "Nanostat/stat_out.txt",
        "processed_reads/input_reads.fq",
        "processed_reads/full_length_reads.fq",
        "alignments/minimap.bam"

# ---------------------------------------------------

rule nanostat:
    input:
        fq = config["reads_fastq"]

    output:
        ns = "Nanostat/stat_out.txt"

    threads: config["threads"]

    shell:
        """
        NanoStat -n {output.ns} -t {threads} --tsv --fastq {input.fq}
        """

# ---------------------------------------------------

rule process_reads:
    input:
        FQ = config["reads_fastq"]
    output:
        pq = "processed_reads/input_reads.fq",
        flq = "processed_reads/full_length_reads.fq",
    params:
        pc = "True" if config["run_pychopper"] else "False",
        pc_opts = config["pychopper_opts"],
        concat = "True" if config["concatenate"] else "False",
    threads: config["threads"]
    shell:
        """
        mkdir -p processed_reads;

        if [[ {params.concat} == "True" ]];
        then
            find {input.FQ}  -regextype posix-extended -regex '.*\.(fastq|fq)$' -exec cat {{}} \\; > processed_reads/input_reads.fq
        else
            ln -s `realpath {input.FQ}` processed_reads/input_reads.fq
        fi

        if [[ {params.pc} == "True" ]];
        then
            cd processed_reads; pychopper -m edlib -t {threads} {params.pc_opts} input_reads.fq full_length_reads.fq
            {SNAKEDIR}/scripts/generate_pychopper_stats.py --data cdna_classifier_report.tsv --output .
        else
            ln -s `realpath processed_reads/input_reads.fq` processed_reads/full_length_reads.fq
        fi
        """
# ---------------------------------------------------

rule map_reads:
    input:
        genome = config["genome"],
        FQ = rules.process_reads.output.flq
    output:
        sam = temp("alignments/minimap.sam"),
        bam = "alignments/minimap.bam"
    threads: config["threads"]
    params: 
        minimap_options = config["minimap2_opts"]
    shell:
        """
        mkdir -p alignments;

        minimap2 -ax splice {params.minimap_options} -t {threads} {output.sam} {input.genome} {input.FQ} \
        | samtools sort -@ {threads} -O SAM -o {output.bam};
        samtools index {output.bam}
        """
