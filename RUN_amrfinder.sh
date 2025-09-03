#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Usage:
# ./RUN_amrfinder_single.sh <path/to/proteins.faa|.faa.gz> <path/to/dna.fna> <path/to/annotations.gff> [path/to/amrfinder_bin]
#
# If no args are provided, defaults below (example from your case) will be used.

# --------- Defaults (cambia si quieres) ----------
DEFAULT_FAA="2_annotation/prokka/GCF_000005845.2/PROKKA_09012025.faa"
DEFAULT_FNA="2_annotation/prokka/GCF_000005845.2/PROKKA_09012025.fna"
DEFAULT_GFF="2_annotation/prokka/GCF_000005845.2/PROKKA_09012025.gff"
DEFAULT_AMRFINDER_BIN="amrfinder"   # o "mrfinder" o la ruta completa /home/usuario/.../amrfinder
OUTPUT_DIR="8_AMR"
THREADS=8
# -------------------------------------------------

faa="${1:-$DEFAULT_FAA}"
fna="${2:-$DEFAULT_FNA}"
gff="${3:-$DEFAULT_GFF}"
AMRFINDER_BIN="${4:-$DEFAULT_AMRFINDER_BIN}"

mkdir -p "$OUTPUT_DIR"

echo "Inputs:"
echo "  proteins: $faa"
echo "  dna:      $fna"
echo "  gff:      $gff"
echo "  amrfinder bin: $AMRFINDER_BIN"
echo

# Validate input files (existence). Accept .faa.gz for proteins.
if [[ ! -f "$faa" ]]; then
    echo "ERROR: archivo de proteínas no encontrado: $faa"
    exit 1
fi
if [[ ! -f "$fna" ]]; then
    echo "ERROR: archivo de DNA no encontrado: $fna"
    exit 1
fi
if [[ ! -f "$gff" ]]; then
    echo "ERROR: archivo GFF no encontrado: $gff"
    exit 1
fi

# Check amrfinder is available (or the provided path points to an executable)
if ! command -v "$AMRFINDER_BIN" >/dev/null 2>&1 && [ ! -x "$AMRFINDER_BIN" ]; then
    echo
    echo "ERROR: No se encontró '$AMRFINDER_BIN' en el PATH ni como ejecutable."
    echo "Soluciones rápidas:"
    echo "  1) Si usas conda: en tu terminal interactiva ejecuta (sólo la primera vez):"
    echo "       conda init bash"
    echo "       source ~/.bashrc"
    echo "       conda activate <env_con_amrfinder>"
    echo "     Luego vuelve a ejecutar este script desde esa misma terminal."
    echo "  2) O proporciona la ruta completa al ejecutable amrfinder/mrfinder como 4º argumento:"
    echo "       ./RUN_amrfinder_single.sh <faa> <fna> <gff> /ruta/completa/al/amrfinder"
    echo
    exit 2
fi

# Prepare protein file: if .faa.gz, decompress to temporary file
cleanup_files=()
protein_for_amr="$faa"
if [[ "$faa" == *.gz ]]; then
    tmp_prot="$(mktemp "${OUTPUT_DIR}/prot_XXXXXX.faa")"
    echo "Descomprimiendo $faa -> $tmp_prot"
    zcat "$faa" > "$tmp_prot"
    protein_for_amr="$tmp_prot"
    cleanup_files+=("$tmp_prot")
fi

# Prepare modified GFF (no sección FASTA)
tmp_gff="$(mktemp "${OUTPUT_DIR}/gff_XXXXXX.gff")"
perl -ne 'last if /^##FASTA/; s/(\W)Name=/$1OldName=/i; s/\bID=([^;]+)/ID=$1;Name=$1/ if $_ =~ /ID=/ && $_ !~ /Name=/; print' "$gff" > "$tmp_gff"
cleanup_files+=("$tmp_gff")

sample_base="$(basename "$protein_for_amr")"
sample_base="${sample_base%%.*}"

out_tsv="$OUTPUT_DIR/${sample_base}_amrfinder.tsv"
out_log="$OUTPUT_DIR/${sample_base}_amrfinder.log"

echo "Ejecutando: $AMRFINDER_BIN -p $protein_for_amr -n $fna -g $tmp_gff --plus --organism Escherichia --threads $THREADS -o $out_tsv"
echo

# Run AMRFinder (foreground so puedas ver errores en consola)
/usr/bin/time -v "$AMRFINDER_BIN" \
    -p "$protein_for_amr" \
    -n "$fna" \
    -g "$tmp_gff" \
    --plus --organism Escherichia \
    --threads "$THREADS" \
    -o "$out_tsv" > "$out_log" 2>&1

rc=$?
if [ $rc -ne 0 ]; then
    echo "AMRFinder terminó con código $rc. Revisa el log: $out_log"
else
    echo "AMRFinder finalizó correctamente. TSV: $out_tsv  Log: $out_log"
fi

# Cleanup temporales
for f in "${cleanup_files[@]:-}"; do
    [ -f "$f" ] && rm -f "$f"
done

exit $rc

