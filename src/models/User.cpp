#include "models/User.h"
#include "core/Config.h"
#include <algorithm>
#include <cmath>
#include <numeric>

User::User() : abilities{{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}}, 
                baseAbilities{{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}},
                eta(Config::ETA), quizCounts{{0, 0, 0, 0, 0, 0, 0, 0, 0, 0}}, lastReadTime(0) {}

void User::setAbility(int index, double value) {
    if (index >= 0 && index < 10) {
        // 能力值范围约束：[0, 1] (论文定义)
        abilities[index] = std::clamp(value, 0.0, 1.0);
    }
}

double User::getAbility(int index) const {
    if (index >= 0 && index < 10) {
        return abilities[index];
    }
    return 0.0;
}



double User::getAverageAbility() const {
    double sum = std::accumulate(abilities.begin(), abilities.end(), 0.0);
    return sum / 10.0;
}

bool User::hasAnyNonDefaultField() const {
    for (double a : abilities) {
        if (std::abs(a) > 1e-12) return true;
    }
    for (double b : baseAbilities) {
        if (std::abs(b) > 1e-12) return true;
    }
    if (std::abs(eta - Config::ETA) > 1e-12) return true;
    for (int q : quizCounts) {
        if (q != 0) return true;
    }
    return lastReadTime != 0;
}

void User::initializeDefault() {
    // 贝叶斯先验均值：u_j(0) = α_0 / (α_0 + β_0) = 3/10 = 0.3
    abilities.fill(0.3);
    baseAbilities.fill(0.3);
    // 全新状态：悟性/答题计数一并复位
    eta = Config::ETA;
    quizCounts.fill(0);
}

time_t User::getLastReadTime() const {
    return lastReadTime;
}

void User::setLastReadTime(time_t time) {
    lastReadTime = time;
}

void User::setBaseAbility(int index, double value) {
    if (index >= 0 && index < 10) {
        baseAbilities[index] = std::clamp(value, 0.0, 1.0);
    }
}

double User::getBaseAbility(int index) const {
    if (index >= 0 && index < 10) {
        return baseAbilities[index];
    }
    return 0.0;
}

void User::setEta(double value) {
    eta = std::clamp(value, Config::ETA_MIN, Config::ETA_MAX);
}

double User::getEta() const {
    return eta;
}

void User::setQuizCount(int index, int value) {
    if (index >= 0 && index < 10) {
        quizCounts[index] = std::max(0, value);
    }
}

int User::getQuizCount(int index) const {
    if (index >= 0 && index < 10) {
        return quizCounts[index];
    }
    return 0;
}

void User::incrementQuizCount(int index) {
    if (index >= 0 && index < 10) {
        quizCounts[index]++;
    }
}