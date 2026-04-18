#include <catch_amalgamated.hpp>
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "core/Config.h"
#include <cmath>

/**
 * @brief 单元测试：核心数学函数
 * 
 * 测试范围：
 * - 高斯函数的数学性质（通过 LearningGain 间接测试）
 * - 动态学习率计算
 * - 学习增益计算
 * - 遗忘因子计算
 */

// 容差阈值
constexpr double EPSILON = 1e-4;

// =============================================================================
// 高斯函数测试（通过 calculateLearningGain 间接验证）
// =============================================================================

TEST_CASE("calculateLearningGain - 在理想难度差距处达到峰值", "[math]") {
    RecommendationEngine engine;
    KnowledgeTracker tracker;
    
    // 当 d_j - u_j = δ* 时，学习增益应为 1.0（高斯峰值）
    double d_j = 0.5;
    double u_j = d_j - Config::DELTA_STAR;  // u_j = 0.5 - 0.13 = 0.37
    
    double gain = engine.calculateLearningGain(d_j, u_j);
    REQUIRE(std::abs(gain - 1.0) < EPSILON);
    
    gain = tracker.calculateLearningGain(d_j, u_j);
    REQUIRE(std::abs(gain - 1.0) < EPSILON);
}

TEST_CASE("calculateLearningGain - 高斯函数对称性", "[math]") {
    RecommendationEngine engine;
    
    double u_j = 0.3;
    double d_j_peak = u_j + Config::DELTA_STAR;  // 峰值点
    
    // 偏移 ±σ 处的增益应该相等（对称性）
    double d_j_plus = d_j_peak + Config::SIGMA;   // 偏移 +σ
    double d_j_minus = d_j_peak - Config::SIGMA;  // 偏移 -σ
    
    double gain_plus = engine.calculateLearningGain(d_j_plus, u_j);
    double gain_minus = engine.calculateLearningGain(d_j_minus, u_j);
    
    REQUIRE(std::abs(gain_plus - gain_minus) < EPSILON);
}

TEST_CASE("calculateLearningGain - 距离峰值越远增益越小", "[math]") {
    RecommendationEngine engine;
    
    double u_j = 0.3;
    double d_j_peak = u_j + Config::DELTA_STAR;
    
    double gain_peak = engine.calculateLearningGain(d_j_peak, u_j);
    double gain_offset_1 = engine.calculateLearningGain(d_j_peak + 0.1, u_j);
    double gain_offset_2 = engine.calculateLearningGain(d_j_peak + 0.2, u_j);
    
    REQUIRE(gain_peak > gain_offset_1);
    REQUIRE(gain_offset_1 > gain_offset_2);
}

TEST_CASE("calculateLearningGain - 在 σ 处衰减到约 0.6065", "[math]") {
    RecommendationEngine engine;
    
    // 高斯函数在 x=σ 处：exp(-1/2) ≈ 0.6065
    double u_j = 0.3;
    double d_j = u_j + Config::DELTA_STAR + Config::SIGMA;
    
    double gain = engine.calculateLearningGain(d_j, u_j);
    double expected = std::exp(-0.5);  // ≈ 0.6065
    
    REQUIRE(std::abs(gain - expected) < EPSILON);
}

TEST_CASE("calculateLearningGain - 在 2σ 处衰减到约 0.1353", "[math]") {
    RecommendationEngine engine;
    
    // 高斯函数在 x=2σ 处：exp(-2) ≈ 0.1353
    double u_j = 0.3;
    double d_j = u_j + Config::DELTA_STAR + 2 * Config::SIGMA;
    
    double gain = engine.calculateLearningGain(d_j, u_j);
    double expected = std::exp(-2.0);  // ≈ 0.1353
    
    REQUIRE(std::abs(gain - expected) < EPSILON);
}

// =============================================================================
// 动态学习率测试
// =============================================================================

TEST_CASE("calculateDynamicLearningRate - 能力为 0 时学习率最大", "[math]") {
    RecommendationEngine engine;
    KnowledgeTracker tracker;
    
    // η(t) = η · (1 - ū)^γ
    // 当 avgAbility = 0 时：η · 1^γ = η = 0.08
    double rate = engine.calculateDynamicLearningRate(0.0);
    REQUIRE(std::abs(rate - Config::ETA) < EPSILON);
    
    rate = tracker.calculateDynamicLearningRate(0.0);
    REQUIRE(std::abs(rate - Config::ETA) < EPSILON);
}

TEST_CASE("calculateDynamicLearningRate - 能力越高学习率越低", "[math]") {
    RecommendationEngine engine;
    
    double rate_0 = engine.calculateDynamicLearningRate(0.0);
    double rate_25 = engine.calculateDynamicLearningRate(0.25);
    double rate_50 = engine.calculateDynamicLearningRate(0.5);
    double rate_75 = engine.calculateDynamicLearningRate(0.75);
    
    REQUIRE(rate_0 > rate_25);
    REQUIRE(rate_25 > rate_50);
    REQUIRE(rate_50 > rate_75);
}

TEST_CASE("calculateDynamicLearningRate - 幂律衰减验证", "[math]") {
    RecommendationEngine engine;
    
    // η(t) = η · (1 - ū)^γ
    // 验证幂律计算
    double avgAbility = 0.5;
    double expected = Config::ETA * std::pow(1.0 - avgAbility, Config::GAMMA);
    double rate = engine.calculateDynamicLearningRate(avgAbility);
    
    REQUIRE(std::abs(rate - expected) < EPSILON);
}

TEST_CASE("calculateDynamicLearningRate - 具体数值验证", "[math]") {
    RecommendationEngine engine;
    
    // avgAbility = 0.5, γ = 1.5
    // rate = 0.08 * 0.5^1.5 = 0.08 * 0.3536 ≈ 0.0283
    double rate = engine.calculateDynamicLearningRate(0.5);
    double expected = 0.08 * std::pow(0.5, 1.5);
    
    REQUIRE(std::abs(rate - expected) < EPSILON);
}

TEST_CASE("calculateDynamicLearningRate - 高能力用户学习率接近 0", "[math]") {
    RecommendationEngine engine;
    
    // avgAbility = 0.9 时，学习率应很低
    double rate = engine.calculateDynamicLearningRate(0.9);
    double expected = 0.08 * std::pow(0.1, 1.5);  // ≈ 0.00253
    
    REQUIRE(std::abs(rate - expected) < EPSILON);
    REQUIRE(rate < 0.01);
}

// =============================================================================
// 遗忘因子测试（幂律遗忘）
// =============================================================================

TEST_CASE("calculateForgettingFactor - 刚学习时遗忘因子为 1", "[math]") {
    KnowledgeTracker tracker;
    
    // Δt = 0 时，ψ = 1
    double psi = tracker.calculateForgettingFactor(0.0);
    REQUIRE(std::abs(psi - 1.0) < EPSILON);
}

TEST_CASE("calculateForgettingFactor - 负时间返回 1", "[math]") {
    KnowledgeTracker tracker;
    
    // 负时间（未来）应返回 1
    double psi = tracker.calculateForgettingFactor(-1.0);
    REQUIRE(std::abs(psi - 1.0) < EPSILON);
}

TEST_CASE("calculateForgettingFactor - 幂律衰减公式验证", "[math]") {
    KnowledgeTracker tracker;
    
    // ψ(Δt) = (1 + Δt/τ)^(-c)
    // τ = 10.0, c = 0.70
    double deltaDays = 10.0;
    double expected = std::pow(1.0 + deltaDays / Config::TAU, -Config::C);
    double psi = tracker.calculateForgettingFactor(deltaDays);
    
    REQUIRE(std::abs(psi - expected) < EPSILON);
}

TEST_CASE("calculateForgettingFactor - 时间越长遗忘越多", "[math]") {
    KnowledgeTracker tracker;
    
    double psi_0 = tracker.calculateForgettingFactor(0.0);
    double psi_5 = tracker.calculateForgettingFactor(5.0);
    double psi_10 = tracker.calculateForgettingFactor(10.0);
    double psi_30 = tracker.calculateForgettingFactor(30.0);
    double psi_100 = tracker.calculateForgettingFactor(100.0);
    
    REQUIRE(psi_0 > psi_5);
    REQUIRE(psi_5 > psi_10);
    REQUIRE(psi_10 > psi_30);
    REQUIRE(psi_30 > psi_100);
}

TEST_CASE("calculateForgettingFactor - 具体数值验证", "[math]") {
    KnowledgeTracker tracker;
    
    // Δt = τ = 10 天
    // ψ = (1 + 1)^(-0.70) = 2^(-0.70) ≈ 0.6156
    double psi = tracker.calculateForgettingFactor(10.0);
    double expected = std::pow(2.0, -0.70);
    
    REQUIRE(std::abs(psi - expected) < EPSILON);
}

TEST_CASE("calculateForgettingFactor - 达到清理阈值 PSI_MIN", "[math]") {
    KnowledgeTracker tracker;
    
    // 找到遗忘因子降到 PSI_MIN (0.05) 以下的天数
    // (1 + Δt/10)^(-0.70) < 0.05
    // 解得 Δt > 712 天左右
    
    // 验证 700 天时仍高于阈值
    double psi_700 = tracker.calculateForgettingFactor(700.0);
    REQUIRE(psi_700 > Config::PSI_MIN);
    
    // 验证 800 天时低于阈值
    double psi_800 = tracker.calculateForgettingFactor(800.0);
    REQUIRE(psi_800 < Config::PSI_MIN);
}

TEST_CASE("calculateForgettingFactor - 长期遗忘趋于 0", "[math]") {
    KnowledgeTracker tracker;
    
    // 365 天（1年）后仍有一定保留
    // ψ(365) = (1 + 365/10)^(-0.70) = 37.5^(-0.70) ≈ 0.079
    double psi_365 = tracker.calculateForgettingFactor(365.0);
    REQUIRE(psi_365 > 0.05);
    REQUIRE(psi_365 < 0.1);
    
    // 1000 天后遗忘接近完全
    double psi_1000 = tracker.calculateForgettingFactor(1000.0);
    REQUIRE(psi_1000 < 0.04);
}

// =============================================================================
// 两个类的一致性测试
// =============================================================================

TEST_CASE("数学函数 - RecommendationEngine 和 KnowledgeTracker 结果一致", "[math]") {
    RecommendationEngine engine;
    KnowledgeTracker tracker;
    
    // 两个类实现了相同的数学函数，应返回相同结果
    double d_j = 0.6;
    double u_j = 0.4;
    
    double gain_engine = engine.calculateLearningGain(d_j, u_j);
    double gain_tracker = tracker.calculateLearningGain(d_j, u_j);
    REQUIRE(std::abs(gain_engine - gain_tracker) < EPSILON);
    
    double avg = 0.5;
    double rate_engine = engine.calculateDynamicLearningRate(avg);
    double rate_tracker = tracker.calculateDynamicLearningRate(avg);
    REQUIRE(std::abs(rate_engine - rate_tracker) < EPSILON);
}
