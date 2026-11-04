# dev/ — exploratory and superseded code (not used for the paper)

Nothing here is needed to reproduce the paper. Kept for reference only; most files are
unmaintained and some will not run against the current classes without small fixes.

To run something from here, start MATLAB in `ADJ/after` (so the core classes are on the path)
and then `cd dev` before calling the script.

| File | What it was |
|---|---|
| `final2.m` | Attack dynamics over time for APJ only (superseded by `final11.m`/`final12.m`). |
| `final3.m`, `final3_plot.m` | Method comparison without DQN-IJ (superseded by `final11.m`). |
| `final4.m`, `final5.m` | Single representative run; BC vs shadow-DQN ablation (old behaviour-cloning predictor). |
| `final6.m`, `final6_plot.m` | APJ–target distance sensitivity sweep (0.01–20 km). |
| `final13.m` | Target-beam-position sweep (target not first in the decision order; future-work scenario). |
| `final14.m`, `TimeSlotP.m` | Non-learning recency/frequency predictor baseline (reviewer sanity check). |
| `finalc.m` | Diagnostic: why the comb jammer's hit rate is near zero. |
| `final11_plot.m`, `final11_rerunIJ.m` | Older variants of `final12.m` / `final12_plot.m`. **Do not run** `final11_plot.m`: it reads `final11_results.mat` (a non-paper DQN-IJ variant) and writes figures under the same names as the paper figures. |
| `main*.m`, `mainIJ1.m`, `mainIJ2.m`, `mainde.m` | Single-run drivers used while developing each jammer / loop variant. |
| `TimeSlot.m`, `TimeSlotB.m`, `TimeSlotD.m`, `TimeSlotDO.m`, `TimeSlot-noAttack.m` | Earlier per-epoch loop variants (`TimeSlotDO.m` and `TimeSlot-noAttack.m` both declare `classdef TimeSlotD` and clash with `TimeSlotD.m`). |
| `APJ_BC.m`, `APJ_BCFactory.m`, `APJPredictor.m`, `APJTrainingBuffer.m` | The first APJ attempt: a behaviour-cloning predictor instead of a shadow DQN (used by `TimeSlot.m`, `main.m`, `final5.m`). Superseded by the shadow-DQN `APJ.m` in the parent folder. |
| `FigureHelper.m` | Plot helpers for the `main*.m` drivers. |
| `calibrateSINRThreshold.m`, `apjCalibrateSINRThreshold.m` | One-off SINR-threshold calibration scripts. |
| `results/` | Result files of the scripts above (git-ignored, local only). `final11_results.mat` and the `*_backup_*` file are intermediate DQN-IJ variants, **not** the paper's numbers (those are in `../results/`). |
| `figures/` | Figures from the scripts above (git-ignored, local only). |
