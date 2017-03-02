
cmake_minimum_required(VERSION 2.8 FATAL_ERROR)
project(atom-rtags-plus-test)

add_executable(testapp test.cpp TestClass.cpp)
set_target_properties(testapp PROPERTIES COMPILE_FLAGS "-std=c++11")
