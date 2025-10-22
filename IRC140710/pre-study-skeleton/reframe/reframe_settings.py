site_configuration = {
    'systems': [
        {
            'name': 'local',
            'descr': 'Generic Slurm system',
            'hostnames': ['.*'],
            'partitions': [
                {
                    'name': 'cpu',
                    'scheduler': 'slurm',
                    'launcher': 'srun',
                    'access': [],
                    'environs': ['builtin']
                },
                {
                    'name': 'gpu',
                    'scheduler': 'slurm',
                    'launcher': 'srun',
                    'access': [],
                    'environs': ['builtin']
                }
            ]
        }
    ],
    'environments': [
        {'name': 'builtin', 'modules': []}
    ],
    'logging': {'handlers': [{'type': 'file', 'level': 'INFO', 'name': 'reframe.log'}]}
}
