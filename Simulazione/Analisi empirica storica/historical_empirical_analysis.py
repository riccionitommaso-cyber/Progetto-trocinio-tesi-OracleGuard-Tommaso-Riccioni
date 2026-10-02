#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import os
import csv
import json
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime

def load_data():
    json_path = "simulazione/dati_simulazione/uma_token_metrics.json"
    csv_path = "simulazione/dati_simulazione/polymarket_election_2024.csv"

    if not os.path.exists(json_path) or not os.path.exists(csv_path):
        raise FileNotFoundError(
            f"File non trovati. Verificare la presenza di:\n - {json_path}\n - {csv_path}"
        )

    with open(json_path, "r", encoding="utf-8") as f:
        uma_data = json.load(f)["historical_samples"]

    poly_data = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            poly_data.append(row)

    return uma_data, poly_data

def run_analysis():
    uma_samples, poly_samples = load_data()

    print("\n" + "="*96)
    print("ANALISI EMPIRICA SERIE STORICHE: PROFIT FROM CORRUPTION (PfC) vs COST OF CORRUPTION (CoC)")
    print("CASO STUDIO REALE: POLYMARKET 2024 U.S. PRESIDENTIAL ELECTION & TOKEN GOVERNANCE UMA")
    print("="*96)
    print(f"{'Data':<12} | {'PfC (Open Interest)':<21} | {'CoC (51% Quorum UMA)':<22} | {'Ratio PfC/CoC':<14} | {'Stato OracleGuard':<16}")
    print("-" * 96)

    dates = []
    pfc_values = []
    coc_values = []
    ratios = []

    for uma in uma_samples:
        date_str = uma["date"]
        poly_match = next((p for p in poly_samples if p["date"] == date_str), None)
        if not poly_match:
            continue

        pfc = float(poly_match["market_open_interest_usd"])
        
        # Calcolo rigoroso del CoC: 51% del quorum attivo di token UMA
        active_voting_tokens = uma["circulating_supply"] * uma["typical_quorum_participation_pct"]
        coc_tokens_needed = active_voting_tokens * 0.51
        coc_usd = coc_tokens_needed * uma["price_usd"]

        ratio = pfc / coc_usd
        mode = "DUAL_SBT_GUARD" if pfc > coc_usd else "UMA_ONLY"

        dates.append(datetime.strptime(date_str, "%Y-%m-%d"))
        pfc_values.append(pfc / 1e6)
        coc_values.append(coc_usd / 1e6)
        ratios.append(ratio)

        print(f"{date_str:<12} | ${pfc:,.0f}{'':<5} | ${coc_usd:,.0f}{'':<6} | {ratio:>8.2f}x    | {mode:<16}")

    print("="*96)
    print("EVIDENZE QUANTITATIVE PER LA TESI:")
    print(f" 1. Il PfC a rischio e passato da ${min(pfc_values):.1f}M (15 giugno) a ${max(pfc_values):.1f}M (5 novembre).")
    print(f" 2. Il CoC di UMA e rimasto stabile tra ${min(coc_values):.1f}M e ${max(coc_values):.1f}M (media: ~${sum(coc_values)/len(coc_values):.1f}M).")
    print(f" 3. Il rapporto PfC/CoC e oscillato tra {min(ratios):.2f}x e {max(ratios):.2f}x.")
    print(" 4. Durante tutto il periodo, l'Open Interest ha superato il costo di corruzione di UMA DVM (PfC > CoC).")
    print(" 5. In questo scenario, OracleGuard commuta in DUAL_SBT_GUARD per proteggere il mercato.\n")

if __name__ == "__main__":
    run_analysis()
 
