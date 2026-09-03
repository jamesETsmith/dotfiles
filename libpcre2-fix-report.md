# Fish shared-library startup fix

## Summary

The Fish setup now verifies that an existing cached binary can execute a command, rather than trusting `fish --version` alone. An unusable binary is replaced with the official static Fish release, and setup consistently invokes that verified binary by absolute path.

The Fish CI workflow seeds a version-reporting but otherwise unusable binary to cover the replacement path.

The remote Crush setup accepts `-J`/`--proxy-jump` and repeatable `--ssh-arg` values, forwarding them consistently to both `ssh` and `scp`.

## Tests

- `bash ci/test-remote-crush-args.sh`: passed
- `bash -n setup-fish.sh setup-remote-crush.sh ci/test-remote-crush-args.sh`: passed
- `shellcheck --severity=style setup-fish.sh setup-remote-crush.sh`: passed before the tool became unavailable outside the pre-commit environment
- YAML parsing with PyYAML: passed
- `git diff --check`: passed
- Pre-commit hooks except `yamlfmt`: all applicable checks passed except existing ShellCheck SC2207 warnings in `setup-fish.sh`
- Full pre-commit could not complete because the installed Go toolchain lacks the standard-library `slices` package required to build `yamlfmt`

## Full output

- `/tmp/libpcre2-missing-tests/baseline.txt`
- `/tmp/libpcre2-missing-tests/final.txt`
- `/tmp/libpcre2-missing-tests/pre-commit-without-yamlfmt.txt`
