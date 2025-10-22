cmake_minimum_required(VERSION 3.18)
project(cuda_saxpy LANGUAGES CXX CUDA)
add_executable(saxpy saxpy.cu)
set_target_properties(saxpy PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
