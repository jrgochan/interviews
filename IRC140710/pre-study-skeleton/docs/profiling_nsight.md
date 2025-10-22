# Nsight Systems Quickstart

On a GPU node:
```bash
nsys profile -o saxpy_profile ./saxpy
nsys stats saxpy_profile.qdrep > report.txt
```
Interpret host-device memcpy and kernel timings; adjust block sizes or memory layout and re-run.
