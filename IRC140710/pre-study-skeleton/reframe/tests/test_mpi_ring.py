import reframe as rfm
import reframe.utility.sanity as sn

@rfm.simple_test
class MPIRingTest(rfm.RegressionTest):
    valid_systems = ['local:cpu']
    valid_prog_environs = ['builtin']
    sourcesdir = '../../examples/mpi'
    build_system = 'CMake'
    @run_before('compile')
    def set_build(self):
        self.build_system.config_opts = []
    @run_before('run')
    def set_exec(self):
        self.num_tasks = 4
        self.executable = 'srun'
        self.executable_opts = ['./mpi_ring']
    @sanity_function
    def assert_output(self):
        return sn.assert_found(r'final token', self.stdout)
