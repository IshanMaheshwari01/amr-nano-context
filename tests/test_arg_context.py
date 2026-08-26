"""Unit tests for the context-joining logic.

These test the part of the pipeline that is my own code rather than a wrapped
tool. The tools have their own test suites; the join and the mobility heuristic
do not.
"""

import pathlib
import sys

import pandas as pd
import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "bin"))

import arg_context
import validate_resistome as vr


def test_mobility_high_plasmid_score():
    row = pd.Series({"plasmid_score": 0.95, "chromosome_score": 0.02,
                     "circular": "N", "contig_len": 40000})
    call, reason = arg_context.call_mobility(row, 0.7, 500000)
    assert call == "plasmid"
    assert "0.95" in reason


def test_mobility_small_circular_contig_without_genomad_signal():
    row = pd.Series({"plasmid_score": 0.1, "chromosome_score": 0.4,
                     "circular": "Y", "contig_len": 5000})
    call, _ = arg_context.call_mobility(row, 0.7, 500000)
    assert call == "plasmid"


def test_mobility_long_contig_is_chromosome():
    row = pd.Series({"plasmid_score": 0.1, "chromosome_score": 0.2,
                     "circular": "N", "contig_len": 3_000_000})
    call, _ = arg_context.call_mobility(row, 0.7, 500000)
    assert call == "chromosome"


def test_mobility_returns_ambiguous_rather_than_guessing():
    row = pd.Series({"plasmid_score": 0.3, "chromosome_score": 0.3,
                     "circular": "N", "contig_len": 20000})
    call, reason = arg_context.call_mobility(row, 0.7, 500000)
    assert call == "ambiguous"
    assert reason == "no confident signal"


@pytest.mark.parametrize("raw,expected", [
    ("blaTEM-1B", "blatem"),
    ("blaTEM-1", "blatem"),
    ("blaTEM", "blatem"),
    ("tet(M)", "tetm"),
    ("aph(3')-IIIa", "aph3iiia"),
    ("", ""),
])
def test_gene_normalisation(raw, expected):
    assert vr.normalise_gene(raw) == expected


def test_genus_extraction():
    assert vr.genus("Escherichia coli") == "escherichia"
    assert vr.genus("  Staphylococcus aureus (taxid 1280)") == "staphylococcus"
    assert vr.genus("") == ""


def test_genus_matches_across_naming_conventions():
    """Regression: Kraken2 writes 'Escherichia coli', the truth set writes
    'Escherichia_coli' because it comes from a filename. Splitting on whitespace
    alone made every host comparison fail and reported accuracy 0.0."""
    assert vr.genus("Escherichia_coli") == vr.genus("Escherichia coli (taxid 562)")
    assert vr.genus("Staphylococcus_aureus") == vr.genus("Staphylococcus aureus")
    assert vr.genus("Enterococcus_faecalis") == "enterococcus"


def test_prf_perfect():
    m = vr.prf(10, 0, 0)
    assert m["precision"] == 1.0 and m["recall"] == 1.0 and m["f1"] == 1.0


def test_prf_no_calls_does_not_divide_by_zero():
    m = vr.prf(0, 0, 0)
    assert m["f1"] == 0.0


def test_amrfinder_column_aliases_v3_and_v4():
    v4 = pd.DataFrame(columns=["Element symbol", "Contig id", "Start"])
    v3 = pd.DataFrame(columns=["Gene symbol", "Contig id", "Start"])
    assert arg_context.resolve_columns(v4)["gene"] == "Element symbol"
    assert arg_context.resolve_columns(v3)["gene"] == "Gene symbol"


def test_missing_required_column_fails_loudly():
    bad = pd.DataFrame(columns=["Something else"])
    with pytest.raises(SystemExit):
        arg_context.resolve_columns(bad)


def test_type_map_prefers_truth_label_over_observed():
    """A gene present in both should take the truth set's type, since that is the
    reference. Observed types only fill gaps for spurious calls."""
    truth = pd.DataFrame({"gene_norm": ["tetm"], "element_type": ["AMR"]})
    obs = pd.DataFrame({"gene_norm": ["tetm"], "element_type": ["STRESS"]})
    assert vr.build_type_map(truth, obs)["tetm"] == "AMR"


def test_type_map_falls_back_to_observed_for_spurious_calls():
    """A spurious call has no truth entry. Without the fallback it would be
    typeless and silently dropped from every per-type figure."""
    truth = pd.DataFrame({"gene_norm": ["tetm"], "element_type": ["AMR"]})
    obs = pd.DataFrame({"gene_norm": ["tetm", "inlb"],
                        "element_type": ["AMR", "VIRULENCE"]})
    m = vr.build_type_map(truth, obs)
    assert m["inlb"] == "VIRULENCE"


def test_type_map_normalises_case_and_whitespace():
    truth = pd.DataFrame({"gene_norm": ["tetm"], "element_type": ["  amr "]})
    obs = pd.DataFrame({"gene_norm": [], "element_type": []})
    assert vr.build_type_map(truth, obs)["tetm"] == "AMR"


def test_type_map_handles_missing_column():
    """Older truth sets have no element_type. Should return empty, not raise."""
    truth = pd.DataFrame({"gene_norm": ["tetm"]})
    obs = pd.DataFrame({"gene_norm": ["tetm"]})
    assert vr.build_type_map(truth, obs) == {}
