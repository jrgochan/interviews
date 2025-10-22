# HPC Programming & Runtime Environments - Technical Portfolio

**A comprehensive technical demonstration for Los Alamos National Laboratory's HPC Programming and Runtime Environment Engineer position**

---

## 🎯 Overview

This repository has been transformed from a basic interview preparation skeleton into a **production-quality technical portfolio** that demonstrates Engineer 2-level competencies in HPC software environments, automated testing, infrastructure automation, and scientific computing support.

**Target Position:** [HPC Programming and Runtime Environment Engineer 1/2](https://lanl.jobs/search/jobdetails/hpc-programming-and-runtime-environment-hpc-engineer-12/eedd907a-cacf-4f79-8abb-fed9bcad18db) at Los Alamos National Laboratory

## ⭐ Key Achievements

This portfolio demonstrates **real-world technical expertise** across all core PRE team responsibilities:

- ✅ **Complex Spack Environments** - Production, GPU, and debug variants with sophisticated dependency management
- ✅ **Advanced MPI Debugging** - Practical deadlock and race condition scenarios with systematic resolution documentation  
- ✅ **Performance Testing Framework** - ReFrame test suites with statistical baselines and regression detection
- ✅ **Infrastructure Automation** - Complete Ansible role for HPC build host provisioning
- ✅ **Production CI/CD** - Multi-stage pipeline with Slurm integration and performance monitoring
- ✅ **Comprehensive Documentation** - Systematic troubleshooting guides for Spack and MPI
- ✅ **AI/ML Integration** - Distributed training examples with HPC integration
- ✅ **Professional Application Materials** - CV generation and interview preparation tools

---

## 📁 Repository Structure

### **🧪 Spack Environments** (`spack/environments/`)

Advanced package management demonstrating real-world complexity:

- **`production.yaml`** - Full scientific software stack with MPI variants, module generation, and external packages
- **`gpu.yaml`** - GPU-accelerated environment with CUDA integration and specialized libraries  
- **`debug.yaml`** - Debug builds with profiling tools, sanitizers, and development utilities

**Demonstrates:** Complex dependency resolution, variant management, module hierarchy, build optimization

### **🐛 MPI Debugging Examples** (`examples/mpi_debugging/`)

Practical debugging scenarios with comprehensive resolution strategies:

- **`mpi_deadlock.c`** - Intentional cyclic dependency deadlock with debugging techniques
- **`mpi_race_condition.c`** - Shared memory race conditions with multiple solution approaches
- **Complete documentation** - Systematic debugging methodology and tool usage

**Demonstrates:** Real-world MPI debugging expertise, problem-solving methodology, tool proficiency

### **📊 Performance Testing Framework** (`reframe/tests/`)

Production-grade testing with meaningful metrics:

- **`test_mpi_bandwidth.py`** - Comprehensive bandwidth/latency testing with statistical baselines
- **Performance regression detection** - Automated threshold management and scaling analysis
- **Multi-system support** - Configurable test parameters for different HPC architectures

**Demonstrates:** Performance analysis, statistical testing, regression detection, cluster health monitoring

### **🤖 Infrastructure Automation** (`ansible/roles/hpc_buildhost/`)

Enterprise-grade configuration management:

- **Complete role implementation** - System configuration, compiler installation, MPI setup
- **Idempotent operations** - Proper Ansible best practices with handlers and variables
- **Security hardening** - Performance tuning, monitoring, and compliance considerations

**Demonstrates:** Infrastructure-as-code, configuration management, enterprise automation

### **🔄 CI/CD Pipeline** (`ci/.gitlab-ci.yml`)

Production-quality pipeline with HPC integration:

- **Multi-stage workflow** - Validation, build, test, benchmark, deployment
- **Slurm integration** - Actual job submission, monitoring, and artifact collection
- **Container builds** - Apptainer/Singularity for reproducible environments
- **Performance benchmarking** - HPL, STREAM, and custom performance validation

**Demonstrates:** DevOps expertise, HPC workflow integration, automated testing, deployment strategies

### **🧠 AI/ML Integration** (`examples/ai_ml/`)

Modern HPC + AI/ML convergence:

- **`distributed_training.py`** - Multi-node PyTorch distributed training
- **`slurm_distributed_training.sbatch`** - Proper Slurm integration for ML workloads
- **HPC-specific optimizations** - NCCL configuration, GPU-aware MPI, performance tuning

**Demonstrates:** AI/ML expertise, distributed computing, modern HPC applications

### **📚 Comprehensive Documentation** (`docs/`)

Reference-quality technical guides:

- **`debugging_mpi.md`** - Systematic MPI debugging methodology (330+ lines)
- **`spack_troubleshooting.md`** - Complete Spack problem-solving guide (500+ lines)
- **Professional CV tools** - Automated PDF generation with LaTeX formatting
- **Interview preparation** - Technical talking points and competency mapping

**Demonstrates:** Technical writing, systematic problem-solving, knowledge transfer

---

## 🚀 Getting Started

### **Prerequisites**

- Linux/macOS environment with development tools
- Python 3.8+ with pip
- Git and basic shell utilities
- Optional: Spack, ReFrame, Ansible, Docker/Podman

### **Quick Tour**

```bash
# Explore Spack environments
cd spack/environments && ls -la
cat production.yaml  # Complex production environment
cat gpu.yaml        # GPU-accelerated stack
cat debug.yaml      # Debug and profiling tools

# Review MPI debugging examples
cd examples/mpi_debugging
cat mpi_deadlock.c     # Deadlock demonstration
cat mpi_race_condition.c  # Race condition example

# Examine CI/CD pipeline
cat ci/.gitlab-ci.yml  # Multi-stage HPC pipeline

# Read comprehensive documentation
cd docs
cat debugging_mpi.md         # MPI debugging guide
cat spack_troubleshooting.md # Spack problem-solving
```

### **Running Examples**

**Spack Environment Setup:**

```bash
cd spack/environments
spack env create production production.yaml
spack env activate production
spack install  # Build complete environment
```

**MPI Debugging (requires MPI installation):**

```bash
cd examples/mpi_debugging
mkdir build && cd build
cmake .. && make
mpirun -np 2 ./mpi_deadlock  # Will demonstrate deadlock
```

**ReFrame Testing:**

```bash
cd reframe
reframe -C reframe_settings.py -c tests/ -r --system local:cpu
```

---

## 🎓 Technical Competencies Demonstrated

### **Core HPC Skills**

- **Spack Expertise** - Complex environments, dependency resolution, custom packages, troubleshooting
- **MPI Programming & Debugging** - Parallel applications, debugging techniques, performance analysis
- **Job Scheduling** - Slurm integration, resource management, workflow optimization
- **Performance Analysis** - Benchmarking, profiling, regression testing, optimization

### **Systems & Infrastructure**

- **Linux System Administration** - Configuration management, performance tuning, security
- **Configuration Management** - Ansible roles, idempotent operations, infrastructure-as-code
- **Container Technologies** - Apptainer/Singularity, Docker, reproducible environments
- **CI/CD Pipelines** - GitLab CI, automated testing, deployment automation

### **Software Development**

- **Build Systems** - CMake, Autotools, Make, cross-platform compilation
- **Testing Frameworks** - ReFrame, unit testing, performance testing, regression detection
- **Documentation** - Technical writing, troubleshooting guides, knowledge transfer
- **Version Control** - Git workflows, collaboration, code review practices

### **Emerging Technologies**

- **AI/ML Integration** - Distributed training, GPU optimization, HPC + AI workflows
- **Modern DevOps** - Automation, monitoring, observability, infrastructure management
- **Cloud-HPC Hybrid** - Containerization, portability, multi-platform deployment

---

## 🎯 Interview Preparation

### **Portfolio Narrative**

*"I created a comprehensive technical portfolio demonstrating my understanding of PRE team responsibilities. This includes complex Spack environments showing dependency resolution expertise, systematic debugging methodologies with documented scenarios, ReFrame test suites with statistical performance baselines, Ansible automation for infrastructure provisioning, and CI/CD pipeline architecture integrating with Slurm. This portfolio represents my approach to PRE work - emphasis on reliability, automation, and comprehensive user support."*

### **Key Talking Points**

**Technical Depth:**

- Complex Spack environments with real-world dependency challenges
- Practical MPI debugging scenarios with systematic resolution approaches
- Performance testing with statistical baselines and regression detection
- Infrastructure automation following enterprise best practices

**Problem-Solving Methodology:**

- Systematic debugging approaches documented in comprehensive guides
- Performance analysis with data-driven decision making
- Automation-first approach to repetitive tasks
- User-centered design for support tools and documentation

**Modern HPC Understanding:**

- Integration of traditional HPC with AI/ML workloads
- Container-based deployment strategies for reproducibility
- DevOps practices adapted for HPC environments
- Performance optimization across the full software stack

### **CV and Application Materials**

Professional CV generation tools available in `docs/`:

```bash
cd docs
./convert.sh  # Generate professional PDF CV
```

---

## 📈 Professional Development Journey

This repository demonstrates the evolution from basic HPC knowledge to **Engineer 2-level expertise**:

1. **Foundation** - Basic MPI, Slurm, and Spack understanding
2. **Intermediate** - Complex environments, debugging scenarios, automated testing
3. **Advanced** - Infrastructure automation, CI/CD integration, performance optimization
4. **Expert** - Systematic problem-solving, comprehensive documentation, modern HPC practices

**Session Documentation:** Complete development process documented in `chats/hpc-interview-prep-session-2025-10-21.md`

---

## 🤝 Contributing & Feedback

This portfolio represents continuous learning and improvement. Key areas for expansion:

- Additional Spack package recipes and environments
- More complex MPI debugging scenarios
- Extended ReFrame test coverage
- Integration with additional HPC tools and frameworks

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🏢 Context

**Target Position:** HPC Programming and Runtime Environment Engineer at Los Alamos National Laboratory  
**Portfolio Purpose:** Demonstrate technical competencies required for supporting world-class scientific computing infrastructure  
**Focus Areas:** Software environment management, automated testing, infrastructure automation, user support

*This technical portfolio showcases the depth of knowledge and practical experience necessary to contribute immediately to LANL's Programming & Runtime Environments team mission of ensuring reliable, performant HPC resources for groundbreaking scientific discovery.*
