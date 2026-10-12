# zRun and MQuickJS full workload run — 2026-10-09

Command from `next-arh/native/zRun`:

```sh
python3 performance/scripts/run.py \
  /home/alexstorm/distrib/business/rd/mquickjs/mqjs \
  --runs 21 --warmups 3 --suite all \
  --json performance/checkpoints/2026-10-09-run-all/results.json
```

The run compared each engine's own compiled artifact for all 19 workloads,
checked stdout equality, and measured compilation and execution separately.
The report contains raw timing samples and executable hashes. Geometric-mean
zRun/MQuickJS time was 1.068x for compilation, 1.561x for execution, and
1.505x for compilation plus execution. Timings include subprocess startup;
the execution phase also includes artifact loading.
