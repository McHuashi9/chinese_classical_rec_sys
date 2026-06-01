#ifndef MATH_UTILS_H
#define MATH_UTILS_H

#include "core/Config.h"
#include <cmath>

namespace math_utils {

inline double gaussian(double x) {
    return std::exp(-x * x / (2.0 * Config::SIGMA * Config::SIGMA));
}

inline double calculateLearningGain(double d_j, double u_j) {
    return gaussian(d_j - u_j - Config::DELTA_STAR);
}

inline double calculateDynamicLearningRate(double avgAbility) {
    return Config::ETA * std::pow(1.0 - avgAbility, Config::GAMMA);
}

} // namespace math_utils

#endif
