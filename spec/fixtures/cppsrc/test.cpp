#include <iostream>
#include <vector>
#include <memory>
#include "TestClass.hpp"

int main(int argc, char const *argv[]) {
    std::vector<TestNamespace::TestClass> testClasses;
    testClasses.emplace_back();
    testClasses.emplace_back(5);

    testClasses[0].SetMemberVar(2);

    std::shared_ptr<TestNamespace::TestClass> pTestClass = std::make_shared<TestNamespace::TestClass>();

    for (auto const& testClass : testClasses)
    {
        std::cout << testClass.GetMemberVar() << std::endl;
    }

    return 0;
}
