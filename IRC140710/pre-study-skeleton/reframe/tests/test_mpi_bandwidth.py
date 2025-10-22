import reframe as rfm
import reframe.utility.sanity as sn

@rfm.simple_test
class MPIBandwidthTest(rfm.RegressionTest):
    """
    MPI bandwidth test using point-to-point communication
    Measures inter-node bandwidth and compares against expected values
    """
    
    valid_systems = ['*']
    valid_prog_environs = ['builtin']
    
    # Test parameters
    message_sizes = rfm.parameter([1024, 4096, 16384, 65536, 262144, 1048576])  # 1KB to 1MB
    
    # System configuration
    num_tasks = 2
    num_tasks_per_node = 1  # Force inter-node communication
    
    executable = 'mpirun'
    
    @rfm.run_before('compile')
    def setup_build(self):
        self.build_system = 'SingleSource'
        self.sourcepath = 'mpi_bandwidth.c'
        self.build_system.cflags = ['-O2', '-std=c99']
        self.build_system.ldflags = ['-lm']
    
    @rfm.run_before('run')
    def setup_run(self):
        self.executable_opts = [
            '-np', str(self.num_tasks),
            '--map-by', 'node',  # Ensure inter-node placement
            './mpi_bandwidth',
            str(self.message_sizes)
        ]
        
        # Set time limit based on message size
        if self.message_sizes >= 1048576:
            self.time_limit = '5m'
        else:
            self.time_limit = '2m'
    
    @rfm.sanity_function
    def assert_completion(self):
        """Basic sanity check - test completed successfully"""
        return sn.all([
            sn.assert_found(r'Bandwidth test completed', self.stdout),
            sn.assert_not_found(r'ERROR', self.stderr),
            sn.assert_not_found(r'TIMEOUT', self.stderr)
        ])
    
    @rfm.performance_function('MB/s')
    def bandwidth(self):
        """Extract bandwidth measurement from output"""
        return sn.extractsingle(
            r'Bandwidth:\s+(?P<bw>\S+)\s+MB/s', self.stdout, 'bw', float
        )
    
    @rfm.performance_function('us')
    def latency(self):
        """Extract latency measurement from output"""
        return sn.extractsingle(
            r'Latency:\s+(?P<lat>\S+)\s+us', self.stdout, 'lat', float
        )
    
    @rfm.run_before('performance')
    def set_perf_reference(self):
        """Set performance references based on message size and system"""
        
        # Define expected bandwidth ranges based on interconnect type
        # These would be customized for specific HPC systems
        if self.message_sizes <= 4096:
            # Small messages - latency bound
            expected_bw_range = (50, 200, None, 'MB/s')
            expected_lat_range = (0.5, 2.0, None, 'us')
        elif self.message_sizes <= 65536:
            # Medium messages
            expected_bw_range = (500, 1500, None, 'MB/s')
            expected_lat_range = (2.0, 10.0, None, 'us')
        else:
            # Large messages - bandwidth bound
            expected_bw_range = (2000, 4000, None, 'MB/s')
            expected_lat_range = (10.0, 100.0, None, 'us')
        
        self.reference = {
            '*': {
                'bandwidth': expected_bw_range,
                'latency': expected_lat_range
            }
        }
        
    @rfm.run_before('performance')  
    def set_perf_variables(self):
        """Configure performance variables"""
        self.perf_patterns = {
            'bandwidth': self.bandwidth,
            'latency': self.latency
        }

@rfm.simple_test
class MPIBandwidthScaling(rfm.RegressionTest):
    """
    Multi-node MPI bandwidth scaling test
    Tests bandwidth scaling with increasing number of nodes
    """
    
    valid_systems = ['*']
    valid_prog_environs = ['builtin']
    
    # Scale from 2 to 16 nodes (if available)
    node_counts = rfm.parameter([2, 4, 8, 16])
    message_size = 1048576  # 1MB messages
    
    @rfm.run_before('compile')
    def setup_build(self):
        self.build_system = 'SingleSource'
        self.sourcepath = 'mpi_alltoall.c'
        self.build_system.cflags = ['-O2', '-std=c99']
        
    @rfm.run_before('run')
    def setup_run(self):
        self.num_tasks = self.node_counts
        self.num_tasks_per_node = 1
        
        self.executable = 'mpirun'
        self.executable_opts = [
            '-np', str(self.num_tasks),
            '--map-by', 'node',
            './mpi_alltoall',
            str(self.message_size)
        ]
        
        self.time_limit = '10m'
        
        # Set resource requirements
        self.extra_resources = {
            'switches': {'num_switches': 1}  # Prefer single switch if possible
        }
    
    @rfm.sanity_function
    def assert_completion(self):
        return sn.assert_found(r'Alltoall completed successfully', self.stdout)
    
    @rfm.performance_function('MB/s')
    def aggregate_bandwidth(self):
        """Total aggregate bandwidth across all pairs"""
        return sn.extractsingle(
            r'Aggregate bandwidth:\s+(?P<bw>\S+)\s+MB/s', self.stdout, 'bw', float
        )
    
    @rfm.performance_function('MB/s')
    def per_pair_bandwidth(self):
        """Average bandwidth per node pair"""
        return sn.extractsingle(
            r'Per-pair bandwidth:\s+(?P<bw>\S+)\s+MB/s', self.stdout, 'bw', float
        )
    
    @rfm.run_before('performance')
    def set_perf_reference(self):
        """Set scaling expectations"""
        
        # Expected scaling efficiency
        base_bw = 3000  # MB/s for 2 nodes
        scaling_efficiency = 0.85  # 85% scaling efficiency
        
        expected_aggregate = base_bw * self.node_counts * scaling_efficiency
        expected_per_pair = base_bw * scaling_efficiency
        
        self.reference = {
            '*': {
                'aggregate_bandwidth': (expected_aggregate * 0.7, expected_aggregate, None, 'MB/s'),
                'per_pair_bandwidth': (expected_per_pair * 0.8, expected_per_pair, None, 'MB/s')
            }
        }
        
        self.perf_patterns = {
            'aggregate_bandwidth': self.aggregate_bandwidth,
            'per_pair_bandwidth': self.per_pair_bandwidth
        }

# Additional test for memory bandwidth (node-local performance)        
@rfm.simple_test
class MemoryBandwidthTest(rfm.RegressionTest):
    """
    Memory bandwidth test to establish node-local performance baseline
    Helps distinguish network vs memory bottlenecks
    """
    
    valid_systems = ['*'] 
    valid_prog_environs = ['builtin']
    
    # Test different access patterns
    access_pattern = rfm.parameter(['sequential', 'random', 'stride'])
    array_sizes = rfm.parameter([1048576, 8388608, 67108864])  # 1MB, 8MB, 64MB
    
    num_tasks = 1
    num_cpus_per_task = 1
    
    @rfm.run_before('compile')
    def setup_build(self):
        self.build_system = 'SingleSource'
        self.sourcepath = 'memory_bandwidth.c'
        self.build_system.cflags = ['-O2', '-fopenmp', '-std=c99']
        self.build_system.ldflags = ['-lm', '-fopenmp']
        
    @rfm.run_before('run')
    def setup_run(self):
        self.executable_opts = [
            str(self.array_sizes),
            self.access_pattern,
            '10'  # Number of iterations
        ]
        
        self.env_vars = {
            'OMP_NUM_THREADS': '1'
        }
        
    @rfm.sanity_function
    def assert_completion(self):
        return sn.assert_found(r'Memory bandwidth test completed', self.stdout)
    
    @rfm.performance_function('GB/s')
    def memory_bandwidth(self):
        return sn.extractsingle(
            r'Memory bandwidth:\s+(?P<bw>\S+)\s+GB/s', self.stdout, 'bw', float
        )
    
    @rfm.run_before('performance')
    def set_perf_reference(self):
        """Set memory bandwidth expectations based on access pattern"""
        
        # Typical memory bandwidth ranges for different patterns
        if self.access_pattern == 'sequential':
            expected_bw = (20.0, 40.0, None, 'GB/s')  # Near peak memory bandwidth
        elif self.access_pattern == 'stride':
            expected_bw = (10.0, 25.0, None, 'GB/s')  # Cache effects
        else:  # random
            expected_bw = (2.0, 10.0, None, 'GB/s')   # Poor cache utilization
            
        self.reference = {
            '*': {
                'memory_bandwidth': expected_bw
            }
        }
        
        self.perf_patterns = {
            'memory_bandwidth': self.memory_bandwidth
        }
