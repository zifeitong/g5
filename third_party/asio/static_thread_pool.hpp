//
// static_thread_pool.hpp
// ~~~~~~~~~~~~~~~~~~~~~~
//
// Copyright (c) 2003-2026 Christopher M. Kohlhoff (chris at kohlhoff dot com)
//
// Distributed under the Boost Software License, Version 1.0. (See accompanying
// file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
//

#ifndef ASIO_STATIC_THREAD_POOL_HPP
#define ASIO_STATIC_THREAD_POOL_HPP

#if defined(_MSC_VER) && (_MSC_VER >= 1200)
# pragma once
#endif // defined(_MSC_VER) && (_MSC_VER >= 1200)

#include "third_party/asio/detail/config.hpp"
#include "third_party/asio/thread_pool.hpp"

#include "third_party/asio/detail/push_options.hpp"

namespace asio {
ASIO_INLINE_NAMESPACE_BEGIN

typedef thread_pool static_thread_pool;

ASIO_INLINE_NAMESPACE_END
} // namespace asio

#include "third_party/asio/detail/pop_options.hpp"

#endif // ASIO_STATIC_THREAD_POOL_HPP
