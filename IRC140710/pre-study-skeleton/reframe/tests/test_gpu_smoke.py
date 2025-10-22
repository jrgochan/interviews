import reframe as rfm
import reframe.utility.sanity as sn

@rfm.simple_test
class GPUSmokeTest(rfm.RunOnlyRegressionTest):
    valid_systems = ['local:gpu']
    valid_prog_environs = ['builtin']
    executable = '../../examples/gpu_smoke/gpu_smoke.sh'
    @sanity_function
    def has_nvidia_smi(self):
        return sn.assert_found(r'NVIDIA-SMI|not found', self.stdout)
