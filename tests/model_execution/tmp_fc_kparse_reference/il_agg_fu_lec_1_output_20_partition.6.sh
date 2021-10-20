#!/usr/bin/env -S bash -euET -o pipefail -O inherit_errexit
SCRIPT=$(readlink -f "$0") && cd $(dirname "$SCRIPT")

# --- Script Init ---

mkdir -p log
rm -R -f log/*

# --- Setup run dirs ---

find output -type f -not -name '*summary-info*' -not -name '*.json' -exec rm -R -f {} +
mkdir output/full_correlation/

rm -R -f /tmp/%FIFO_DIR%/fifo/*
mkdir /tmp/%FIFO_DIR%/fifo/full_correlation/
rm -R -f work/*
mkdir work/kat/
mkdir work/full_correlation/
mkdir work/full_correlation/kat/

mkdir work/il_S1_summaryleccalc
mkdir work/full_correlation/il_S1_summaryleccalc

mkfifo /tmp/%FIFO_DIR%/fifo/full_correlation/gul_fc_P7

mkfifo /tmp/%FIFO_DIR%/fifo/il_P7

mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_summary_P7
mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_summary_P7.idx

mkfifo /tmp/%FIFO_DIR%/fifo/full_correlation/il_P7

mkfifo /tmp/%FIFO_DIR%/fifo/full_correlation/il_S1_summary_P7
mkfifo /tmp/%FIFO_DIR%/fifo/full_correlation/il_S1_summary_P7.idx



# --- Do insured loss computes ---
tee < /tmp/%FIFO_DIR%/fifo/il_S1_summary_P7 work/il_S1_summaryleccalc/P7.bin > /dev/null & pid1=$!
tee < /tmp/%FIFO_DIR%/fifo/il_S1_summary_P7.idx work/il_S1_summaryleccalc/P7.idx > /dev/null & pid2=$!
summarycalc -m -f  -1 /tmp/%FIFO_DIR%/fifo/il_S1_summary_P7 < /tmp/%FIFO_DIR%/fifo/il_P7 &

# --- Do insured loss computes ---
tee < /tmp/%FIFO_DIR%/fifo/full_correlation/il_S1_summary_P7 work/full_correlation/il_S1_summaryleccalc/P7.bin > /dev/null & pid3=$!
tee < /tmp/%FIFO_DIR%/fifo/full_correlation/il_S1_summary_P7.idx work/full_correlation/il_S1_summaryleccalc/P7.idx > /dev/null & pid4=$!
summarycalc -m -f  -1 /tmp/%FIFO_DIR%/fifo/full_correlation/il_S1_summary_P7 < /tmp/%FIFO_DIR%/fifo/full_correlation/il_P7 &

fmcalc -a2 < /tmp/%FIFO_DIR%/fifo/full_correlation/gul_fc_P7 > /tmp/%FIFO_DIR%/fifo/full_correlation/il_P7 &
eve 7 20 | getmodel | gulcalc -S100 -L100 -r -j /tmp/%FIFO_DIR%/fifo/full_correlation/gul_fc_P7 -a1 -i - | fmcalc -a2 > /tmp/%FIFO_DIR%/fifo/il_P7  &

wait $pid1 $pid2 $pid3 $pid4


# --- Do insured loss kats ---


# --- Do insured loss kats for fully correlated output ---
