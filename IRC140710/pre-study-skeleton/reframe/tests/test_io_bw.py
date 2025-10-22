import reframe as rfm
import reframe.utility.sanity as sn

@rfm.simple_test
class IOThroughputTest(rfm.RunOnlyRegressionTest):
    valid_systems = ['local:cpu']
    valid_prog_environs = ['builtin']
    executable = '../../examples/io/ior_like.sh'
    @sanity_function
    def check_dd(self):
        return sn.assert_found(r'copied', self.stdout)
