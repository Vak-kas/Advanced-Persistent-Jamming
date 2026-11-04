# APJ Simulation — Advanced Persistent Jamming in LEO NTNs

MATLAB simulation of a reconnaissance-based predictive jamming attack against deep-reinforcement-learning channel selection in a LEO non-terrestrial network.

## What it does

A LEO satellite serves 19 spot beams over 10 shared channels. Each beam picks its channel with a
DQN agent that adapts to co-channel interference and jamming. The attacker,
**Advanced Persistent Jamming (APJ)**, stays silent during a reconnaissance phase and trains a
*shadow DQN* that imitates the target beam's channel-selection policy using only externally
observed channel selections. It then jams the top-2 channels predicted by the shadow policy while
continuing to update it. APJ is compared with random, swept, comb and a DQN-based intelligent
jammer under the same jamming budget.

## Layout

- `env.m` — all simulation parameters (geometry, channels, DQN hyper-parameters, jammer settings)
- `*.m` classes — satellite / beams / UTs with their DQN agents, the APJ node and shadow DQN,
  the DQN-IJ baseline, and the per-epoch loops `TimeSlotDE` (APJ), `TimeSlotR/S/C` (random,
  swept, comb) and `TimeSlotIJ` (DQN-IJ)
- `final11.m` → `final12.m` → `final12_plot.m` — comparison of the five jamming methods
- `final1.m` → `final1_plot.m` — reconnaissance-duration sweep
- `dev/` — exploratory scripts and older variants, not used for the main experiments
- `legacy/` — earlier prototypes (behaviour-cloning APJ, hybrid-reward DQN sample, frequency-hopping samples), kept for reference only

Run the scripts from the repository root in MATLAB (R2025b, Deep Learning Toolbox). Results and figures
are written to `results/` and `figures/`, which are not versioned.
