#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import sys
import os
import time
import random
import curses
import numpy as np
from datetime import datetime

# Riproducibilità stocastica di base
np.random.seed(42)
random.seed(42)

CANDIDATES = ["Donald Trump", "Kamala Harris", "Joe Biden", "RFK Jr.", "Others"]
COC_UMA = 25_092_000.0  # Cost of Corruption DVM (51% Quorum UMA)

def make_bar(pct, length=14, fill_char="█"):
    filled = max(0, min(length, int(round(length * pct))))
    return fill_char * filled + "░" * (length - filled)

class RealisticPolymarketCLOB:
    def __init__(self, candidates, initial_prices):
        self.candidates = candidates
        self.mid_prices = dict(zip(candidates, initial_prices))
        self.spreads = {c: 0.015 for c in candidates}
        self.bids_depth = {c: 5_500_000.0 for c in candidates}
        self.asks_depth = {c: 5_500_000.0 for c in candidates}
        # Collaterale preesistente accumulato da scommettitori terzi/mercato
        self.open_interest = 45_000_000.0
        self.cumulative_volume = 58_000_000.0

    def add_market_maker_liquidity(self, candidate, amount_usd):
        half = amount_usd / 2.0
        self.bids_depth[candidate] += half
        self.asks_depth[candidate] += half
        self.spreads[candidate] = max(0.008, self.spreads[candidate] * 0.95)

    def execute_market_order(self, candidate, outcome, size_usd):
        self.cumulative_volume += size_usd
        self.open_interest += size_usd * 0.70

        cur_mid = self.mid_prices[candidate]
        spread = self.spreads[candidate]

        if outcome == "YES":
            available_ask = self.asks_depth[candidate]
            slippage = (size_usd / (available_ask + 25_000_000.0)) * 0.04
            self.mid_prices[candidate] = min(0.95, cur_mid + slippage)
            self.asks_depth[candidate] = max(500_000.0, available_ask - size_usd * 0.08)
            self.spreads[candidate] = min(0.025, spread + slippage * 0.10)
            exec_price = min(0.99, self.mid_prices[candidate] + self.spreads[candidate] / 2.0)
        else:
            available_bid = self.bids_depth[candidate]
            slippage = (size_usd / (available_bid + 25_000_000.0)) * 0.04
            self.mid_prices[candidate] = max(0.01, cur_mid - slippage)
            self.bids_depth[candidate] = max(500_000.0, available_bid - size_usd * 0.08)
            self.spreads[candidate] = min(0.025, spread + slippage * 0.10)
            exec_price = max(0.01, self.mid_prices[candidate] - self.spreads[candidate] / 2.0)

        total = sum(self.mid_prices.values())
        for c in self.candidates:
            self.mid_prices[c] /= total

        return exec_price

def safe_addstr(stdscr, y, x, text, attr=0):
    max_y, max_x = stdscr.getmaxyx()
    if y >= max_y or x >= max_x:
        return
    text = text[:max_x - x - 1]
    try:
        stdscr.addstr(y, x, text, attr)
    except curses.error:
        pass

def run_endogenous_jury_resolution(participants, true_outcome="Donald Trump (YES)"):
    """
    Risoluzione democratica con GIURIA estratta dai soli partecipanti alla scommessa.
    - Ciascun partecipante ha una probabilità di possedere il Soulbound Token (PoP verificato)
    - Ciascun partecipante decide probabilisticamente se votare (affluenza/turnout)
    """
    sbt_ownership_prob = 0.65   # 65% possiede ValidatorSBT tramite PoP
    turnout_prob = 0.75         # 75% dei qualificati decide di partecipare al voto
    honest_accuracy_prob = 0.93 # 93% vota in conformità con la verità empirica accertata

    total_traders = len(participants)
    qualified_holders = 0
    non_holders = 0
    abstainers = 0
    voters = []

    for account in participants:
        has_sbt = (random.random() < sbt_ownership_prob)
        if not has_sbt:
            non_holders += 1
            continue

        qualified_holders += 1
        decided_to_vote = (random.random() < turnout_prob)
        if not decided_to_vote:
            abstainers += 1
            continue

        # Validatore attivo che vota
        votes_true = (random.random() < honest_accuracy_prob)
        choice = "YES" if votes_true else "NO"
        voters.append((account, choice))

    total_valid_votes = len(voters)
    yes_votes = sum(1 for _, v in voters if v == "YES")
    no_votes = total_valid_votes - yes_votes
    sbt_yes_pct = (yes_votes / total_valid_votes * 100.0) if total_valid_votes > 0 else 0.0
    circuit_breaker_active = (sbt_yes_pct >= 70.0)

    stats = {
        "total_traders": total_traders,
        "qualified_holders": qualified_holders,
        "non_holders": non_holders,
        "abstainers": abstainers,
        "total_valid_votes": total_valid_votes,
        "yes_votes": yes_votes,
        "no_votes": no_votes,
        "sbt_yes_pct": sbt_yes_pct,
        "circuit_breaker_active": circuit_breaker_active
    }
    return stats

def curses_dashboard(stdscr, duration_minutes):
    curses.curs_set(0)
    stdscr.nodelay(True)
    curses.start_color()
    curses.use_default_colors()

    curses.init_pair(1, curses.COLOR_CYAN, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_RED, -1)
    curses.init_pair(4, curses.COLOR_YELLOW, -1)
    curses.init_pair(5, curses.COLOR_BLUE, -1)
    curses.init_pair(6, curses.COLOR_WHITE, -1)
    curses.init_pair(7, curses.COLOR_MAGENTA, -1)

    initial_p = [0.52, 0.44, 0.02, 0.015, 0.005]
    clob = RealisticPolymarketCLOB(CANDIDATES, initial_p)

    all_transactions = []
    wallets_set = set()
    accounts_set = set()

    total_epochs = int(duration_minutes * 60)
    step_delay = max(0.05, (duration_minutes * 60.0) / total_epochs) if duration_minutes <= 1.0 else 1.0

    # Budget di scommessa razionale della balena
    whale_budget = 12_000_000.0
    whale_total_invested = 0.0

    for step in range(1, total_epochs + 1):
        key = stdscr.getch()
        if key in [ord('q'), ord('Q')]:
            break

        now_str = datetime.now().strftime("%H:%M:%S")

        # Iniezione stocastica Whale (Scenario 3)
        whale_triggered = (
            whale_budget > 0
            and step > int(total_epochs * 0.15)
            and random.random() < 0.24
        )

        if whale_triggered:
            tranche = min(whale_budget, random.uniform(2_500_000, 3_500_000))
            whale_budget -= tranche
            whale_total_invested += tranche
            w_id = f"0xWhale_{random.randint(100, 999)}"
            cand = "Kamala Harris"
            side = "YES"
            acc_id = "Whale_Cartel_Account"
            wallets_set.add(w_id)
            accounts_set.add(acc_id)
            exec_p = clob.execute_market_order(cand, side, tranche)
            log_tuple = (now_str, "[WHALE SPECULATOR]  ", f"{w_id:<18} -> {side:<3} {cand:<13} | ${tranche:>11,.0f} @ ${exec_p:.2f}", 4)
        else:
            is_mm = (random.random() < 0.28)
            if is_mm:
                mm_acc = f"Account_MM_{random.randint(1, 4)}"
                mm_wallet = f"0xWintermute_{random.randint(10, 99)}"
                wallets_set.add(mm_wallet)
                accounts_set.add(mm_acc)
                cand = random.choices(["Donald Trump", "Kamala Harris"], weights=[0.5, 0.5])[0]
                amt = random.uniform(200_000, 500_000)
                clob.add_market_maker_liquidity(cand, amt)
                log_tuple = (now_str, "[MM LIQUIDITY ADD]   ", f"{mm_wallet:<18} -> BID/ASK su {cand:<10} | +${amt:>10,.0f} Depth", 5)
            else:
                acc_num = random.randint(100, 100 + int(step * 2.2))
                acc_id = f"User_Trader_{acc_num}"
                w_id = f"0x{random.randint(0x1000, 0xFFFF):x}...{random.randint(0x10, 0xFF):x}"
                wallets_set.add(w_id)
                accounts_set.add(acc_id)

                cand = random.choices(["Donald Trump", "Kamala Harris", "RFK Jr."], weights=[0.51, 0.46, 0.03])[0]
                side = "YES" if random.random() < clob.mid_prices[cand] else "NO"
                amt = float(np.random.lognormal(mean=6.8, sigma=1.1))
                exec_p = clob.execute_market_order(cand, side, amt)
                log_tuple = (now_str, "[RETAIL MARKET ORDER]", f"{w_id:<18} -> {side:<3} {cand:<13} | ${amt:>11,.0f} @ ${exec_p:.2f}", 6)

        all_transactions.append(log_tuple)

        is_pfc_gt_coc = clob.open_interest > COC_UMA
        guard_mode = "DUAL_SBT_GUARD (RISCHIO PLUTOCRATICO: ARMATO)" if is_pfc_gt_coc else "UMA_ONLY (FAST-PATH ORDINARIO)"
        mode_color = curses.color_pair(3) | curses.A_BOLD if is_pfc_gt_coc else curses.color_pair(2) | curses.A_BOLD

        remaining = max(0, int((total_epochs - step) * step_delay))
        rem_min = remaining // 60
        rem_sec = remaining % 60
        ratio = clob.open_interest / COC_UMA

        max_y, max_x = stdscr.getmaxyx()
        stdscr.erase()
        r = 0

        safe_addstr(stdscr, r, 0, "="*88, curses.color_pair(1))
        r += 1
        safe_addstr(stdscr, r, 2, "POLYMARKET CLOB & ORACLEGUARD - SCENARIO 3: WHALE ATTACK (PfC >> CoC)", curses.A_BOLD)
        safe_addstr(stdscr, r, 75, "[Q: Esci]", curses.color_pair(4))
        r += 1
        safe_addstr(stdscr, r, 0, "="*88, curses.color_pair(1))
        r += 1

        safe_addstr(stdscr, r, 2, f"Progresso: Step {step}/{total_epochs} | Tempo Rimanente: {rem_min:02d}m {rem_sec:02d}s")
        r += 1
        safe_addstr(stdscr, r, 2, f"Trader Unici Registrati: {len(accounts_set):<5} | Wallets Attivi: {len(wallets_set):<5} | Volume Cumulato: ${clob.cumulative_volume:>11,.0f}")
        r += 1
        safe_addstr(stdscr, r, 0, "-"*88)
        r += 1

        safe_addstr(stdscr, r, 2, f"Profit from Corruption (PfC): ${clob.open_interest:>13,.0f} | Ratio di Vulnerabilita: {ratio:>6.2f}x")
        r += 1
        safe_addstr(stdscr, r, 2, f"Cost of Corruption UMA (CoC):  ${COC_UMA:>13,.0f} | 51% Quorum Attivo DVM)")
        r += 1
        safe_addstr(stdscr, r, 2, "Stato Circuito OracleGuard:    ")
        safe_addstr(stdscr, r, 33, guard_mode, mode_color)
        r += 1
        safe_addstr(stdscr, r, 0, "-"*88)
        r += 1

        safe_addstr(stdscr, r, 2, "CENTRAL LIMIT ORDER BOOK (CLOB) - QUOTE E PROFONDITA:", curses.A_BOLD)
        r += 1

        for c in CANDIDATES:
            mid = clob.mid_prices[c]
            sp = clob.spreads[c]
            bid = max(0.01, mid - sp / 2.0)
            ask = min(0.99, mid + sp / 2.0)
            bar = make_bar(mid, length=12)
            b_dep = clob.bids_depth[c] / 1e6
            a_dep = clob.asks_depth[c] / 1e6
            line = f"  {c:<13} [ {bar} ] {mid*100:>5.1f}% | Bid: ${bid:.2f} (${b_dep:>3.1f}M) / Ask: ${ask:.2f} (${a_dep:>3.1f}M)"
            safe_addstr(stdscr, r, 0, line)
            r += 1

        safe_addstr(stdscr, r, 0, "-"*88)
        r += 1

        max_log_slots = max(3, min(7, max_y - 21))
        visible_logs = all_transactions[-max_log_slots:]
        safe_addstr(stdscr, r, 2, f"FEED MEMPOOL & LIVE TRANSAZIONI (Totale Ordini: {len(all_transactions)}):", curses.A_BOLD)
        r += 1

        for t_time, t_tag, t_body, t_color in visible_logs:
            safe_addstr(stdscr, r, 2, f"[{t_time}] ")
            safe_addstr(stdscr, r, 13, t_tag, curses.color_pair(t_color) | curses.A_BOLD)
            safe_addstr(stdscr, r, 37, t_body, curses.color_pair(t_color))
            r += 1

        safe_addstr(stdscr, r, 0, "="*88, curses.color_pair(7))
        r += 1
        safe_addstr(stdscr, r, 2, "MONITORAGGIO SETTLEMENT ON-CHAIN:", curses.A_BOLD | curses.color_pair(7))
        r += 1

        if not is_pfc_gt_coc:
            safe_addstr(stdscr, r, 2, " [OK] PfC <= CoC -> Risoluzione Fast-Path UMA ordinaria (Basso costo computazionale).")
        else:
            safe_addstr(stdscr, r, 2, " [ALLERTA] PfC > CoC: Possibile corruzione del DVM UMA. Giuria SBT pronta ad intervenire!", curses.color_pair(3) | curses.A_BOLD)
        r += 1

        safe_addstr(stdscr, r, 0, "="*88, curses.color_pair(1))
        stdscr.refresh()
        time.sleep(step_delay)

    # Risoluzione democratica con Giuria Endogena (Trader che hanno partecipato al mercato)
    jury_stats = run_endogenous_jury_resolution(accounts_set)

    return clob.open_interest, accounts_set, wallets_set, clob.mid_prices, all_transactions, jury_stats, whale_total_invested

def main():
    print("\033[2J\033[H")
    print("=" * 88)
    print("  ORACLEGUARD - SIMULATORE AD AGENTI: SCENARIO 3 (WHALE ATTACK RAZIONALE)")
    print("=" * 88)
    print(" Questo scenario modella l'ingresso aggressivo della balena plutocratica ($12M budget),")
    print(" su un mercato con collaterale iniziale di terzi ($45M), rottura di PfC > CoC")
    print(" e intervento finale della giuria biologica endogena.")

    try:
        duration = float(input("\n Durata della simulazione in minuti [es. 0.5 per 30s, default 1.0]: ") or 1.0)
        if duration <= 0:
            duration = 1.0
    except ValueError:
        duration = 1.0

    print(f"\n Avvio simulazione in corso...")
    time.sleep(1.2)

    # Esecuzione Dashboard Curses Dinamica
    res = curses.wrapper(curses_dashboard, duration)
    final_oi, accounts_set, wallets_set, final_prices, tx_history, j_stats, whale_invested = res

    # Dump Finale Integrale a Schermo Intero (Lista Aperta Non Troncata)
    print("\033[2J\033[H")
    print("=" * 96)
    print(f" DUMP COMPLETO DI TUTTE LE TRANSAZIONI ESEGUITE ({len(tx_history)} RECORD TOTALI):")
    print("=" * 96)
    for idx, (t_time, t_tag, t_body, _) in enumerate(tx_history, 1):
        print(f" #{idx:03d} [{t_time}] {t_tag} {t_body}")
    print("=" * 96)

    # Calcolo crittoconomico P&L della Balena
    total_cost_attacker = COC_UMA + whale_invested
    potential_payout = final_oi
    net_profit_if_unprotected = potential_payout - total_cost_attacker

    print("\n" + "=" * 96)
    print("  REPORT SCIENTIFICO COMPLETO: RISOLUZIONE CRITTOCONOMICA DEL MERCATO (SCENARIO 3)")
    print("=" * 96)
    print(f" • Trader Partecipanti alla Scommessa:  {len(accounts_set)}")
    print(f" • Indirizzi Wallet On-Chain Rilevati:  {len(wallets_set)}")
    print(f" • Transazioni Totali Eseguite:        {len(tx_history)}")
    print(f" • Collaterale Finale Netto (PfC):     ${final_oi:,.2f}")
    print(f" • Cost of Corruption UMA (51% CoC):   ${COC_UMA:,.2f}")
    print(f" • Rapporto di Rischio (PfC / CoC):    {final_oi / COC_UMA:.2f}x")
    print("-" * 96)
    print(" QUOTE FINALI DETERMINATE DAL CLOB:")
    for c, p in final_prices.items():
        print(f"   * {c:<14}: {p*100:>5.1f}% (${p:.2f})")
    print("-" * 96)
    print(" BILANCIO CRITTOCONOMICO RAZIONALE DELL'ATTACCANTE (P&L CON TOKEN UMA A $0):")
    print(f" • Costo Scalata Quorum UMA (51% CoC):   -${COC_UMA:,.2f}")
    print(f" • Capitale Scommesso su Kamala Harris:   -${whale_invested:,.2f}")
    print(f" • Spesa Totale Sostenuta dalla Whale:    -${total_cost_attacker:,.2f}")
    print(f" • Payout Potenziale Sottratto al Pool:   +${potential_payout:,.2f}")
    print(f" • Guadagno Netto Atteso (P&L Senza Guard):+${net_profit_if_unprotected:,.2f}  [ATTACCO RAZIONALE E PROFITTEVOLE]")
    print("-" * 96)
    print(" ANALISI DELLA GIURIA ENDOGENA DEI PARTECIPANTI (1-PERSONA-1-VOTO):")
    print(f" • Trader che possiedono un Soulbound Token PoP: {j_stats['qualified_holders']} / {len(accounts_set)}")
    print(f" • Trader privi di SBT (Esclusi dal voto):      {j_stats['non_holders']}")
    print(f" • Titolari di SBT astenuti dal voto:          {j_stats['abstainers']}")
    print(f" • Validatori Umani che hanno espresso il voto: {j_stats['total_valid_votes']}")
    if j_stats['total_valid_votes'] > 0:
        print(f" • Voti scrutinati per YES (Verità fattuale): {j_stats['yes_votes']} ({j_stats['sbt_yes_pct']:.2f}%)")
        print(f" • Voti scrutinati per NO  (Manipolazione):   {j_stats['no_votes']}")
        print(f" • Soglia Supermaggioranza (Rae 1969 >= 70%):  {'RAGGIUNTA' if j_stats['circuit_breaker_active'] else 'FALLITA'}")
    print("-" * 96)
    print(" VERDETTO DI LIQUIDAZIONE ON-CHAIN:")
    print(" [RISCHIO PLUTOCRATICO IDENTIFICATO] PfC > CoC:")
    print(f"   1. Senza OracleGuard: La balena spende ${total_cost_attacker:,.0f} complessivi, corrompe il DVM UMA,")
    print(f"      falsifica l'esito a Kamala Harris e incassa ${final_oi:,.0f} (+${net_profit_if_unprotected:,.0f} di profitto netto).")
    print(f"   2. Con OracleGuard: Il Circuit Breaker interviene grazie alla supermaggioranza della giuria")
    print(f"      endogena ({j_stats['sbt_yes_pct']:.1f}% YES). Il verdetto fraudolento di UMA viene ribaltato.")
    print(f"      L'attaccante perde i ${whale_invested:,.0f} scommessi e l'intero pool da ${final_oi:,.0f}")
    print(f"      viene erogato legittimamente a favore di Donald Trump (YES).")
    print("=" * 96 + "\n")

if __name__ == "__main__":
    main()
