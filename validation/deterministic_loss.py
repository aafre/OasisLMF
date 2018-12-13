#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Deterministic loss validation
"""
import argparse
import itertools
import multiprocessing
import os
import subprocess
import time

import pandas as pd

import oasislmf.model_execution.bin as ktools_bin
from oasislmf.exposures.manager import OasisExposuresManager as oem
from oasislmf.exposures import oed
from oasislmf.keys.lookup import OasisLookupFactory as olf
from oasislmf.utils.concurrency import (
    multithread,
    Task,
)

from tests.data import (
    canonical_oed_accounts_profile as cap,
    canonical_oed_exposures_profile as cep,
    oed_fm_agg_profile as fmap,
)


def generate_oasis_files(
    input_dir,
    srcexp_fp,
    srcexptocan_trans_fp,
    srcacc_fp,
    srcacctocan_trans_fp,
    canexp_profile,
    canacc_profile,
    fm_agg_profile
):
    """
    Generates Oasis input files (GUL + FM/IL) using OED source exposure +
    accounts data, and canonical OED exposure and accounts profiles and
    an FM OED aggregation profile, in the specified ``input_dir``, using
    simulated keys data. This is a model independent way of generating
    Oasis files.
    """

    # Create exposure manager instance
    manager = oem()

    # Generate the canonical loc./exposure and accounts files from the source files (in ``input_dir``)
    canexp_fp = os.path.join(input_dir, 'canexp.csv')
    manager.transform_source_to_canonical(
        source_exposures_file_path=srcexp_fp,
        source_to_canonical_exposures_transformation_file_path=srcexptocan_trans_fp,
        canonical_exposures_file_path=canexp_fp
    )
    canacc_fp = os.path.join(input_dir, 'canacc.csv')
    manager.transform_source_to_canonical(
        source_type='accounts',
        source_accounts_file_path=srcacc_fp,
        source_to_canonical_accounts_transformation_file_path=srcacctocan_trans_fp,
        canonical_accounts_file_path=canacc_fp
    )

    # Mock up the keys file (in ``input_dir``) - keys are generated for assumed
    # coverage type set of {1,2,3,4} present in the source exposure file. These
    # are the columns
    #
    # BuildingTIV,OtherTIV,ContentsTIV,BITIV
    #
    # This means that if there are n locations in the source file then 4 x n 
    # keys items are written out in the keys file. This means that 4 x n GUL
    # items will be present in the items and coverages and GUL summary xref files.
    n = len(pd.read_csv(srcexp_fp))
    keys = [
        {'id': i + 1 , 'peril_id': 1, 'coverage_type': j, 'area_peril_id': i + 1, 'vulnerability_id': i + 1}
        for i, j in itertools.product(range(n), [1,2,3,4])
    ]
    keys_fp, _ = olf.write_oasis_keys_file(keys, os.path.join(input_dir, 'keys.csv'))

    # Generate the GUL files (in ``input_dir``)
    gul_items_df, canexp_df = manager.load_gul_items(
        canexp_profile,
        canexp_fp,
        keys_fp
    )
    gul_files = {
        'items': os.path.join(input_dir, 'items.csv'),
        'coverages': os.path.join(input_dir, 'coverages.csv'),
        'gulsummaryxref': os.path.join(input_dir, 'gulsummaryxref.csv')
    }
    concurrent_tasks = (
        Task(getattr(manager, 'write_{}_file'.format(f)), args=(gul_items_df.copy(deep=True), gul_files[f],), key=f)
        for f in gul_files
    )
    num_ps = min(len(gul_files), multiprocessing.cpu_count())
    for _, _ in multithread(concurrent_tasks, pool_size=num_ps):
        pass

    # Generate the FM files (in ``input_dir``)
    fm_items_df, canacc_df = manager.load_fm_items(
        canexp_df,
        gul_items_df,
        canexp_profile,
        canacc_profile,
        canacc_fp,
        fmap
    )
    fm_files = {
        'fm_policytc': os.path.join(input_dir, 'fm_policytc.csv'),
        'fm_programme': os.path.join(input_dir, 'fm_programme.csv'),
        'fm_profile': os.path.join(input_dir, 'fm_profile.csv'),
        'fm_xref': os.path.join(input_dir, 'fm_programme.csv'),
        'fmsummaryxref': os.path.join(input_dir, 'fmsummaryxref.csv')
    }

    concurrent_tasks = (
        Task(getattr(manager, 'write_{}_file'.format(f)), args=(fm_items_df.copy(deep=True), fm_files[f],), key=f)
        for f in fm_files
    )
    num_ps = min(len(fm_files), multiprocessing.cpu_count())
    n = len(fm_files)
    for _, _ in multithread(concurrent_tasks, pool_size=num_ps):
        pass

    # By this stage all the input files, including source and intermediate files
    # should be in ``input_dir``.

def apply_fm(input_dir, loss_percentage_of_tiv=1.0, net=False):
    # Generate an items and coverages dataframe and set column types (important!!)
    items_df = pd.merge(
        pd.read_csv(os.path.join(input_dir, 'items.csv')),
        pd.read_csv(os.path.join(input_dir, 'coverages.csv'))
    )
    for col in items_df:
        if col != 'tiv':
            items_df[col] = items_df[col].astype(int)
        else:
            items_df[col] = items_df[col].astype(float)

    guls_list = []
    for item_id, tiv in zip(items_df['item_id'], items_df['tiv']):
        event_loss = loss_percentage_of_tiv * tiv
        guls_list.append(
            oed.GulRecord(event_id=1, item_id=item_id, sidx=-1, loss=event_loss))
        guls_list.append(
            oed.GulRecord(event_id=1, item_id=item_id, sidx=-2, loss=0))
        guls_list.append(
            oed.GulRecord(event_id=1, item_id=item_id, sidx=1, loss=event_loss))
    guls_df = pd.DataFrame(guls_list)
    guls_df.to_csv(os.path.join(input_dir, "guls.csv"), index=False)
    # Debugging - print(guls_df)

    net_flag = ""
    if net:
        net_flag = "-n"
    command = "gultobin -S 1 < guls.csv | fmcalc -p direct {} -a {} | tee ils.bin | fmtocsv > ils.csv".format(
        net_flag, oed.ALLOCATE_TO_ITEMS_BY_PREVIOUS_LEVEL_ALLOC_ID)
    proc = subprocess.Popen(command, shell=True)
    proc.wait()
    if proc.returncode != 0:
        raise Exception("Failed to run fm")
    losses_df = pd.read_csv("ils.csv")
    losses_df.drop(losses_df[losses_df.sidx != 1].index, inplace=True)
    del losses_df['sidx']
    guls_df.drop(guls_df[guls_df.sidx != 1].index, inplace=True)
    del guls_df['event_id']
    del guls_df['sidx']
    guls_df = pd.merge(
        self.xref_descriptions,
        guls_df, left_on=['xref_id'], right_on=['item_id'])
    losses_df = pd.merge(
        guls_df,
        losses_df, left_on='xref_id', right_on='output_id',
        suffixes=["_gul", "_il"])
    del losses_df['event_id']
    del losses_df['output_id']
    del losses_df['xref_id']
    del losses_df['item_id']

    return losses_df

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Validate deterministic losses')
    parser.add_argument(
        '-o', '--output-dir', type=str, required=True, default=os.path.join(os.getcwd(), 'output'),
        help='Output dir')
    parser.add_argument(
        '-i', '--input-dir', type=str, default=os.getcwd(), required=True,
        help='Input dir - should contain the OED exposure + accounts data + other assets required for Oasis files generation via MDK')
    parser.add_argument(
        '-l', '--loss-factor', type=float, default=1.0,
        help='Loss factor to apply to TIVs.')

    args = parser.parse_args()

    output_dir = args.output_dir
    input_dir = args.input_dir
    loss_factor = args.loss_factor

    # Create file paths for the source exposure + accounts files + transformation files
    # and all these are assumed to be already present in the specified input directory
    srcexp_fp = os.path.join(input_dir, 'location.csv')
    srcexptocan_trans_fp = os.path.join(input_dir, 'MappingMapToOED_CanLocA.xslt')

    srcacc_fp = os.path.join(input_dir, 'account.csv')
    srcacctocan_trans_fp = os.path.join(input_dir, 'MappingMapToOED_CanAccA.xslt')

    # Invoke Oasis files generation
    generate_oasis_files(
        input_dir,
        srcexp_fp,
        srcexptocan_trans_fp,
        srcacc_fp,
        srcacctocan_trans_fp,
        cep,
        cap,
        fmap
    )

    ## this step doesn't complete because of an error in `apply_fm`
    ##losses_df = apply_fm(input_dir, loss_percentage_of_tiv=loss_factor)
    ##print(losses_df)
