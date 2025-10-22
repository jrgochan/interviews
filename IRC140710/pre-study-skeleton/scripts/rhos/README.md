# RHOS/OpenShift Local Test Environment

This directory contains scripts to set up a complete HPC testing environment using Red Hat OpenShift (RHOS) running on Podman Desktop. This allows you to demonstrate all interview examples locally without requiring access to actual HPC clusters.

## 🎯 Purpose

Provide a containerized, local environment that simulates HPC workflows for:

- MPI debugging demonstrations
- ReFrame performance testing
- AI/ML distributed training examples
- Spack environment testing
- Infrastructure automation validation

## 📋 Prerequisites

### Required Software

- **Podman Desktop** - With OpenShift Local enabled
- **OpenShift CLI (oc)** - For cluster management
- **Git** - For repository management

### Setup Steps

1. **Install Podman Desktop:** [Download from Red Hat](https://podman-desktop.io/)
2. **Enable OpenShift Local:** In Podman Desktop settings
3. **Start OpenShift cluster:** Wait for cluster to be ready
4. **Install OpenShift CLI:**

   ```bash
   brew install openshift-cli
   # or download from: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html
   ```

5. **Login to cluster:**

   ```bash
   oc login -u developer
   ```

## 🚀 Quick Start

```bash
# Set up the complete environment
./setup.sh

# Run individual demonstrations
./examples/run-mpi-debug.sh       # MPI debugging examples
./examples/run-reframe-tests.sh   # Performance testing
./examples/run-aiml-demo.sh       # AI/ML distributed training

# Get interactive access
./examples/shell.sh               # HPC environment shell
./examples/shell.sh aiml          # AI/ML environment shell

# Cleanup when done
./cleanup.sh
```

## 📁 Directory Structure

```
scripts/rhos/
├── setup.sh                     # Main setup script
├── cleanup.sh                   # Environment cleanup
├── containers/                  # Container definitions
│   ├── Containerfile.hpc-base   # Base HPC environment
│   ├── Containerfile.mpi-debug  # MPI debugging tools
│   ├── Containerfile.reframe    # ReFrame testing environment
│   └── Containerfile.aiml       # AI/ML training environment
├── manifests/                   # OpenShift resource definitions
│   ├── hpc-workspace-deployment.yaml
│   └── aiml-deployment.yaml
├── examples/                    # Demonstration scripts
│   ├── run-mpi-debug.sh         # MPI debugging demos
│   ├── run-reframe-tests.sh     # Performance testing
│   ├── run-aiml-demo.sh         # AI/ML training demos
│   └── shell.sh                 # Interactive access
└── README.md                    # This file
```

## 🔧 Container Images

### **hpc-base:latest**

- **Purpose:** Foundation HPC environment
- **Includes:** GCC, OpenMPI, Python, debugging tools
- **Use Cases:** Basic MPI examples, general HPC workflows

### **hpc-mpi-debug:latest**

- **Purpose:** Enhanced debugging environment
- **Includes:** GDB, Valgrind, performance profiling tools
- **Use Cases:** MPI debugging demonstrations, deadlock analysis

### **hpc-reframe:latest**

- **Purpose:** Performance testing and regression detection
- **Includes:** ReFrame framework, testing utilities
- **Use Cases:** Automated performance testing, cluster health monitoring

### **hpc-aiml:latest**

- **Purpose:** AI/ML distributed training
- **Includes:** PyTorch, TensorBoard, Jupyter, distributed computing tools
- **Use Cases:** ML training demonstrations, HPC + AI integration

## 🎮 Usage Examples

### **MPI Debugging Demonstration**

```bash
# Run all debugging examples
./examples/run-mpi-debug.sh

# Individual examples
./examples/run-mpi-debug.sh deadlock     # Show deadlock detection
./examples/run-mpi-debug.sh race         # Demonstrate race conditions
./examples/run-mpi-debug.sh tools        # Show debugging tools
./examples/run-mpi-debug.sh interactive  # Interactive debugging session
```

### **Performance Testing**

```bash
# Run all ReFrame tests
./examples/run-reframe-tests.sh

# Individual test suites
./examples/run-reframe-tests.sh basic       # Basic functionality tests
./examples/run-reframe-tests.sh performance # Performance regression tests
./examples/run-reframe-tests.sh results     # Show test results
```

### **AI/ML Demonstrations**

```bash
# Run ML training demo
./examples/run-aiml-demo.sh

# Individual components
./examples/run-aiml-demo.sh single       # Single node training
./examples/run-aiml-demo.sh distributed  # Multi-process simulation
./examples/run-aiml-demo.sh jupyter      # Start Jupyter notebook
./examples/run-aiml-demo.sh tensorboard  # Start TensorBoard
```

### **Interactive Development**

```bash
# HPC environment shell
./examples/shell.sh hpc

# AI/ML environment shell
./examples/shell.sh aiml

# Direct pod access
oc exec -it $(oc get pods -l app=hpc-workspace -o name | head -1) -- /bin/bash
```

## 🌐 Web Interfaces

When AI/ML components are deployed, web interfaces are available:

### **Jupyter Notebook**

```bash
# Get Jupyter URL
oc get route jupyter-route -o jsonpath='{.spec.host}'

# Access: https://<route-url>
# Token: Check pod logs for authentication token
```

### **TensorBoard**

```bash
# Get TensorBoard URL  
oc get route tensorboard-route -o jsonpath='{.spec.host}'

# Access: https://<route-url>
```

## 📊 Monitoring & Debugging

### **Check Pod Status**

```bash
oc get pods -n hpc-interview
oc describe pod <pod-name> -n hpc-interview
```

### **View Logs**

```bash
oc logs -f deployment/hpc-workspace -n hpc-interview
oc logs -f deployment/aiml-workspace -n hpc-interview
```

### **Resource Usage**

```bash
oc top pods -n hpc-interview
oc get events -n hpc-interview --sort-by='.lastTimestamp'
```

## 🛠️ Troubleshooting

### **Common Issues**

**Container Build Failures:**

```bash
# Check Podman connectivity
podman version
podman system info

# Rebuild specific image
podman build -t hpc-base:latest -f containers/Containerfile.hpc-base ../..
```

**Pod Startup Issues:**

```bash
# Check pod status
oc get pods -n hpc-interview
oc describe pod <failing-pod>

# Check resource constraints
oc describe nodes
```

**OpenShift Connection Problems:**

```bash
# Verify cluster status
oc status
oc get nodes

# Re-login if needed
oc login -u developer
```

### **Performance Optimization**

**Increase Resource Limits:**

```bash
# Edit deployment resources
oc edit deployment hpc-workspace -n hpc-interview

# Or apply updated manifests
oc apply -f manifests/ -n hpc-interview
```

**Storage Performance:**

- Use local Podman volumes for better I/O performance
- Consider using tmpfs for temporary build operations

## 🧪 Testing & Validation

### **Environment Validation**

```bash
# Quick environment check
./examples/shell.sh hpc -c "mpirun --version && gcc --version && python3 --version"
```

### **Example Workflows**

1. **Setup environment:** `./setup.sh`
2. **Test MPI debugging:** `./examples/run-mpi-debug.sh`
3. **Run performance tests:** `./examples/run-reframe-tests.sh`
4. **Demo AI/ML capabilities:** `./examples/run-aiml-demo.sh`
5. **Interactive exploration:** `./examples/shell.sh`
6. **Cleanup:** `./cleanup.sh`

## 💡 Interview Demonstration Strategy

This local environment enables you to:

1. **Show Real Examples** - Demonstrate actual MPI debugging, not just theory
2. **Interactive Technical Discussion** - Run examples live during interviews
3. **Prove Technical Depth** - Show understanding of complex HPC concepts
4. **Demonstrate Modern Skills** - Container-based workflows, CI/CD integration

### **Key Demo Points**

- **MPI Debugging:** Show deadlock detection and resolution strategies
- **Performance Testing:** Demonstrate ReFrame test development and thresholds
- **Infrastructure Automation:** Show container orchestration and automation
- **AI/ML Integration:** Demonstrate distributed training setup and optimization

## 🔗 Integration with Main Portfolio

This RHOS environment complements the main technical portfolio by:

- Providing **runnable demonstrations** of documented concepts
- Enabling **interactive technical discussions** during interviews
- Showing **practical implementation** of theoretical knowledge
- Demonstrating **modern containerization** and orchestration skills

Use this environment to bring your technical portfolio to life during interviews and technical discussions.
