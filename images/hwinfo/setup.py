from setuptools import setup, find_packages

setup(
    name='hwinfo',
    version='0.1.0',
    description='A package that detects the hw configurations of a given machine',
    author='Lightbits R&D',
    author_email='dev@lightbitslabs.com',
    url='https://github.com/LightbitsLabs/image-store',
    packages=find_packages(include=['hwinfo', 'hwinfo.*']),
    install_requires=[
        'requests',
    ],
    extras_require={},
    setup_requires=['pytest-runner', 'flake8'],
    tests_require=['pytest'],
    entry_points={
        'console_scripts': ['hwinfo=hwinfo.main:main']
    },
    package_data={}
)
