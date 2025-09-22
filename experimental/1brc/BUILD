cc_binary(
  name = "1brc",
  srcs = [
    "1brc.cc",
  ],
  deps = [
    "@abseil-cpp//absl/strings",
    "@abseil-cpp//absl/log:check",
    "@abseil-cpp//absl/container:flat_hash_map",
    "@highway//:algo",
    "@highway//:topology",
    "//third_party/mph",
  ],
)

fdo_profile(
    name = "fdo_profile",
    profile = "fdo.profdata",
)
