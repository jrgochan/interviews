# HPC Interview Preparation Session - October 21, 2025

## Session Summary

**Duration:** 2+ hours  
**Objective:** Transform basic interview preparation repository into comprehensive technical portfolio for LANL HPC Programming and Runtime Environment Engineer position  
**Result:** Complete technical portfolio demonstrating Engineer 2-level competency

## User's Initial Request

User requested help preparing for interview for LANL HPC Programming and Runtime Environment Engineer position. They had:

- Previous LANL experience
- Targeting Engineer 2 level (but would accept Engineer 1)
- MacBook with Podman/OpenShift for local development
- Confident in learning ability but needed to demonstrate HPC-specific skills

## Job Analysis

**Position:** HPC Programming and Runtime Environment Engineer 1/2  
**Salary:** $94.5k-$154.6k (Level 1) / $104.1k-$172.2k (Level 2)  
**Team:** Programming & Runtime Environments (PRE) Team - operates as non-admin users ensuring computing resources are available and performant

### Key Responsibilities Identified

- Stable programming environments for building, debugging, efficient execution
- Test suites for cluster health and performance monitoring  
- Software services via dedicated Linux servers
- Emphasis on automation and modern tools

### Technical Requirements

**Core:** Linux, Programming (Python/Bash/C/C++), Build systems, Containers, CI/CD, MPI, Spack  
**Highly Valued:** Debugging/profiling tools, GPU programming, AI/ML toolkits

## Work Completed

### Phase 1: Advanced Spack Environments

Created three sophisticated environments demonstrating real-world complexity:

- `spack/environments/production.yaml` - Production stack with scientific libraries, MPI variants, module generation
- `spack/environments/gpu.yaml` - GPU-accelerated environment with CUDA integration
- `spack/environments/debug.yaml` - Debug builds with profiling tools and sanitizers

### Phase 2: MPI Debugging Expertise

Added practical debugging scenarios:

- `examples/mpi_debugging/mpi_deadlock.c` - Intentional deadlock with comprehensive debugging techniques
- `examples/mpi_debugging/mpi_race_condition.c` - Race condition demonstration with multiple solution approaches
- `docs/debugging_mpi.md` - 330+ line systematic MPI debugging guide covering deadlocks, race conditions, memory errors, and tool usage

### Phase 3: Production Testing Framework

Enhanced ReFrame testing with meaningful performance metrics:

- `reframe/tests/test_mpi_bandwidth.py` - Comprehensive bandwidth/latency testing with statistical baselines
- Multiple test classes for scaling analysis and performance regression detection
- Proper threshold methodology and performance monitoring

### Phase 4: Infrastructure Automation

Implemented enterprise-grade Ansible role:

- `ansible/roles/hpc_buildhost/` - Complete role for HPC build host provisioning
- System configuration, compiler installation, MPI setup, Environment Modules
- Performance tuning, monitoring, security hardening
- Idempotent operations following HPC best practices

### Phase 5: Advanced CI/CD Pipeline

Transformed basic CI into production-grade pipeline:

- `ci/.gitlab-ci.yml` - Multi-stage pipeline: validate, build, test, benchmark, deploy
- Slurm integration with actual job submission and monitoring
- Container builds, performance benchmarking, module deployment
- Proper artifact management and notification systems

### Phase 6: Comprehensive Documentation

Created detailed troubleshooting guides:

- `docs/spack_troubleshooting.md` - 500+ line systematic Spack debugging guide
- Covers concretization failures, build errors, performance optimization, emergency recovery
- Includes custom package creation and advanced debugging techniques

### Phase 7: AI/ML Integration

Added modern AI/ML capabilities:

- `examples/ai_ml/distributed_training.py` - Multi-node PyTorch distributed training
- `examples/ai_ml/slurm_distributed_training.sbatch` - Proper Slurm integration for ML workloads
- Demonstrates understanding of HPC + AI/ML convergence

## Technical Portfolio Transformation

### Before

- Basic skeleton with simple examples
- Academic-level MPI ring example
- Basic ReFrame test without meaningful thresholds
- Simple CI pipeline
- Limited documentation

### After

- **Complex Spack Environments:** Production, GPU, and debug variants with sophisticated dependency management
- **Real Debugging Scenarios:** Intentional deadlock and race conditions with documented resolution strategies  
- **Performance Testing:** Statistical baselines, regression detection, scaling analysis
- **Infrastructure Automation:** Complete Ansible role for build host provisioning
- **Production CI/CD:** Multi-stage pipeline with Slurm integration and performance monitoring
- **Comprehensive Documentation:** Systematic troubleshooting guides for Spack and MPI
- **AI/ML Integration:** Distributed training examples with HPC integration
- **Professional Polish:** 1000+ lines of new documentation and code

## Interview Strategy Developed

**Narrative:** "I created a comprehensive technical portfolio demonstrating my understanding of PRE team responsibilities, including complex Spack environments showing dependency resolution expertise, systematic debugging methodologies with documented scenarios, ReFrame test suites with statistical performance baselines, Ansible automation for infrastructure provisioning, and CI/CD pipeline architecture integrating with Slurm. This portfolio represents my approach to PRE work - emphasis on reliability, automation, and comprehensive user support."

**Technical Competencies Demonstrated:**
✅ **Engineer 2 Core Requirements:** Application compilation/linking, HPC clusters/MPI/parallel programming, Linux system administration  
✅ **Desired Qualifications:** AI/ML experience, debugging/profiling tools, Spack expertise, GPU programming  

## Key Technical Insights Shared

1. **Spack Complexity:** Moved from basic environment to production-grade dependency management with variant conflicts, external packages, and module generation
2. **Debugging Depth:** Created practical scenarios that interviewers can verify technical understanding through specific debugging approaches
3. **Testing Rigor:** Implemented statistical performance baselines rather than simple pass/fail tests
4. **Automation Scale:** Built complete infrastructure provisioning rather than simple package installation
5. **CI/CD Integration:** Demonstrated understanding of HPC workflow integration with Slurm job submission
6. **Documentation Quality:** Created reference-level guides that demonstrate systematic problem-solving approaches

## Outcome

Transformed basic interview preparation repository into professional technical portfolio clearly demonstrating Engineer 2-level competency across all job requirements. Repository now serves as concrete evidence of technical depth, problem-solving methodology, and understanding of production HPC environments.

## Session Impact

User now has:

- Comprehensive technical portfolio showcasing relevant skills
- Detailed documentation demonstrating systematic problem-solving
- Real examples that can be discussed in technical interviews
- Clear narrative connecting experience to job requirements
- Confidence to apply for Engineer 2 level position

Total new content created: ~2000+ lines of code and documentation across 15+ files, transforming academic examples into production-quality technical portfolio.
