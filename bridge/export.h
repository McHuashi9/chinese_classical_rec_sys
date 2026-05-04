#pragma once

#if defined(_MSC_VER) || defined(_WIN32)
  #define CHINESE_CORE_EXPORT __declspec(dllexport)
#elif defined(__clang__) || defined(__GNUC__)
  #define CHINESE_CORE_EXPORT __attribute__((visibility("default")))
#else
  #define CHINESE_CORE_EXPORT
#endif
