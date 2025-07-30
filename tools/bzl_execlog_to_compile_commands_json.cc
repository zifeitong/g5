// Convert bazel compact execlog into clangd compile_commands.json.

#include <filesystem>

#include "absl/container/flat_hash_map.h"
#include "absl/flags/flag.h"
#include "absl/flags/parse.h"
#include "absl/log/check.h"
#include "absl/log/initialize.h"
#include "absl/log/log.h"
#include "absl/strings/str_cat.h"
#include "google/protobuf/util/json_util.h"
#include "riegeli/bytes/fd_reader.h"
#include "riegeli/bytes/fd_writer.h"
#include "riegeli/bytes/read_all.h"
#include "riegeli/lines/line_writing.h"
#include "riegeli/messages/parse_message.h"
#include "riegeli/zstd/zstd_reader.h"
#include "tools/compilation_database.pb.h"
#include "tools/spawn.pb.h"

ABSL_FLAG(std::string, execlog, "", "Bazel compact execution log file path");

ABSL_FLAG(std::string, compile_commands_json, "",
          "Clangd compilation database file to create / extend");

ABSL_FLAG(std::string, directory, "/src",
          "Root directory of compilation database commands");

namespace {

using g5::tools::compilation_database::Command;
using g5::tools::compilation_database::CompilationDatabase;

bool IsCppSourceFile(std::string_view path) {
  return path.ends_with(".cc") || path.ends_with(".cpp") ||
         path.ends_with(".cxx") || path.ends_with(".c++") ||
         path.ends_with(".c");
}

absl::flat_hash_map<std::string, Command> ParseCompilationDatabase(
    std::string_view compilation_database_json) {
  if (!std::filesystem::exists(compilation_database_json)) {
    return {};
  }

  riegeli::FdReader<> reader(compilation_database_json);

  std::string_view json_content;
  CHECK_OK(riegeli::ReadAll(reader, json_content));

  CompilationDatabase compilation_database;
  CHECK_OK(google::protobuf::util::JsonStringToMessage(
      absl::StrCat("{commands:", json_content, "}"), &compilation_database));

  absl::flat_hash_map<std::string, Command> commands;
  for (auto& command : compilation_database.commands()) {
    commands.emplace(absl::StrCat(command.directory(), command.file()),
                     std::move(command));
  }
  return commands;
}

std::vector<Command> ParseExecLog(std::string_view execlog) {
  riegeli::ZstdReader<riegeli::FdReader<>> reader(riegeli::Maker(execlog));

  absl::flat_hash_map<uint32_t, std::string> files;
  absl::flat_hash_map<uint32_t, std::vector<std::string>> source_files;

  bazel::ExecLogEntry log_entry;
  std::vector<Command> commands;
  while (riegeli::ParseLengthPrefixedMessage(reader, log_entry).ok()) {
    // Keep track of input files
    if (log_entry.has_file()) {
      files[log_entry.id()] = log_entry.file().path();
      continue;
    }

    if (log_entry.has_input_set()) {
      for (uint32_t input_id : log_entry.input_set().input_ids()) {
        if (IsCppSourceFile(files[input_id])) {
          source_files[log_entry.id()].push_back(files[input_id]);
        }
      }

      for (uint32_t input_set_id : log_entry.input_set().transitive_set_ids()) {
        source_files[log_entry.id()].append_range(source_files[input_set_id]);
      }

      continue;
    }

    if (!(log_entry.spawn().mnemonic() == "CppCompile")) {
      continue;
    }

    uint32_t input_set_id = log_entry.spawn().input_set_id();
    auto it = source_files.find(input_set_id);
    if (it == source_files.end() || it->second.empty()) {
      LOG(WARNING) << "C/C++ source file not found: "
                   << log_entry.spawn().target_label();
      continue;
    }

    const auto& target_source_files = it->second;
    if (target_source_files.size() > 1) {
      LOG(ERROR) << "Multiple C/C++ source file found: "
                 << log_entry.spawn().target_label();
      continue;
    }
    std::string_view source_file = target_source_files[0];

    Command command;
    command.set_directory(absl::GetFlag(FLAGS_directory));
    command.set_file(source_file);

    for (const auto& arg : log_entry.spawn().args()) {
      command.add_arguments(arg);
    }
    commands.push_back(std::move(command));
  }

  return commands;
}

}  // namespace

int main(int argc, char* argv[]) {
  absl::InitializeLog();
  absl::ParseCommandLine(argc, argv);

  absl::flat_hash_map<std::string, Command> commands =
      ParseCompilationDatabase(absl::GetFlag(FLAGS_compile_commands_json));

  for (auto& command : ParseExecLog(absl::GetFlag(FLAGS_execlog))) {
    commands.emplace(absl::StrCat(command.directory(), command.file()),
                     std::move(command));
  }

  riegeli::FdWriter<> writer(absl::GetFlag(FLAGS_compile_commands_json));
  riegeli::WriteLine("[", writer);
  int count = 0;
  for (const auto& [_, command] : commands) {
    std::string json_string;
    CHECK_OK(
        google::protobuf::util::MessageToJsonString(command, &json_string));
    if (count == commands.size() - 1) {
      // No trailing comma
      riegeli::WriteLine(json_string, writer);
    } else {
      riegeli::WriteLine(json_string, ",", writer);
    }
    ++count;
  }
  riegeli::WriteLine("]", writer);
  writer.Close();
}
