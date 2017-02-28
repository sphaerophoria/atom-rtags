#include "TestClass.hpp"

namespace TestNamespace {

    TestClass::TestClass()
    : m_memberVar(0)
    {}

    TestClass::TestClass(int memberVar)
    : m_memberVar(memberVar)
    {}

    void TestClass::SetMemberVar(int memberVar)
    {
        m_memberVar = memberVar;
    }

    int TestClass::GetMemberVar() const
    {
        return PrivateMemberFunc();
    }

    int TestClass::PrivateMemberFunc() const
    {
        return m_memberVar;
    }

}
