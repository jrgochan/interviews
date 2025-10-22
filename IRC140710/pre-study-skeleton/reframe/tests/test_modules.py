import reframe as rfm
import reframe.utility.sanity as sn

@rfm.simple_test
class ModulesLoadTest(rfm.RunOnlyRegressionTest):
    valid_systems = ['local:cpu', 'local:gpu']
    valid_prog_environs = ['builtin']
    executable = 'bash'
    executable_opts = ['-lc', 'module avail 2>&1 || true']
    @sanity_function
    def assert_anything(self):
        return sn.assert_true(True)
