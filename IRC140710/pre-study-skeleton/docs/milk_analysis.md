# MILK (MAUD Interface Language Kit) Analysis

## Overview

MILK (MAUD Interface Language Kit) is a Python-based toolkit for automated processing of diffraction datasets using Rietveld refinement. It provides a programmatic interface to MAUD (Materials Analysis Using Diffraction) for high-throughput crystallographic analysis.

## Features

- **Programmable Refinements**: Custom, reproducible refinement workflows
- **Database Configuration**: Store and reuse refinement configurations
- **Distributed Computing**: Scale analysis across multiple compute nodes
- **Automated Processing**: Batch processing of large diffraction datasets
- **Cinema Integration**: Output formatted for cinema_debye_scherrer visualization
- **Multi-platform Support**: Linux, Windows, macOS compatibility

## Installation and Setup

### Container Environment

MILK is deployed as a containerized workspace in the HPC interview environment:

```bash
# Start MILK workspace
./scripts/rhos/examples/shell.sh milk

# Run MILK demo
./scripts/rhos/examples/run-milk-demo.sh
```

### Environment Components

The MILK container includes:

- **Java Runtime**: OpenJDK 11 (required for MAUD)
- **MAUD**: Materials Analysis Using Diffraction software
- **Python Environment**: NumPy, SciPy, matplotlib, pandas
- **MILK Library**: Latest version from LANL repository

## Quick Start

### 1. Verify Environment

```bash
# Check MILK installation
./scripts/rhos/examples/run-milk-demo.sh test
```

### 2. Interactive Session

```bash
# Start interactive MILK session
./scripts/rhos/examples/run-milk-demo.sh interactive

# Inside the container:
source milk/milk_env.sh
cd milk/examples
python3 run_sample.py
```

### 3. Sample Analysis

```bash
# Run sample diffraction analysis
./scripts/rhos/examples/run-milk-demo.sh analysis
```

## Core Concepts

### Rietveld Refinement

MILK automates the Rietveld refinement process:

1. **Data Loading**: Import diffraction patterns
2. **Structure Setup**: Define crystal structure parameters
3. **Parameter Refinement**: Iterative least-squares fitting
4. **Quality Assessment**: Statistical analysis of refinement quality
5. **Results Export**: Generate reports and visualizations

### Workflow Components

```python
import MILK

# Initialize MILK workflow
workflow = MILK.Workflow()

# Configure analysis parameters
workflow.set_data_path("diffraction_data/")
workflow.set_structure("crystal.cif")
workflow.set_parameters({
    'background': 'polynomial',
    'peak_shape': 'pseudo_voigt',
    'max_cycles': 100
})

# Execute refinement
results = workflow.run_refinement()

# Export results
workflow.export_results("output/")
```

## File Structure

```
/home/hpcuser/workspace/milk/
├── milk_env.sh          # Environment setup script
├── run_sample.py        # Basic functionality test
├── examples/            # MILK example workflows
│   ├── basic_refinement.py
│   ├── batch_processing.py
│   └── parameter_study.py
├── data/               # Sample diffraction data
└── results/            # Analysis output directory
```

## Environment Variables

Key environment variables set by `milk_env.sh`:

```bash
MAUD_PATH=/opt/maud/Maud_unix          # MAUD installation path
JAVA_HOME=/usr/lib/jvm/java-11-openjdk # Java runtime
PATH=$MAUD_PATH:$JAVA_HOME/bin:$PATH   # Updated PATH
PYTHONPATH=/home/hpcuser/workspace:$PYTHONPATH  # Python modules
```

## Usage Examples

### Basic Refinement

```python
#!/usr/bin/env python3
import MILK
import os

def basic_refinement():
    """Basic single-pattern Rietveld refinement"""
    
    # Load diffraction data
    data = MILK.load_pattern("data/sample.dat")
    
    # Set up crystal structure
    structure = MILK.Structure.from_cif("structures/sample.cif")
    
    # Configure refinement
    refinement = MILK.Refinement(data, structure)
    refinement.set_background("polynomial", order=6)
    refinement.set_profile("pseudo_voigt")
    
    # Run refinement
    results = refinement.run(max_cycles=50)
    
    # Export results
    results.export("output/basic_refinement/")
    
    return results

if __name__ == "__main__":
    results = basic_refinement()
    print(f"Refinement completed: Rwp = {results.rwp:.3f}%")
```

### Batch Processing

```python
#!/usr/bin/env python3
import MILK
import glob
import multiprocessing

def process_pattern(pattern_file):
    """Process a single diffraction pattern"""
    
    try:
        # Load and process pattern
        data = MILK.load_pattern(pattern_file)
        structure = MILK.Structure.from_database("standard_phases")
        
        refinement = MILK.Refinement(data, structure)
        results = refinement.run(max_cycles=25)
        
        return {
            'file': pattern_file,
            'rwp': results.rwp,
            'success': True
        }
    except Exception as e:
        return {
            'file': pattern_file,
            'error': str(e),
            'success': False
        }

def batch_processing():
    """Process multiple diffraction patterns in parallel"""
    
    # Find all data files
    pattern_files = glob.glob("data/batch/*.dat")
    
    # Process in parallel
    with multiprocessing.Pool(processes=4) as pool:
        results = pool.map(process_pattern, pattern_files)
    
    # Summarize results
    successful = [r for r in results if r['success']]
    failed = [r for r in results if not r['success']]
    
    print(f"Processed {len(pattern_files)} patterns:")
    print(f"  Successful: {len(successful)}")
    print(f"  Failed: {len(failed)}")
    
    return results

if __name__ == "__main__":
    results = batch_processing()
```

## Performance Considerations

### Optimization Strategies

1. **Parallel Processing**: Use multiprocessing for batch analyses
2. **Parameter Constraints**: Apply reasonable parameter bounds
3. **Initial Estimates**: Provide good starting values
4. **Convergence Criteria**: Set appropriate tolerances
5. **Memory Management**: Process large datasets in chunks

### Resource Requirements

- **CPU**: 2-4 cores recommended for parallel processing
- **Memory**: 2-8 GB depending on dataset size
- **Storage**: Variable based on input/output data volume
- **Java Heap**: Adjust based on MAUD memory requirements

## Troubleshooting

### Common Issues

1. **Java Memory Error**

   ```bash
   export JAVA_OPTS="-Xmx4g -Xms1g"
   ```

2. **MAUD Not Found**

   ```bash
   source milk/milk_env.sh
   echo $MAUD_PATH
   ls -la $MAUD_PATH/maud
   ```

3. **Python Import Error**

   ```bash
   export PYTHONPATH=/home/hpcuser/workspace:$PYTHONPATH
   python3 -c "import MILK; print('MILK available')"
   ```

4. **Refinement Convergence Issues**
   - Check initial parameter values
   - Verify data quality and format
   - Adjust convergence criteria
   - Review structure model accuracy

### Debug Mode

Enable verbose output for troubleshooting:

```python
import MILK
MILK.set_log_level('DEBUG')

# Enable MAUD verbose output
refinement = MILK.Refinement(data, structure)
refinement.set_verbose(True)
```

## Integration with HPC Environment

### MPI Support

MILK can leverage MPI for distributed processing:

```python
from mpi4py import MPI
import MILK

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

# Distribute patterns across MPI ranks
patterns_per_rank = total_patterns // size
local_patterns = patterns[rank * patterns_per_rank:(rank + 1) * patterns_per_rank]

# Process local patterns
local_results = []
for pattern in local_patterns:
    result = MILK.process_pattern(pattern)
    local_results.append(result)

# Gather results
all_results = comm.gather(local_results, root=0)
```

### Slurm Integration

Submit MILK jobs to Slurm scheduler:

```bash
#!/bin/bash
#SBATCH --job-name=milk-analysis
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=02:00:00
#SBATCH --partition=compute

module load python/3.9
source milk/milk_env.sh

mpirun -np 8 python3 batch_refinement.py
```

## References and Resources

### Official Documentation

- [MILK GitHub Repository](https://github.com/lanl/MILK)
- [MILK Wiki](https://github.com/lanl/MILK/wiki)
- [MAUD Documentation](http://maud.radiographema.eu/)

### Scientific Publication

- Savage, D. J., et al. (2023). "MILK: a Python scripting interface to MAUD for automation of Rietveld analysis." *J. Appl. Cryst.* **56**. DOI: [10.1107/S1600576723005472](https://doi.org/10.1107/S1600576723005472)

### Learning Resources

- [Rietveld Method Introduction](https://en.wikipedia.org/wiki/Rietveld_refinement)
- [Crystallographic Data Analysis](https://www.iucr.org/resources/commissions/powder-diffraction)
- [Python Scientific Computing](https://scipy-lectures.org/)

## Support and Development

### Community

- GitHub Issues: Report bugs and feature requests
- Discussions: Ask questions and share workflows
- Contributions: Submit pull requests for improvements

### LANL Contact

MILK is developed and maintained by Los Alamos National Laboratory (LANL) researchers. For specific scientific or technical questions, refer to the GitHub repository or contact the development team through official channels.
