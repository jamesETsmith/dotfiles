---
name: llm-workload
description: Use when running LLM inference workloads to capture performance and accuracy metrics, especially with YAML-defined benchmark recipes, vLLM, perf-eval, lm-eval, BFCL, traces, logs, and organized workload artifacts.
---

# LLM Workload

## Purpose

Use this skill when running an LLM inference workload where the goal is to capture repeatable performance and accuracy metrics. Prefer concrete workload definitions over ad hoc scripts so the run can be reviewed by customers, developers, operators, and other stakeholders.

## Default Approach

- Prefer existing tools and harnesses before writing custom runners.
- Use `vllm-project/perf-eval` as the default reference for vLLM inference workloads when applicable.
- Define workloads as simple YAML recipes whenever possible. Avoid a hodgepodge of one-off bash scripts.
- Capture both performance and accuracy when the workload supports it.
- Keep every run reproducible: record model, hardware, container image, commit SHA, serve args, benchmark args, eval tasks, and environment overrides.

## Required Preflight

Before running or designing the workload, check with the user about model weights:

1. Where do the model weights live?
2. Are they already present on the node or shared filesystem where the workload will run?
3. If not, what is the expected download or staging path, and who owns access credentials?
4. Is the cache persistent across runs, or will it be reclaimed when the job exits?

Do not assume weights can be downloaded cheaply or quickly. Prefer using weights already staged on the target node.

## Workload Definition

When creating or modifying a workload:

1. Start from an existing recipe that matches the model family, GPU type, or benchmark style.
2. Keep hardware variants in separate YAML files.
3. Include server configuration, perf benchmark configuration, and accuracy eval configuration in the recipe instead of separate shell fragments.
4. Make the optimization target explicit: throughput, latency, cost per token, accuracy, function-calling quality, long-context behavior, or reliability.
5. Validate the recipe with the harness's parser or smoke tests before launching expensive GPU work.

For `perf-eval`-style workloads, prefer the established blocks:

- `vllm` for model serving configuration.
- `vllm_bench` for throughput and latency measurements.
- `lm_eval` for accuracy tasks.
- `bfcl` for function-calling quality.

## Profiling Defaults

When enabling profiling, default to these profiler args unless the user specifies otherwise:

```text
--profiler-config.torch_profiler_with_stack false
--profiler-config.torch_profiler_use_gzip true
--profiler-config.torch_profiler_dump_cuda_time_total true
```

## Project Organization

Keep logs, artifacts, Dockerfiles, traces, configs, and reports in well-organized subdirectories of the project. Use a stable layout such as:

```text
workloads/
  <workload>.yaml
artifacts/
  <run-id>/
    logs/
    traces/
    results/
    docker/
    configs/
    reports/
```

Do not scatter generated outputs across the repository root. If the project already has a convention for run artifacts, follow it.

## Run Report

At the end of a workload run, summarize:

- The workload recipe and any local changes.
- Model, hardware, image, commit, serve args, and model weight location.
- Perf metrics captured, including throughput, latency, concurrency, input length, and output length where available.
- Accuracy metrics captured, including task names, scores, and whether results are partial or full evals.
- Artifact locations for logs, traces, raw results, Dockerfiles, and reports.
- Failures, retries, missing data, and any reasons the run is not comparable to prior runs.
