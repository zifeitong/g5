//
// impl/src.hpp
// ~~~~~~~~~~~~
//
// Copyright (c) 2003-2026 Christopher M. Kohlhoff (chris at kohlhoff dot com)
//
// Distributed under the Boost Software License, Version 1.0. (See accompanying
// file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
//

#ifndef ASIO_IMPL_SRC_HPP
#define ASIO_IMPL_SRC_HPP

#define ASIO_SOURCE

#include "third_party/asio/detail/config.hpp"

#if defined(ASIO_HEADER_ONLY)
# error Do not compile Asio library source with ASIO_HEADER_ONLY defined
#endif

#include "third_party/asio/impl/any_completion_executor.ipp"
#include "third_party/asio/impl/any_io_executor.ipp"
#include "third_party/asio/impl/awaitable.ipp"
#include "third_party/asio/impl/cancellation_signal.ipp"
#include "third_party/asio/impl/config.ipp"
#include "third_party/asio/impl/connect_pipe.ipp"
#include "third_party/asio/impl/error.ipp"
#include "third_party/asio/impl/error_code.ipp"
#include "third_party/asio/impl/execution_context.ipp"
#include "third_party/asio/impl/io_context.ipp"
#include "third_party/asio/impl/serial_port_base.ipp"
#include "third_party/asio/impl/system_context.ipp"
#include "third_party/asio/impl/thread_pool.ipp"
#include "third_party/asio/detail/impl/buffer_sequence_adapter.ipp"
#include "third_party/asio/detail/impl/descriptor_ops.ipp"
#include "third_party/asio/detail/impl/dev_poll_reactor.ipp"
#include "third_party/asio/detail/impl/epoll_reactor.ipp"
#include "third_party/asio/detail/impl/eventfd_select_interrupter.ipp"
#include "third_party/asio/detail/impl/handler_tracking.ipp"
#include "third_party/asio/detail/impl/io_uring_descriptor_service.ipp"
#include "third_party/asio/detail/impl/io_uring_file_service.ipp"
#include "third_party/asio/detail/impl/io_uring_socket_service_base.ipp"
#include "third_party/asio/detail/impl/io_uring_service.ipp"
#include "third_party/asio/detail/impl/kqueue_reactor.ipp"
#include "third_party/asio/detail/impl/null_event.ipp"
#include "third_party/asio/detail/impl/pipe_select_interrupter.ipp"
#include "third_party/asio/detail/impl/posix_event.ipp"
#include "third_party/asio/detail/impl/posix_mutex.ipp"
#include "third_party/asio/detail/impl/posix_serial_port_service.ipp"
#include "third_party/asio/detail/impl/posix_thread.ipp"
#include "third_party/asio/detail/impl/posix_tss_ptr.ipp"
#include "third_party/asio/detail/impl/reactive_descriptor_service.ipp"
#include "third_party/asio/detail/impl/reactive_socket_service_base.ipp"
#include "third_party/asio/detail/impl/resolver_service_base.ipp"
#include "third_party/asio/detail/impl/resolver_thread_pool.ipp"
#include "third_party/asio/detail/impl/scheduler.ipp"
#include "third_party/asio/detail/impl/select_reactor.ipp"
#include "third_party/asio/detail/impl/service_registry.ipp"
#include "third_party/asio/detail/impl/signal_set_service.ipp"
#include "third_party/asio/detail/impl/socket_ops.ipp"
#include "third_party/asio/detail/impl/socket_select_interrupter.ipp"
#include "third_party/asio/detail/impl/strand_executor_service.ipp"
#include "third_party/asio/detail/impl/strand_service.ipp"
#include "third_party/asio/detail/impl/thread_context.ipp"
#include "third_party/asio/detail/impl/throw_error.ipp"
#include "third_party/asio/detail/impl/timer_queue_set.ipp"
#include "third_party/asio/detail/impl/win_iocp_file_service.ipp"
#include "third_party/asio/detail/impl/win_iocp_handle_service.ipp"
#include "third_party/asio/detail/impl/win_iocp_io_context.ipp"
#include "third_party/asio/detail/impl/win_iocp_serial_port_service.ipp"
#include "third_party/asio/detail/impl/win_iocp_socket_service_base.ipp"
#include "third_party/asio/detail/impl/win_event.ipp"
#include "third_party/asio/detail/impl/win_critsec_mutex.ipp"
#include "third_party/asio/detail/impl/win_object_handle_service.ipp"
#include "third_party/asio/detail/impl/win_static_mutex.ipp"
#include "third_party/asio/detail/impl/win_thread.ipp"
#include "third_party/asio/detail/impl/win_tss_ptr.ipp"
#include "third_party/asio/detail/impl/winrt_ssocket_service_base.ipp"
#include "third_party/asio/detail/impl/winrt_timer_scheduler.ipp"
#include "third_party/asio/detail/impl/winsock_init.ipp"
#include "third_party/asio/experimental/impl/channel_error.ipp"
#include "third_party/asio/generic/detail/impl/endpoint.ipp"
#include "third_party/asio/ip/impl/address.ipp"
#include "third_party/asio/ip/impl/address_v4.ipp"
#include "third_party/asio/ip/impl/address_v6.ipp"
#include "third_party/asio/ip/impl/host_name.ipp"
#include "third_party/asio/ip/impl/network_v4.ipp"
#include "third_party/asio/ip/impl/network_v6.ipp"
#include "third_party/asio/ip/detail/impl/endpoint.ipp"
#include "third_party/asio/local/detail/impl/endpoint.ipp"

#endif // ASIO_IMPL_SRC_HPP
