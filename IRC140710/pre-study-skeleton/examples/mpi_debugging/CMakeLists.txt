cmake_minimum_required(VERSION 3.12)
project(MPIDebuggingExamples C)

# Find MPI package
find_package(MPI REQUIRED)

# Set C standard
set(CMAKE_C_STANDARD 99)

# Enable debug symbols and warnings
set(CMAKE_C_FLAGS_DEBUG "-g -O0 -Wall -Wextra")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-g -O2")

# Add compile options for debugging
add_compile_options(
    -Wall
    -Wextra
    -Wunused-variable
    -Wunused-parameter
    -Wmissing-prototypes
)

# Option to enable sanitizers for debugging
option(ENABLE_SANITIZERS "Enable address and thread sanitizers" OFF)
if(ENABLE_SANITIZERS)
    add_compile_options(-fsanitize=address,thread,undefined)
    add_link_options(-fsanitize=address,thread,undefined)
endif()

# MPI Deadlock example
add_executable(mpi_deadlock mpi_deadlock.c)
target_link_libraries(mpi_deadlock MPI::MPI_C)

# MPI Race Condition example
add_executable(mpi_race_condition mpi_race_condition.c)
target_link_libraries(mpi_race_condition MPI::MPI_C)

# Install targets
install(TARGETS mpi_deadlock mpi_race_condition
        RUNTIME DESTINATION bin)

# Custom targets for debugging
add_custom_target(debug-deadlock
    COMMAND mpirun -np 2 gdb --batch --ex run --ex bt --ex quit --args ${CMAKE_BINARY_DIR}/mpi_deadlock
    DEPENDS mpi_deadlock
    COMMENT "Run deadlock example under GDB"
)

add_custom_target(debug-race
    COMMAND mpirun -np 4 ${CMAKE_BINARY_DIR}/mpi_race_condition
    DEPENDS mpi_race_condition
    COMMENT "Run race condition example"
)

# Valgrind targets (if available)
find_program(VALGRIND_EXECUTABLE valgrind)
if(VALGRIND_EXECUTABLE)
    add_custom_target(valgrind-deadlock
        COMMAND mpirun -np 2 ${VALGRIND_EXECUTABLE} --tool=helgrind --log-file=deadlock-valgrind.log ${CMAKE_BINARY_DIR}/mpi_deadlock
        DEPENDS mpi_deadlock
        COMMENT "Run deadlock example under Valgrind Helgrind"
    )
    
    add_custom_target(valgrind-race
        COMMAND mpirun -np 4 ${VALGRIND_EXECUTABLE} --tool=helgrind --log-file=race-valgrind.log ${CMAKE_BINARY_DIR}/mpi_race_condition
        DEPENDS mpi_race_condition
        COMMENT "Run race condition example under Valgrind Helgrind"
    )
endif()
