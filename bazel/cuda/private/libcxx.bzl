"""A tuple-header overlay for nvcc with libc++ 23.1.2."""

visibility(["//bazel/cuda/..."])

def _libcxx_overlay_impl(ctx):
    headers = [f for f in ctx.files.headers if f.path.endswith("/libcxx/include/tuple")]
    if len(headers) != 1:
        fail("Expected one libc++ tuple source header, got: " + str(headers))
    output = ctx.actions.declare_file(ctx.label.name + "/tuple")
    ctx.actions.expand_template(
        template = headers[0],
        output = output,
        substitutions = {
            "_LIBCPP_BEGIN_NAMESPACE_STD": """_LIBCPP_BEGIN_NAMESPACE_STD
#if _LIBCPP_STD_VER >= 23
template <class _Tp, class _Up>
concept __tuple_can_compare_equal = requires(const _Tp& __t, const _Up& __u) {
  { __t == __u } -> __boolean_testable;
};
#endif
""",
            """__all<requires(const _Tp& __t, const _Up& __u) {
    { __t == __u } -> __boolean_testable;
  }...>::value""": "__all<__tuple_can_compare_equal<_Tp, _Up>...>::value",
        },
    )
    return [DefaultInfo(files = depset([output]))]

libcxx_overlay = rule(
    implementation = _libcxx_overlay_impl,
    attrs = {
        "headers": attr.label(
            default = Label("@llvm-project//libcxx:libcxx_headers_files"),
            doc = "LLVM source headers supplying the tuple-header template.",
        ),
    },
)
