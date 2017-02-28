#ifndef __TEST_CLASS_H__
#define __TEST_CLASS_H__


namespace TestNamespace {
    class TestClass
    {
    public:
        TestClass();
        TestClass(int memberVar);

        void SetMemberVar(int memberVar);
        int GetMemberVar() const;

    private:
        int PrivateMemberFunc() const;
        int m_memberVar;
    };
}

#endif /* end of include guard: __TEST_CLASS_H__ */
