
cmake_minimum_required(VERSION 3.2 FATAL_ERROR)
project(atom-rtags-plus-test)
set(CMAKE_CXX_STANDARD 14)

add_executable(testapp test.cpp TestClass.cpp)
