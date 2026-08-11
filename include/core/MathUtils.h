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

inline double calculateDynamicLearningRate(double avgAbility, double eta) {
    // 论文公式16: η(t) = η·(1-ū)^γ，其中 η 为用户悟性（答题效应动态调整）
    return eta * std::pow(1.0 - avgAbility, Config::GAMMA);
}

// 答题效应预期正确率（论文§5.3）：E[s_j] = 1/(1+e^(-β(u_j - d̂_j)))
inline double expectedAccuracy(double u_j, double d_j) {
    return 1.0 / (1.0 + std::exp(-Config::QUIZ_BETA * (u_j - d_j)));
}

// 答题效应动态学习率（论文§5.3 公式）：K_j(t) = max(K_min, K_0/(1 + λ_K·N_j))
inline double quizLearningRate(int n_j) {
    const double k = Config::QUIZ_K0 / (1.0 + Config::QUIZ_LAMBDA_K * n_j);
    return std::max(Config::QUIZ_K_MIN, k);
}

} // namespace math_utils

#endif
