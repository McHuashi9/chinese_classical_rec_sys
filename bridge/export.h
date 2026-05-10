#pragma once

#if defined(_MSC_VER) || defined(_WIN32)
  #define CHINESE_CORE_EXPORT __declspec(dllexport)
#elif defined(__clang__) || defined(__GNUC__)
  #define CHINESE_CORE_EXPORT __attribute__((visibility("default")))
  #define CHINESE_CORE_EXPORT_USED \
      __attribute__((visibility("default"))) __attribute__((used))
#else
  #define CHINESE_CORE_EXPORT
  #define CHINESE_CORE_EXPORT_USED
#endif
