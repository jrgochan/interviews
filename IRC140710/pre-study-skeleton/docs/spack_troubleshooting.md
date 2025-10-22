# Spack Troubleshooting Guide

This guide provides systematic approaches for debugging Spack builds, dependency conflicts, and deployment issues commonly encountered in HPC environments.

## Common Spack Issues

### 1. Concretization Failures

**Symptoms:**

- `spack spec` fails with "unsatisfiable" errors
- Conflicting dependency requirements
- No valid solution found

**Common Causes & Solutions:**

#### Version Conflicts

```bash
# Problem: Multiple versions required for same package
==> Error: An unsatisfiable variant value was used
==> hdf5 requires variant +mpi but openmpi@3.1.6 requires ~mpi

# Solution 1: Use constraints to unify versions
spack spec hdf5+mpi ^openmpi@4.1.4

# Solution 2: Update spack.yaml with explicit constraints
spack:
  packages:
    openmpi:
      require: "@4.1.4"
```

#### Variant Conflicts

```bash
# Problem: Incompatible variants across dependencies
# Check what's causing conflicts
spack spec -I mypackage

# Solution: Create explicit variant configuration
spack:
  packages:
    all:
      variants: +shared
    hdf5:
      require: "+mpi +fortran"
```

#### Compiler Compatibility

```bash
# Problem: Package doesn't build with available compilers
# Check compiler compatibility
spack compilers
spack spec mypackage %gcc@11.3.0

# Solution: Add compatible compiler or external package
spack compiler find /opt/gcc/11.3.0
spack external find cmake
```

### 2. Build Failures

**Symptoms:**

- Compilation errors during build phase
- Linking failures
- Configure script failures

**Debugging Strategies:**

#### Examine Build Logs

```bash
# Find the build directory
spack cd -b mypackage
# Or use build log location
spack find -v mypackage
cd $(spack location -b mypackage@version)

# Check detailed logs
less spack-build-out.txt
less spack-build-env.txt

# For configure failures
less spack-configure-out.txt
```

#### Build Environment Analysis

```bash
# Check build environment
spack build-env mypackage -- printenv | sort

# Compare working vs failing environment
spack build-env mypackage@working -- printenv > working.env
spack build-env mypackage@failing -- printenv > failing.env
diff -u working.env failing.env
```

#### Dependency Issues

```bash
# Check dependency tree
spack find -d mypackage

# Verify dependency locations
spack find -p $(spack dependencies mypackage)

# Check for missing libraries
spack build-env mypackage -- ldd /path/to/failing/binary
```

#### Manual Debugging

```bash
# Enter build environment for manual compilation
spack build-env mypackage -- bash

# Try building manually
cd $(spack location -b mypackage)
make VERBOSE=1

# Or re-run specific build phase
spack install --verbose --debug mypackage
```

### 3. Performance Issues

#### Slow Concretization

```bash
# Use faster solver
spack config add config:concretizer:original

# Or enable reuse for faster solving
spack config add concretizer:reuse:true

# Parallel installs
spack install -j 8 mypackage
```

#### Build Performance

```bash
# Use local fast storage for builds
spack config add config:build_stage:/dev/shm/spack-stage

# Enable ccache
export SPACK_CCACHE_DIR=/opt/spack/ccache
spack install mypackage
```

### 4. Module Generation Issues

#### Module Files Not Generated

```bash
# Check modules configuration
spack config get modules

# Enable modules for specific packages
spack:
  modules:
    default:
      enable: [tcl, lmod]
      tcl:
        all:
          filter:
            exclude_implicits: true

# Regenerate modules
spack module tcl refresh --delete-tree
```

#### Module Load Failures

```bash
# Check module conflicts
module list
module avail mypackage

# Verify module file syntax
module show mypackage/version

# Check environment modifications
module load mypackage
printenv | grep -i mypackage
```

### 5. Installation Location Issues

#### Permission Errors

```bash
# Check Spack permissions
ls -la $SPACK_ROOT/opt/spack/

# Use user-specific install tree
spack config add config:install_tree:~/spack/opt/spack

# Or set up group-writable installation
chmod -R g+w $SPACK_ROOT/opt/spack/
```

#### Disk Space Issues

```bash
# Check space usage
spack find --show-full-compiler-names | wc -l
du -sh $SPACK_ROOT/opt/spack/

# Clean build stage
spack clean --stage

# Remove old installations
spack find --old
spack uninstall --dependents old_package_hash
```

## Advanced Troubleshooting

### 1. Custom Package Creation

When packages aren't in Spack, create custom recipes:

```python
# packages/mypackage/package.py
from spack.package import *

class Mypackage(AutotoolsPackage):
    """Custom HPC application"""
    
    homepage = "https://example.com/mypackage"
    url = "https://example.com/mypackage-1.0.tar.gz"
    
    version('1.0', sha256='abc123...')
    
    depends_on('mpi')
    depends_on('hdf5+mpi')
    
    def configure_args(self):
        args = []
        args.append(f'--with-mpi={self.spec["mpi"].prefix}')
        return args
        
    def setup_build_environment(self, env):
        env.set('CC', self.spec['mpi'].mpicc)
        env.set('CXX', self.spec['mpi'].mpicxx)
```

### 2. Debugging Build System Issues

#### CMake Problems

```bash
# Check CMake configuration
spack build-env mypackage -- cmake -LAH /path/to/source

# Debug CMake find modules
spack build-env mypackage -- cmake --debug-find /path/to/source

# Override CMake variables
spack install mypackage cmake_args="-DCMAKE_BUILD_TYPE=Debug"
```

#### Autotools Issues

```bash
# Regenerate configure scripts
spack install mypackage autoreconf=true

# Check config.log for failures
cd $(spack location -b mypackage)
less config.log

# Override configure options
spack install mypackage configure_args="--enable-debug"
```

### 3. Compiler and Toolchain Issues

#### Cross-Compilation

```bash
# Set target architecture
spack install mypackage target=x86_64_v3

# Use specific compiler flags
spack install mypackage cppflags="-march=native" cflags="-O3"
```

#### Linking Problems

```bash
# Check library dependencies
spack build-env mypackage -- ldd $(spack location -i mypackage)/bin/binary

# Debug missing symbols
spack build-env mypackage -- nm -D library.so | grep missing_symbol

# Use different linking strategy
spack install mypackage ldflags="-Wl,--as-needed"
```

### 4. Environment and Module Issues

#### Environment Conflicts

```bash
# Clean environment before building
spack install --fresh mypackage

# Check for conflicting environment variables
env | grep -E "(PATH|LD_LIBRARY_PATH|PKG_CONFIG_PATH)"

# Use isolated environment
spack install --test=root --clean-build mypackage
```

#### Module Hierarchy Problems

```bash
# Check module hierarchy configuration
spack config get modules:default:tcl:hierarchy

# Rebuild hierarchy
spack module tcl refresh --delete-tree --upstream-modules
```

## Systematic Debugging Workflow

### Phase 1: Information Gathering

```bash
# Document the problem
spack --version
spack config get config
spack compilers
uname -a

# Capture full error output
spack install --verbose mypackage 2>&1 | tee build.log
```

### Phase 2: Reproduce and Isolate

```bash
# Try minimal reproduction
spack spec mypackage
spack install --dry-run mypackage

# Isolate variables
spack uninstall --dependents mypackage
spack clean --stage
spack install mypackage
```

### Phase 3: Analyze Dependencies

```bash
# Check dependency issues
spack find -d -L mypackage
spack graph mypackage

# Test dependencies individually
for dep in $(spack dependencies mypackage); do
    echo "Testing $dep"
    spack test run $dep
done
```

### Phase 4: Environment Analysis

```bash
# Compare environments
spack build-env mypackage -- env | sort > current.env
spack build-env working_package -- env | sort > working.env
diff -u working.env current.env
```

### Phase 5: Source Code Analysis

```bash
# Examine source code
spack stage mypackage
spack cd -s mypackage
ls -la

# Check patches applied
spack info mypackage | grep patches
```

## Performance Optimization

### Build Performance

```bash
# Parallel builds
spack config add config:build_jobs:$(nproc)

# Use faster file system
spack config add config:build_stage:/dev/shm/spack

# Enable compiler cache
export CCACHE_DIR=/opt/spack/ccache
spack install mypackage
```

### Installation Optimization

```bash
# Binary package reuse
spack buildcache keys --install --trust

# Mirror setup for faster downloads
spack mirror add local file:///opt/spack/mirror
spack mirror create -D -d /opt/spack/mirror mypackage
```

## Best Practices

### 1. Environment Management

```bash
# Use environments for reproducibility
spack env create myproject
spack env activate myproject
spack add mypackage@version
spack install

# Version control environments
git add spack.yaml spack.lock
git commit -m "Add mypackage dependency"
```

### 2. Testing and Validation

```bash
# Enable testing
spack install --test=root mypackage

# Custom test scripts
spack test run mypackage

# Smoke tests
spack load mypackage
mypackage --version
mypackage --test
```

### 3. Documentation

```bash
# Document custom packages
# packages/mypackage/package.py should include:
# - Clear description
# - Homepage and documentation links  
# - Version information and checksums
# - Complete dependency list
# - Build instructions and known issues
```

### 4. Monitoring and Maintenance

```bash
# Regular maintenance
spack gc  # Garbage collect unused installs
spack clean --stage  # Clean build artifacts
spack audit packages  # Check package consistency

# Update Spack
spack fetch --all  # Update package info
spack upgrade mypackage  # Upgrade to newer versions
```

## Emergency Recovery

### Corrupted Installation

```bash
# Remove and reinstall
spack uninstall --force --dependents mypackage
spack clean --stage --downloads
spack install mypackage

# Check database consistency
spack reindex
```

### Spack Database Issues

```bash
# Rebuild database
spack clean --all
spack reindex --reindex

# In extreme cases, rebuild from scratch
rm -rf $SPACK_ROOT/opt/spack/.spack-db
spack reindex
```

### Configuration Problems

```bash
# Reset to defaults
spack config --scope=user remove config
spack config --scope=user remove packages
spack config --scope=user remove modules

# Backup and restore
cp -r $SPACK_ROOT/etc/spack/ /backup/spack-config/
# Later restore:
cp -r /backup/spack-config/ $SPACK_ROOT/etc/spack/
```

This troubleshooting guide should be used in conjunction with Spack's official documentation and adapted to your specific HPC environment and requirements.
