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

// d1: 平均句长能力 (f1)
void User::setD1Ability(double ability) {
    abilities[0] = std::clamp(ability, 0.0, 1.0);
}

double User::getD1Ability() const {
    return abilities[0];
}

// d2: 句子数能力 (f3)
void User::setD2Ability(double ability) {
    abilities[1] = std::clamp(ability, 0.0, 1.0);
}

double User::getD2Ability() const {
    return abilities[1];
}

// d3: 虚词比例能力 (f5)
void User::setD3Ability(double ability) {
    abilities[2] = std::clamp(ability, 0.0, 1.0);
}

double User::getD3Ability() const {
    return abilities[2];
}

// d4: 字平均对数频次能力 (f6)
void User::setD4Ability(double ability) {
    abilities[3] = std::clamp(ability, 0.0, 1.0);
}

double User::getD4Ability() const {
    return abilities[3];
}

// d5: 通假字密度能力 (f8)
void User::setD5Ability(double ability) {
    abilities[4] = std::clamp(ability, 0.0, 1.0);
}

double User::getD5Ability() const {
    return abilities[4];
}

// d6: 古汉语困惑度能力 (f9)
void User::setD6Ability(double ability) {
    abilities[5] = std::clamp(ability, 0.0, 1.0);
}

double User::getD6Ability() const {
    return abilities[5];
}

// d7: 今汉语困惑度能力 (f10)
void User::setD7Ability(double ability) {
    abilities[6] = std::clamp(ability, 0.0, 1.0);
}

double User::getD7Ability() const {
    return abilities[6];
}

// d8: MATTR词汇多样性能力 (f11)
void User::setD8Ability(double ability) {
    abilities[7] = std::clamp(ability, 0.0, 1.0);
}

double User::getD8Ability() const {
    return abilities[7];
}

// d9: 典故密度能力 (f12)
void User::setD9Ability(double ability) {
    abilities[8] = std::clamp(ability, 0.0, 1.0);
}

double User::getD9Ability() const {
    return abilities[8];
}

// d10: 语义复杂度能力 (f13)
void User::setD10Ability(double ability) {
    abilities[9] = std::clamp(ability, 0.0, 1.0);
}

double User::getD10Ability() const {
    return abilities[9];
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