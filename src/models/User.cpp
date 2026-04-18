#include "models/User.h"
#include <algorithm>
#include <numeric>

User::User() : name(""), abilities{{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}}, 
                baseAbilities{{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}}, lastReadTime(0) {}

void User::setName(const std::string& name) {
    this->name = name;
}

std::string User::getName() const {
    return name;
}

bool User::isEmpty() const {
    return name.empty();
}

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

void User::initializeDefault() {
    // 贝叶斯先验均值：u_j(0) = α_0 / (α_0 + β_0) = 3/10 = 0.3
    abilities.fill(0.3);
    baseAbilities.fill(0.3);
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