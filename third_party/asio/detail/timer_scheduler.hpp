//
// detail/timer_scheduler.hpp
// ~~~~~~~~~~~~~~~~~~~~~~~~~~
//
// Copyright (c) 2003-2026 Christopher M. Kohlhoff (chris at kohlhoff dot com)
//
// Distributed under the Boost Software License, Version 1.0. (See accompanying
// file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
//

#ifndef ASIO_DETAIL_TIMER_SCHEDULER_HPP
#define ASIO_DETAIL_TIMER_SCHEDULER_HPP

#if defined(_MSC_VER) && (_MSC_VER >= 1200)
# pragma once
#endif // defined(_MSC_VER) && (_MSC_VER >= 1200)

#include "third_party/asio/detail/config.hpp"
#include "third_party/asio/detail/timer_scheduler_fwd.hpp"

#if defined(ASIO_WINDOWS_RUNTIME)
# include "third_party/asio/detail/winrt_timer_scheduler.hpp"
#elif defined(ASIO_HAS_IOCP)
# include "third_party/asio/detail/win_iocp_io_context.hpp"
#elif defined(ASIO_HAS_IO_URING_AS_DEFAULT)
# include "third_party/asio/detail/io_uring_service.hpp"
#elif defined(ASIO_HAS_EPOLL)
# include "third_party/asio/detail/epoll_reactor.hpp"
#elif defined(ASIO_HAS_KQUEUE)
# include "third_party/asio/detail/kqueue_reactor.hpp"
#elif defined(ASIO_HAS_DEV_POLL)
# include "third_party/asio/detail/dev_poll_reactor.hpp"
#else
# include "third_party/asio/detail/select_reactor.hpp"
#endif

#endif // ASIO_DETAIL_TIMER_SCHEDULER_HPP
