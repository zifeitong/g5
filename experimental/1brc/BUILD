load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc/toolchains:fdo_profile.bzl", "fdo_profile")

cc_binary(
    name = "1brc",
    srcs = [
        "1brc.cc",
    ],
    cxxopts = ["-fbracket-depth=512"],
    deps = [
        "//third_party/mph",
        "@abseil-cpp//absl/container:flat_hash_map",
        "@abseil-cpp//absl/log:check",
        "@abseil-cpp//absl/strings",
        "@highway//:algo",
        "@highway//:topology",
    ],
)

fdo_profile(
    name = "fdo_profile",
    profile = "fdo.profdata",
)
