// Copyright 2024 Dennis Hezel
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * @file asio_grpc.hpp
 * @brief Convenience header
 */

/**
 * @namespace agrpc
 * @brief Public namespace
 */

#ifndef AGRPC_AGRPC_ASIO_GRPC_HPP
#define AGRPC_AGRPC_ASIO_GRPC_HPP

#include "third_party/agrpc/alarm.hpp"
#include "third_party/agrpc/client_rpc.hpp"
#include "third_party/agrpc/default_server_rpc_traits.hpp"
#include "third_party/agrpc/grpc_context.hpp"
#include "third_party/agrpc/grpc_executor.hpp"
#include "third_party/agrpc/notify_on_state_change.hpp"
#include "third_party/agrpc/read.hpp"
#include "third_party/agrpc/register_awaitable_rpc_handler.hpp"
#include "third_party/agrpc/register_callback_rpc_handler.hpp"
#include "third_party/agrpc/register_coroutine_rpc_handler.hpp"
#include "third_party/agrpc/register_sender_rpc_handler.hpp"
#include "third_party/agrpc/rpc_type.hpp"
#include "third_party/agrpc/run.hpp"
#include "third_party/agrpc/server_rpc.hpp"
#include "third_party/agrpc/test.hpp"
#include "third_party/agrpc/use_sender.hpp"
#include "third_party/agrpc/waiter.hpp"

#endif  // AGRPC_AGRPC_ASIO_GRPC_HPP
