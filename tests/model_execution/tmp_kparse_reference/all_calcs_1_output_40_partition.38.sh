#!/bin/bash
SCRIPT=$(readlink -f "$0") && cd $(dirname "$SCRIPT")

# --- Script Init ---
set -euET -o pipefail
shopt -s inherit_errexit 2>/dev/null || echo "WARNING: Unable to set inherit_errexit. Possibly unsupported by this shell, Subprocess failures may not be detected."

mkdir -p log
rm -R -f log/*

# --- Setup run dirs ---

find output -type f -not -name '*summary-info*' -not -name '*.json' -exec rm -R -f {} +

rm -R -f /tmp/%FIFO_DIR%/fifo/*
rm -R -f work/*
mkdir work/kat/

mkdir work/gul_S1_summaryleccalc
mkdir work/gul_S1_summaryaalcalc
mkdir work/il_S1_summaryleccalc
mkdir work/il_S1_summaryaalcalc

mkfifo /tmp/%FIFO_DIR%/fifo/gul_P39

mkfifo /tmp/%FIFO_DIR%/fifo/gul_S1_summary_P39
mkfifo /tmp/%FIFO_DIR%/fifo/gul_S1_summary_P39.idx
mkfifo /tmp/%FIFO_DIR%/fifo/gul_S1_eltcalc_P39
mkfifo /tmp/%FIFO_DIR%/fifo/gul_S1_summarycalc_P39
mkfifo /tmp/%FIFO_DIR%/fifo/gul_S1_pltcalc_P39

mkfifo /tmp/%FIFO_DIR%/fifo/il_P39

mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_summary_P39
mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_summary_P39.idx
mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_eltcalc_P39
mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_summarycalc_P39
mkfifo /tmp/%FIFO_DIR%/fifo/il_S1_pltcalc_P39



# --- Do insured loss computes ---
eltcalc -s < /tmp/%FIFO_DIR%/fifo/il_S1_eltcalc_P39 > work/kat/il_S1_eltcalc_P39 & pid1=$!
summarycalctocsv -s < /tmp/%FIFO_DIR%/fifo/il_S1_summarycalc_P39 > work/kat/il_S1_summarycalc_P39 & pid2=$!
pltcalc -s < /tmp/%FIFO_DIR%/fifo/il_S1_pltcalc_P39 > work/kat/il_S1_pltcalc_P39 & pid3=$!
tee < /tmp/%FIFO_DIR%/fifo/il_S1_summary_P39 /tmp/%FIFO_DIR%/fifo/il_S1_eltcalc_P39 /tmp/%FIFO_DIR%/fifo/il_S1_summarycalc_P39 /tmp/%FIFO_DIR%/fifo/il_S1_pltcalc_P39 work/il_S1_summaryaalcalc/P39.bin work/il_S1_summaryleccalc/P39.bin > /dev/null & pid4=$!
tee < /tmp/%FIFO_DIR%/fifo/il_S1_summary_P39.idx work/il_S1_summaryaalcalc/P39.idx work/il_S1_summaryleccalc/P39.idx > /dev/null & pid5=$!
summarycalc -m -f  -1 /tmp/%FIFO_DIR%/fifo/il_S1_summary_P39 < /tmp/%FIFO_DIR%/fifo/il_P39 &

# --- Do ground up loss computes ---
eltcalc -s < /tmp/%FIFO_DIR%/fifo/gul_S1_eltcalc_P39 > work/kat/gul_S1_eltcalc_P39 & pid6=$!
summarycalctocsv -s < /tmp/%FIFO_DIR%/fifo/gul_S1_summarycalc_P39 > work/kat/gul_S1_summarycalc_P39 & pid7=$!
pltcalc -s < /tmp/%FIFO_DIR%/fifo/gul_S1_pltcalc_P39 > work/kat/gul_S1_pltcalc_P39 & pid8=$!
tee < /tmp/%FIFO_DIR%/fifo/gul_S1_summary_P39 /tmp/%FIFO_DIR%/fifo/gul_S1_eltcalc_P39 /tmp/%FIFO_DIR%/fifo/gul_S1_summarycalc_P39 /tmp/%FIFO_DIR%/fifo/gul_S1_pltcalc_P39 work/gul_S1_summaryaalcalc/P39.bin work/gul_S1_summaryleccalc/P39.bin > /dev/null & pid9=$!
tee < /tmp/%FIFO_DIR%/fifo/gul_S1_summary_P39.idx work/gul_S1_summaryaalcalc/P39.idx work/gul_S1_summaryleccalc/P39.idx > /dev/null & pid10=$!
summarycalc -m -i  -1 /tmp/%FIFO_DIR%/fifo/gul_S1_summary_P39 < /tmp/%FIFO_DIR%/fifo/gul_P39 &

eve 39 40 | getmodel | gulcalc -S100 -L100 -r -a1 -i - | tee /tmp/%FIFO_DIR%/fifo/gul_P39 | fmcalc -a2 > /tmp/%FIFO_DIR%/fifo/il_P39  &

wait $pid1 $pid2 $pid3 $pid4 $pid5 $pid6 $pid7 $pid8 $pid9 $pid10


# --- Do insured loss kats ---

kat -s work/kat/il_S1_eltcalc_P39 > output/il_S1_eltcalc.csv & kpid1=$!
kat work/kat/il_S1_pltcalc_P39 > output/il_S1_pltcalc.csv & kpid2=$!
kat work/kat/il_S1_summarycalc_P39 > output/il_S1_summarycalc.csv & kpid3=$!

# --- Do ground up loss kats ---

kat -s work/kat/gul_S1_eltcalc_P39 > output/gul_S1_eltcalc.csv & kpid4=$!
kat work/kat/gul_S1_pltcalc_P39 > output/gul_S1_pltcalc.csv & kpid5=$!
kat work/kat/gul_S1_summarycalc_P39 > output/gul_S1_summarycalc.csv & kpid6=$!
wait $kpid1 $kpid2 $kpid3 $kpid4 $kpid5 $kpid6

